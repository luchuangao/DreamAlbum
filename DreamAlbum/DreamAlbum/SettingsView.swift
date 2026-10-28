import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @State private var isShowingPremium = false
    private func copy(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    private var totalImages: Int { store.dreams.reduce(0) { $0 + $1.imagePaths.count + $1.logs.reduce(0) { $0 + $1.imagePaths.count } } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatarPicker(size: 60)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(copy("梦想相册", "Dream Album")).font(.title2.bold())
                            Text(copy("管理照片与画册", "Manage photos and albums"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                    HStack {
                        metric("\(store.activeDreams.count)", copy("活跃画册", "Active albums"))
                        Spacer()
                        metric("\(store.dreams.reduce(0) { $0 + $1.evidenceCount })", copy("成长记录", "Records"))
                        Spacer()
                        metric("\(totalImages)", copy("收藏画面", "Photos"))
                    }.padding(.vertical, 6)
                }.listRowBackground(LibraryStyle.surface)
                Section { PhotoSettingsCard().listRowInsets(EdgeInsets()).listRowBackground(LibraryStyle.surface) }
                PhotoSortingReminderSection()
                Section(copy("偏好设置", "Preferences")) {
                    Picker(copy("语言", "Language"), selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(copy("成长足迹样式", "Footprint style"), selection: $store.timelineDisplayStyle) {
                        ForEach(TimelineDisplayStyle.allCases) { Text($0.title(language: store.appLanguage)).tag($0) }
                    }
                    Toggle(copy("显示心情曲线", "Show mood curve"), isOn: $store.isMoodChartEnabled)
                }.listRowBackground(LibraryStyle.surface)
                Section {
                    Toggle(copy("梦想提醒", "Dream reminder"), isOn: $store.isDailyReminderEnabled)
                    if store.isDailyReminderEnabled {
                        DatePicker(copy("提醒时间", "Reminder time"), selection: $store.dailyReminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: { Text(copy("在当前设备提醒你回来看看梦想画面。", "A local reminder to revisit your dreams.")) }
                    .listRowBackground(LibraryStyle.surface)
                Section(copy("归档画册", "Archived albums")) {
                    if store.archivedDreams.isEmpty {
                        Text(copy("暂无归档画册", "No archived albums")).foregroundStyle(.secondary)
                    }
                    ForEach(store.archivedDreams) { dream in
                        NavigationLink(value: dream.id) {
                            HStack(spacing: 12) {
                                MagazineCollageView(paths: dream.imagePaths, cornerRadius: 10, showCountBadge: false).frame(width: 48, height: 48)
                                Text(dream.title).foregroundStyle(.primary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(copy("恢复", "Restore")) {
                                if store.canCreateDream { store.restore(dream) } else { isShowingPremium = true }
                            }.tint(LibraryStyle.mint)
                        }
                        .contextMenu {
                            Button(copy("恢复", "Restore"), systemImage: "arrow.uturn.backward") {
                                if store.canCreateDream { store.restore(dream) } else { isShowingPremium = true }
                            }
                        }
                    }
                }.listRowBackground(LibraryStyle.surface)
                Section {
                    Text(copy("画册图片独立保存，支持 iCloud 同步。整理进度仅保存在本机。", "Album images are independent copies with iCloud sync. Review progress stays on this device."))
                        .font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(LibraryStyle.surface)
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let dream = store.dreams.first(where: { $0.id == id }) { DreamDetailView(dream: dream).toolbar(.visible, for: .navigationBar) }
            }
            .sheet(isPresented: $isShowingPremium) {
                PremiumUnlockSheet().environmentObject(store).environmentObject(purchaseStore)
            }
        }
    }
    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ProfileAvatarPicker: View {
    @EnvironmentObject private var store: DreamStore
    @State private var selectedItem: PhotosPickerItem?
	let size: CGFloat

	var body: some View {
		let changeAvatarLabel = AlbumCopy.pick(store.appLanguage, "更换头像", "Change avatar")
		let resetAvatarLabel = AlbumCopy.pick(store.appLanguage, "恢复默认头像", "Use default avatar")

		PhotosPicker(selection: $selectedItem, matching: .images) {
			ZStack(alignment: .bottomTrailing) {
				avatarImage
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.88), lineWidth: max(2, size * 0.04))
                    }
                    .shadow(color: Color.albumInk.opacity(0.16), radius: 14, x: 0, y: 8)

                Image(systemName: "camera.fill")
                    .font(.system(size: max(11, size * 0.18), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(24, size * 0.34), height: max(24, size * 0.34))
                    .background(Color.albumGreen, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 2)
					}
					.offset(x: size * 0.03, y: size * 0.03)
			}
			.accessibilityLabel(changeAvatarLabel)
		}
		.buttonStyle(.plain)
		.contextMenu {
            if !store.avatarImagePath.isEmpty {
				Button(role: .destructive) {
					store.resetAvatar()
				} label: {
					Label(resetAvatarLabel, systemImage: "arrow.counterclockwise")
				}
			}
		}
        .onChange(of: selectedItem) { _, newItem in
            Task { await importAvatar(from: newItem) }
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if !store.avatarImagePath.isEmpty,
           let url = ImageLibrary.imageURL(for: store.avatarImagePath),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image("AppLogoTencentClean")
                .resizable()
                .scaledToFill()
        }
    }

    private func importAvatar(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let path = try? ImageLibrary.saveImageData(data) else {
            await MainActor.run { selectedItem = nil }
            return
        }

        await MainActor.run {
            store.avatarImagePath = path
            selectedItem = nil
        }
    }
}

private struct BackgroundStyleButton: View {
    @EnvironmentObject private var store: DreamStore
    let style: AlbumBackgroundStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(gradient)
                    .frame(height: 42)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.albumGreen : .white.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                    }
                Text(style.title(language: store.appLanguage))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.albumGreen : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var gradient: LinearGradient {
        switch style {
        case .morningMistBlue:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.98), Color(red: 0.82, green: 0.89, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .rainBlue:
            return LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.99), Color(red: 0.76, green: 0.84, blue: 0.90)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .porcelainWhite:
            return LinearGradient(colors: [Color.white, Color(red: 0.92, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottom)
        case .mistPink:
            return LinearGradient(colors: [Color(red: 1.00, green: 0.95, blue: 0.97), Color(red: 0.90, green: 0.86, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .lakeBlue:
            return LinearGradient(colors: [Color(red: 0.90, green: 0.96, blue: 0.97), Color(red: 0.68, green: 0.81, blue: 0.87)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct BackgroundImageButton: View {
    @EnvironmentObject private var store: DreamStore
    let choice: BackgroundImageChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let assetName = choice.assetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.5)
                    }
                }
                .frame(height: 56)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.albumGreen : .white.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.albumGreen, in: Circle())
                            .overlay { Circle().stroke(.white.opacity(0.92), lineWidth: 1.5) }
                            .padding(5)
                    }
                }

                Text(choice.title(language: store.appLanguage))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.albumGreen : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .scaleEffect(isSelected ? 1.015 : 1)
            .shadow(color: isSelected ? Color.albumGreen.opacity(0.18) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct DisplayStyleButton: View {
    @EnvironmentObject private var store: DreamStore
    let style: SettingsDisplayStyle
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isLocked ? "lock.fill" : symbol)
                Text(style.title(language: store.appLanguage))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                if isLocked {
                    Text("Pro")
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.albumGreen.opacity(0.16), in: Capsule())
                }
            }
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.albumGreen.opacity(0.14) : Color.white.opacity(0.58), in: Capsule())
            .foregroundStyle(isSelected ? Color.albumGreen : (isLocked ? Color.albumInk.opacity(0.55) : .secondary))
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.albumGreen.opacity(0.35) : Color.white.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch style {
        case .collage: return "sparkles.rectangle.stack.fill"
        case .beach: return "sun.max.fill"
        case .porcelain: return "seal.fill"
        case .magazine: return "rectangle.stack.fill"
        case .compact: return "list.bullet"
        case .dashboard: return "gauge.with.dots.needle.67percent"
        }
    }
}

private struct TimelineStyleButton: View {
    @EnvironmentObject private var store: DreamStore
    let style: TimelineDisplayStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(style.title(language: store.appLanguage), systemImage: symbol)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .padding(.vertical, 10)
                .background(isSelected ? Color.albumGreen.opacity(0.14) : Color.white.opacity(0.58), in: Capsule())
                .foregroundStyle(isSelected ? Color.albumGreen : .secondary)
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.albumGreen.opacity(0.35) : Color.white.opacity(0.45), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch style {
        case .timeline: return "list.bullet.indent"
        case .card: return "rectangle.stack.fill"
        }
    }
}

struct PremiumUnlockSheet: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(LibraryStyle.mint)
                            .frame(width: 58, height: 58)
                            .background(LibraryStyle.mint.opacity(0.14), in: Circle())

                        Text(copy("解锁梦想相册 Pro", "Unlock Dream Album Pro"))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(copy("不限量画册。", "Unlimited dream albums. Make room for more dreams."))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        PremiumFeatureRow(symbol: "rectangle.stack.fill", title: copy("免费可用", "Included free"), subtitle: copy("照片整理、分组与成长记录", "Photo review, groups, and growth records"))
                        PremiumFeatureRow(symbol: "infinity", title: copy("不限量梦想相册", "Unlimited dream albums"), subtitle: copy("免费版最多 \(DreamStore.freeActiveDreamLimit) 本活跃相册", "Free version supports up to \(DreamStore.freeActiveDreamLimit) active albums"))
                    }

                    if purchaseStore.isPremiumUnlocked {
                        Label(copy("你已经解锁 Pro", "Pro is already unlocked"), systemImage: "checkmark.seal.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(LibraryStyle.mint)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LibraryStyle.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            Button {
                                Task {
                                    await purchaseStore.purchasePremium()
                                    if purchaseStore.isPremiumUnlocked {
                                        dismiss()
                                    }
                                }
                            } label: {
                                HStack {
                                    if purchaseStore.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(copy("解锁 Pro", "Unlock Pro"))
                                    Spacer()
                                    Text(purchaseStore.premiumDisplayPrice)
                                }
                                .font(.headline.weight(.bold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(LibraryStyle.mint, in: Capsule())
                                .foregroundStyle(LibraryStyle.background)
                            }
                            .buttonStyle(.plain)
                            .disabled(purchaseStore.isLoading)

                            Button(copy("恢复购买", "Restore Purchases")) {
                                Task {
                                    await purchaseStore.restorePurchases()
                                    if purchaseStore.isPremiumUnlocked {
                                        dismiss()
                                    }
                                }
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(LibraryStyle.mint)
                            .buttonStyle(.plain)

                            if let message = purchaseStore.purchaseMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(AlbumBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("关闭", "Close")) { dismiss() }
                }
            }
            .task {
                if purchaseStore.premiumProduct == nil {
                    await purchaseStore.loadProducts()
                }
            }
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct PremiumFeatureRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
                .foregroundStyle(LibraryStyle.mint)
                .frame(width: 36, height: 36)
                .background(LibraryStyle.mint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CollageStatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.90), tint.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.68), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.12), radius: 16, x: 0, y: 10)
    }
}

