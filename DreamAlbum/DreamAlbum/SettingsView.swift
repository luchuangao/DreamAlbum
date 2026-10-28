import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.albumTheme) private var theme
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.mistBlue.rawValue
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var reminder: PhotoSortingReminder
    @State private var showingPending = false
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ProfileAvatarPicker(size: 42)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(c("照片与画册", "Photos & albums")).font(.headline)
                            Text(library.hasAccess
                                 ? c("\(library.photos.count) 张照片 · \(store.activeDreams.count) 本画册", "\(library.photos.count) photos · \(store.activeDreams.count) albums")
                                 : c("\(store.activeDreams.count) 本画册", "\(store.activeDreams.count) albums"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }.listRowBackground(theme.surface)
                Section(c("照片管理", "Photo management")) {
                    NavigationLink { PhotoBrowserView().libraryErrorAlert() } label: {
                        managementRow("photo.on.rectangle", c("全部照片", "All photos"), library.hasAccess ? "\(library.photos.count)" : "—")
                    }.accessibilityIdentifier("management.photos")
                    NavigationLink { PhotoGroupsView().toolbar(.visible, for: .navigationBar) } label: {
                        managementRow("folder", c("分组", "Albums"), "\(library.groups.count)")
                    }.accessibilityIdentifier("management.groups")
                    Button { showingPending = true } label: {
                        HStack {
                            managementRow("tray", c("待删清单", "Pending deletions"), "\(library.session.pendingDeletion.count)")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.accessibilityIdentifier("management.pending").buttonStyle(.plain)
                }.listRowBackground(theme.surface)
                Section(c("画册管理", "Dream albums")) {
                    NavigationLink { DreamGalleryView().toolbar(.visible, for: .navigationBar) } label: {
                        managementRow("book", c("梦想画册", "Dream albums"), "\(store.activeDreams.count)")
                    }.accessibilityIdentifier("management.dreams")
                    NavigationLink { ArchivedDreamAlbumsView() } label: {
                        managementRow("archivebox", c("归档画册", "Archived albums"), "\(store.archivedDreams.count)")
                    }.accessibilityIdentifier("management.archived")
                    NavigationLink { AlbumPreferencesView() } label: {
                        managementRow("slider.horizontal.3", c("画册设置", "Album settings"))
                    }.accessibilityIdentifier("management.albumSettings")
                }.listRowBackground(theme.surface)
                Section {
                    NavigationLink { SortingReminderSettingsView() } label: {
                        managementRow("bell", c("提醒设置", "Reminders"), reminder.enabled || store.isDailyReminderEnabled ? c("已开启", "On") : c("已关闭", "Off"))
                    }.accessibilityIdentifier("settings.reminders")
                    NavigationLink { AppThemePicker() } label: {
                        managementRow("paintpalette", c("背景主题", "Background theme"), AppTheme.resolve(themeID).title(store.appLanguage))
                    }.accessibilityIdentifier("settings.theme")
                    Picker(selection: $store.appLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    } label: { Label(c("语言", "Language"), systemImage: "globe") }
                    Button { openPhotoSettings() } label: {
                        managementRow("lock.shield", c("照片权限", "Photo access"), permissionLabel)
                    }.buttonStyle(.plain).accessibilityIdentifier("management.permissions")
                    if library.authorization == .limited {
                        Button(c("管理可访问照片", "Manage accessible photos")) { manageLimitedPhotos() }
                    }
                } header: { Text(c("设置", "Settings")) } footer: {
                    Text(c("画册支持 iCloud 同步，整理进度保存在本机。", "Albums support iCloud sync. Review progress stays on this device."))
                }.listRowBackground(theme.surface)
            }
            .listStyle(.insetGrouped).listSectionSpacing(20)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPending) { NavigationStack { PendingPhotosView() } }
        }
    }
    private func managementRow(_ icon: String, _ title: String, _ value: String = "") -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 24)
            Text(title).foregroundStyle(theme.primary)
            Spacer(minLength: 8)
            if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
        }.frame(minHeight: 32).contentShape(Rectangle())
    }
    private var permissionLabel: String {
        switch library.authorization {
        case .authorized: return c("完整访问", "Full access")
        case .limited: return c("部分照片", "Limited")
        case .restricted: return c("系统限制", "Restricted")
        case .denied: return c("未允许", "Denied")
        default: return c("尚未授权", "Not requested")
        }
    }
}

private struct SortingReminderSettingsView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var store: DreamStore
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            PhotoSortingReminderSection()
            Section {
                Toggle(c("梦想提醒", "Dream reminder"), isOn: $store.isDailyReminderEnabled)
                if store.isDailyReminderEnabled {
                    DatePicker(c("提醒时间", "Reminder time"), selection: $store.dailyReminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: { Text(c("提醒你回来看看梦想画面。", "A reminder to revisit your dreams.")) }
                .listRowBackground(theme.surface)
        }.scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle(c("提醒设置", "Reminders")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct AlbumPreferencesView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var store: DreamStore
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            Section {
                Picker(c("成长足迹样式", "Footprint style"), selection: $store.timelineDisplayStyle) {
                    ForEach(TimelineDisplayStyle.allCases) { Text($0.title(language: store.appLanguage)).tag($0) }
                }
                Toggle(c("显示心情曲线", "Show mood curve"), isOn: $store.isMoodChartEnabled)
            }.listRowBackground(theme.surface)
        }.scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle(c("画册设置", "Album settings")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}

private struct ArchivedDreamAlbumsView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var store: DreamStore
    @State private var showingPremium = false
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        List {
            if store.archivedDreams.isEmpty { Text(c("暂无归档画册", "No archived albums")).foregroundStyle(.secondary) }
            ForEach(store.archivedDreams) { dream in
                NavigationLink { DreamDetailView(dream: dream).toolbar(.visible, for: .navigationBar) } label: {
                    HStack(spacing: 12) {
                        MagazineCollageView(paths: dream.imagePaths, cornerRadius: 10, showCountBadge: false).frame(width: 48, height: 48)
                        Text(dream.title).foregroundStyle(.primary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(c("恢复", "Restore")) { restore(dream) }.tint(theme.accent)
                }
                .contextMenu { Button(c("恢复", "Restore"), systemImage: "arrow.uturn.backward") { restore(dream) } }
            }.listRowBackground(theme.surface)
        }.scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle(c("归档画册", "Archived albums")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showingPremium) { PremiumUnlockSheet() }
    }
    private func restore(_ dream: Dream) {
        if store.canCreateDream { store.restore(dream) } else { showingPremium = true }
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
    @Environment(\.albumTheme) private var theme
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
                            .foregroundStyle(theme.accent)
                            .frame(width: 58, height: 58)
                            .background(theme.accent.opacity(0.14), in: Circle())

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
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                                .background(theme.accent, in: Capsule())
                                .foregroundStyle(theme.background)
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
                            .foregroundStyle(theme.accent)
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
    @Environment(\.albumTheme) private var theme
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.black))
                .foregroundStyle(theme.accent)
                .frame(width: 36, height: 36)
                .background(theme.accent.opacity(0.12), in: Circle())

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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
