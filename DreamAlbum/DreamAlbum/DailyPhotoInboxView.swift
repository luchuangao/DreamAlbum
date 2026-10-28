import SwiftUI

/// Calendar-day boundaries include DST and the user's current time zone. Assets
/// with unknown capture dates remain in All Photos, never in an invented day.
struct PhotoDaySummary {
    let date: Date
    let startDate: Date
    let isRecent: Bool
    let items: [LibraryPhoto]
    let photos: [LibraryPhoto]
    let screenshots: [LibraryPhoto]
    let reviewed: Set<String>
    init(date: Date, assets: [LibraryPhoto], reviewed: Set<String>, calendar: Calendar = .current, recentDays: Int = 1) {
        self.date = date
        isRecent = recentDays > 1
        let start = calendar.date(byAdding: .day, value: 1 - recentDays, to: calendar.startOfDay(for: date))!
        startDate = start
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        items = assets.filter { asset in
            guard let captured = asset.date else { return false }
            return captured >= start && captured < end
        }
        photos = items.filter { !$0.isScreenshot }
        screenshots = items.filter(\.isScreenshot)
        self.reviewed = reviewed
    }
    /// Explicit calendar choices stay on that day. An empty Today falls back to
    /// seven calendar days, ending on the latest accessible day if the library is older.
    static func home(today: Date, selectedDay: Date?, assets: [LibraryPhoto], reviewed: Set<String>, calendar: Calendar = .current) -> Self {
        if let selectedDay { return Self(date: selectedDay, assets: assets, reviewed: reviewed, calendar: calendar) }
        let daily = Self(date: today, assets: assets, reviewed: reviewed, calendar: calendar)
        guard daily.items.isEmpty,
              let latest = assets.compactMap(\.date).filter({ $0 < calendar.startOfDay(for: today) }).max() else { return daily }
        let recentStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today))!
        return Self(date: latest >= recentStart ? today : latest, assets: assets, reviewed: reviewed, calendar: calendar, recentDays: 7)
    }
    var completed: Int { items.reduce(0) { $0 + (reviewed.contains($1.id) ? 1 : 0) } }
    var remaining: Int { items.count - completed }
    var progress: Double { items.isEmpty ? 0 : Double(completed) / Double(items.count) }
    func remaining(in assets: [LibraryPhoto]) -> Int { assets.reduce(0) { $0 + (reviewed.contains($1.id) ? 0 : 1) } }
}

/// Continue with the nearest earlier day that still contains unreviewed images.
/// Undated images are offered only after dated history has been exhausted.
struct PhotoInboxContinuation {
    let date: Date?
    let photos: [LibraryPhoto]
    init?(before: Date, assets: [LibraryPhoto], reviewed: Set<String>, calendar: Calendar = .current) {
        let cutoff = calendar.startOfDay(for: before)
        let remaining = assets.filter { !reviewed.contains($0.id) }
        if let latest = remaining.compactMap(\.date).filter({ $0 < cutoff }).max() {
            date = calendar.startOfDay(for: latest)
            photos = remaining.filter { $0.date.map { calendar.isDate($0, inSameDayAs: latest) } ?? false }
        } else {
            date = nil
            photos = remaining.filter { $0.date == nil }
        }
        if photos.isEmpty { return nil }
    }
}

/// A home task is the most recent unfinished day, followed by undated images.
/// Explicit dates can look backward, but completed days never fill the inbox.
struct PhotoInboxBatch {
    let date: Date?
    let items: [LibraryPhoto]
    let total: Int
    let completed: Int
    var progress: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    var photos: [LibraryPhoto] { items.filter { !$0.isScreenshot } }
    var screenshots: [LibraryPhoto] { items.filter(\.isScreenshot) }
    init(today: Date, selectedDay: Date?, assets: [LibraryPhoto], reviewed: Set<String>, calendar: Calendar = .current) {
        let limit = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDay ?? today))!
        let pending = assets.filter { !reviewed.contains($0.id) }
        if let latest = pending.compactMap(\.date).filter({ $0 < limit }).max() {
            date = calendar.startOfDay(for: latest)
            let day = assets.filter { $0.date.map { calendar.isDate($0, inSameDayAs: latest) } ?? false }
            items = day.filter { !reviewed.contains($0.id) }
            total = day.count
            completed = total - items.count
        } else {
            date = nil
            items = pending.filter { $0.date == nil }
            total = assets.filter { $0.date == nil }.count
            completed = total - items.count
        }
    }
}

