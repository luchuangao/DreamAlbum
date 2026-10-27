import Foundation
import StoreKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@MainActor
final class DreamStore: ObservableObject {
    static let freeActiveDreamLimit = 4

    @Published var dreams: [Dream] = [] {
        didSet { save() }
    }

    @Published var isDailyReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDailyReminderEnabled, forKey: Self.reminderEnabledKey)
            Task { await ReminderScheduler.sync(enabled: isDailyReminderEnabled, time: dailyReminderTime, language: appLanguage) }
        }
    }

    @Published var dailyReminderTime: Date {
        didSet {
            UserDefaults.standard.set(dailyReminderTime, forKey: Self.reminderTimeKey)
            guard isDailyReminderEnabled else { return }
            Task { await ReminderScheduler.sync(enabled: isDailyReminderEnabled, time: dailyReminderTime, language: appLanguage) }
        }
    }

    @Published var backgroundStyle: AlbumBackgroundStyle {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: Self.backgroundStyleKey)
            syncSettingsToICloud()
        }
    }

    @Published var backgroundImageChoice: BackgroundImageChoice {
        didSet {
            UserDefaults.standard.set(backgroundImageChoice.rawValue, forKey: Self.backgroundImageChoiceKey)
            syncSettingsToICloud()
        }
    }

    @Published var customBackgroundImagePath: String? {
        didSet {
            if let customBackgroundImagePath {
                UserDefaults.standard.set(customBackgroundImagePath, forKey: Self.customBackgroundImagePathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.customBackgroundImagePathKey)
            }
            syncSettingsToICloud()
        }
    }

    @Published private(set) var backgroundContrast: BackgroundContrast {
        didSet {
            UserDefaults.standard.set(backgroundContrast.rawValue, forKey: Self.backgroundContrastKey)
        }
    }

    @Published var settingsDisplayStyle: SettingsDisplayStyle {
        didSet {
            UserDefaults.standard.set(settingsDisplayStyle.rawValue, forKey: Self.settingsDisplayStyleKey)
            syncSettingsToICloud()
        }
    }

    @Published var timelineDisplayStyle: TimelineDisplayStyle {
        didSet {
            UserDefaults.standard.set(timelineDisplayStyle.rawValue, forKey: Self.timelineDisplayStyleKey)
            syncSettingsToICloud()
        }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
            syncSettingsToICloud()
            guard isDailyReminderEnabled else { return }
            Task { await ReminderScheduler.sync(enabled: isDailyReminderEnabled, time: dailyReminderTime, language: appLanguage) }
        }
    }

    @Published var isMoodChartEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMoodChartEnabled, forKey: Self.moodChartEnabledKey)
            syncSettingsToICloud()
        }
    }

    @Published var avatarImagePath: String {
        didSet {
            UserDefaults.standard.set(avatarImagePath, forKey: Self.avatarImagePathKey)
            syncSettingsToICloud()
        }
    }

    @Published var isPremiumUnlocked = false {
        didSet {
            guard oldValue != isPremiumUnlocked else { return }
            enforcePremiumAccess()
        }
    }

    private static let dreamsKey = "dream_album.dreams"
    private static let localUpdatedAtKey = "dream_album.local_updated_at"
    private static let reminderEnabledKey = "dream_album.daily_reminder_enabled"
    private static let reminderTimeKey = "dream_album.daily_reminder_time"
    private static let backgroundStyleKey = "dream_album.background_style"
    private static let backgroundImageChoiceKey = "dream_album.background_image_choice"
    private static let customBackgroundImagePathKey = "dream_album.custom_background_image_path"
    private static let backgroundContrastKey = "dream_album.background_contrast"
    private static let settingsDisplayStyleKey = "dream_album.settings_display_style"
    private static let timelineDisplayStyleKey = "dream_album.timeline_display_style"
    private static let appLanguageKey = "dream_album.app_language"
    private static let moodChartEnabledKey = "dream_album.mood_chart_enabled"
    private static let avatarImagePathKey = "dream_album.avatar_image_path"
    private var isApplyingICloudBackup = false

    init() {
        isDailyReminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderEnabledKey)
        dailyReminderTime = UserDefaults.standard.object(forKey: Self.reminderTimeKey) as? Date
            ?? Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())
            ?? Date()
        let savedBackgroundStyle = AlbumBackgroundStyle(rawValue: UserDefaults.standard.string(forKey: Self.backgroundStyleKey) ?? "")
        backgroundStyle = savedBackgroundStyle == .morningMistBlue ? .rainBlue : (savedBackgroundStyle ?? .rainBlue)
        let savedBackgroundImageChoice = BackgroundImageChoice(rawValue: UserDefaults.standard.string(forKey: Self.backgroundImageChoiceKey) ?? "")
            ?? .worldSea
        backgroundImageChoice = savedBackgroundImageChoice.isCurrentBuiltInBackground || savedBackgroundImageChoice == .custom
            ? savedBackgroundImageChoice
            : .worldSea
        customBackgroundImagePath = UserDefaults.standard.string(forKey: Self.customBackgroundImagePathKey)
        backgroundContrast = BackgroundContrast(rawValue: UserDefaults.standard.string(forKey: Self.backgroundContrastKey) ?? "") ?? .regular
        let savedDisplayStyle = SettingsDisplayStyle(rawValue: UserDefaults.standard.string(forKey: Self.settingsDisplayStyleKey) ?? "")
        settingsDisplayStyle = Self.supportedDisplayStyles.contains(savedDisplayStyle ?? .magazine) ? (savedDisplayStyle ?? .magazine) : .magazine
        timelineDisplayStyle = TimelineDisplayStyle(rawValue: UserDefaults.standard.string(forKey: Self.timelineDisplayStyleKey) ?? "")
            ?? .timeline
        appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.appLanguageKey) ?? "")
            ?? .chinese
        isMoodChartEnabled = UserDefaults.standard.bool(forKey: Self.moodChartEnabledKey)
        avatarImagePath = UserDefaults.standard.string(forKey: Self.avatarImagePathKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.dreamsKey),
           let decoded = try? JSONDecoder().decode([Dream].self, from: data) {
            dreams = decoded
        } else {
            dreams = [Dream.sample]
        }
        updateWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await restoreNewerICloudBackupIfNeeded() }
    }

    var activeDreams: [Dream] {
        dreams.filter { !$0.isArchived }
    }

    var archivedDreams: [Dream] {
        dreams.filter(\.isArchived)
    }

    var canCreateDream: Bool {
        !AppFeatureFlags.paidAccessEnabled || isPremiumUnlocked || activeDreams.count < Self.freeActiveDreamLimit
    }

    var activeDreamLimitText: String {
        (!AppFeatureFlags.paidAccessEnabled || isPremiumUnlocked) ? "∞" : "\(Self.freeActiveDreamLimit)"
    }

    func addDream(title: String, visionText: String, imagePaths: [String]) {
        guard canCreateDream else { return }
        dreams.insert(Dream(title: title, visionText: visionText, imagePaths: imagePaths.isEmpty ? ["sample:marathon"] : imagePaths), at: 0)
    }

    func update(_ dream: Dream) {
        guard let index = dreams.firstIndex(where: { $0.id == dream.id }) else { return }
        dreams[index] = dream
    }

    func archive(_ dream: Dream) {
        var copy = dream
        copy.isArchived = true
        copy.archivedAt = Date()
        update(copy)
    }

    func restore(_ dream: Dream) {
        guard canCreateDream else { return }
        var copy = dream
        copy.isArchived = false
        copy.archivedAt = nil
        update(copy)
    }

    func delete(_ dream: Dream) {
        dreams.removeAll { $0.id == dream.id }
    }

    func moveDream(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = dreams.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = dreams.firstIndex(where: { $0.id == targetID }),
              !dreams[sourceIndex].isArchived,
              !dreams[targetIndex].isArchived else { return }

        let movedDream = dreams.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        dreams.insert(movedDream, at: adjustedTargetIndex)
    }

    func enforcePremiumAccess() {
        guard AppFeatureFlags.paidAccessEnabled, !isPremiumUnlocked, settingsDisplayStyle.requiresPremium else { return }
        settingsDisplayStyle = .magazine
    }

    func resetAvatar() {
        avatarImagePath = ""
    }

    func resetBackgroundImage() {
        customBackgroundImagePath = nil
        backgroundImageChoice = .worldSea
    }

    func updateBackgroundContrast(_ contrast: BackgroundContrast) {
        guard backgroundContrast != contrast else { return }
        backgroundContrast = contrast
        syncSettingsToICloud()
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(dreams) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.dreamsKey)
        let updatedAt = Date()
        UserDefaults.standard.set(updatedAt, forKey: Self.localUpdatedAtKey)
        updateWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
        pushICloudBackup(updatedAt: updatedAt)
    }

    private func syncSettingsToICloud() {
        guard !isApplyingICloudBackup else { return }
        let updatedAt = Date()
        UserDefaults.standard.set(updatedAt, forKey: Self.localUpdatedAtKey)
        pushICloudBackup(updatedAt: updatedAt)
    }

    private func pushICloudBackup(updatedAt: Date) {
        guard !isApplyingICloudBackup else { return }
        let backup = makeICloudBackup(updatedAt: updatedAt)
        Task.detached {
            await ICloudDreamSync.pushBackup(backup)
        }
    }

    private func makeICloudBackup(updatedAt: Date) -> ICloudDreamBackup {
        ICloudDreamBackup(
            updatedAt: updatedAt,
            dreams: dreams,
            backgroundStyle: backgroundStyle,
            settingsDisplayStyle: settingsDisplayStyle,
            timelineDisplayStyle: timelineDisplayStyle,
            appLanguage: appLanguage,
            isMoodChartEnabled: isMoodChartEnabled,
            avatarImagePath: avatarImagePath,
            backgroundImageChoice: backgroundImageChoice,
            customBackgroundImagePath: customBackgroundImagePath,
            backgroundContrast: backgroundContrast
        )
    }

    private func restoreNewerICloudBackupIfNeeded() async {
        guard let backup = await ICloudDreamSync.loadBackup() else {
            pushICloudBackup(updatedAt: UserDefaults.standard.object(forKey: Self.localUpdatedAtKey) as? Date ?? Date())
            return
        }

        let localUpdatedAt = UserDefaults.standard.object(forKey: Self.localUpdatedAtKey) as? Date ?? .distantPast
        guard backup.updatedAt > localUpdatedAt else { return }

        await ICloudDreamSync.restoreImages(for: backup)
        applyICloudBackup(backup)
    }

    private func applyICloudBackup(_ backup: ICloudDreamBackup) {
        isApplyingICloudBackup = true
        dreams = backup.dreams
        backgroundStyle = backup.backgroundStyle
        backgroundImageChoice = backup.backgroundImageChoice
        customBackgroundImagePath = backup.customBackgroundImagePath
        backgroundContrast = backup.backgroundContrast
        settingsDisplayStyle = Self.supportedDisplayStyles.contains(backup.settingsDisplayStyle) ? backup.settingsDisplayStyle : .magazine
        timelineDisplayStyle = backup.timelineDisplayStyle
        appLanguage = backup.appLanguage
        isMoodChartEnabled = backup.isMoodChartEnabled
        avatarImagePath = backup.avatarImagePath
        isApplyingICloudBackup = false

        if let encoded = try? JSONEncoder().encode(dreams) {
            UserDefaults.standard.set(encoded, forKey: Self.dreamsKey)
        }
        UserDefaults.standard.set(backup.updatedAt, forKey: Self.localUpdatedAtKey)
        UserDefaults.standard.set(backgroundStyle.rawValue, forKey: Self.backgroundStyleKey)
        UserDefaults.standard.set(backgroundImageChoice.rawValue, forKey: Self.backgroundImageChoiceKey)
        if let customBackgroundImagePath {
            UserDefaults.standard.set(customBackgroundImagePath, forKey: Self.customBackgroundImagePathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.customBackgroundImagePathKey)
        }
        UserDefaults.standard.set(backgroundContrast.rawValue, forKey: Self.backgroundContrastKey)
        UserDefaults.standard.set(settingsDisplayStyle.rawValue, forKey: Self.settingsDisplayStyleKey)
        UserDefaults.standard.set(timelineDisplayStyle.rawValue, forKey: Self.timelineDisplayStyleKey)
        UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
        UserDefaults.standard.set(isMoodChartEnabled, forKey: Self.moodChartEnabledKey)
        UserDefaults.standard.set(avatarImagePath, forKey: Self.avatarImagePathKey)
        updateWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateWidgetSnapshot() {
        let featured = activeDreams.first

        guard let featured else {
            DreamWidgetSnapshotStore.write(snapshot: .empty, coverImage: nil)
            return
        }

        let latestRecord = featured.latestLog?.action.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackRecord = featured.visionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = DreamWidgetSnapshot(
            title: featured.title,
            visionText: fallbackRecord,
            latestRecord: latestRecord.isEmpty ? fallbackRecord : latestRecord,
            recordCount: featured.evidenceCount,
            imageCount: featured.imagePaths.count,
            updatedAt: Date()
        )
        DreamWidgetSnapshotStore.write(snapshot: snapshot, coverImage: coverImage(for: featured))
    }

    private static let supportedDisplayStyles: [SettingsDisplayStyle] = [.magazine, .compact, .dashboard]

    private func coverImage(for dream: Dream) -> UIImage? {
        guard let firstPath = dream.imagePaths.first else { return nil }
        if firstPath.hasPrefix("sample:") {
            return UIImage(named: "DemoDream")
        }
        guard let url = ImageLibrary.imageURL(for: firstPath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

@MainActor
final class PurchaseStore: ObservableObject {
    static let premiumProductID = "com.luchuangao.mengxiangxiangce.premium"

    @Published private(set) var premiumProduct: Product?
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var purchaseMessage: String?

    private var updatesTask: Task<Void, Never>?

    var isPremiumUnlocked: Bool {
        !AppFeatureFlags.paidAccessEnabled || purchasedProductIDs.contains(Self.premiumProductID)
    }

    var premiumDisplayPrice: String {
        premiumProduct?.displayPrice ?? AlbumCopy.pick(.chinese, "获取价格中", "Loading price")
    }

    init() {
        guard AppFeatureFlags.paidAccessEnabled else { return }
        updatesTask = observeTransactions()
        Task {
            await loadProducts()
            await refreshPurchasedProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            premiumProduct = try await Product.products(for: [Self.premiumProductID]).first
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func purchasePremium() async {
        if premiumProduct == nil {
            await loadProducts()
        }

        guard let premiumProduct else {
            purchaseMessage = AlbumCopy.pick(.chinese, "暂时无法连接内购商品，请确认 App Store Connect 已配置商品。", "The premium product is not available yet. Please check App Store Connect.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await premiumProduct.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func refreshPurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            purchased.insert(transaction.productID)
        }
        purchasedProductIDs = purchased
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let transaction = try? Self.checkVerified(result) else { continue }
                self?.purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            "Store transaction verification failed."
        }
    }
}

enum ReminderScheduler {
    private static let identifier = "dream_album.daily_reminder"

    static func sync(enabled: Bool, time: Date, language: AppLanguage) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            var components = Calendar.current.dateComponents([.hour, .minute], from: time)
            components.second = 0

            let content = UNMutableNotificationContent()
            content.title = AlbumCopy.pick(language, "梦想相册", "Dream Album")
            content.body = AlbumCopy.pick(
                language,
                "回望旧日心愿，见证当下成长，留存每一步闪光。",
                "Look back at old wishes, witness today's growth, and keep every bright step."
            )
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try await center.add(request)
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }
}

enum ImageLibrary {
    static func imageURL(for path: String) -> URL? {
        guard !path.hasPrefix("sample:") else { return nil }
        return documentsDirectory.appendingPathComponent(path)
    }

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func saveImageData(_ data: Data) throws -> String {
        let name = "\(UUID().uuidString).jpg"
        let url = documentsDirectory.appendingPathComponent(name)
        let optimized = optimizedJPEGData(from: data) ?? data
        try optimized.write(to: url, options: .atomic)
        return name
    }

    private static func optimizedJPEGData(from data: Data, maxLength: CGFloat = 2200, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxLength / max(longestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
