import XCTest
import UserNotifications
import Photos
import UIKit
@testable import DreamAlbum

@MainActor
final class FakePhotoLibrary: PhotoLibraryService {
    var authorization: PHAuthorizationStatus = .authorized
    var onChange: (() -> Void)?
    var authorizationAfterSnapshot: PHAuthorizationStatus?
    var state = LibrarySnapshot(photos: [LibraryPhoto(id: "a", date: Date(), isScreenshot: false, isLivePhoto: true), LibraryPhoto(id: "b", date: nil, isScreenshot: true, isLivePhoto: false)], groups: [])
    var deletedGroups: [String] = []
    var deletionRequests = 0
    var deletionError: Error?
    var deletionFails = false
    var failedImages: Set<String> = []
    var deleted: [String] = []
    var imageRequests = 0
    var imageSizes: [CGSize] = []
    var previewFailures: Set<String> = []
    var previewDelay: Duration = .zero
    var imageCancellations = 0
    var onImageRequest: ((String) -> Void)?
    var liveRequests = 0
    var liveDelay: Duration = .zero
    var liveCancellations = 0
    var onLiveRequest: (() -> Void)?
    var dataRequests = 0
    func preheat(ids: [String]) { }
    func requestAccess() async -> PHAuthorizationStatus { authorization }
    func snapshot() async -> LibrarySnapshot {
        let result = state
        if let next = authorizationAfterSnapshot { authorization = next; authorizationAfterSnapshot = nil }
        return result
    }
    func photos(in groupID: String) async -> [LibraryPhoto] { state.photos }
    func image(id: String, size: CGSize, progress: @escaping (Double) -> Void) async throws -> UIImage {
        imageRequests += 1
        imageSizes.append(size)
        onImageRequest?(id)
        if previewDelay != .zero {
            do { try await Task.sleep(for: previewDelay) }
            catch { imageCancellations += 1; throw error }
        }
        if previewFailures.contains(id) { throw PhotoLibraryFailure.imageUnavailable }
        return UIImage(systemName: "photo")!
    }
    func livePhoto(id: String, size: CGSize) async throws -> PHLivePhoto {
        liveRequests += 1
        onLiveRequest?()
        if liveDelay != .zero {
            do { try await Task.sleep(for: liveDelay) }
            catch { liveCancellations += 1; throw error }
        }
        throw PhotoLibraryFailure.imageUnavailable
    }
    func imageData(id: String, progress: @escaping (Double) -> Void) async throws -> Data {
        dataRequests += 1
        if failedImages.contains(id) { throw PhotoLibraryFailure.imageUnavailable }
        progress(1)
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    func createGroup(title: String, photoIDs: [String]) async throws { }
    func renameGroup(id: String, title: String) async throws { }
    func deleteGroup(id: String) async throws { deletedGroups.append(id); state.groups.removeAll { $0.id == id } }
    func deleteGroupAndPhotos(id: String) async throws -> [String] {
        guard state.groups.contains(where: { $0.id == id && $0.canDelete }) else { throw PhotoLibraryFailure.notEditable }
        let ids = state.photos.map(\.id)
        try await deletePhotos(ids)
        try await deleteGroup(id: id)
        return ids
    }
    func addPhotos(_ ids: [String], to groupID: String) async throws { }
    func removePhotos(_ ids: [String], from groupID: String) async throws { }
    func deletePhotos(_ ids: [String]) async throws {
        deletionRequests += 1
        if let deletionError { throw deletionError }
        if deletionFails { throw PhotoLibraryFailure.notEditable }
        deleted = ids
        state.photos.removeAll { ids.contains($0.id) }
    }
}

final class PhotoReviewSessionTests: XCTestCase {
    func testDecisionsUndoAndPersistence() throws {
        var session = PhotoReviewSession()
        session.start(["a", "b", "a"])
        XCTAssertEqual(session.queue, ["a", "b"])
        session.decide("a", delete: true)
        session.decide("b", delete: false)
        XCTAssertNil(session.currentID)
        XCTAssertEqual(session.pendingDeletion, ["a"])
        let restored = try JSONDecoder().decode(PhotoReviewSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
        session.undo(); XCTAssertEqual(session.currentID, "b")
        session.undo(); XCTAssertEqual(session.currentID, "a"); XCTAssertTrue(session.pendingDeletion.isEmpty)
    }
    func testNewRoundRetainsPendingAndDeduplicates() {
        var session = PhotoReviewSession()
        session.start(["a", "b"]); session.decide("a", delete: true); session.decide("a", delete: true)
        XCTAssertEqual(session.history.count, 1)
        session.start(["c"]); XCTAssertEqual(session.queue, ["a", "b"])
        session.start(["c"], restart: true)
        XCTAssertEqual(session.pendingDeletion, ["a"])
        XCTAssertEqual(session.queue, ["c"])
    }
    func testUnmarkAndClearCannotBeUndoneIntoDeletion() {
        var session = PhotoReviewSession()
        session.decide("a", delete: true); session.decide("a", delete: false)
        session.decide("a", delete: true); session.unmark("a"); session.undo()
        XCTAssertTrue(session.pendingDeletion.isEmpty)
        session.decide("a", delete: true); session.clearPending(); session.undo()
        XCTAssertTrue(session.pendingDeletion.isEmpty)
    }
    func testExternalDeletionReconcilesAndUndoNeverRestoresMissingAsset() {
        var session = PhotoReviewSession()
        session.start(["a", "b"]); session.decide("a", delete: true)
        session.reconcile(availableIDs: ["b"])
        XCTAssertEqual(session.queue, ["b"]); XCTAssertTrue(session.pendingDeletion.isEmpty)
        session.undo(); XCTAssertEqual(session.currentID, "b")
    }
    func testTenThousandPhotosKeepOnlyMetadata() {
        var session = PhotoReviewSession()
        let ids = (0..<10_000).map(String.init)
        session.start(ids)
        for id in ids.prefix(100) { session.decide(id, delete: false) }
        XCTAssertEqual(session.currentID, "100")
        XCTAssertEqual(session.completedCount, 100)
        XCTAssertLessThan(try! JSONEncoder().encode(session).count, 150_000)
    }
    func testLegacyDreamDecodingAndRoundTrip() throws {
        let old = Data(#"{"title":"旧梦想","imagePaths":["existing.jpg"]}"#.utf8)
        let dream = try JSONDecoder().decode(Dream.self, from: old)
        XCTAssertEqual(dream.title, "旧梦想"); XCTAssertEqual(dream.imagePaths, ["existing.jpg"])
        XCTAssertTrue(dream.logs.isEmpty); XCTAssertFalse(dream.isArchived)
        XCTAssertEqual(try JSONDecoder().decode(Dream.self, from: JSONEncoder().encode(dream)), dream)
    }
}

@MainActor
final class PhotoLibraryStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() async throws {
        suite = "PhotoLibraryTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }
    func testDeleteGroupWithOriginalsFailureAndCancellationKeepBoth() async {
        let service = FakePhotoLibrary()
        service.state.groups = [LibraryGroup(id: "g", title: "Test", count: 2, canAdd: true, canRemove: true, canRename: true, canDelete: true)]
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.mark(["a"])
        service.deletionFails = true
        await store.deleteGroupAndPhotos("g")
        XCTAssertEqual(store.photos.count, 2); XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(store.session.pendingDeletion, ["a"]); XCTAssertTrue(service.deletedGroups.isEmpty)
        store.error = nil; service.deletionFails = false
        service.deletionError = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.userCancelled.rawValue)
        await store.deleteGroupAndPhotos("g")
        XCTAssertNil(store.error); XCTAssertEqual(store.groups.count, 1); XCTAssertEqual(store.photos.count, 2)
        XCTAssertEqual(store.session.pendingDeletion, ["a"])
    }
    func testDeleteGroupWithOriginalsPrunesKnownIDsUnderLimitedAccess() async {
        let service = FakePhotoLibrary(); service.authorization = .limited
        service.state.groups = [LibraryGroup(id: "g", title: "Test", count: 2, canAdd: true, canRemove: true, canRename: true, canDelete: true)]
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.resumeReview(["a", "b"]); store.mark(["a"])
        await store.deleteGroupAndPhotos("g")
        XCTAssertTrue(store.photos.isEmpty); XCTAssertTrue(store.groups.isEmpty)
        XCTAssertEqual(Set(service.deleted), ["a", "b"]); XCTAssertEqual(service.deletedGroups, ["g"])
        XCTAssertTrue(store.session.pendingDeletion.isEmpty); XCTAssertTrue(store.session.reviewed.isEmpty)
        XCTAssertTrue(store.session.queue.isEmpty); XCTAssertTrue(store.session.history.isEmpty)
    }
    func testMarkNeverDeletesAndFailureRetainsQueue() async {
        let service = FakePhotoLibrary()
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.mark(["a"])
        XCTAssertTrue(service.deleted.isEmpty)
        service.deletionFails = true
        let failed = await store.deletePending()
        XCTAssertFalse(failed)
        XCTAssertEqual(store.session.pendingDeletion, ["a"])
        XCTAssertNotNil(store.error)
        service.deletionFails = false
        let succeeded = await store.deletePending()
        XCTAssertTrue(succeeded)
        XCTAssertTrue(store.session.pendingDeletion.isEmpty)
        XCTAssertEqual(service.deleted, ["a"])
        XCTAssertEqual(store.photos.map(\.id), ["b"])
    }
    func testLimitedAndDeniedAccessNeverDiscardPending() async {
        let service = FakePhotoLibrary()
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.mark(["a"])
        service.authorization = .limited; service.state.photos = []
        await store.refresh(); XCTAssertEqual(store.session.pendingDeletion, ["a"])
        await store.deletePending(); XCTAssertTrue(service.deleted.isEmpty)
        service.authorization = .denied
        await store.refresh(); XCTAssertFalse(store.hasAccess)
        XCTAssertEqual(store.session.pendingDeletion, ["a"])
        XCTAssertTrue(store.photoByID.isEmpty)
        let relaunched = PhotoLibraryStore(service: service, defaults: defaults)
        XCTAssertEqual(relaunched.session.pendingDeletion, ["a"])
    }
    func testPermissionUpgradeDuringQueryNeverTreatsLimitedSnapshotAsComplete() async throws {
        let service = FakePhotoLibrary()
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.mark(["a"])
        let full = service.state
        service.authorization = .limited
        service.state.photos.removeAll { $0.id == "a" }
        service.authorizationAfterSnapshot = .authorized
        await store.refresh()
        XCTAssertEqual(store.session.pendingDeletion, ["a"])
        service.state = full
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(store.session.pendingDeletion, ["a"])
        XCTAssertEqual(store.photos.count, 2)
    }
    func testCompleteAccessReconcilesExternalChanges() async {
        let service = FakePhotoLibrary()
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.startReview(["a", "b"]); store.mark(["a"])
        service.state.photos.removeAll { $0.id == "a" }
        await store.refresh()
        XCTAssertTrue(store.session.pendingDeletion.isEmpty)
        XCTAssertEqual(store.session.currentID, "b")
    }
    func testOperationFailureIsReportedAndUnlocked() async {
        let store = PhotoLibraryStore(service: FakePhotoLibrary(), defaults: defaults)
        let result = await store.perform { throw PhotoLibraryFailure.notEditable }
        XCTAssertFalse(result); XCTAssertFalse(store.isChanging); XCTAssertNotNil(store.error)
    }
    func testImportFailureRetryAndCancellationCleansTemporaryCopies() async throws {
        let service = FakePhotoLibrary(); service.failedImages = ["b"]
        let importer = DreamPhotoImport()
        importer.run(ids: ["a", "b"], service: service)
        while importer.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(importer.ready.count, 1); XCTAssertEqual(importer.failed, ["b"])
        let firstPath = importer.ready[0].path
        XCTAssertTrue(FileManager.default.fileExists(atPath: ImageLibrary.imageURL(for: firstPath)!.path))
        service.failedImages = []
        importer.run(ids: importer.failed, service: service)
        while importer.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(importer.ready.count, 2); XCTAssertTrue(importer.failed.isEmpty)
        let paths = importer.ready.map(\.path)
        importer.close()
        for path in paths { XCTAssertFalse(FileManager.default.fileExists(atPath: ImageLibrary.imageURL(for: path)!.path)) }
    }
    func testDreamCommitKeepsIndependentCopyAfterOriginalDeletion() async throws {
        let service = FakePhotoLibrary()
        let dreams = DreamStore()
        let before = dreams.dreams
        defer { dreams.dreams = before }
        let importer = DreamPhotoImport()
        importer.run(ids: ["a"], service: service)
        for _ in 0..<300 {
            if !importer.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(importer.isRunning)
        let path = try XCTUnwrap(importer.ready.first?.path)
        let url = try XCTUnwrap(ImageLibrary.imageURL(for: path))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(importer.commit(to: nil, title: "独立画册", store: dreams))
        importer.close()
        try await service.deletePhotos(["a"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(dreams.activeDreams.first?.imagePaths, [path])
        XCTAssertNotNil(UIImage(contentsOfFile: url.path))
    }
    func testImportReplacesSampleCoverAndCommitsOnlyOnce() async throws {
        let service = FakePhotoLibrary(); let dreams = DreamStore(); let before = dreams.dreams
        defer { dreams.dreams = before }
        let target = Dream(title: "示例测试", visionText: "", imagePaths: ["sample:marathon"])
        dreams.dreams = [target]
        let importer = DreamPhotoImport(); importer.run(ids: ["a"], service: service)
        while importer.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        let path = try XCTUnwrap(importer.ready.first?.path)
        defer { if let url = ImageLibrary.imageURL(for: path) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(importer.commit(to: target.id, title: "", store: dreams))
        XCTAssertEqual(dreams.activeDreams.first?.imagePaths, [path])
        XCTAssertFalse(importer.commit(to: target.id, title: "", store: dreams))
        importer.close()
        XCTAssertNotNil(UIImage(contentsOfFile: ImageLibrary.imageURL(for: path)!.path))
    }
    func testImportAppendsWithoutRemovingUserPhotos() async throws {
        let service = FakePhotoLibrary(); let dreams = DreamStore(); let before = dreams.dreams
        defer { dreams.dreams = before }
        let target = Dream(title: "已有照片", visionText: "", imagePaths: ["existing-user-photo.jpg"])
        dreams.dreams = [target]
        let importer = DreamPhotoImport(); importer.run(ids: ["b"], service: service)
        while importer.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        let path = try XCTUnwrap(importer.ready.first?.path)
        defer { if let url = ImageLibrary.imageURL(for: path) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(importer.commit(to: target.id, title: "", store: dreams))
        importer.close()
        XCTAssertEqual(dreams.dreams.first?.imagePaths, ["existing-user-photo.jpg", path])
    }
    func testLargeLibrarySnapshotDoesNotRequestImages() async {
        let service = FakePhotoLibrary()
        service.state.photos = (0..<10_000).map { LibraryPhoto(id: String($0), date: nil, isScreenshot: false, isLivePhoto: false) }
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate()
        XCTAssertEqual(store.photos.count, 10_000)
        XCTAssertEqual(store.photoByID.count, 10_000)
        XCTAssertEqual(service.imageRequests, 0)
        XCTAssertEqual(service.dataRequests, 0)
        store.startReview(store.photos.map(\.id))
        XCTAssertEqual(store.session.currentID, "0")
    }
    func testImmediateImportCancelNeverLeavesCopies() async throws {
        let importer = DreamPhotoImport()
        importer.run(ids: ["a"], service: FakePhotoLibrary()); importer.close()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(importer.ready.isEmpty)
    }
}

final class PhotoSelectionSweepTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e", "f"]
    func testAddingRangeInBothDirectionsAndReversingRestoresBaseline() {
        let sweep = PhotoSelectionSweep(anchor: 2, baseline: ["f"], adds: true)
        XCTAssertEqual(sweep.selection(through: 4, ids: ids), ["c", "d", "e", "f"])
        XCTAssertEqual(sweep.selection(through: 2, ids: ids), ["c", "f"])
        XCTAssertEqual(sweep.selection(through: 0, ids: ids), ["a", "b", "c", "f"])
    }
    func testDeselectRangeNeverRemovesOutsideBaselineAndCanReverse() {
        let sweep = PhotoSelectionSweep(anchor: 1, baseline: ["a", "b", "c", "e"], adds: false)
        XCTAssertEqual(sweep.selection(through: 4, ids: ids), ["a"])
        XCTAssertEqual(sweep.selection(through: 2, ids: ids), ["a", "e"])
        XCTAssertEqual(sweep.selection(through: 1, ids: ids), ["a", "c", "e"])
    }
    func testStaleIndexAfterLibraryChangeLeavesSelectionUntouched() {
        let sweep = PhotoSelectionSweep(anchor: 4, baseline: ["a"], adds: true)
        XCTAssertEqual(sweep.selection(through: 0, ids: ["a"]), ["a"])
        XCTAssertEqual(sweep.selection(through: -1, ids: ids), ["a"])
    }
}

final class DailyInboxTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func photo(_ id: String, _ time: String?, screenshot: Bool = false) -> LibraryPhoto {
        LibraryPhoto(id: id, date: time.map(date), isScreenshot: screenshot, isLivePhoto: false)
    }
    func testLocalDayIncludesBothTypesButExcludesUnknownAndAdjacentDays() {
        let photos = [photo("before", "2026-10-25T15:59:59Z"), photo("p", "2026-10-25T16:00:00Z"), photo("s", "2026-10-26T15:59:59Z", screenshot: true), photo("after", "2026-10-26T16:00:00Z"), photo("unknown", nil)]
        let summary = PhotoDaySummary(date: date("2026-10-26T03:00:00Z"), assets: photos, reviewed: ["s", "before"], calendar: calendar)
        XCTAssertEqual(summary.items.map(\.id), ["p", "s"])
        XCTAssertEqual(summary.photos.map(\.id), ["p"])
        XCTAssertEqual(summary.screenshots.map(\.id), ["s"])
        XCTAssertEqual(summary.completed, 1); XCTAssertEqual(summary.remaining, 1)
        XCTAssertEqual(summary.progress, 0.5)
    }
    func testDSTBoundaryAndNextDayRollover() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let assets = [photo("early", "2026-11-01T07:00:00Z"), photo("late", "2026-11-02T07:59:59Z"), photo("next", "2026-11-02T08:00:00Z")]
        let first = PhotoDaySummary(date: date("2026-11-01T20:00:00Z"), assets: assets, reviewed: ["early"], calendar: c)
        XCTAssertEqual(first.items.map(\.id), ["early", "late"])
        let next = PhotoDaySummary(date: date("2026-11-02T20:00:00Z"), assets: assets, reviewed: ["early"], calendar: c)
        XCTAssertEqual(next.items.map(\.id), ["next"]); XCTAssertEqual(next.completed, 0)
    }
    func testEmptyTodayUsesRecentWeekIncludingScreenshotsAndKeepsProgress() {
        let today = date("2026-10-26T03:00:00Z")
        let assets = [photo("p", "2026-10-25T03:00:00Z"), photo("s", "2026-10-19T16:00:00Z", screenshot: true), photo("old", "2026-10-19T15:59:59Z"), photo("future", "2026-10-27T03:00:00Z"), photo("unknown", nil)]
        let summary = PhotoDaySummary.home(today: today, selectedDay: nil, assets: assets, reviewed: ["s"], calendar: calendar)
        XCTAssertTrue(summary.isRecent)
        XCTAssertEqual(summary.items.map(\.id), ["p", "s"])
        XCTAssertEqual(summary.completed, 1); XCTAssertEqual(summary.remaining, 1)
        XCTAssertEqual(summary.screenshots.map(\.id), ["s"])
        let explicitEmpty = PhotoDaySummary.home(today: today, selectedDay: today, assets: assets, reviewed: [], calendar: calendar)
        XCTAssertFalse(explicitEmpty.isRecent); XCTAssertTrue(explicitEmpty.items.isEmpty)
        let arrivals = assets + [photo("today", "2026-10-26T03:00:00Z")]
        let daily = PhotoDaySummary.home(today: today, selectedDay: nil, assets: arrivals, reviewed: [], calendar: calendar)
        XCTAssertFalse(daily.isRecent); XCTAssertEqual(daily.items.map(\.id), ["today"])
    }
    func testOlderLibraryUsesLatestAccessibleWeekAndUnknownOnlyStaysEmpty() {
        let today = date("2026-10-26T03:00:00Z")
        let assets = [photo("older", "2026-08-01T03:00:00Z"), photo("latest", "2026-08-07T03:00:00Z", screenshot: true), photo("outside", "2026-07-31T03:00:00Z"), photo("unknown", nil)]
        let summary = PhotoDaySummary.home(today: today, selectedDay: nil, assets: assets, reviewed: [], calendar: calendar)
        XCTAssertTrue(summary.isRecent); XCTAssertEqual(summary.items.map(\.id), ["older", "latest"])
        XCTAssertTrue(calendar.isDate(summary.date, inSameDayAs: date("2026-08-07T03:00:00Z")))
        let empty = PhotoDaySummary.home(today: today, selectedDay: nil, assets: [photo("unknown", nil)], reviewed: [], calendar: calendar)
        XCTAssertFalse(empty.isRecent); XCTAssertTrue(empty.items.isEmpty)
    }
    func testContinuationChoosesNearestEarlierUnreviewedDayAndBothTypes() {
        let today = date("2026-10-26T03:00:00Z")
        let assets = [photo("today", "2026-10-26T03:00:00Z"), photo("old", "2026-10-24T03:00:00Z"), photo("p", "2026-10-25T03:00:00Z"), photo("s", "2026-10-25T04:00:00Z", screenshot: true), photo("done", "2026-10-25T05:00:00Z"), photo("future", "2026-10-27T03:00:00Z"), photo("unknown", nil)]
        let batch = PhotoInboxContinuation(before: today, assets: assets, reviewed: ["today", "done"], calendar: calendar)
        XCTAssertEqual(batch?.photos.map(\.id), ["p", "s"])
        XCTAssertTrue(calendar.isDate(batch!.date!, inSameDayAs: date("2026-10-25T03:00:00Z")))
        let next = PhotoInboxContinuation(before: today, assets: assets, reviewed: ["p", "s", "done"], calendar: calendar)
        XCTAssertEqual(next?.photos.map(\.id), ["old"])
    }
    func testContinuationSkipsCompleteHistoryAndOffersUndatedLast() {
        let today = date("2026-10-26T03:00:00Z")
        let assets = [photo("old", "2026-10-20T03:00:00Z"), photo("unknown", nil)]
        let batch = PhotoInboxContinuation(before: today, assets: assets, reviewed: ["old"], calendar: calendar)
        XCTAssertNil(batch?.date); XCTAssertEqual(batch?.photos.map(\.id), ["unknown"])
        XCTAssertNil(PhotoInboxContinuation(before: today, assets: assets, reviewed: ["old", "unknown"], calendar: calendar))
        let arriving = assets + [photo("new", "2026-10-20T05:00:00Z", screenshot: true)]
        XCTAssertEqual(PhotoInboxContinuation(before: today, assets: arriving, reviewed: ["old"], calendar: calendar)?.photos.map(\.id), ["new"])
    }
    func testContinuationRespectsRecentRangeAndLocalDayBoundary() {
        let cutoff = date("2026-10-19T16:00:00Z")
        let assets = [photo("inside", "2026-10-19T16:00:00Z"), photo("before", "2026-10-19T15:59:59Z"), photo("older", "2026-10-18T16:00:00Z")]
        let batch = PhotoInboxContinuation(before: cutoff, assets: assets, reviewed: [], calendar: calendar)
        XCTAssertEqual(Set(batch!.photos.map(\.id)), ["before", "older"])
    }
    func testChangingScopeAndRelaunchPreserveDecisionsAndPending() throws {
        var session = PhotoReviewSession()
        session.resume(["p", "s"]); session.decide("p", delete: false); session.decide("s", delete: true)
        session.resume(["tomorrow"]); session.decide("tomorrow", delete: false)
        session = try JSONDecoder().decode(PhotoReviewSession.self, from: JSONEncoder().encode(session))
        session.resume(["s", "p", "new", "s"])
        XCTAssertEqual(session.queue, ["s", "p", "new"]); XCTAssertEqual(session.currentID, "new")
        XCTAssertEqual(session.completedCount, 2); XCTAssertEqual(session.pendingDeletion, ["s"])
        XCTAssertTrue(session.reviewed.contains("tomorrow"))
        session.restartScope(["p"])
        XCTAssertFalse(session.reviewed.contains("p")); XCTAssertTrue(session.reviewed.contains("s")); XCTAssertTrue(session.reviewed.contains("tomorrow"))
        XCTAssertEqual(session.pendingDeletion, ["s"])
    }
    func testUndoStaysInCurrentScopeAndReconcilePrunesPastScopeDecisions() {
        var session = PhotoReviewSession()
        session.resume(["p", "s"]); session.decide("p", delete: false); session.decide("s", delete: true)
        session.resume(["s"]); session.undo()
        XCTAssertEqual(session.reviewed, ["p"]); XCTAssertTrue(session.pendingDeletion.isEmpty)
        session.reconcile(availableIDs: ["s"])
        XCTAssertTrue(session.reviewed.isEmpty); XCTAssertTrue(session.history.isEmpty)
    }
    func testEmptyAndCompletedDayAndNewArrivals() {
        let day = date("2026-10-26T03:00:00Z")
        let empty = PhotoDaySummary(date: day, assets: [], reviewed: [], calendar: calendar)
        XCTAssertEqual(empty.progress, 0); XCTAssertEqual(empty.remaining, 0)
        let photos = [photo("a", "2026-10-26T03:00:00Z"), photo("b", "2026-10-26T04:00:00Z", screenshot: true)]
        let complete = PhotoDaySummary(date: day, assets: photos, reviewed: ["a", "b"], calendar: calendar)
        XCTAssertEqual(complete.progress, 1)
        let next = PhotoDaySummary(date: day, assets: photos + [photo("new", "2026-10-26T05:00:00Z")], reviewed: ["a", "b"], calendar: calendar)
        XCTAssertEqual(next.completed, 2); XCTAssertEqual(next.remaining, 1)
    }
    func testReviewSessionFromOldVersionStillLoads() throws {
        let data = Data(#"{"queue":["old"],"reviewed":["old"],"pendingDeletion":[],"history":[]}"#.utf8)
        var session = try JSONDecoder().decode(PhotoReviewSession.self, from: data)
        session.resume(["old", "new"])
        XCTAssertEqual(session.currentID, "new"); XCTAssertEqual(session.completedCount, 1)
    }
}

final class PhotoCalendarTests: XCTestCase {
    func testMonthCountsBothTypesAndExcludesOtherMonthsAndUnknownDates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!; calendar.firstWeekday = 2
        let date = ISO8601DateFormatter().date(from: "2026-10-26T03:00:00Z")!
        let assets = [LibraryPhoto(id: "p", date: date, isScreenshot: false, isLivePhoto: false), LibraryPhoto(id: "s", date: date, isScreenshot: true, isLivePhoto: false), LibraryPhoto(id: "n", date: nil, isScreenshot: true, isLivePhoto: false), LibraryPhoto(id: "old", date: calendar.date(byAdding: .month, value: -1, to: date), isScreenshot: false, isLivePhoto: false)]
        let month = PhotoCalendarMonth(containing: date, assets: assets, calendar: calendar)
        XCTAssertEqual(month.leadingDays, 3); XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(month.days.first { $0.number == 26 }?.count, 2)
        XCTAssertEqual(month.days.reduce(0) { $0 + $1.count }, 2)
    }
    func testReviewStatusReflectsLedgerAndNewArrivals() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let date = ISO8601DateFormatter().date(from: "2026-10-26T03:00:00Z")!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)!
        let assets = [LibraryPhoto(id: "p", date: date, isScreenshot: false, isLivePhoto: false), LibraryPhoto(id: "s", date: date, isScreenshot: true, isLivePhoto: false), LibraryPhoto(id: "old", date: yesterday, isScreenshot: true, isLivePhoto: false)]
        let partial = PhotoCalendarMonth(containing: date, assets: assets, reviewed: ["p", "missing"], calendar: calendar)
        XCTAssertEqual(partial.days[25].reviewedCount, 1); XCTAssertEqual(partial.days[25].state, .partial)
        XCTAssertEqual(partial.days[24].state, .unreviewed); XCTAssertEqual(partial.days[23].state, .empty)
        let completed = PhotoCalendarMonth(containing: date, assets: assets, reviewed: ["p", "s"], calendar: calendar)
        XCTAssertEqual(completed.days[25].state, .complete)
        let arriving = assets + [LibraryPhoto(id: "new", date: date, isScreenshot: false, isLivePhoto: false)]
        let updated = PhotoCalendarMonth(containing: date, assets: arriving, reviewed: ["p", "s"], calendar: calendar)
        XCTAssertEqual(updated.days[25].count, 3); XCTAssertEqual(updated.days[25].state, .partial)
    }
    func testLeapMonthAndDSTDayCounts() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let leap = ISO8601DateFormatter().date(from: "2024-02-15T12:00:00Z")!
        XCTAssertEqual(PhotoCalendarMonth(containing: leap, assets: [], calendar: calendar).days.count, 29)
        let times = ["2026-11-01T07:00:00Z", "2026-11-02T07:59:59Z", "2026-11-02T08:00:00Z"].map { ISO8601DateFormatter().date(from: $0)! }
        let assets = times.enumerated().map { LibraryPhoto(id: String($0.offset), date: $0.element, isScreenshot: false, isLivePhoto: false) }
        let month = PhotoCalendarMonth(containing: times[0], assets: assets, calendar: calendar)
        XCTAssertEqual(month.days.first { $0.number == 1 }?.count, 2)
        XCTAssertEqual(month.days.first { $0.number == 2 }?.count, 1)
    }
    @MainActor
    func testDirectDeleteCallsServiceOnceAndPreservesPendingOnFailure() async {
        let service = FakePhotoLibrary(); service.deletionFails = true
        let defaults = UserDefaults(suiteName: "calendar-delete-" + UUID().uuidString)!
        let store = PhotoLibraryStore(service: service, defaults: defaults)
        await store.activate(); store.mark(["a"])
        await store.deletePending()
        XCTAssertEqual(service.deletionRequests, 1); XCTAssertEqual(store.session.pendingDeletion, ["a"])
        service.deletionFails = false
        await store.deletePending()
        XCTAssertEqual(service.deletionRequests, 2); XCTAssertTrue(store.session.pendingDeletion.isEmpty)
    }
}

@MainActor
final class DeletePresentationTests: XCTestCase {
    func testFailureIsDeliveredOnlyToTheOwningPresenter() async {
        let service = FakePhotoLibrary(); service.deletionFails = true
        let store = PhotoLibraryStore(service: service, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.activate(); store.mark(["a"])
        var errors = 0
        await store.deletePending(onError: { _ in errors += 1 })
        XCTAssertEqual(errors, 1); XCTAssertNil(store.error)
        XCTAssertEqual(store.session.pendingDeletion, ["a"]); XCTAssertFalse(store.isChanging)
    }
    func testPhotoKitCancellationKeepsPendingAndDoesNotShowFailure() async {
        let service = FakePhotoLibrary()
        service.deletionError = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.userCancelled.rawValue)
        let store = PhotoLibraryStore(service: service, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.activate(); store.mark(["a"])
        var errors = 0
        let succeeded = await store.deletePending(onError: { _ in errors += 1 })
        XCTAssertFalse(succeeded)
        XCTAssertEqual(errors, 0); XCTAssertNil(store.error)
        XCTAssertEqual(store.session.pendingDeletion, ["a"]); XCTAssertEqual(store.photos.count, 2)
        XCTAssertFalse(store.isChanging)
    }
}

final class PhotoSwipeGestureTests: XCTestCase {
    func testDownwardDismissalRejectsOtherDirectionsAndTinyDrags() {
        XCTAssertTrue(PhotoSwipeGesture.dismisses(translation: CGSize(width: 12, height: 200)))
        XCTAssertFalse(PhotoSwipeGesture.dismisses(translation: CGSize(width: 12, height: -200)))
        XCTAssertFalse(PhotoSwipeGesture.dismisses(translation: CGSize(width: 240, height: 200)))
        XCTAssertFalse(PhotoSwipeGesture.dismisses(translation: CGSize(width: 200, height: 12)))
        XCTAssertFalse(PhotoSwipeGesture.dismisses(translation: CGSize(width: 0, height: 5)))
    }
    func testShortDownwardDragsCloseWithoutDependingOnReleaseVelocity() {
        XCTAssertTrue(PhotoSwipeGesture.dismisses(translation: CGSize(width: 0, height: 12)))
        XCTAssertTrue(PhotoSwipeGesture.dismisses(translation: CGSize(width: 5, height: 35)))
        XCTAssertTrue(PhotoSwipeGesture.dismisses(translation: CGSize(width: 5, height: 110)))
    }
    func testPhoneAndWideScreenDragsUseReachableDistances() {
        XCTAssertTrue(PhotoSwipeGesture.commits(translation: CGSize(width: -110, height: 10), width: 393))
        XCTAssertTrue(PhotoSwipeGesture.commits(translation: CGSize(width: 180, height: 10), width: 834))
        XCTAssertFalse(PhotoSwipeGesture.commits(translation: CGSize(width: 70, height: 10), width: 834))
    }
    func testShortFlickRequiresDistanceSpeedAndMatchingDirection() {
        XCTAssertTrue(PhotoSwipeGesture.commits(translation: CGSize(width: -60, height: 5), velocity: CGSize(width: -800, height: 20), width: 834))
        XCTAssertFalse(PhotoSwipeGesture.commits(translation: CGSize(width: -20, height: 5), velocity: CGSize(width: -900, height: 20), width: 834))
        XCTAssertFalse(PhotoSwipeGesture.commits(translation: CGSize(width: -60, height: 5), velocity: CGSize(width: 800, height: 20), width: 834))
    }
    func testVerticalPansNeverBecomeReviewDecisions() {
        XCTAssertFalse(PhotoSwipeGesture.commits(translation: CGSize(width: 150, height: 180), velocity: CGSize(width: 900, height: 1100), width: 393))
        XCTAssertFalse(PhotoSwipeGesture.commits(translation: .zero, velocity: .zero, width: 393))
    }
}

@MainActor
final class PreviewLoadingTests: XCTestCase {
    func testMotionFailureKeepsImageAndDecisionsUntouched() async {
        let service = FakePhotoLibrary()
        let loader = NativePhotoZoom.Coordinator(); loader.id = "a"
        let view = PhotoZoomScrollView()
        var swipes = 0; view.onSwipe = { _ in swipes += 1 }
        loader.load(view, id: "a", service: service, isLivePhoto: true)
        await loader.request?.value
        await loader.liveRequest?.value
        XCTAssertNotNil(view.photo.image); XCTAssertTrue(view.retry.isHidden)
        XCTAssertNil(view.motion.livePhoto); XCTAssertEqual(swipes, 0)
        XCTAssertEqual(service.liveRequests, 1)
        view.onLiveRetry?(); await loader.liveRequest?.value
        XCTAssertEqual(service.liveRequests, 2)
        XCTAssertNotNil(view.photo.image)
        loader.cancel()
    }
    func testSwitchingPhotoCancelsMotionAndDoesNotPrefetchMotion() async {
        let service = FakePhotoLibrary(); service.liveDelay = .seconds(5)
        let started = expectation(description: "motion started")
        service.onLiveRequest = { started.fulfill() }
        let loader = NativePhotoZoom.Coordinator(); loader.id = "a"
        let view = PhotoZoomScrollView()
        loader.load(view, id: "a", service: service, isLivePhoto: true)
        await loader.request?.value
        await fulfillment(of: [started], timeout: 2)
        let motion = loader.liveRequest
        await loader.preloadNext("b", service: service)?.value
        XCTAssertEqual(service.liveRequests, 1)
        loader.id = "b"; loader.load(view, id: "b", service: service)
        await loader.request?.value; await motion?.value
        XCTAssertEqual(service.liveCancellations, 1)
        XCTAssertNotNil(view.photo.image); XCTAssertNil(view.motion.livePhoto)
        XCTAssertNil(view.onLiveRetry)
        loader.cancel()
    }
    func testClosingCancelsMotion() async {
        let service = FakePhotoLibrary(); service.liveDelay = .seconds(5)
        let started = expectation(description: "motion started")
        service.onLiveRequest = { started.fulfill() }
        let loader = NativePhotoZoom.Coordinator(); loader.id = "a"
        let view = PhotoZoomScrollView()
        loader.load(view, id: "a", service: service, isLivePhoto: true)
        await loader.request?.value
        await fulfillment(of: [started], timeout: 2)
        loader.cancel(); await loader.liveRequest?.value
        XCTAssertEqual(service.liveCancellations, 1)
        view.resetPhoto()
        XCTAssertNil(view.photo.image); XCTAssertNil(view.motion.livePhoto)
    }
    func testOriginalRequestBypassesSmallerPrefetch() async {
        let service = FakePhotoLibrary()
        let loader = NativePhotoZoom.Coordinator()
        await loader.preloadNext("b", service: service)?.value
        let view = PhotoZoomScrollView()
        loader.id = "b"
        loader.load(view, id: "b", service: service, targetSize: PHImageManagerMaximumSize)
        await loader.request?.value
        XCTAssertEqual(service.imageRequests, 2)
        XCTAssertEqual(service.imageSizes.last, PHImageManagerMaximumSize)
        XCTAssertNotNil(view.photo.image)
        loader.cancel()
    }
    func testOriginalFailureCanRetryAtOriginalSize() async {
        let service = FakePhotoLibrary(); service.previewFailures = ["a"]
        let loader = NativePhotoZoom.Coordinator(); loader.id = "a"
        let view = PhotoZoomScrollView()
        loader.load(view, id: "a", service: service, targetSize: PHImageManagerMaximumSize)
        await loader.request?.value
        XCTAssertFalse(view.retry.isHidden); XCTAssertNil(view.photo.image)
        service.previewFailures = []
        loader.load(view, id: "a", service: service, targetSize: PHImageManagerMaximumSize)
        await loader.request?.value
        XCTAssertTrue(view.retry.isHidden); XCTAssertNotNil(view.photo.image)
        XCTAssertEqual(service.imageSizes, [PHImageManagerMaximumSize, PHImageManagerMaximumSize])
        loader.cancel()
    }
    func testClosingCancelsOriginalDownload() async {
        let service = FakePhotoLibrary(); service.previewDelay = .seconds(5)
        let started = expectation(description: "original started")
        service.onImageRequest = { _ in started.fulfill() }
        let loader = NativePhotoZoom.Coordinator(); loader.id = "a"
        let view = PhotoZoomScrollView()
        loader.load(view, id: "a", service: service, targetSize: PHImageManagerMaximumSize)
        await fulfillment(of: [started], timeout: 2)
        loader.cancel()
        await loader.request?.value
        XCTAssertEqual(service.imageCancellations, 1)
        XCTAssertNil(view.photo.image)
    }
    func testNextImageIsReusedWithoutASecondRequest() async {
        let service = FakePhotoLibrary()
        let loader = NativePhotoZoom.Coordinator()
        await loader.preloadNext("b", service: service)?.value
        let view = PhotoZoomScrollView()
        loader.id = "b"; loader.load(view, id: "b", service: service)
        await loader.request?.value
        XCTAssertEqual(service.imageRequests, 1)
        XCTAssertNotNil(view.photo.image); XCTAssertTrue(view.retry.isHidden)
        loader.cancel()
    }
    func testPrefetchFailureDoesNotPoisonForegroundRetry() async {
        let service = FakePhotoLibrary(); service.previewFailures = ["b"]
        let loader = NativePhotoZoom.Coordinator()
        await loader.preloadNext("b", service: service)?.value
        service.previewFailures = []
        let view = PhotoZoomScrollView()
        loader.id = "b"; loader.load(view, id: "b", service: service)
        await loader.request?.value
        XCTAssertEqual(service.imageRequests, 2)
        XCTAssertNotNil(view.photo.image); XCTAssertTrue(view.retry.isHidden)
        loader.cancel()
    }
    func testClosingCancelsAnInFlightPrefetch() async {
        let service = FakePhotoLibrary(); service.previewDelay = .seconds(5)
        let started = expectation(description: "prefetch started")
        service.onImageRequest = { _ in started.fulfill() }
        let loader = NativePhotoZoom.Coordinator()
        let task = loader.preloadNext("b", service: service)
        await fulfillment(of: [started], timeout: 2)
        loader.cancel()
        await task?.value
        XCTAssertEqual(service.imageCancellations, 1)
    }
}

@MainActor
final class PendingInboxTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!; return c }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func photo(_ id: String, _ text: String?, screenshot: Bool = false) -> LibraryPhoto {
        LibraryPhoto(id: id, date: text.map(date), isScreenshot: screenshot, isLivePhoto: false)
    }
    func testCompletedTodaySkipsToLatestUnreviewedDayAndHidesReviewedMembers() {
        let assets = [photo("today", "2026-10-27T02:00:00Z"), photo("done", "2026-10-26T02:00:00Z"), photo("p", "2026-10-26T03:00:00Z"), photo("s", "2026-10-26T04:00:00Z", screenshot: true), photo("older", "2026-05-01T02:00:00Z")]
        let batch = PhotoInboxBatch(today: date("2026-10-27T05:00:00Z"), selectedDay: nil, assets: assets, reviewed: ["today", "done"], calendar: calendar)
        XCTAssertEqual(batch.items.map(\.id), ["p", "s"])
        XCTAssertEqual(batch.total, 3); XCTAssertEqual(batch.completed, 1)
        XCTAssertEqual(batch.photos.map(\.id), ["p"]); XCTAssertEqual(batch.screenshots.map(\.id), ["s"])
    }
    func testCompletedHistoryNeverRepeatsAndUnknownComesLast() {
        let today = date("2026-10-27T05:00:00Z")
        let assets = [photo("old", "2026-05-01T02:00:00Z"), photo("unknown", nil)]
        let batch = PhotoInboxBatch(today: today, selectedDay: nil, assets: assets, reviewed: ["old"], calendar: calendar)
        XCTAssertNil(batch.date); XCTAssertEqual(batch.items.map(\.id), ["unknown"])
        XCTAssertTrue(PhotoInboxBatch(today: today, selectedDay: nil, assets: assets, reviewed: ["old", "unknown"], calendar: calendar).items.isEmpty)
    }
    func testNewTodayImageTakesPriorityAndFutureDayIsExcluded() {
        let today = date("2026-10-27T05:00:00Z")
        let assets = [photo("new", "2026-10-26T16:01:00Z"), photo("future", "2026-10-27T16:00:00Z"), photo("old", "2026-05-01T02:00:00Z")]
        XCTAssertEqual(PhotoInboxBatch(today: today, selectedDay: nil, assets: assets, reviewed: [], calendar: calendar).items.map(\.id), ["new"])
        XCTAssertEqual(PhotoInboxBatch(today: today, selectedDay: nil, assets: assets, reviewed: ["new"], calendar: calendar).items.map(\.id), ["old"])
    }
    func testSelectedCompletedDayLooksEarlierAndRestartOnlyResetsThatDay() {
        let today = date("2026-10-27T05:00:00Z")
        let selected = date("2026-10-25T05:00:00Z")
        let assets = [photo("today", "2026-10-27T02:00:00Z"), photo("day", "2026-10-25T02:00:00Z"), photo("old", "2026-10-24T02:00:00Z")]
        var session = PhotoReviewSession(); session.resume(assets.map(\.id))
        session.decide("day", delete: true); session.decide("today", delete: false)
        XCTAssertEqual(PhotoInboxBatch(today: today, selectedDay: selected, assets: assets, reviewed: session.reviewed, calendar: calendar).items.map(\.id), ["old"])
        session.restartScope(["day"])
        XCTAssertEqual(PhotoInboxBatch(today: today, selectedDay: selected, assets: assets, reviewed: session.reviewed, calendar: calendar).items.map(\.id), ["day"])
        XCTAssertEqual(session.pendingDeletion, ["day"]); XCTAssertTrue(session.reviewed.contains("today"))
    }
}

