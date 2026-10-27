import SwiftUI
import WidgetKit

struct DreamAlbumWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DreamWidgetSnapshot
}

struct DreamAlbumWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DreamAlbumWidgetEntry {
        DreamAlbumWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DreamAlbumWidgetEntry) -> Void) {
        completion(DreamAlbumWidgetEntry(date: Date(), snapshot: DreamWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DreamAlbumWidgetEntry>) -> Void) {
        let entry = DreamAlbumWidgetEntry(date: Date(), snapshot: DreamWidgetSnapshotStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DreamAlbumWidgetView: View {
    let entry: DreamAlbumWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            background
            if family == .accessoryRectangular {
                lockRectangularContent
            } else if family == .accessoryInline {
                lockInlineContent
            } else if family == .systemSmall {
                albumImageContent(previewImage ?? coverImage)
            } else {
                albumImageContent(previewImage ?? coverImage)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.84, green: 0.93, blue: 0.98), Color(red: 0.96, green: 0.98, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var background: some View {
        ZStack {
            if previewImage != nil, family != .accessoryRectangular, family != .accessoryInline {
                Color.clear
            } else if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.12), .black.opacity(0.48)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    colors: [Color(red: 0.74, green: 0.88, blue: 0.96), Color(red: 0.94, green: 0.97, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func albumImageContent(_ image: UIImage?) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                smallContent
            }
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("梦想相册")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white.opacity(coverImage == nil ? 0.78 : 0.88))
            Spacer()
            Text(entry.snapshot.title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(coverImage == nil ? Color(red: 0.06, green: 0.13, blue: 0.18) : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text("\(entry.snapshot.recordCount) 条记录 · \(entry.snapshot.imageCount) 张画面")
                .font(.caption2.weight(.bold))
                .foregroundStyle(coverImage == nil ? Color(red: 0.22, green: 0.34, blue: 0.40) : .white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    private var lockRectangularContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.snapshot.title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .lineLimit(1)
            Text(displayText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("\(entry.snapshot.recordCount) 条记录 · \(entry.snapshot.imageCount) 张画面")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var lockInlineContent: some View {
        Text("\(entry.snapshot.title) · \(entry.snapshot.recordCount) 条记录")
    }

    private var mediumContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("让梦想在眼前")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(coverImage == nil ? 0.78 : 0.90))
                Text(entry.snapshot.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(coverImage == nil ? Color(red: 0.06, green: 0.13, blue: 0.18) : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(displayText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coverImage == nil ? Color(red: 0.22, green: 0.34, blue: 0.40) : .white.opacity(0.88))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 8) {
                stat(value: "\(entry.snapshot.recordCount)", label: "记录")
                stat(value: "\(entry.snapshot.imageCount)", label: "画面")
            }
        }
        .padding(16)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
            Text(label)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(coverImage == nil ? Color(red: 0.06, green: 0.13, blue: 0.18) : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(coverImage == nil ? 0.55 : 0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var displayText: String {
        if !entry.snapshot.latestRecord.isEmpty {
            return entry.snapshot.latestRecord
        }
        if !entry.snapshot.visionText.isEmpty {
            return entry.snapshot.visionText
        }
        return "让梦想变具体，让未来在进行时"
    }

    private var coverImage: UIImage? {
        guard let url = DreamWidgetSnapshotStore.coverURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private var previewImage: UIImage? {
        let url = family == .systemMedium ? DreamWidgetSnapshotStore.mediumAlbumURL : DreamWidgetSnapshotStore.smallAlbumURL
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

@main
struct DreamAlbumWidget: Widget {
    let kind = "DreamAlbumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DreamAlbumWidgetProvider()) { entry in
            DreamAlbumWidgetView(entry: entry)
        }
        .configurationDisplayName("梦想相册")
        .description("把当前梦想放到手机屏幕上。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
