import Photos
import UIKit

struct LibraryPhoto: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date?
    let isScreenshot: Bool
    let isLivePhoto: Bool
}

struct LibraryGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let count: Int
    let canAdd: Bool
    let canRemove: Bool
    let canRename: Bool
    let canDelete: Bool
    var isSystem = false
    var isEditable: Bool { canAdd || canRemove || canRename || canDelete }
}

struct LibrarySnapshot: Sendable {
    var photos: [LibraryPhoto]
    var groups: [LibraryGroup]
}

enum PhotoLibraryFailure: LocalizedError {
    case unavailable, notEditable, imageUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: return "照片不可访问或已被移除。 / Photo is unavailable."
        case .notEditable: return "此相册不支持这项修改。 / This album cannot be edited."
        case .imageUnavailable: return "图片加载失败，请检查网络后重试。 / Could not load image. Please retry."
        }
    }
}

@MainActor
protocol PhotoLibraryService: AnyObject {
    var authorization: PHAuthorizationStatus { get }
    var onChange: (() -> Void)? { get set }
    func requestAccess() async -> PHAuthorizationStatus
    func preheat(ids: [String])
    func snapshot() async -> LibrarySnapshot
    func photos(in groupID: String) async -> [LibraryPhoto]
    func image(id: String, size: CGSize, progress: @escaping (Double) -> Void) async throws -> UIImage
    func imageData(id: String, progress: @escaping (Double) -> Void) async throws -> Data
    func createGroup(title: String, photoIDs: [String]) async throws
    func renameGroup(id: String, title: String) async throws
    func deleteGroup(id: String) async throws
    func deleteGroupAndPhotos(id: String) async throws -> [String]
    func addPhotos(_ ids: [String], to groupID: String) async throws
    func removePhotos(_ ids: [String], from groupID: String) async throws
    func deletePhotos(_ ids: [String]) async throws
}

/// A PhotoKit callback may race cancellation, or deliver multiple representations.
private final class PhotoRequest<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var requestID: PHImageRequestID?
    private let manager: PHImageManager
    init(manager: PHImageManager) { self.manager = manager }
    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func setID(_ id: PHImageRequestID) {
        lock.lock(); requestID = id
        let finished = result != nil
        lock.unlock()
        if finished { manager.cancelImageRequest(id) }
    }
    func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: value)
    }
    func cancel() {
        finish(.failure(CancellationError()))
        lock.lock(); let id = requestID; lock.unlock()
        if let id { manager.cancelImageRequest(id) }
    }
}

