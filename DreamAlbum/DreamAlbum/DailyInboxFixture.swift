#if DEBUG
import Photos
import UserNotifications
import UIKit

@MainActor
final class FixtureSortingNotifications: SortingNotificationService {
    private var status: UNAuthorizationStatus = .notDetermined
    func authorization() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { status = .authorized; return true }
    func schedule(time: SortingReminderTime, language: AppLanguage) async throws { }
    func cancel() { }
}

/// UI tests opt in explicitly. The ordinary app always uses the real library;
/// fixture decisions live in an isolated suite and never touch the user's data.
@MainActor
final class DailyInboxFixture: PhotoLibraryService {
    let authorization: PHAuthorizationStatus = .authorized
    var onChange: (() -> Void)?
    private var assets: [LibraryPhoto]
    private var albumNames = ["editable": "测试分组", "readonly": "最近项目"]
    private var members: [String: Set<String>] = ["editable": ["p0", "s0"]]
    static func makeStore() -> PhotoLibraryStore {
        let fixture = DailyInboxFixture()
        let name = "com.luchuangao.dreamalbum.daily-inbox-uitests"
        let defaults = UserDefaults(suiteName: name)!
        if ProcessInfo.processInfo.arguments.contains("-resetDailyFixture") {
            defaults.removePersistentDomain(forName: name)
            UserDefaults.standard.removeObject(forKey: "dream_album.hide_readonly_groups")
            UserDefaults.standard.removeObject(forKey: AppTheme.storageKey)
            var session = PhotoReviewSession()
            let today = fixture.assets.filter { $0.date.map { Calendar.current.isDateInToday($0) } ?? false }
            session.resume(today.map(\.id))
            let arguments = ProcessInfo.processInfo.arguments
            let reviewedIDs = arguments.contains("-allReviewedFixture") ? fixture.assets.map(\.id)
                : arguments.contains("-completedDailyFixture") ? today.map(\.id)
                : ["p0", "p1", "p2", "p3", "p4", "p5", "s0", "s1"]
            let seededIDs = arguments.contains("-homeDateTaskFixture") ? ["todayDone", "dayDone"] : reviewedIDs
            for id in seededIDs where fixture.assets.contains(where: { $0.id == id }) { session.decide(id, delete: false) }
            if arguments.contains("-homeDateTaskFixture") { session.decide("dayDone", delete: true) }
            for photo in fixture.assets where photo.id.hasPrefix("pending-fixture-") { session.decide(photo.id, delete: true) }
            defaults.set(try? JSONEncoder().encode(session), forKey: "dream_album.photo_review.v1")
        }
        return PhotoLibraryStore(service: fixture, defaults: defaults)
    }
    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let empty = ProcessInfo.processInfo.arguments.contains("-emptyDailyFixture")
        var photos = empty || ProcessInfo.processInfo.arguments.contains("-screenshotsOnlyFixture") ? [] : (0..<18).map { LibraryPhoto(id: "p\($0)", date: today.addingTimeInterval(Double(18 - $0) * 60), isScreenshot: false, isLivePhoto: false) }
        if !empty { photos += (0..<6).map { LibraryPhoto(id: "s\($0)", date: today.addingTimeInterval(Double(6 - $0) * 60), isScreenshot: true, isLivePhoto: false) } }
        if !ProcessInfo.processInfo.arguments.contains("-undatedOnlyFixture") {
            photos.append(LibraryPhoto(id: "yesterday", date: calendar.date(byAdding: .day, value: -1, to: today), isScreenshot: false, isLivePhoto: false))
            if empty { photos.append(LibraryPhoto(id: "recentScreenshot", date: calendar.date(byAdding: .day, value: -2, to: today), isScreenshot: true, isLivePhoto: false)) }
        }
        if ProcessInfo.processInfo.arguments.contains("-singleScreenshotFixture") { photos.removeAll { $0.id.hasPrefix("s") && $0.id != "s0" } }
        photos.append(LibraryPhoto(id: "unknown", date: nil, isScreenshot: true, isLivePhoto: false))
        if ProcessInfo.processInfo.arguments.contains("-homeDateTaskFixture") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            photos = [LibraryPhoto(id: "todayDone", date: today.addingTimeInterval(60), isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "dayDone", date: yesterday.addingTimeInterval(120), isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "dayRemaining", date: yesterday.addingTimeInterval(60), isScreenshot: false, isLivePhoto: false),
                      LibraryPhoto(id: "older", date: calendar.date(byAdding: .month, value: -1, to: yesterday), isScreenshot: false, isLivePhoto: false)]
        }
        assets = photos
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-fixturePendingCount"), args.indices.contains(index + 1),
           let count = Int(args[index + 1]) {
            let day = calendar.date(byAdding: .day, value: -3, to: today)!
            assets += (0..<min(max(count, 0), 10000)).map {
                LibraryPhoto(id: "pending-fixture-\($0)", date: day, isScreenshot: false, isLivePhoto: false)
            }
        }
    }
    func requestAccess() async -> PHAuthorizationStatus { authorization }
    func snapshot() async -> LibrarySnapshot {
        let groups = ["editable", "readonly"].compactMap { id -> LibraryGroup? in
            guard let title = albumNames[id] else { return nil }
            let editable = id == "editable"
            return LibraryGroup(id: id, title: title, count: editable ? members[id, default: []].count : assets.count,
                                canAdd: editable, canRemove: editable, canRename: editable, canDelete: editable, isSystem: !editable)
        }
        return LibrarySnapshot(photos: assets, groups: groups)
    }
    func preheat(ids: [String]) { }
    func photos(in groupID: String) async -> [LibraryPhoto] {
        if groupID == "readonly" { return assets }
        return assets.filter { members[groupID, default: []].contains($0.id) }
    }
    func image(id: String, size: CGSize, progress: @escaping (Double) -> Void) async throws -> UIImage {
        if assets.first(where: { $0.id == id })?.isScreenshot == true { return screenshot(id: id) }
        let names = ["WorldLandBackground", "WorldSeaBackground", "MorningCloudsBackground"]
        let index = Int(id.dropFirst()) ?? 0
        return UIImage(named: names[index % names.count])!
    }
    private func screenshot(id: String) -> UIImage {
        // A test screenshot rendered from UIKit text, not production photo content.
        let size = CGSize(width: 360, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemGray6.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let examples = ["随手记\n\n今天想做的事\n\n整理手机照片\n去公园散步\n读完手边的书", "消费记录\n\n今日咖啡\n\n¥ 32.00\n\n订单已完成", "备忘录\n\n旅行清单\n\n相机\n充电器\n舒适的鞋子"]
            let index = Int(id.dropFirst()) ?? 0
            (examples[index % examples.count] as NSString).draw(in: CGRect(x: 26, y: 38, width: 308, height: 520), withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: UIColor.darkGray])
        }
    }
    func imageData(id: String, progress: @escaping (Double) -> Void) async throws -> Data { try await image(id: id, size: CGSize(width: 360, height: 600), progress: progress).pngData()! }
    func createGroup(title: String, photoIDs: [String]) async throws { throw PhotoLibraryFailure.notEditable }
    func renameGroup(id: String, title: String) async throws {
        guard id == "editable", albumNames[id] != nil else { throw PhotoLibraryFailure.notEditable }
        albumNames[id] = title
    }
    func deleteGroup(id: String) async throws {
        guard id == "editable", albumNames[id] != nil else { throw PhotoLibraryFailure.notEditable }
        albumNames.removeValue(forKey: id); members.removeValue(forKey: id)
    }
    func deleteGroupAndPhotos(id: String) async throws -> [String] {
        guard id == "editable", albumNames[id] != nil else { throw PhotoLibraryFailure.notEditable }
        // Validate before either mutation, matching PhotoKit transaction semantics.
        let ids = Array(members[id, default: []])
        try await deletePhotos(ids)
        try await deleteGroup(id: id)
        return ids
    }
    func addPhotos(_ ids: [String], to groupID: String) async throws {
        guard groupID == "editable", albumNames[groupID] != nil else { throw PhotoLibraryFailure.notEditable }
        members[groupID, default: []].formUnion(ids)
    }
    func removePhotos(_ ids: [String], from groupID: String) async throws {
        guard groupID == "editable", albumNames[groupID] != nil else { throw PhotoLibraryFailure.notEditable }
        members[groupID, default: []].subtract(ids)
    }
    func deletePhotos(_ ids: [String]) async throws {
        if ProcessInfo.processInfo.arguments.contains("-cancelFixtureDelete") {
            throw NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.userCancelled.rawValue)
        }
        if ProcessInfo.processInfo.arguments.contains("-failFixtureDelete") {
            throw NSError(domain: "FixtureDelete", code: 1, userInfo: [NSLocalizedDescriptionKey: "删除失败，请重试。"])
        }
        assets.removeAll { ids.contains($0.id) }
        for key in Array(members.keys) { members[key]?.subtract(ids) }
    }
}
#endif
