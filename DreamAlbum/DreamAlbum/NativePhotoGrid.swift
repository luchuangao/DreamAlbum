import SwiftUI
import UIKit

/// A sweep is computed from its initial selection so reversing direction restores
/// photos outside the current range instead of toggling them a second time.
struct PhotoSelectionSweep {
    let anchor: Int
    let baseline: Set<String>
    let adds: Bool

    func selection(through end: Int, ids: [String]) -> Set<String> {
        guard ids.indices.contains(anchor), ids.indices.contains(end) else { return baseline }
        let range = Set(ids[min(anchor, end)...max(anchor, end)])
        return adds ? baseline.union(range) : baseline.subtracting(range)
    }
}

struct NativePhotoGrid: UIViewRepresentable {
    let photos: [LibraryPhoto]
    let service: any PhotoLibraryService
    let pending: Set<String>
    let language: AppLanguage
    let active: Bool
    let picking: Bool
    @Binding var selecting: Bool
    @Binding var selection: Set<String>
    let onOpen: (LibraryPhoto) -> Void
    let onPreheat: (String) -> Void
    var onBack: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        let view = PhotoGridCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.contentInset.bottom = 12
        view.allowsMultipleSelection = true
        view.allowsMultipleSelectionDuringEditing = true
        view.register(PhotoGridCell.self, forCellWithReuseIdentifier: "photo")
        view.delegate = context.coordinator
        view.dataSource = context.coordinator
        view.accessibilityIdentifier = "library.grid"
        context.coordinator.collection = view
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.35
        view.addGestureRecognizer(hold)
        let sweep = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.sweep(_:)))
        sweep.maximumNumberOfTouches = 1
        sweep.delegate = context.coordinator
        view.addGestureRecognizer(sweep)
        view.panGestureRecognizer.require(toFail: sweep)
        let back = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeBack(_:)))
        back.direction = .right
        back.delegate = context.coordinator
        view.addGestureRecognizer(back)
        view.panGestureRecognizer.require(toFail: back)
        view.returnGesture = back
        view.selectionGesture = sweep
        view.onSelectAll = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            coordinator.parent.selecting = true
            coordinator.parent.selection = Set(coordinator.ids)
        }
        view.onEscape = { [weak coordinator = context.coordinator] in
            guard let coordinator, !coordinator.parent.picking else { return }
            coordinator.parent.selecting = false
            coordinator.parent.selection = []
        }
        return view
    }
    func updateUIView(_ view: UICollectionView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.stopSweep()
        (view as? PhotoGridCollectionView)?.blocksNavigationBack = false
        view.visibleCells.compactMap { $0 as? PhotoGridCell }.forEach { $0.stopLoading() }
    }

    @MainActor final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        var parent: NativePhotoGrid
        weak var collection: UICollectionView?
        var ids: [String] = []
        var photos: [LibraryPhoto] = []
        private var range: PhotoSelectionSweep?
        private var lastEnd: Int?
        private var pointer = CGPoint.zero
        private var displayLink: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        private let feedback = UISelectionFeedbackGenerator()
        init(_ parent: NativePhotoGrid) { self.parent = parent }
        var selectionMode: Bool { parent.selecting || parent.picking }
        func update(_ parent: NativePhotoGrid) {
            let wasActive = self.parent.active
            self.parent = parent
            guard let collection else { return }
            if photos != parent.photos {
                stopSweep()
                photos = parent.photos
                ids = photos.map(\.id)
                collection.reloadData()
            }
            collection.isEditing = selectionMode
            (collection as? PhotoGridCollectionView)?.blocksNavigationBack = parent.active && selectionMode
            if !parent.active || !selectionMode { stopSweep() }
            if wasActive && !parent.active {
                collection.resignFirstResponder()
                collection.visibleCells.compactMap { $0 as? PhotoGridCell }.forEach { $0.stopLoading() }
            }
            for case let cell as PhotoGridCell in collection.visibleCells {
                guard let index = collection.indexPath(for: cell)?.item, photos.indices.contains(index) else { continue }
                configure(cell, at: index)
                let path = IndexPath(item: index, section: 0)
                if parent.selection.contains(ids[index]) { collection.selectItem(at: path, animated: false, scrollPosition: []) }
                else { collection.deselectItem(at: path, animated: false) }
            }
        }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { photos.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! PhotoGridCell
            configure(cell, at: indexPath.item)
            return cell
        }
        private func configure(_ cell: PhotoGridCell, at index: Int) {
            let photo = photos[index]
            cell.configure(photo: photo, service: parent.service, active: parent.active,
                           choosing: selectionMode, selected: parent.selection.contains(photo.id),
                           pending: parent.pending.contains(photo.id), language: parent.language)
            cell.accessibilityActivateAction = { [weak self] in self?.activate(index) }
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = collectionView.bounds.width
            let columns = width > 600 ? max(5, Int(width / 150)) : 3
            let side = floor((width - CGFloat(columns - 1) * 2) / CGFloat(columns))
            return CGSize(width: side, height: side)
        }
        func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
            if !selectionMode { collectionView.resignFirstResponder(); parent.onOpen(photos[indexPath.item]); return false }
            collectionView.becomeFirstResponder()
            return true
        }
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) { set(indexPath.item, selected: true) }
        func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) { set(indexPath.item, selected: false) }
        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) { (cell as? PhotoGridCell)?.stopLoading() }
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            configure(cell as! PhotoGridCell, at: indexPath.item)
            parent.onPreheat(ids[indexPath.item])
        }
        func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool { true }
        func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) { parent.selecting = true; feedback.prepare() }
        private func set(_ index: Int, selected: Bool) {
            guard ids.indices.contains(index) else { return }
            if selected { parent.selection.insert(ids[index]) } else { parent.selection.remove(ids[index]) }
            feedback.selectionChanged()
        }
        private func activate(_ index: Int) {
            guard photos.indices.contains(index) else { return }
            if selectionMode { set(index, selected: !parent.selection.contains(ids[index])) }
            else { parent.onOpen(photos[index]) }
        }
        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let collection,
                  let path = collection.indexPathForItem(at: gesture.location(in: collection)) else { return }
            parent.selecting = true
            set(path.item, selected: true)
            collection.becomeFirstResponder()
        }
        @objc func swipeBack(_ gesture: UISwipeGestureRecognizer) {
            if gesture.state == .ended && parent.active && !selectionMode { parent.onBack?() }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UISwipeGestureRecognizer { return parent.active && !selectionMode && parent.onBack != nil }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let collection else { return false }
            let velocity = pan.velocity(in: collection)
            return selectionMode && abs(velocity.x) > abs(velocity.y) && collection.indexPathForItem(at: pan.location(in: collection)) != nil
        }
        @objc func sweep(_ gesture: UIPanGestureRecognizer) {
            guard let collection else { return }
            pointer = gesture.location(in: collection)
            let translation = gesture.translation(in: collection)
            let start = CGPoint(x: pointer.x - translation.x, y: pointer.y - translation.y)
            if gesture.state == .began, let path = collection.indexPathForItem(at: start) {
                range = PhotoSelectionSweep(anchor: path.item, baseline: parent.selection, adds: !parent.selection.contains(ids[path.item]))
                lastEnd = nil
                feedback.prepare()
                lastTick = 0
                displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
                displayLink?.add(to: .main, forMode: .common)
            }
            if gesture.state == .began || gesture.state == .changed { updateRange() }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { stopSweep() }
        }
        private func updateRange() {
            guard let collection, let range else { return }
            // Gutters belong to the nearest photo, including the last partial row.
            let point = CGPoint(x: min(max(1, pointer.x), collection.bounds.width - 1), y: min(max(1, pointer.y), max(1, collection.contentSize.height - 1)))
            let path = collection.indexPathForItem(at: point) ?? collection.indexPathsForVisibleItems.min {
                let a = collection.layoutAttributesForItem(at: $0)?.center ?? .zero
                let b = collection.layoutAttributesForItem(at: $1)?.center ?? .zero
                return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
            }
            guard let end = path?.item, end != lastEnd else { return }
            lastEnd = end
            parent.selection = range.selection(through: end, ids: ids)
            feedback.selectionChanged()
        }
        @objc private func tick(_ link: CADisplayLink) {
            guard let collection else { stopSweep(); return }
            let dt = lastTick == 0 ? 0 : min(link.timestamp - lastTick, 0.05)
            lastTick = link.timestamp
            let y = pointer.y - collection.contentOffset.y
            let edge: CGFloat = 60
            let velocity: CGFloat = y < edge ? -min(1, (edge - y) / edge) * 500 : (y > collection.bounds.height - edge ? min(1, (y - collection.bounds.height + edge) / edge) * 500 : 0)
            let old = collection.contentOffset.y
            let next = min(max(-collection.adjustedContentInset.top, old + velocity * dt), max(-collection.adjustedContentInset.top, collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom))
            if next != old {
                collection.contentOffset.y = next
                pointer.y += next - old
                updateRange()
            }
        }
        func stopSweep() { displayLink?.invalidate(); displayLink = nil; range = nil; lastEnd = nil }
    }
}

