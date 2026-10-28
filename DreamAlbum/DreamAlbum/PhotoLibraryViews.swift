import SwiftUI
import Photos

// The selected visual: matte dark surfaces, photographic content, quiet mint actions.
enum LibraryStyle {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.067)
    static let surface = Color(red: 0.105, green: 0.115, blue: 0.12)
    static let mint = Color(red: 0.70, green: 0.86, blue: 0.79)
    static let coral = Color(red: 0.91, green: 0.52, blue: 0.50)
}

private struct LibraryScreenActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var libraryScreenActive: Bool {
        get { self[LibraryScreenActiveKey.self] }
        set { self[LibraryScreenActiveKey.self] = newValue }
    }
}

struct LibraryThumbnail: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.libraryScreenActive) private var screenActive
    let id: String
    var large = false
    var hero = false
    var fit = false
    var onLoaded: (Bool) -> Void = { _ in }
    @State private var image: UIImage?
    @State private var failed = false
    @State private var progress = 0.0
    @State private var attempt = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LibraryStyle.surface
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: large || fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if failed {
                    Button { attempt += 1 } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text(AlbumCopy.pick(store.appLanguage, "重试", "Retry")).font(.caption)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(AlbumCopy.pick(store.appLanguage, "图片加载失败，重试", "Image unavailable. Retry"))
                } else {
                    ProgressView(value: progress > 0 ? progress : nil).frame(maxWidth: 80)
                }
            }
            .task(id: "\(id)-\(large)-\(hero)-\(attempt)-\(screenActive)") {
                image = nil; failed = false; progress = 0; onLoaded(false)
                guard screenActive else { return }
                do {
                    let loaded = try await library.service.image(id: id, size: large ? CGSize(width: 1600, height: 2000) : (hero ? CGSize(width: 1200, height: 800) : CGSize(width: 360, height: 360))) { progress = $0 }
                    try Task.checkCancellation()
                    image = loaded; onLoaded(true)
                } catch is CancellationError { }
                catch { failed = true; onLoaded(false) }
            }
            .onDisappear { image = nil; onLoaded(false) }
        }
        .clipped()
    }
}

struct LibraryPermissionView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        ContentUnavailableView {
            Label(c("访问你的照片", "Your photo library"), systemImage: "photo.on.rectangle")
        } description: {
            Text(library.authorization == .restricted
                 ? c("系统限制了照片访问。已有梦想画册仍可使用。", "Photo access is restricted. Your dream albums are still available.")
                 : c("允许访问照片，即可整理、分组和制作梦想画册。已有画册不受影响。", "Allow access to organize photos and create dream albums. Existing albums remain available."))
        } actions: {
            if library.authorization == .notDetermined {
                Button(c("允许访问照片", "Allow photo access")) { Task { await library.activate() } }
            } else if library.authorization != .restricted {
                Button(c("打开系统设置", "Open Settings")) { openPhotoSettings() }
            }
        }
    }
}

@MainActor
func openPhotoSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

@MainActor
func manageLimitedPhotos() {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    guard var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
    while let presented = controller.presentedViewController { controller = presented }
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
}