struct DailyPhotoInboxView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.photoHomeGeneration) private var photoHomeGeneration
    @State private var selectedDay: Date?
    @State private var showCalendar = false
    @State private var calendarDay = Date()
    @State private var restartIDs: [String]?
    @State private var showAllPhotos = false
    @State private var showReview = false
    @State private var showPending = false
    @State private var lastActiveDay = Calendar.current.startOfDay(for: Date())
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    private var batch: PhotoInboxBatch {
        PhotoInboxBatch(today: Date(), selectedDay: selectedDay, assets: library.photos, reviewed: library.session.reviewed)
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            let current = PhotoInboxBatch(today: clock.date, selectedDay: selectedDay, assets: library.photos, reviewed: library.session.reviewed)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(current)
                        LimitedPhotosBanner()
                        if !library.hasAccess {
                            LibraryPermissionView().frame(minHeight: 300)
                        } else if library.isLoading && library.photos.isEmpty {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                        } else if current.items.isEmpty {
                            emptyInbox
                        } else {
                            if !current.photos.isEmpty { collection(title: c("照片", "Photos"), icon: "photo", assets: current.photos, identifier: "today.photos") }
                            if !current.screenshots.isEmpty { collection(title: c("截图", "Screenshots"), icon: "viewfinder", assets: current.screenshots, identifier: "today.screenshots") }
                        }
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                if library.hasAccess && !current.items.isEmpty { actionBar(current) }
            }
        }
        .background(LibraryStyle.background)
        .navigationTitle(c("首页", "Home"))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showAllPhotos) { PhotoBrowserView().libraryErrorAlert() }
        .fullScreenCover(isPresented: $showReview) { NavigationStack { PhotoReviewView() } }
        .sheet(isPresented: $showPending) { NavigationStack { PendingPhotosView() } }
        .sheet(isPresented: $showCalendar, onDismiss: {
            if let ids = restartIDs { restartIDs = nil; library.restartReview(ids); showReview = true }
        }) { calendarSheet }
        .task { await library.activate() }
        .onChange(of: photoHomeGeneration) { _, _ in
            selectedDay = nil; showAllPhotos = false; showCalendar = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let today = Calendar.current.startOfDay(for: Date())
            if today != lastActiveDay { selectedDay = nil; showAllPhotos = false }
            lastActiveDay = today
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in selectedDay = nil }
    }
    private func header(_ current: PhotoInboxBatch) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text(c("整理照片", "Review photos")).font(.system(size: 32, weight: .bold))
                Spacer(minLength: 12)
                Button { showAllPhotos = true } label: {
                    HStack(spacing: 5) { Text(c("全部照片", "All photos")); Image(systemName: "chevron.right").font(.caption) }
                }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("today.all")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { dateButton(current); Spacer(minLength: 0); pendingButton }
                VStack(alignment: .leading, spacing: 8) { dateButton(current); pendingButton }
            }
        }
    }
    private func dateButton(_ current: PhotoInboxBatch) -> some View {
        let displayedDate = current.date ?? (current.items.isEmpty ? selectedDay : nil)
        return Button { calendarDay = displayedDate ?? selectedDay ?? Date(); showCalendar = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(displayedDate.map(dateLabel) ?? (current.items.isEmpty ? c("选择日期", "Choose date") : c("日期未知", "Undated")))
                    .accessibilityIdentifier("today.date")
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.font(.subheadline).foregroundStyle(.primary).padding(.horizontal, 14).frame(minHeight: 44)
                .background(LibraryStyle.surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel(c("选择日期", "Choose date"))
            .accessibilityValue(displayedDate.map(dateLabel) ?? c("日期未知", "Undated"))
            .accessibilityIdentifier("today.calendar").disabled(!library.hasAccess)
    }
    private var pendingButton: some View {
        Button { showPending = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                Text(c("待删", "Pending"))
                Text("\(library.session.pendingDeletion.count)").monospacedDigit().fontWeight(.semibold)
            }.font(.subheadline).padding(.horizontal, 12).frame(minHeight: 40)
                .background(LibraryStyle.surface, in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(LibraryStyle.mint)
            .accessibilityLabel(c("待删 \(library.session.pendingDeletion.count)", "Pending \(library.session.pendingDeletion.count)"))
            .accessibilityIdentifier("today.pending")
    }
    private func collection(title: String, icon: String, assets: [LibraryPhoto], identifier: String) -> some View {
        Button { review(assets.map(\.id)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label(title, systemImage: icon).font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary)
                }.frame(minHeight: 32)
                if let photo = assets.first, assets.count == 1 {
                    LibraryThumbnail(id: photo.id, hero: true)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, -8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(assets.prefix(3).enumerated()), id: \.element.id) { index, photo in
                            LibraryThumbnail(id: photo.id)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    if index == 2 && assets.count > 3 {
                                        RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.4))
                                        Text("+\(assets.count - 3)").font(.title2.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(c("\(title)，待整理 \(assets.count) 张", "\(title), \(assets.count) remaining"))
            .accessibilityIdentifier(identifier)
    }
    private func actionBar(_ current: PhotoInboxBatch) -> some View {
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 5)
                Circle().trim(from: 0, to: current.progress)
                    .stroke(LibraryStyle.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }.frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(c("还剩 \(current.items.count) 张", "\(current.items.count) remaining"))
                    .font(.subheadline.weight(.medium)).accessibilityIdentifier("today.remaining")
                Text(c("已整理 \(current.completed) / \(current.total)", "Reviewed \(current.completed) / \(current.total)"))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("today.next")
            }
            Spacer(minLength: 8)
            Button { review(current.items.map(\.id)) } label: {
                HStack(spacing: 8) {
                    Text(c("继续整理", "Continue"))
                    Image(systemName: "arrow.right")
                }.frame(minHeight: 44)
            }.font(.subheadline.weight(.semibold)).foregroundStyle(LibraryStyle.mint)
                .buttonStyle(.plain).accessibilityIdentifier("today.continue")
                .accessibilityLabel(c("继续整理 \(current.items.count) 张", "Continue, \(current.items.count) items"))
        }
        .frame(maxWidth: 700).padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background(LibraryStyle.background).overlay(alignment: .top) { Divider() }
    }
    private var emptyInbox: some View {
        let hasOtherPending = selectedDay != nil && library.photos.contains { !library.session.reviewed.contains($0.id) }
        return VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 52, weight: .light)).foregroundStyle(LibraryStyle.mint)
            Text(hasOtherPending ? c("此前已整理", "Earlier photos are sorted") : c("全部已整理", "All caught up")).font(.title2.bold()).accessibilityIdentifier("today.completed")
            Text(hasOtherPending ? c("可以继续整理最近的照片。", "Continue with your recent photos.") : c("新照片会出现在这里。", "New photos will appear here."))
                .font(.subheadline).foregroundStyle(.secondary)
            if hasOtherPending {
                Button(c("返回待整理", "Back to pending photos")) { selectedDay = nil }.padding(.top, 4)
            } else {
                Button(c("查看全部照片", "View all photos")) { showAllPhotos = true }.padding(.top, 4)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }
    private var calendarSheet: some View {
        NavigationStack {
            PhotoCountCalendar(assets: library.photos, language: store.appLanguage, selection: $calendarDay, reviewed: library.session.reviewed, onToday: { selectedDay = nil; showCalendar = false }, onRestart: { date in
                    selectedDay = Calendar.current.startOfDay(for: date)
                    restartIDs = library.photos.filter { $0.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }.map(\.id)
                    showCalendar = false
                })
                .navigationTitle(c("选择日期", "Choose date"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { selectedDay = Calendar.current.isDateInToday(calendarDay) ? nil : calendarDay; showCalendar = false } } }
        }.presentationDetents([.large])
    }
    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: store.appLanguage == .english ? "en_US" : "zh_CN")
        formatter.dateFormat = store.appLanguage == .english ? "MMM d, EEE" : "M月d日 EE"
        return formatter.string(from: date)
    }
    private func review(_ ids: [String]) { library.resumeReview(ids); showReview = true }
}
