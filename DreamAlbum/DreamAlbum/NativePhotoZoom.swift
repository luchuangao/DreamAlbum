import SwiftUI
import UIKit

enum PhotoSwipeGesture {
    static func commits(translation: CGSize, velocity: CGSize = .zero, width: CGFloat) -> Bool {
        guard abs(translation.width) > abs(translation.height) else { return false }
        let distance = min(140, max(80, width * 0.22))
        let flick = abs(translation.width) >= 44 && abs(velocity.width) >= 500
            && abs(velocity.width) > abs(velocity.height) && translation.width * velocity.width > 0
        return abs(translation.width) > distance || flick
    }
}

/// UIScrollView supplies the familiar pinch, double-tap and pan behavior,
/// including centering a photo smaller than the available screen.
struct NativePhotoZoom: UIViewRepresentable {
    @Environment(\.albumTheme) private var theme
    let id: String
    let service: any PhotoLibraryService
    let language: AppLanguage
    var nextID: String? = nil
    var onWillSwipe: ((Bool) -> Bool)? = nil
    var onSwipe: ((Bool) -> Void)? = nil
    var onLoaded: ((Bool) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let view = PhotoZoomScrollView()
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "library.preview"
        view.accessibilityValue = "100%"
        view.photo.accessibilityLabel = AlbumCopy.pick(language, "照片", "Photo")
        view.retry.accessibilityLabel = AlbumCopy.pick(language, "图片加载失败，重试", "Image unavailable. Retry")
        return view
    }
    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        view.retry.tintColor = UIColor(theme.accent)
        let coordinator = context.coordinator
        view.onSwipe = onSwipe
        view.onWillSwipe = onWillSwipe
        view.onLoaded = onLoaded
        view.readyLabel = AlbumCopy.pick(language, "已加载", "Ready")
        view.loadingLabel = AlbumCopy.pick(language, "加载中", "Loading")
        view.transitionLabel = AlbumCopy.pick(language, "正在切换", "Changing")
        view.photo.accessibilityIdentifier = "preview.photo." + id
        if coordinator.id != id {
            coordinator.id = id
            coordinator.load(view, id: id, service: service)
            view.onRetry = { [weak view, weak coordinator] in
                guard let view, let coordinator else { return }
                coordinator.load(view, id: id, service: service)
            }
        }
        coordinator.preloadNext(nextID, service: service)
    }
    static func dismantleUIView(_ view: PhotoZoomScrollView, coordinator: Coordinator) {
        coordinator.cancel()
        view.cancelTransition()
        view.onRetry = nil
        view.onWillSwipe = nil
        view.onSwipe = nil
        view.onLoaded = nil
    }
    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var id: String?
        var request: Task<Void, Never>?
        private var upcomingID: String?
        private var preload: Task<Void, Never>?
        private var cached: (id: String, image: UIImage)?
        func cancel() {
            id = nil; upcomingID = nil
            request?.cancel(); preload?.cancel(); cached = nil
        }
        @discardableResult
        func preloadNext(_ next: String?, service: any PhotoLibraryService) -> Task<Void, Never>? {
            guard upcomingID != next else { return preload }
            preload?.cancel(); cached = nil; upcomingID = next
            guard let next else { return nil }
            preload = Task { [weak self] in
                do {
                    try Task.checkCancellation()
                    let image = try await service.image(id: next, size: CGSize(width: 1600, height: 2000)) { _ in }
                    try Task.checkCancellation()
                    guard let self, upcomingID == next else { return }
                    cached = (next, image)
                } catch { /* Prefetch failure never changes a decision or hides foreground retry. */ }
            }
            return preload
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? PhotoZoomScrollView)?.photo }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? PhotoZoomScrollView)?.centerPhoto()
            scrollView.accessibilityValue = "\(Int((scrollView.zoomScale * 100).rounded()))%"
        }
        func load(_ view: PhotoZoomScrollView, id: String, service: any PhotoLibraryService) {
            request?.cancel()
            view.resetPhoto()
            view.retry.isHidden = true
            view.spinner.startAnimating()
            view.progress.isHidden = true
            let ready = cached?.id == id ? cached?.image : nil
            if ready != nil { cached = nil }
            request = Task { [weak self, weak view] in
                do {
                    let image: UIImage
                    if let ready { image = ready }
                    else {
                        image = try await service.image(id: id, size: CGSize(width: 1600, height: 2000)) { [weak view] value in
                            view?.progress.isHidden = false
                            view?.progress.text = "\(Int(value * 100))%"
                        }
                    }
                    try Task.checkCancellation()
                    guard self?.id == id, let view else { return }
                    view.setPhoto(image)
                    view.spinner.stopAnimating()
                    view.progress.isHidden = true
                } catch is CancellationError { }
                catch {
                    guard !Task.isCancelled, self?.id == id, let view else { return }
                    view.spinner.stopAnimating()
                    view.progress.isHidden = true
                    view.retry.isHidden = false
                }
            }
        }
    }
}

