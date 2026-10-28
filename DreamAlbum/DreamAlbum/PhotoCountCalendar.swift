import SwiftUI

enum PhotoDayReviewState: Hashable {
    case empty, unreviewed, partial, complete
    var symbol: String {
        switch self {
        case .empty, .unreviewed: return "circle"
        case .partial: return "circle.lefthalf.filled"
        case .complete: return "checkmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .empty, .unreviewed: return .secondary
        case .partial: return .orange
        case .complete: return LibraryStyle.mint
        }
    }
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .empty: return AlbumCopy.pick(language, "无照片", "No photos")
        case .unreviewed: return AlbumCopy.pick(language, "未整理", "Not started")
        case .partial: return AlbumCopy.pick(language, "整理中", "In progress")
        case .complete: return AlbumCopy.pick(language, "已整理", "Done")
        }
    }
}

/// A metadata-only month index. Counts include photos and screenshots, exclude
/// undated assets, and share the inbox's local Calendar/day boundaries.
struct PhotoCalendarMonth {
    struct Day: Identifiable {
        let date: Date
        let number: Int
        let count: Int
        let reviewedCount: Int
        var state: PhotoDayReviewState {
            count == 0 ? .empty : reviewedCount == 0 ? .unreviewed : reviewedCount == count ? .complete : .partial
        }
        var id: Date { date }
    }
    let start: Date
    let leadingDays: Int
    let days: [Day]
    init(containing date: Date, assets: [LibraryPhoto], reviewed: Set<String> = [], calendar: Calendar = .current) {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        start = monthStart
        leadingDays = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var counts: [Date: Int] = [:]
        var completed: [Date: Int] = [:]
        for asset in assets {
            guard let date = asset.date, calendar.isDate(date, equalTo: start, toGranularity: .month) else { continue }
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += 1
            if reviewed.contains(asset.id) { completed[day, default: 0] += 1 }
        }
        days = (calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<1).compactMap { number in
            guard let date = calendar.date(byAdding: .day, value: number - 1, to: monthStart) else { return nil }
            return Day(date: date, number: number, count: counts[date, default: 0], reviewedCount: completed[date, default: 0])
        }
    }
}

enum PhotoCalendarNavigation {
    static func offset(for translation: CGSize) -> Int? {
        guard abs(translation.width) >= 50, abs(translation.width) > abs(translation.height) * 1.3 else { return nil }
        return translation.width < 0 ? 1 : -1
    }
    static func month(by offset: Int, from date: Date, today: Date, calendar: Calendar = .current) -> Date? {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start,
              let next = calendar.date(byAdding: .month, value: offset, to: start),
              let latest = calendar.dateInterval(of: .month, for: today)?.start,
              next <= latest else { return nil }
        return next
    }
}