private final class PhotoGridCollectionView: UICollectionView {
    var onSelectAll: (() -> Void)?
    var onEscape: (() -> Void)?
    var returnGesture: UIGestureRecognizer?
    var selectionGesture: UIGestureRecognizer?
    private weak var navigationBackGesture: UIGestureRecognizer?
    private weak var contentBackGesture: UIGestureRecognizer?
    private var previousBackEnabled: Bool?
    private var previousContentBackEnabled: Bool?
    var blocksNavigationBack = false { didSet { updateNavigationBack() } }
    private static func setBlocked(_ blocked: Bool, gesture: UIGestureRecognizer?, previous: inout Bool?) {
        guard let gesture else { return }
        if blocked {
            if previous == nil { previous = gesture.isEnabled }
            gesture.isEnabled = false
        } else if let saved = previous {
            gesture.isEnabled = saved; previous = nil
        }
    }
    private func updateNavigationBack() {
        if navigationBackGesture == nil, window != nil { bindNavigationBack() }
        Self.setBlocked(blocksNavigationBack, gesture: navigationBackGesture, previous: &previousBackEnabled)
        Self.setBlocked(blocksNavigationBack, gesture: contentBackGesture, previous: &previousContentBackEnabled)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            Self.setBlocked(false, gesture: navigationBackGesture, previous: &previousBackEnabled)
            Self.setBlocked(false, gesture: contentBackGesture, previous: &previousContentBackEnabled)
            navigationBackGesture = nil; contentBackGesture = nil
            return
        }
        updateNavigationBack()
    }
    private func bindNavigationBack() {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController,
               let navigation = controller.navigationController,
               let edge = navigation.interactivePopGestureRecognizer {
                navigationBackGesture = edge
                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    contentBackGesture = navigation.interactiveContentPopGestureRecognizer
                }
                // Prefer the system's interactive full-content transition on
                // newer OS versions; the swipe fallback serves iOS 17–25.
                returnGesture?.isEnabled = contentBackGesture == nil
                for gesture in [navigationBackGesture, contentBackGesture].compactMap({ $0 }) {
                    returnGesture?.require(toFail: gesture)
                    selectionGesture?.require(toFail: gesture)
                }
                break
            }
            responder = current.next
        }
    }
    // Photo selection accepts hardware shortcuts without summoning the text keyboard.
    private lazy var selectionInputView = UIView(frame: .zero)
    override var inputView: UIView? { selectionInputView }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(title: "Select All", action: #selector(selectAllPhotos), input: "a", modifierFlags: .command),
         UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))]
    }
    @objc private func selectAllPhotos() { onSelectAll?() }
    @objc private func escape() { onEscape?() }
    private var lastWidth: CGFloat = 0
    override func layoutSubviews() {
        if lastWidth != bounds.width { lastWidth = bounds.width; collectionViewLayout.invalidateLayout() }
        super.layoutSubviews()
    }
}

