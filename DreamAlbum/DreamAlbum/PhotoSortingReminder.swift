import SwiftUI
import UserNotifications

struct SortingReminderTime: Equatable {
    var hour: Int = 22
    var minute: Int = 0
    var components: DateComponents { DateComponents(hour: hour, minute: minute, second: 0) }
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

@MainActor
protocol SortingNotificationService {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func schedule(time: SortingReminderTime, language: AppLanguage) async throws
    func cancel()
}

@MainActor
final class SystemSortingNotificationService: SortingNotificationService {
    static let identifier = "dream_album.photo_sorting_reminder"
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func schedule(time: SortingReminderTime, language: AppLanguage) async throws {
        try await center.add(Self.request(time: time, language: language))
    }
    static func request(time: SortingReminderTime, language: AppLanguage) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = AlbumCopy.pick(language, "整理照片", "Review your photos")
        content.body = AlbumCopy.pick(language, "花一点时间，整理今天的照片。", "Take a moment to sort today’s photos.")
        content.sound = .default
        // Hour/minute only: repeat at the chosen local time, including after time-zone changes.
        let trigger = UNCalendarNotificationTrigger(dateMatching: time.components, repeats: true)
        return UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
    }
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

/// Local preferences and one serialized reconciliation worker. A slow permission
/// response or add request cannot leave a stale reminder after the user turns it off.
@MainActor
final class PhotoSortingReminder: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var time: SortingReminderTime
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var failed = false
    private let defaults: UserDefaults
    private let service: SortingNotificationService
    private var language: AppLanguage = .chinese
    private var revision = 0
    private var askPermission = false
    private var worker: Task<Void, Never>?
    private static let enabledKey = "dream_album.sorting_reminder.enabled"
    private static let hourKey = "dream_album.sorting_reminder.hour"
    private static let minuteKey = "dream_album.sorting_reminder.minute"

    init(defaults: UserDefaults = .standard, service: SortingNotificationService? = nil) {
        self.defaults = defaults
        self.service = service ?? SystemSortingNotificationService()
        enabled = defaults.bool(forKey: Self.enabledKey)
        let hour = defaults.object(forKey: Self.hourKey) as? Int ?? 22
        let minute = defaults.object(forKey: Self.minuteKey) as? Int ?? 0
        time = SortingReminderTime(hour: (0...23).contains(hour) ? hour : 22, minute: (0...59).contains(minute) ? minute : 0)
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        askPermission = value
        failed = false
        if !value { service.cancel() }
        reconcile()
    }
    func setTime(_ date: Date, calendar: Calendar = .current) {
        time = SortingReminderTime(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date))
        defaults.set(time.hour, forKey: Self.hourKey)
        defaults.set(time.minute, forKey: Self.minuteKey)
        failed = false
        reconcile()
    }
    func refresh(language: AppLanguage) {
        failed = false
        self.language = language
        reconcile()
    }
    func waitUntilSynced() async { await worker?.value }
    private func reconcile() {
        revision += 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while true {
                let version = self.revision
                let wantsEnabled = self.enabled
                let desiredTime = self.time
                let desiredLanguage = self.language
                let canAsk = self.askPermission
                self.authorization = await self.service.authorization()
                if version == self.revision {
                    self.askPermission = false
                    do {
                        if !wantsEnabled { self.service.cancel() }
                        else {
                            if self.authorization == .notDetermined && canAsk {
                                _ = try await self.service.requestAuthorization()
                                self.authorization = await self.service.authorization()
                            }
                            if version == self.revision {
                                switch self.authorization {
                                case .authorized, .provisional, .ephemeral:
                                    try await self.service.schedule(time: desiredTime, language: desiredLanguage)
                                default:
                                    self.service.cancel()
                                    // An explicit opt-in that was denied must not appear active.
                                    if canAsk { self.enabled = false; self.defaults.set(false, forKey: Self.enabledKey) }
                                }
                            }
                        }
                    } catch {
                        if version == self.revision { self.failed = true }
                        self.service.cancel()
                    }
                }
                if version == self.revision { self.worker = nil; break }
            }
        }
    }
}

struct PhotoSortingReminderSection: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var reminder: PhotoSortingReminder
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { reminder.enabled }, set: { reminder.setEnabled($0) })) {
                Label(c("整理提醒", "Photo reminders"), systemImage: "bell")
            }.accessibilityIdentifier("reminder.toggle")
            if reminder.enabled {
                DatePicker(c("提醒时间", "Time"), selection: Binding(get: { reminder.time.date() }, set: { reminder.setTime($0) }), displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("reminder.time")
            }
            if reminder.authorization == .denied {
                Button(c("允许通知", "Allow notifications")) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }.accessibilityIdentifier("reminder.settings")
            }
            if reminder.failed {
                Button(c("提醒设置失败，重试", "Couldn’t set reminder. Retry")) { reminder.refresh(language: store.appLanguage) }
                    .foregroundStyle(.red).accessibilityIdentifier("reminder.retry")
            }
        } footer: {
            Text(reminder.authorization == .denied ? c("请在系统设置中允许通知。", "Allow notifications in system settings.") : c("每天提醒，默认 22:00。", "Daily reminder. Default: 10:00 PM."))
        }
        .listRowBackground(LibraryStyle.surface)
        .task { reminder.refresh(language: store.appLanguage) }
        .onChange(of: phase) { _, value in if value == .active { reminder.refresh(language: store.appLanguage) } }
        .onChange(of: store.appLanguage) { _, value in reminder.refresh(language: value) }
    }
}