struct PhotoCountCalendar: View {
    let assets: [LibraryPhoto]
    let language: AppLanguage
    let reviewed: Set<String>
    var onToday: () -> Void = {}
    var onRestart: ((Date) -> Void)?
    @Binding var selection: Date
    @State private var month: Date
    @State private var jumpDate: Date
    @State private var showJump = false
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: language == .english ? "en_US" : "zh_CN")
        return calendar
    }
    init(assets: [LibraryPhoto], language: AppLanguage, selection: Binding<Date>, reviewed: Set<String> = [], onToday: @escaping () -> Void = {}, onRestart: ((Date) -> Void)? = nil) {
        self.assets = assets; self.language = language; self.reviewed = reviewed; _selection = selection
        self.onToday = onToday; self.onRestart = onRestart
        _month = State(initialValue: selection.wrappedValue)
        _jumpDate = State(initialValue: selection.wrappedValue)
    }
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(language, zh, en) }
    var body: some View {
        let model = PhotoCalendarMonth(containing: month, assets: assets, reviewed: reviewed, calendar: calendar)
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Button { jumpDate = selection; showJump = true } label: {
                        HStack { Text(monthTitle(model.start)).font(.title3.bold()); Image(systemName: "chevron.down").font(.caption) }
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("calendar.month")
                    Spacer()
                    Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel(c("上个月", "Previous month")).accessibilityIdentifier("calendar.previous")
                    Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(calendar.isDate(model.start, equalTo: Date(), toGranularity: .month))
                        .accessibilityLabel(c("下个月", "Next month")).accessibilityIdentifier("calendar.next")
                }.buttonStyle(.plain)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                    ForEach(0..<7) { index in
                        Text(weekdays[index]).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 8)
                    }
                    ForEach(0..<model.leadingDays, id: \.self) { _ in Color.clear.frame(height: 62).accessibilityHidden(true) }
                    ForEach(model.days) { day in dayButton(day) }
                }
                HStack(spacing: 16) {
                    ForEach([PhotoDayReviewState.unreviewed, .partial, .complete], id: \.self) { state in
                        Label(state.label(language), systemImage: state.symbol).foregroundStyle(state.color)
                            .font(.caption)
                    }
                }.accessibilityIdentifier("calendar.legend")
                if let day = model.days.first(where: { calendar.isDate($0.date, inSameDayAs: selection) }) {
                    VStack(spacing: 4) {
                        Text(c("已选 \(calendar.component(.month, from: selection))月\(calendar.component(.day, from: selection))日 · \(day.count) 张图片", "Selected \(selection.formatted(date: .abbreviated, time: .omitted)) · \(day.count) photos"))
                        if day.count > 0 { Text(c("已整理 \(day.reviewedCount) 张", "\(day.reviewedCount) reviewed")).foregroundStyle(day.state.color) }
                    }.font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("calendar.selection")
                }
            }.frame(maxWidth: 600).padding(20).frame(maxWidth: .infinity)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if let offset = PhotoCalendarNavigation.offset(for: value.translation) { moveMonth(offset) }
        })
        .background(LibraryStyle.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
                    Button(c("回到今天", "Today")) {
                        selection = Date(); month = selection; onToday()
                    }.frame(minHeight: 44).accessibilityIdentifier("calendar.today")
                    Spacer(minLength: 8)
                    if calendar.isDate(selection, equalTo: month, toGranularity: .month), assets.contains(where: { $0.date.map { calendar.isDate($0, inSameDayAs: selection) } ?? false }), let onRestart {
                        Button(c("重新整理当天", "Review this day again")) { onRestart(selection) }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("calendar.restart")
                    }
                }.foregroundStyle(LibraryStyle.mint).frame(maxWidth: 600).padding(.horizontal, 20).padding(.vertical, 8)
            }.frame(maxWidth: .infinity).background(LibraryStyle.background)
        }
        .sheet(isPresented: $showJump) {
            NavigationStack {
                DatePicker(c("跳转日期", "Jump to date"), selection: $jumpDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().padding().background(LibraryStyle.background)
                    .navigationTitle(c("跳转日期", "Jump to date")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { showJump = false } }
                        ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { selection = jumpDate; month = jumpDate; showJump = false } }
                    }
            }.presentationDetents([.medium])
                .environment(\.locale, calendar.locale ?? .current)
        }
    }
    private var weekdays: [String] {
        let formatter = DateFormatter(); formatter.locale = calendar.locale; formatter.calendar = calendar
        let names = formatter.shortStandaloneWeekdaySymbols!
        return (0..<7).map { names[($0 + calendar.firstWeekday - 1) % 7] }
    }
    private func dayButton(_ day: PhotoCalendarMonth.Day) -> some View {
        let selected = calendar.isDate(day.date, inSameDayAs: selection)
        let future = day.date > calendar.startOfDay(for: Date())
        return Button { selection = day.date } label: {
            VStack(spacing: 3) {
                Text("\(day.number)").font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(selected ? LibraryStyle.background : (calendar.isDateInToday(day.date) ? LibraryStyle.mint : .primary))
                    .background(selected ? LibraryStyle.mint : .clear, in: Circle())
                HStack(spacing: 2) {
                    if day.count > 0 && !future { Image(systemName: day.state.symbol).font(.system(size: 8, weight: .semibold)) }
                    Text(future ? " " : c("\(day.count)张", "\(day.count)"))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                }.font(.caption2).foregroundStyle(day.state.color)
            }.frame(maxWidth: .infinity, minHeight: 62).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(future).opacity(future ? 0.3 : 1)
        .accessibilityLabel(c("\(calendar.component(.month, from: day.date))月\(day.number)日，\(day.count) 张图片", "\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) photos"))
        .accessibilityValue(c("\(day.count) 张图片，已整理 \(day.reviewedCount) 张，", "\(day.count) photos, \(day.reviewedCount) reviewed, ") + day.state.label(language))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(String(format: "calendar.day.%04d-%02d-%02d", calendar.component(.year, from: day.date), calendar.component(.month, from: day.date), day.number))
    }
    private func moveMonth(_ offset: Int) {
        if let next = PhotoCalendarNavigation.month(by: offset, from: month, today: Date(), calendar: calendar) {
            withAnimation(.easeInOut(duration: 0.2)) { month = next }
        }
    }
    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = calendar.locale; formatter.calendar = calendar
        formatter.dateFormat = language == .english ? "MMMM yyyy" : "yyyy年M月"
        return formatter.string(from: date)
    }
}
