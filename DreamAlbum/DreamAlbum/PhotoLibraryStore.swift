import Photos
import SwiftUI

@MainActor
final class PhotoLibraryStore: ObservableObject {
    let service: any PhotoLibraryService
    @Published private(set) var authorization: PHAuthorizationStatus
    @Published private(set) var photos: [LibraryPhoto] = []
    @Published private(set) var groups: [LibraryGroup] = []
    @Published private(set) var session: PhotoReviewSession
    @Published private(set) var revision = 0
    private(set) var photoByID: [String: LibraryPhoto] = [:]
    private var photoIndices: [String: Int] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isChanging = false
    @Published var error: String?
    private let defaults: UserDefaults
    private let sessionKey = "dream_album.photo_review.v1"
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var accessRequest: Task<PHAuthorizationStatus, Never>?

    init(service: (any PhotoLibraryService)? = nil, defaults: UserDefaults = .standard) {
        let service = service ?? SystemPhotoLibraryService()
        self.service = service
        self.defaults = defaults
        authorization = service.authorization
        session = defaults.data(forKey: sessionKey).flatMap { try? JSONDecoder().decode(PhotoReviewSession.self, from: $0) } ?? PhotoReviewSession()
        service.onChange = { [weak self] in self?.scheduleRefresh() }
    }
    var hasAccess: Bool { authorization == .authorized || authorization == .limited }
    var availableIDs: Set<String> { Set(photoByID.keys) }
    func preheat(around id: String) {
        guard let index = photoIndices[id] else { return }
        let range = max(0, index - 6)..<min(photos.count, index + 13)
        service.preheat(ids: photos[range].map(\.id))
    }
    var pendingPhotos: [LibraryPhoto] { photos.filter { session.pendingDeletion.contains($0.id) } }
    func copy(_ chinese: String, _ english: String, language: AppLanguage) -> String {
        AlbumCopy.pick(language, chinese, english)
    }
    func activate() async {
        authorization = service.authorization
        if authorization == .notDetermined {
            if accessRequest == nil { accessRequest = Task { await service.requestAccess() } }
            authorization = await accessRequest!.value
            accessRequest = nil
        }
        await refresh()
    }
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
    func refresh() async {
        generation += 1
        let ticket = generation
        authorization = service.authorization
        guard hasAccess else { photos = []; photoByID = [:]; photoIndices = [:]; groups = []; revision += 1; isLoading = false; return }
        isLoading = true
        let queriedAuthorization = authorization
        let snapshot = await service.snapshot()
        guard ticket == generation, !Task.isCancelled else { return }
        // Authorization can change while the query is running.
        authorization = service.authorization
        guard hasAccess else { photos = []; photoByID = [:]; photoIndices = [:]; groups = []; revision += 1; isLoading = false; return }
        // A limited snapshot must never reconcile the pending list as a full library.
        guard authorization == queriedAuthorization else {
            isLoading = false
            scheduleRefresh()
            return
        }
        photos = snapshot.photos
        groups = snapshot.groups
        photoByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        photoIndices = Dictionary(uniqueKeysWithValues: photos.enumerated().map { ($0.element.id, $0.offset) })
        revision += 1
        if authorization == .authorized { session.reconcile(availableIDs: availableIDs); persist() }
        isLoading = false
    }
    func startReview(_ ids: [String], restart: Bool = false) { session.start(ids, restart: restart); persist() }
    func resumeReview(_ ids: [String]) { session.resume(ids); persist() }
    func restartReview(_ ids: [String]) { session.restartScope(ids); persist() }
    func decide(_ id: String, delete: Bool) { session.decide(id, delete: delete); persist() }
    func mark(_ ids: [String]) { for id in ids { session.decide(id, delete: true) }; persist() }
    func undo() { session.undo(); persist() }
    func unmark(_ id: String) { session.unmark(id); persist() }
    func clearPending() { session.clearPending(); persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: sessionKey) }
    }
    @discardableResult
    func perform(onError: ((Error) -> Void)? = nil, _ operation: () async throws -> Void) async -> Bool {
        guard !isChanging else { return false }
        isChanging = true
        defer { isChanging = false }
        do { try await operation(); await refresh(); return true }
        catch is CancellationError { return false }
        catch {
            let systemError = error as NSError
            if systemError.domain == PHPhotosErrorDomain && systemError.code == PHPhotosError.Code.userCancelled.rawValue { return false }
            if let onError { onError(error) } else { self.error = error.localizedDescription }
            return false
        }
    }
    func deleteGroupAndPhotos(_ id: String) async {
        var deleted: [String] = []
        let success = await perform { deleted = try await service.deleteGroupAndPhotos(id: id) }
        // Limited snapshots cannot reconcile the whole library. Only prune the
        // exact assets returned by the successful transaction.
        if success { session.removeDeleted(Set(deleted)); persist() }
    }
    @discardableResult
    func deletePending(onError: ((Error) -> Void)? = nil) async -> Bool {
        let ids = pendingPhotos.map(\.id)
        guard !ids.isEmpty else { return false }
        let success = await perform(onError: onError) { try await service.deletePhotos(ids) }
        if success { session.removeDeleted(Set(ids)); persist() }
        return success
    }
}

/// Owns temporary copies until a synchronous dream-store commit transfers ownership.
@MainActor
final class DreamPhotoImport: ObservableObject {
    @Published private(set) var ready: [(id: String, path: String)] = []
    @Published private(set) var failed: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var closed = false
    private var committed = false

    func run(ids: [String], service: any PhotoLibraryService) {
        guard !isRunning, !closed else { return }
        isRunning = true
        failed = []
        error = nil
        progress = 0
        task = Task {
            defer { isRunning = false }
            for (index, id) in ids.enumerated() {
                guard !Task.isCancelled, !closed else { break }
                do {
                    let data = try await service.imageData(id: id) { [weak self] fraction in
                        self?.progress = (Double(index) + fraction) / Double(max(ids.count, 1))
                    }
                    try Task.checkCancellation()
                    let path = try await Task.detached(priority: .utility) { try ImageLibrary.saveImageData(data) }.value
                    if Task.isCancelled || closed {
                        Self.remove(path)
                        break
                    }
                    ready.append((id, path))
                } catch is CancellationError { break }
                catch { failed.append(id); self.error = error.localizedDescription }
                progress = Double(index + 1) / Double(max(ids.count, 1))
            }
        }
    }
    func commit(to dreamID: UUID?, title: String, store: DreamStore) -> Bool {
        guard !closed, !isRunning, !ready.isEmpty else { return false }
        if let dreamID {
            guard var dream = store.dreams.first(where: { $0.id == dreamID }) else { return false }
            // Sample paths are placeholders, not the user's album photos.
            dream.imagePaths.removeAll { $0.hasPrefix("sample:") }
            dream.imagePaths.append(contentsOf: ready.map(\.path))
            store.update(dream)
        } else {
            guard store.canCreateDream, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            store.addDream(title: title, visionText: "", imagePaths: ready.map(\.path))
        }
        committed = true
        closed = true
        return true
    }
    func close() {
        closed = true
        task?.cancel()
        if !committed { for item in ready { Self.remove(item.path) }; ready = [] }
    }
    private static func remove(_ path: String) {
        guard let url = ImageLibrary.imageURL(for: path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