@MainActor
final class FakeSortingNotifications: SortingNotificationService {
    var status: UNAuthorizationStatus = .notDetermined
    var grants = true
    var requests = 0
    var scheduled: SortingReminderTime?
    var language: AppLanguage?
    var fails = false
    var onSchedule: (() -> Void)?
    func authorization() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { requests += 1; status = grants ? .authorized : .denied; return grants }
    func schedule(time: SortingReminderTime, language: AppLanguage) async throws {
        if fails { throw NSError(domain: "SortingReminderTests", code: 1) }
        let callback = onSchedule; onSchedule = nil; callback?()
        await Task.yield()
        scheduled = time; self.language = language
    }
    func cancel() { scheduled = nil }
}

@MainActor
final class SortingReminderTests: XCTestCase {
    private var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "sorting-reminder-tests.\(UUID().uuidString)")!
    }
    override func tearDown() { defaults = nil }
    func testDefaultIsOffAt22AndStartupNeverPrompts() async {
        let service = FakeSortingNotifications(); let model = PhotoSortingReminder(defaults: defaults, service: service)
        model.refresh(language: .chinese); await model.waitUntilSynced()
        XCTAssertFalse(model.enabled); XCTAssertEqual(model.time, SortingReminderTime(hour: 22, minute: 0))
        XCTAssertEqual(service.requests, 0); XCTAssertNil(service.scheduled)
    }
    func testEnableCustomTimeLanguageAndPersistenceThenDisable() async {
        let service = FakeSortingNotifications(); let model = PhotoSortingReminder(defaults: defaults, service: service)
        model.setEnabled(true); await model.waitUntilSynced()
        XCTAssertTrue(model.enabled); XCTAssertEqual(service.requests, 1); XCTAssertEqual(service.scheduled, SortingReminderTime())
        let date = Calendar.current.date(bySettingHour: 8, minute: 35, second: 0, of: Date())!
        model.setTime(date); model.refresh(language: .english); await model.waitUntilSynced()
        XCTAssertEqual(service.scheduled, SortingReminderTime(hour: 8, minute: 35)); XCTAssertEqual(service.language, .english)
        let restored = PhotoSortingReminder(defaults: defaults, service: service)
        XCTAssertTrue(restored.enabled); XCTAssertEqual(restored.time, model.time)
        model.setEnabled(false); await model.waitUntilSynced(); XCTAssertNil(service.scheduled)
        XCTAssertFalse(PhotoSortingReminder(defaults: defaults, service: service).enabled)
    }
    func testDeniedPermissionDoesNotAppearEnabledAndRevocationCancels() async {
        let service = FakeSortingNotifications(); service.grants = false
        let model = PhotoSortingReminder(defaults: defaults, service: service)
        model.setEnabled(true); await model.waitUntilSynced()
        XCTAssertFalse(model.enabled); XCTAssertEqual(model.authorization, .denied); XCTAssertNil(service.scheduled)
        service.status = .authorized; model.setEnabled(true); await model.waitUntilSynced()
        XCTAssertNotNil(service.scheduled)
        service.status = .denied; model.refresh(language: .chinese); await model.waitUntilSynced()
        XCTAssertEqual(model.authorization, .denied); XCTAssertNil(service.scheduled)
        XCTAssertEqual(service.requests, 1)
    }
    func testTurningOffDuringSlowScheduleCannotLeaveReminder() async {
        let service = FakeSortingNotifications(); service.status = .authorized
        let model = PhotoSortingReminder(defaults: defaults, service: service)
        service.onSchedule = { model.setEnabled(false) }
        model.setEnabled(true); await model.waitUntilSynced()
        XCTAssertFalse(model.enabled); XCTAssertNil(service.scheduled)
    }
    func testSchedulingFailureCanRetry() async {
        let service = FakeSortingNotifications(); service.status = .authorized; service.fails = true
        let model = PhotoSortingReminder(defaults: defaults, service: service)
        model.setEnabled(true); await model.waitUntilSynced()
        XCTAssertTrue(model.failed); XCTAssertNil(service.scheduled)
        service.fails = false; model.refresh(language: .chinese); await model.waitUntilSynced()
        XCTAssertNotNil(service.scheduled)
        // Refresh is also the retry operation.
    }
    func testSystemRequestRepeatsAtLocalHourAndDoesNotReplaceDreamReminder() {
        let request = SystemSortingNotificationService.request(time: SortingReminderTime(hour: 22, minute: 15), language: .chinese)
        XCTAssertEqual(request.identifier, "dream_album.photo_sorting_reminder")
        let trigger = request.trigger as! UNCalendarNotificationTrigger
        XCTAssertTrue(trigger.repeats); XCTAssertEqual(trigger.dateComponents.hour, 22); XCTAssertEqual(trigger.dateComponents.minute, 15)
        XCTAssertNil(trigger.dateComponents.timeZone); XCTAssertNil(trigger.dateComponents.day)
        XCTAssertEqual(request.content.title, "整理照片")
    }
}