private final class PhotoGridCell: UICollectionViewCell {
    private let photoView = UIImageView()
    private let shade = UIView()
    private let check = UIImageView()
    private let pendingBadge = UIImageView(image: UIImage(systemName: "tray.fill"))
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retry = UIButton(type: .system)
    private var request: Task<Void, Never>?
    private var representedID: String?
    private var retryAction: (() -> Void)?
    var accessibilityActivateAction: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(LibraryStyle.surface)
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        check.contentMode = .scaleAspectFit
        pendingBadge.tintColor = .white
        pendingBadge.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        pendingBadge.layer.cornerRadius = 14
        pendingBadge.contentMode = .center
        retry.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        retry.tintColor = .white
        retry.isHidden = true
        retry.addTarget(self, action: #selector(retryImage), for: .touchUpInside)
        [photoView, shade, check, pendingBadge, spinner, retry].forEach(contentView.addSubview)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        photoView.frame = contentView.bounds.insetBy(dx: isSelected ? 4 : 0, dy: isSelected ? 4 : 0)
        shade.frame = photoView.frame
        check.frame = CGRect(x: bounds.width - 33, y: bounds.height - 33, width: 26, height: 26)
        pendingBadge.frame = CGRect(x: bounds.width - 34, y: 6, width: 28, height: 28)
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        retry.frame = contentView.bounds
    }
    override var isSelected: Bool { didSet { setNeedsLayout() } }
    override var isHighlighted: Bool { didSet { photoView.alpha = isHighlighted ? 0.75 : 1 } }
    func configure(photo: LibraryPhoto, service: any PhotoLibraryService, active: Bool, choosing: Bool, selected: Bool, pending: Bool, language: AppLanguage) {
        accessibilityIdentifier = "library.photo." + photo.id
        accessibilityLabel = AlbumCopy.pick(language, "照片", "Photo") + (photo.isLivePhoto ? " Live Photo" : "")
        accessibilityValue = selected ? AlbumCopy.pick(language, "已选择", "Selected") : nil
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        isSelected = selected
        check.isHidden = !choosing
        shade.isHidden = !selected
        check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold))
        check.tintColor = selected ? UIColor(LibraryStyle.mint) : .white
        check.layer.shadowColor = UIColor.black.cgColor
        check.layer.shadowOpacity = 0.6
        check.layer.shadowRadius = 2
        pendingBadge.isHidden = choosing || !pending
        retry.accessibilityLabel = AlbumCopy.pick(language, "图片加载失败，重试", "Image unavailable. Retry")
        // Updating a checkmark never restarts an image request.
        guard active else { stopLoading(); return }
        if representedID != photo.id {
            stopLoading(); representedID = photo.id; photoView.image = nil; retry.isHidden = true
        }
        retryAction = { [weak self] in self?.load(id: photo.id, service: service) }
        if photoView.image == nil && request == nil && retry.isHidden { load(id: photo.id, service: service) }
    }
    private func load(id: String, service: any PhotoLibraryService) {
        request?.cancel()
        retry.isHidden = true
        isAccessibilityElement = true
        spinner.startAnimating()
        request = Task { [weak self] in
            do {
                let image = try await service.image(id: id, size: CGSize(width: 360, height: 360)) { _ in }
                try Task.checkCancellation()
                guard let self, self.representedID == id else { return }
                self.photoView.image = image; self.spinner.stopAnimating(); self.request = nil
            } catch is CancellationError { }
            catch {
                guard let self, self.representedID == id, !Task.isCancelled else { return }
                self.spinner.stopAnimating(); self.retry.isHidden = false; self.request = nil
                self.isAccessibilityElement = false // Expose the retry button to VoiceOver.
            }
        }
    }
    @objc private func retryImage() { retryAction?() }
    override func accessibilityActivate() -> Bool { accessibilityActivateAction?(); return true }
    func stopLoading() { request?.cancel(); request = nil; spinner.stopAnimating() }
    override func prepareForReuse() {
        super.prepareForReuse()
        stopLoading(); representedID = nil; photoView.image = nil; retry.isHidden = true
        retryAction = nil; accessibilityActivateAction = nil
    }
}