@MainActor
final class SystemPhotoLibraryService: NSObject, PhotoLibraryService, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?
    private let manager = PHCachingImageManager()
    private var cachedIDs: Set<String> = []
    func preheat(ids: [String]) {
        let next = Set(ids)
        guard next != cachedIDs else { return }
        let removed = PHAsset.fetchAssets(withLocalIdentifiers: Array(cachedIDs.subtracting(next)), options: nil)
        let added = PHAsset.fetchAssets(withLocalIdentifiers: Array(next.subtracting(cachedIDs)), options: nil)
        var old: [PHAsset] = []; var fresh: [PHAsset] = []
        removed.enumerateObjects { asset, _, _ in old.append(asset) }
        added.enumerateObjects { asset, _, _ in fresh.append(asset) }
        let size = CGSize(width: 360, height: 360)
        let options = PHImageRequestOptions(); options.resizeMode = .fast; options.deliveryMode = .highQualityFormat
        manager.stopCachingImages(for: old, targetSize: size, contentMode: .aspectFit, options: options)
        manager.startCachingImages(for: fresh, targetSize: size, contentMode: .aspectFit, options: options)
        cachedIDs = next
    }
    var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in self?.onChange?() }
    }
    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    nonisolated private static func fetchPhotos(group: PHAssetCollection? = nil) -> [LibraryPhoto] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = group.map { PHAsset.fetchAssets(in: $0, options: options) } ?? PHAsset.fetchAssets(with: options)
        var photos: [LibraryPhoto] = []
        result.enumerateObjects { asset, _, _ in
            photos.append(LibraryPhoto(id: asset.localIdentifier, date: asset.creationDate,
                                       isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                                       isLivePhoto: asset.mediaSubtypes.contains(.photoLive)))
        }
        return photos
    }
    func snapshot() async -> LibrarySnapshot {
        await Task.detached(priority: .userInitiated) {
            let photos = Self.fetchPhotos()
            var groups: [LibraryGroup] = []
            for type in [PHAssetCollectionType.album, .smartAlbum] {
                let result = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
                result.enumerateObjects { group, _, _ in
                    guard group.assetCollectionSubtype != .smartAlbumAllHidden,
                          group.assetCollectionSubtype != .albumCloudShared else { return }
                    let editable = group.assetCollectionType == .album
                    let options = PHFetchOptions()
                    options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                    groups.append(LibraryGroup(id: group.localIdentifier, title: group.localizedTitle ?? "Album",
                                               count: PHAsset.fetchAssets(in: group, options: options).count,
                                               canAdd: editable && group.canPerform(.addContent), canRemove: editable && group.canPerform(.removeContent),
                                               canRename: editable && group.canPerform(.rename), canDelete: editable && group.canPerform(.delete), isSystem: group.assetCollectionType == .smartAlbum))
                }
            }
            return LibrarySnapshot(photos: photos, groups: groups)
        }.value
    }
    func photos(in groupID: String) async -> [LibraryPhoto] {
        await Task.detached(priority: .userInitiated) {
            guard let group = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [groupID], options: nil).firstObject else { return [] }
            return Self.fetchPhotos(group: group)
        }.value
    }
    private func asset(_ id: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { throw PhotoLibraryFailure.unavailable }
        return asset
    }
    private func group(_ id: String, operation: PHCollectionEditOperation) throws -> PHAssetCollection {
        guard let group = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
              group.assetCollectionType == .album, group.assetCollectionSubtype != .albumCloudShared,
              group.canPerform(operation) else { throw PhotoLibraryFailure.notEditable }
        return group
    }
    func image(id: String, size: CGSize, progress: @escaping (Double) -> Void) async throws -> UIImage {
        let asset = try asset(id)
        let request = PhotoRequest<UIImage>(manager: manager)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.attach(continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = size == PHImageManagerMaximumSize ? .none : .fast
                options.isNetworkAccessAllowed = true
                options.progressHandler = { value, _, _, _ in Task { @MainActor in progress(value) } }
                request.setID(manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true { request.finish(.failure(CancellationError())); return }
                    if let error = info?[PHImageErrorKey] as? Error { request.finish(.failure(error)); return }
                    guard (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                    if let image { request.finish(.success(image)) }
                    else { request.finish(.failure(PhotoLibraryFailure.imageUnavailable)) }
                })
            }
        } onCancel: { request.cancel() }
    }
    func imageData(id: String, progress: @escaping (Double) -> Void) async throws -> Data {
        let asset = try asset(id)
        let request = PhotoRequest<Data>(manager: manager)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.attach(continuation)
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                options.progressHandler = { value, _, _, _ in Task { @MainActor in progress(value) } }
                request.setID(manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error { request.finish(.failure(error)) }
                    else if let data { request.finish(.success(data)) }
                    else { request.finish(.failure(PhotoLibraryFailure.imageUnavailable)) }
                })
            }
        } onCancel: { request.cancel() }
    }
    private func change(_ block: @escaping () -> Void) async throws {
        try await PHPhotoLibrary.shared().performChanges(block)
    }
    func createGroup(title: String, photoIDs: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: photoIDs, options: nil)
        try await change {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if assets.count > 0 { request.addAssets(assets) }
        }
    }
    func renameGroup(id: String, title: String) async throws {
        let group = try group(id, operation: .rename)
        try await change { PHAssetCollectionChangeRequest(for: group)?.title = title }
    }
    func deleteGroup(id: String) async throws {
        let group = try group(id, operation: .delete)
        try await change { PHAssetCollectionChangeRequest.deleteAssetCollections([group] as NSArray) }
    }
    func deleteGroupAndPhotos(id: String) async throws -> [String] {
        let group = try group(id, operation: .delete)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: group, options: options)
        var canDeleteAll = true
        var ids: [String] = []
        assets.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
            if !asset.canPerform(.delete) { canDeleteAll = false }
        }
        guard canDeleteAll else { throw PhotoLibraryFailure.notEditable }
        // A single PhotoKit transaction: cancellation/failure keeps both album
        // and originals. Images shared with other albums are library originals.
        try await change {
            if assets.count > 0 { PHAssetChangeRequest.deleteAssets(assets) }
            PHAssetCollectionChangeRequest.deleteAssetCollections([group] as NSArray)
        }
        return ids
    }
    func addPhotos(_ ids: [String], to groupID: String) async throws {
        let group = try group(groupID, operation: .addContent)
        let current = PHAsset.fetchAssets(in: group, options: nil)
        var existing = Set<String>()
        current.enumerateObjects { asset, _, _ in existing.insert(asset.localIdentifier) }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids.filter { !existing.contains($0) }, options: nil)
        guard assets.count > 0 else { return }
        try await change { PHAssetCollectionChangeRequest(for: group)?.addAssets(assets) }
    }
    func removePhotos(_ ids: [String], from groupID: String) async throws {
        let group = try group(groupID, operation: .removeContent)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await change { PHAssetCollectionChangeRequest(for: group)?.removeAssets(assets) }
    }
    func deletePhotos(_ ids: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { throw PhotoLibraryFailure.unavailable }
        try await change { PHAssetChangeRequest.deleteAssets(assets) }
    }
}