struct LimitedPhotosBanner: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    var body: some View {
        if library.authorization == .limited {
            VStack(alignment: .leading, spacing: 6) {
                Text(AlbumCopy.pick(store.appLanguage, "仅显示获准访问的照片与可访问的相册", "Showing permitted photos and accessible albums only")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(AlbumCopy.pick(store.appLanguage, "管理可访问照片", "Manage selection")) { manageLimitedPhotos() }
                    Spacer()
                    Button(AlbumCopy.pick(store.appLanguage, "完整访问", "Full access")) { openPhotoSettings() }
                }.font(.caption)
            }.padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}

private enum LibraryDestination: String, Identifiable {
    case groups, dreams
    var id: String { rawValue }
}

struct PhotoBrowserView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    var group: LibraryGroup? = nil
    var onPick: (([String]) -> Void)? = nil
    var scopeIDs: Set<String>? = nil
    var scopeTitle: String? = nil
    @State private var groupPhotoIDs: Set<String> = []
    @State private var month = ""
    @State private var screenshotsOnly = false
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var preview: LibraryPhoto?
    @State private var showReview = false
    @State private var showPending = false
    @State private var destination: LibraryDestination?
    @State private var addPhotos = false
    @State private var showFilters = false
    @State private var filterReviewIDs: [String]?
    @Environment(\.libraryScreenActive) private var screenActive
    @Environment(\.dismiss) private var dismiss

    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    private var source: [LibraryPhoto] {
        library.photos.filter { photo in (group == nil || groupPhotoIDs.contains(photo.id)) && (scopeIDs?.contains(photo.id) ?? true) }
    }
    private var allReviewed: Bool { !filtered.isEmpty && filtered.allSatisfy { library.session.reviewed.contains($0.id) } }
    private var filtered: [LibraryPhoto] {
        source.filter { (!screenshotsOnly || $0.isScreenshot) && (month.isEmpty || Self.monthKey($0.date) == month) }
    }
    private var orderedSelection: [String] { filtered.filter { selection.contains($0.id) }.map(\.id) }
    private var months: [String] { Array(Set(source.map { Self.monthKey($0.date) })).sorted(by: >) }
    private static func monthKey(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
    private func monthLabel(_ key: String) -> String {
        if key == "unknown" { return c("日期未知", "Unknown date") }
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return c("\(parts[0])年\(Int(parts[1]) ?? 1)月", key)
    }

    var body: some View {
        VStack(spacing: 0) {
            LimitedPhotosBanner()
            if !library.hasAccess { LibraryPermissionView() }
            else {
                filters
                if library.isLoading && library.photos.isEmpty { ProgressView().frame(maxHeight: .infinity) }
                else if filtered.isEmpty {
                    ContentUnavailableView(c("暂无照片", "No photos"), systemImage: "photo", description: Text(c("更换筛选条件，或在照片库中添加照片。", "Change the filters or add photos to your library.")))
                } else {
                    photoGrid
                }
            }
        }
        .background(LibraryStyle.background)
        .navigationTitle(browserTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(LibraryStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { browserToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting && onPick == nil { selectionToolbar }
        }
        .task { await library.activate() }
        .task(id: "\(group?.id ?? "all")-\(library.revision)") {
            if let group { groupPhotoIDs = Set(await library.service.photos(in: group.id).map(\.id)) }
            selection.formIntersection(library.availableIDs)
        }
        .onChange(of: month) { _, _ in selection = [] }
        .onChange(of: screenshotsOnly) { _, _ in selection = [] }
        .fullScreenCover(item: $preview) { photo in PhotoPreview(photo: photo, photos: filtered) }
        .sheet(isPresented: $addPhotos) {
            NavigationStack {
                PhotoBrowserView(onPick: { ids in
                    guard let group else { return }
                    Task { if await library.perform({ try await library.service.addPhotos(ids, to: group.id) }) { addPhotos = false } }
                }).libraryErrorAlert()
            }
        }
        .sheet(isPresented: $showFilters, onDismiss: {
            if let ids = filterReviewIDs {
                filterReviewIDs = nil; selecting = false; selection = []
                library.restartReview(ids); showReview = true
            }
        }) { filterSheet }
        .sheet(isPresented: $showPending) { NavigationStack { PendingPhotosView() } }
        .fullScreenCover(isPresented: $showReview) { NavigationStack { PhotoReviewView() } }
        .fullScreenCover(item: $destination) { destination in
            NavigationStack {
                switch destination {
                case .groups: GroupDestinationView(ids: orderedSelection)
                case .dreams: DreamImportView(ids: orderedSelection)
                }
            }
        }

    }
    private var browserTitle: String {
        selecting || onPick != nil ? c("已选择 \(selection.count) 张", "\(selection.count) selected") : group?.title ?? scopeTitle ?? c("全部照片", "All photos")
    }
    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(browserTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityIdentifier("library.selection.title")
        }
        if onPick != nil {
            ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { dismiss() } }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if onPick != nil {
                Button(c("添加 \(selection.count)", "Add \(selection.count)")) { onPick?(orderedSelection) }
                    .disabled(selection.isEmpty || library.isChanging)
            } else {
                Button(selecting ? c("完成", "Done") : c("选择", "Select")) { selecting.toggle(); selection = [] }
                if !selecting {
                    Button(allReviewed ? c("重新整理", "Review again") : c("整理", "Review")) { beginReview() }.disabled(filtered.isEmpty)
                }
                if group?.canAdd == true {
                    Button { addPhotos = true } label: { Image(systemName: "plus") }.accessibilityLabel(c("添加照片", "Add photos"))
                }
            }
        }
    }
    private var filters: some View {
        HStack(spacing: 12) {
            Text(screenshotsOnly ? c("仅屏幕截图", "Screenshots only") : (month.isEmpty ? c("全部月份", "All dates") : monthLabel(month)))
                .foregroundStyle(.secondary)
            Spacer()
            Button { showFilters = true } label: {
                Label(c("筛选", "Filter"), systemImage: "line.3.horizontal.decrease").frame(minHeight: 44)
            }.accessibilityIdentifier("library.filters")
            if onPick == nil {
                Button { showPending = true } label: { Label(c("待删 \(library.session.pendingDeletion.count)", "Pending \(library.session.pendingDeletion.count)"), systemImage: "tray").frame(minHeight: 44) }
                    .accessibilityIdentifier("library.pending")
            }
        }.font(.subheadline).buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 2)
    }
    private var filterSheet: some View {
        NavigationStack {
            List {
                Section(c("内容", "Content")) {
                    filterTypeRow(title: c("照片与截图", "Photos and screenshots"), icon: "photo.on.rectangle", screenshots: false)
                    filterTypeRow(title: c("仅屏幕截图", "Screenshots only"), icon: "viewfinder", screenshots: true)
                }.listRowBackground(LibraryStyle.surface)
                Section(c("日期", "Date")) {
                    NavigationLink {
                        PhotoMonthFilterView(months: months.map { (key: $0, title: monthLabel($0)) }, selection: $month, language: store.appLanguage)
                    } label: {
                        HStack {
                            Label(c("月份", "Month"), systemImage: "calendar")
                            Spacer(minLength: 12)
                            Text(month.isEmpty ? c("全部月份", "All months") : monthLabel(month))
                                .foregroundStyle(.secondary)
                        }.frame(minHeight: 32)
                    }.accessibilityIdentifier("filter.month")
                }.listRowBackground(LibraryStyle.surface)
                if onPick == nil {
                    Section {
                        Button {
                            filterReviewIDs = filtered.map(\.id); showFilters = false
                        } label: {
                            Label(c("重新整理当前范围", "Review this scope again"), systemImage: "arrow.clockwise")
                                .frame(minHeight: 32)
                        }.foregroundStyle(LibraryStyle.mint).disabled(filtered.isEmpty)
                    } footer: {
                        Text(c("当前范围 \(filtered.count) 张", "\(filtered.count) photos in this scope"))
                    }.listRowBackground(LibraryStyle.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle(c("筛选照片", "Filter photos")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(c("重置", "Reset")) { month = ""; screenshotsOnly = false }
                        .disabled(month.isEmpty && !screenshotsOnly).accessibilityIdentifier("filter.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(c("完成", "Done")) { showFilters = false }.accessibilityIdentifier("filter.done")
                }
            }
        }
        .presentationDetents([.height(480), .large])
        .presentationDragIndicator(.visible)
    }
    private func filterTypeRow(title: String, icon: String, screenshots: Bool) -> some View {
        Button { screenshotsOnly = screenshots } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 24)
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 12)
                if screenshotsOnly == screenshots {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(LibraryStyle.mint)
                }
            }.frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier(screenshots ? "filter.screenshots" : "filter.all")
            .accessibilityAddTraits(screenshotsOnly == screenshots ? .isSelected : [])
    }
    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selecting || onPick != nil ? c("横滑或双指拖动可多选", "Swipe across or drag with two fingers to select") : c("\(filtered.count) 张", "\(filtered.count) photos"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if selecting || onPick != nil {
                    Button(selection.count == filtered.count ? c("取消全选", "Deselect all") : c("全选", "Select all")) {
                        selection = selection.count == filtered.count ? [] : Set(filtered.map(\.id))
                    }.font(.subheadline).frame(minHeight: 44)
                }
            }.frame(height: 48).padding(.horizontal, 20)
            NativePhotoGrid(photos: filtered, service: library.service, pending: library.session.pendingDeletion,
                            language: store.appLanguage, active: screenActive, picking: onPick != nil,
                            selecting: $selecting, selection: $selection,
                            onOpen: { preview = $0 }, onPreheat: { library.preheat(around: $0) },
                            onBack: group == nil && onPick == nil ? { dismiss() } : nil)
        }
    }
    private var selectionToolbar: some View {
        HStack(spacing: 16) {
            if group?.canRemove == true {
                Menu {
                    Button(c("加入分组", "Add to album"), systemImage: "folder.badge.plus") { destination = .groups }
                    Button(c("移出分组", "Remove from album"), systemImage: "folder.badge.minus") { removeSelectionFromGroup() }
                } label: { Label(c("分组", "Group"), systemImage: "folder.badge.plus") }
                    .disabled(selection.isEmpty).accessibilityIdentifier("library.action.groups")
            } else {
                Button { destination = .groups } label: { Label(c("分组", "Group"), systemImage: "folder.badge.plus") }
                    .disabled(selection.isEmpty).accessibilityIdentifier("library.action.groups")
            }
            Spacer(minLength: 0)
            Button { destination = .dreams } label: { Label(c("画册", "Dream album"), systemImage: "book") }.accessibilityIdentifier("library.action.dreams").disabled(selection.isEmpty)
            Spacer(minLength: 0)
            Button { library.mark(orderedSelection); selection = [] } label: {
                Label(c("待删", "Pending"), systemImage: "tray")
            }.accessibilityIdentifier("library.action.pending").disabled(selection.isEmpty)
        }
        .font(.subheadline).padding(20).frame(minHeight: 56)
        .background(LibraryStyle.surface).disabled(library.isChanging)
    }
    private func removeSelectionFromGroup() {
        guard let group else { return }
        let ids = orderedSelection
        Task { if await library.perform({ try await library.service.removePhotos(ids, from: group.id) }) { selection = [] } }
    }
    private func beginReview() {
        if allReviewed { library.restartReview(filtered.map(\.id)) }
        else { library.resumeReview(filtered.map(\.id)) }
        showReview = true
    }
}