private struct BeachStatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: Circle())
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.albumInk.opacity(0.58))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.90), Color.beachSand.opacity(0.42), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.beachSeaBlue.opacity(0.10), radius: 16, x: 0, y: 10)
    }
}

private struct PorcelainStatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.porcelainBlue, in: Circle())
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.porcelainDeepBlue)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(Color.porcelainDeepBlue.opacity(0.58))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), Color.porcelainMist.opacity(0.58), Color.porcelainBlue.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            PorcelainRimOverlay(cornerRadius: 24)
        }
        .shadow(color: Color.porcelainBlue.opacity(0.10), radius: 16, x: 0, y: 10)
    }
}

private struct CompactStatsList: View {
    @EnvironmentObject private var store: DreamStore
    let totalImages: Int
    let totalEvidence: Int

    var body: some View {
        VStack(spacing: 0) {
            CompactStatRow(value: "\(store.activeDreams.count)", label: copy("活跃梦想", "Active"), symbol: "sparkles")
            Divider().opacity(0.45)
            CompactStatRow(value: "\(store.archivedDreams.count)", label: copy("归档相册", "Archived"), symbol: "archivebox.fill")
            Divider().opacity(0.45)
            CompactStatRow(value: "\(totalEvidence)", label: copy("成长记录", "Records"), symbol: "sparkles")
            Divider().opacity(0.45)
            CompactStatRow(value: "\(totalImages)", label: copy("收藏画面", "Photos"), symbol: "photo.stack")
        }
        .padding(.horizontal, 16)
        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CompactStatRow: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.albumGreen)
                .frame(width: 28)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.albumInk)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Spacer()
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(Color.albumGreen)
        }
        .padding(.vertical, 14)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.albumGreen)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @EnvironmentObject private var store: DreamStore
    let symbol: String
    let title: String
    let subtitle: String
    let content: Content

    init(symbol: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        let isBeachStyle = store.settingsDisplayStyle == .beach
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(isBeachStyle ? Color.beachSeaBlue : Color.albumGreen, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: store.appLanguage == .english ? 19 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(Color.albumInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            content
        }
        .padding(18)
        .background(
            isBeachStyle ? AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.88), Color.beachSand.opacity(0.66)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) : AnyShapeStyle(Color.white.opacity(0.66)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.54), lineWidth: 1)
        }
    }
}

private struct SettingsDisclosureLabel: View {
    @EnvironmentObject private var store: DreamStore
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.albumGreen, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: store.appLanguage == .english ? 19 : 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