final class PhotoCalendarNavigationTests: XCTestCase {
    func testMonthSwipeRequiresClearHorizontalMotion() {
        XCTAssertEqual(PhotoCalendarNavigation.offset(for: CGSize(width: 90, height: 10)), -1)
        XCTAssertEqual(PhotoCalendarNavigation.offset(for: CGSize(width: -90, height: 10)), 1)
        XCTAssertNil(PhotoCalendarNavigation.offset(for: CGSize(width: 40, height: 0)))
        XCTAssertNil(PhotoCalendarNavigation.offset(for: CGSize(width: 60, height: 80)))
        XCTAssertNil(PhotoCalendarNavigation.offset(for: CGSize(width: 60, height: 50)))
    }
    func testMonthPagingClampsFutureAndUsesMonthStartsAcrossYear() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = ISO8601DateFormatter().date(from: "2026-01-31T12:00:00Z")!
        let previous = PhotoCalendarNavigation.month(by: -1, from: today, today: today, calendar: calendar)!
        XCTAssertEqual(calendar.component(.year, from: previous), 2025)
        XCTAssertEqual(calendar.component(.month, from: previous), 12)
        XCTAssertEqual(calendar.component(.day, from: previous), 1)
        let restored = PhotoCalendarNavigation.month(by: 1, from: previous, today: today, calendar: calendar)!
        XCTAssertEqual(calendar.component(.month, from: restored), 1)
        XCTAssertNil(PhotoCalendarNavigation.month(by: 1, from: restored, today: today, calendar: calendar))
    }
    func testProgressBelongsToPendingDayEvenWhenTodayIsComplete() {
        let calendar = Calendar.current, today = Date()
        let previous = calendar.date(byAdding: .day, value: -1, to: today)!
        let photos = [LibraryPhoto(id: "today", date: today, isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "done", date: previous, isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "left", date: previous, isScreenshot: false, isLivePhoto: false)]
        let batch = PhotoInboxBatch(today: today, selectedDay: nil, assets: photos, reviewed: ["today", "done"])
        XCTAssertEqual(batch.items.map(\.id), ["left"])
        XCTAssertEqual(batch.progress, 0.5); XCTAssertEqual(batch.completed, 1); XCTAssertEqual(batch.total, 2)
    }
    func testUndatedProgressIncludesReviewedMembers() {
        let photos = [LibraryPhoto(id: "done", date: nil, isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "left", date: nil, isScreenshot: true, isLivePhoto: false)]
        let batch = PhotoInboxBatch(today: Date(), selectedDay: nil, assets: photos, reviewed: ["done"])
        XCTAssertNil(batch.date); XCTAssertEqual(batch.progress, 0.5)
    }
}


final class SilverAppearanceTests: XCTestCase {
    func testExistingThemeMigratesOnceThenRespectsChoice() {
        let name = "SilverAppearanceTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("bluePearl", forKey: AppTheme.storageKey)
        AppTheme.installSilverAppearance(in: defaults)
        XCTAssertEqual(defaults.string(forKey: AppTheme.storageKey), "silver")
        defaults.set("mistBlue", forKey: AppTheme.storageKey)
        AppTheme.installSilverAppearance(in: defaults)
        XCTAssertEqual(defaults.string(forKey: AppTheme.storageKey), "mistBlue")
    }
    func testLegacyIDsAndUnknownFallback() {
        for theme in AppTheme.allCases { XCTAssertEqual(AppTheme.resolve(theme.rawValue), theme) }
        XCTAssertEqual(AppTheme.resolve("future-or-missing-theme"), .silver)
        XCTAssertEqual(AppTheme.resolve("iceMint"), .silver)
    }
}