private struct PhotoMonthFilterView: View {
    let months: [(key: String, title: String)]
    @Binding var selection: String
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                row(key: "", title: AlbumCopy.pick(language, "全部月份", "All months"))
                ForEach(months, id: \.key) { month in row(key: month.key, title: month.title) }
            }.listRowBackground(LibraryStyle.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
        .background(LibraryStyle.background)
        .navigationTitle(AlbumCopy.pick(language, "月份", "Month")).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LibraryStyle.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
    private func row(key: String, title: String) -> some View {
        Button { selection = key; dismiss() } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection == key { Image(systemName: "checkmark").foregroundStyle(LibraryStyle.mint) }
            }.frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == key ? .isSelected : [])
    }
}

struct PhotoPreview: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var library: PhotoLibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.returnToPhotoHome) private var returnToPhotoHome
    let items: [LibraryPhoto]
    @State private var index = 0
    @State private var loaded = false
    @State private var swiping = false
    @State private var destination: LibraryDestination?
    private var photo: LibraryPhoto? { items.dropFirst(index).first { library.photoByID[$0.id] != nil } }
    private var nextPhoto: LibraryPhoto? {
        guard let photo, let position = items.firstIndex(where: { $0.id == photo.id }) else { return nil }
        return items.dropFirst(position + 1).first { library.photoByID[$0.id] != nil }
    }
    init(photo: LibraryPhoto, photos: [LibraryPhoto] = []) {
        if let start = photos.firstIndex(where: { $0.id == photo.id }) { items = Array(photos[start...]) }
        else { items = [photo] }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !library.hasAccess { LibraryPermissionView() }
                else if let photo {
                    NativePhotoZoom(id: photo.id, service: library.service, language: store.appLanguage, nextID: nextPhoto?.id,
                                    onWillSwipe: { commitSwipe(photo.id, delete: $0) },
                                    onSwipe: { _ in advance(photo.id) }, onLoaded: { loaded = $0 })
                        .accessibilityAction(named: c("移至待删", "Mark for deletion")) { decide(photo.id, delete: true) }
                        .accessibilityAction(named: c("留在相册", "Keep photo")) { decide(photo.id, delete: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LibraryStyle.background)
            .navigationTitle(photo?.isLivePhoto == true ? "Live Photo · " + c("静态预览", "Still preview") : c("照片", "Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { dismiss() } } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Text(c("左滑待删 · 右滑保留", "Swipe left to mark · right to keep"))
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                    HStack {
                        Button { destination = .groups } label: { Label(c("分组", "Group"), systemImage: "folder.badge.plus") }.accessibilityIdentifier("preview.groups")
                        Spacer()
                        Button { destination = .dreams } label: { Label(c("画册", "Dream album"), systemImage: "book") }
                        Spacer()
                        Button {
                            guard let photo else { return }
                            if library.session.pendingDeletion.contains(photo.id) { library.unmark(photo.id) }
                            else { decide(photo.id, delete: true) }
                        } label: { Label(photo.map { library.session.pendingDeletion.contains($0.id) } == true ? c("取消待删", "Unmark") : c("待删", "Pending"), systemImage: "tray") }
                            .disabled(!loaded).accessibilityIdentifier("preview.pending")
                    }.font(.subheadline).padding(20).background(LibraryStyle.surface).disabled(photo == nil || swiping)
                }.background(LibraryStyle.background)
            }
            .fullScreenCover(item: $destination) { destination in
                if let photo { NavigationStack {
                    switch destination {
                    case .groups: GroupDestinationView(ids: [photo.id])
                    case .dreams: DreamImportView(ids: [photo.id])
                    }
                } }
            }
        }
        .onChange(of: photo?.id) { _, id in
            if id == nil && library.hasAccess { finish() }
        }
        .preferredColorScheme(.dark)
    }
    private func advance(_ id: String) {
        guard photo?.id == id, let position = items.firstIndex(where: { $0.id == id }) else { swiping = false; return }
        loaded = false; swiping = false; index = position + 1
    }
    private func commitSwipe(_ id: String, delete: Bool) -> Bool {
        guard loaded, !swiping, photo?.id == id else { return false }
        library.decide(id, delete: delete)
        loaded = false; swiping = true
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        return true
    }
    private func decide(_ id: String, delete: Bool) {
        if commitSwipe(id, delete: delete) { advance(id) }
    }
    private func finish() { dismiss(); returnToPhotoHome() }
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
}