final class PhotoZoomScrollView: UIScrollView, UIGestureRecognizerDelegate {
    let photo = UIImageView()
    let spinner = UIActivityIndicatorView(style: .large)
    let progress = UILabel()
    let retry = UIButton(type: .system)
    var onRetry: (() -> Void)?
    var onSwipe: ((Bool) -> Void)?
    var onWillSwipe: ((Bool) -> Bool)?
    var onLoaded: ((Bool) -> Void)?
    var readyLabel = "Ready"
    var loadingLabel = "Loading"
    var transitionLabel = "Changing"
    private var reviewing = false
    private var transitioning = false
    private lazy var reviewPan = UIPanGestureRecognizer(target: self, action: #selector(swipePhoto(_:)))
    private var fittedSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photo.contentMode = .scaleAspectFit
        photo.isAccessibilityElement = true
        addSubview(photo)
        [spinner, progress, retry].forEach(addSubview)
        progress.textColor = .secondaryLabel
        progress.font = .preferredFont(forTextStyle: .caption1)
        progress.textAlignment = .center
        retry.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)), for: .normal)
        retry.tintColor = .tintColor
        retry.isHidden = true
        retry.addTarget(self, action: #selector(retryPhoto), for: .touchUpInside)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomPhoto(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        reviewPan.maximumNumberOfTouches = 1
        reviewPan.delegate = self
        addGestureRecognizer(reviewPan)
        panGestureRecognizer.require(toFail: reviewPan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func cancelTransition() {
        transitioning = false
        layer.removeAllAnimations()
        transform = .identity; alpha = 1
    }
    func resetPhoto() {
        cancelTransition()
        reviewing = false
        setZoomScale(1, animated: false)
        transform = .identity
        photo.image = nil
        photo.accessibilityValue = loadingLabel
        onLoaded?(false)
    }
    func setPhoto(_ image: UIImage) {
        photo.image = image; fittedSize = .zero; setNeedsLayout()
        photo.accessibilityValue = readyLabel
        onLoaded?(true)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === reviewPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = reviewPan.velocity(in: self)
        return !transitioning && onSwipe != nil && photo.image != nil && zoomScale <= 1.01 && abs(velocity.x) > abs(velocity.y)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A second finger hands control to native zooming, cancelling the
        // one-finger review pan without blocking the scroll view's pinch.
        (gestureRecognizer === reviewPan && otherGestureRecognizer === pinchGestureRecognizer)
            || (otherGestureRecognizer === reviewPan && gestureRecognizer === pinchGestureRecognizer)
    }
    @objc private func swipePhoto(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .began, .changed:
            reviewing = true
            transform = CGAffineTransform(translationX: translation.x, y: 0)
        case .ended:
            reviewing = false
            let velocity = gesture.velocity(in: superview)
            let delete = translation.x < 0
            if zoomScale <= 1.01 && PhotoSwipeGesture.commits(
                translation: CGSize(width: translation.x, height: translation.y),
                velocity: CGSize(width: velocity.x, height: velocity.y), width: bounds.width),
               onWillSwipe?(delete) != false {
                transitioning = true
                photo.accessibilityValue = transitionLabel
                let reduced = UIAccessibility.isReduceMotionEnabled
                UIView.animate(withDuration: reduced ? 0.08 : 0.18, delay: 0, options: [.curveEaseIn]) {
                    if reduced { self.alpha = 0 }
                    else { self.transform = CGAffineTransform(translationX: (delete ? -1 : 1) * self.bounds.width * 1.15, y: 0) }
                } completion: { [weak self] finished in
                    guard let self, finished, transitioning else { return }
                    transitioning = false
                    onSwipe?(delete)
                }
            } else { returnToCenter() }
        default:
            reviewing = false
            returnToCenter()
        }
    }
    private func returnToCenter() {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.08 : 0.28, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = .identity
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize, bounds.width > 0, bounds.height > 0, let image = photo.image {
            fittedSize = bounds.size
            setZoomScale(1, animated: false)
            let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
            photo.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * ratio, height: image.size.height * ratio))
            contentSize = photo.bounds.size
            centerPhoto()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
        centerPhoto()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        spinner.center = center
        progress.frame = CGRect(x: center.x - 50, y: center.y + 30, width: 100, height: 30)
        retry.frame = CGRect(x: center.x - 40, y: center.y - 40, width: 80, height: 80)
    }
    func centerPhoto() {
        guard !reviewing else { return }
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - photo.frame.height) / 2), left: max(0, (bounds.width - photo.frame.width) / 2), bottom: max(0, (bounds.height - photo.frame.height) / 2), right: max(0, (bounds.width - photo.frame.width) / 2))
    }
    @objc private func retryPhoto() { onRetry?() }
    @objc private func zoomPhoto(_ gesture: UITapGestureRecognizer) {
        guard photo.image != nil, !transitioning else { return }
        if zoomScale > 1.01 { setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: photo)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