struct PhotoReviewView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.returnToPhotoHome) private var returnToPhotoHome
    @State private var loaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translation = CGSize.zero
    @State private var exitingID: String?
    @State private var transitionTask: Task<Void, Never>?
    @State private var cardWidth: CGFloat = 400
    @State private var showPending = false
    @State private var destination: LibraryDestination?
    private var current: String? { exitingID ?? library.session.queue.first { !library.session.reviewed.contains($0) && library.photoByID[$0] != nil } }
    private var finished: Bool { library.hasAccess && !library.isLoading && current == nil }
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel(c("关闭整理", "Close review"))
                Spacer()
                Text(c("整理照片", "Review photos")).font(.headline)
                Spacer()
                Text("\(min(library.session.completedCount + (current == nil ? 0 : 1), library.session.queue.count)) / \(library.session.queue.count)").font(.subheadline.monospacedDigit()).frame(minWidth: 44)
            }.buttonStyle(.plain).padding(.horizontal, 16)
            if !library.hasAccess { LibraryPermissionView() }
            else if let id = current {
                GeometryReader { geometry in
                    LibraryThumbnail(id: id, large: true, onLoaded: { if current == id { loaded = $0 } })
                        .accessibilityIdentifier("review.photo." + id)
                        .accessibilityValue(exitingID != nil ? c("正在切换", "Changing") : loaded ? c("已加载", "Ready") : c("加载中", "Loading"))
                        .id(id).clipShape(RoundedRectangle(cornerRadius: 12))
                        .offset(x: translation.width)
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(max(-6, min(6, translation.width / 40)))))
                        .opacity(exitingID != nil && reduceMotion ? 0 : 1)
                        .overlay(alignment: .top) {
                            if abs(translation.width) > 35 {
                                Text(translation.width < 0 ? c("移至待删", "Mark for deletion") : c("留在相册", "Keep photo"))
                                    .font(.headline).padding(12).background(.black.opacity(0.8), in: Capsule()).padding(16)
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 12).onChanged { value in
                            if loaded && exitingID == nil && abs(value.translation.width) > abs(value.translation.height) {
                                translation = CGSize(width: value.translation.width, height: 0)
                            }
                        }.onEnded { value in
                            if loaded && exitingID == nil && PhotoSwipeGesture.commits(translation: value.translation, velocity: value.velocity, width: geometry.size.width) {
                                decide(id, delete: value.translation.width < 0)
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88)) { translation = .zero }
                            }
                        })
                        .onChange(of: geometry.size.width, initial: true) { _, width in cardWidth = width }
                        .accessibilityAction(named: c("移至待删", "Mark for deletion")) { if loaded { decide(id, delete: true) } }
                        .accessibilityAction(named: c("留在相册", "Keep photo")) { if loaded { decide(id, delete: false) } }
                }.padding(.horizontal, 12).padding(.top, 8)
                Text(c("左滑待删 · 右滑保留", "Swipe left to mark · right to keep")).font(.caption).foregroundStyle(.secondary).padding(.vertical, 14)
            } else {
                ContentUnavailableView(c("整理完成", "Review complete"), systemImage: "checkmark", description: Text(c("可在待删清单中删除原图。", "Open the pending list to delete originals.")))
            }
            Divider()
            HStack {
                Button { let previous = current; library.undo(); if current != previous { loaded = false } } label: { Label(c("撤销", "Undo"), systemImage: "arrow.uturn.backward") }.disabled(library.session.history.isEmpty).keyboardShortcut("z", modifiers: .command)
                Spacer()
                Menu {
                    Button(c("加入分组", "Add to album"), systemImage: "folder.badge.plus") { destination = .groups }.accessibilityIdentifier("review.destination.groups")
                    Button(c("加入梦想画册", "Add to dream album"), systemImage: "book") { destination = .dreams }
                } label: { Label(c("加入分组", "Add to album"), systemImage: "folder") }.disabled(current == nil).accessibilityIdentifier("review.groups")
                Spacer()
                Button { showPending = true } label: { Label(c("待删 \(library.session.pendingDeletion.count)", "Pending \(library.session.pendingDeletion.count)"), systemImage: "tray") }
                    .foregroundStyle(LibraryStyle.mint).frame(minHeight: 44).accessibilityIdentifier("review.pending")
            }.font(.subheadline).buttonStyle(.plain).padding(.horizontal, 24).frame(minHeight: 60).padding(.bottom, 4).disabled(exitingID != nil)
        }
        .background(LibraryStyle.background).navigationTitle(c("整理照片", "Review photos")).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            transitionTask?.cancel(); exitingID = nil; translation = .zero
        }
        .onChange(of: finished, initial: true) { _, complete in
            if complete { dismiss(); returnToPhotoHome() }
        }
        .sheet(isPresented: $showPending) { NavigationStack { PendingPhotosView() } }
        .fullScreenCover(item: $destination) { target in
            if let current { NavigationStack {
                switch target {
                case .groups: GroupDestinationView(ids: [current])
                case .dreams: DreamImportView(ids: [current])
                }
            } }
        }
        // Keyboard equivalents stay available without adding visible controls.
        .background {
            HStack {
                Button("Mark") { if let current { decide(current, delete: true) } }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Keep") { if let current { decide(current, delete: false) } }.keyboardShortcut(.rightArrow, modifiers: [])
            }.disabled(!loaded || exitingID != nil || showPending || destination != nil)
                .frame(width: 0, height: 0).clipped().opacity(0).accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
    }
    private func decide(_ id: String, delete: Bool) {
        guard loaded, exitingID == nil, current == id else { return }
        // Persist the decision at release. The outgoing card remains visible
        // only for the animation, so closing the page cannot lose the decision.
        exitingID = id
        library.decide(id, delete: delete)
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        withAnimation(.easeIn(duration: reduceMotion ? 0.08 : 0.18)) {
            translation = CGSize(width: reduceMotion ? 0 : (delete ? -1 : 1) * cardWidth * 1.15, height: 0)
        }
        transitionTask?.cancel()
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 180))
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { loaded = false; translation = .zero; exitingID = nil }
        }
    }
}

struct PendingPhotosView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleteError: String?
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        List {
            if library.session.pendingDeletion.count > library.pendingPhotos.count {
                Section { Text(c("不可访问的照片保留待删状态。", "Inaccessible photos remain pending.")) }
            }
            Section(c("待删 \(library.session.pendingDeletion.count) 张", "\(library.session.pendingDeletion.count) pending")) {
                ForEach(library.pendingPhotos) { photo in
                    HStack(spacing: 14) {
                        LibraryThumbnail(id: photo.id).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(photo.date?.formatted(date: .abbreviated, time: .omitted) ?? c("日期未知", "Unknown date"))
                            if photo.isLivePhoto { Text("Live Photo").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button(c("取消待删", "Unmark")) { library.unmark(photo.id) }.buttonStyle(.borderless)
                    }
                }
            }
            if !library.session.pendingDeletion.isEmpty {
                Button(c("清空待删清单", "Clear pending list")) { library.clearPending() }
            }
        }
        .navigationTitle(c("待删清单", "Pending deletions")).navigationBarTitleDisplayMode(.inline)
        .disabled(library.isChanging)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { dismiss() }.disabled(library.isChanging) } }
        .safeAreaInset(edge: .bottom) {
            Button(role: .destructive) {
                Task { if await library.deletePending(onError: { deleteError = $0.localizedDescription }) { dismiss() } }
            } label: {
                HStack {
                    if library.isChanging { ProgressView() }
                    Text(c("删除 \(library.pendingPhotos.count) 张原图", "Delete \(library.pendingPhotos.count) originals"))
                }.frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.bordered).tint(LibraryStyle.coral).padding(16).background(LibraryStyle.background)
                .disabled(library.pendingPhotos.isEmpty || library.isChanging)
        }
        .alert(c("删除失败", "Deletion failed"), isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button(c("好", "OK")) { deleteError = nil }
        } message: { Text(deleteError ?? "") }
        .preferredColorScheme(.dark)
    }
}

private struct LibraryErrorAlert: ViewModifier {
    @State private var visible = false
    @Environment(\.libraryScreenActive) private var screenActive
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    func body(content: Content) -> some View {
        content.alert(AlbumCopy.pick(store.appLanguage, "操作失败", "Operation failed"), isPresented: Binding(get: { library.error != nil && screenActive && visible }, set: { if !$0 && screenActive && visible { library.error = nil } })) {
            Button(AlbumCopy.pick(store.appLanguage, "好", "OK")) { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
extension View {
    func libraryErrorAlert() -> some View { modifier(LibraryErrorAlert()) }
}
