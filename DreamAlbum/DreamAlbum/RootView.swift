import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var sortingReminder: PhotoSortingReminder
    @Environment(\.scenePhase) private var phase
    var body: some View {
        MainTabView()
            .tint(LibraryStyle.mint)
            .preferredColorScheme(.dark)
            .environment(\.albumBackgroundContrast, .dark)
            .task { sortingReminder.refresh(language: store.appLanguage) }
            .onChange(of: store.appLanguage) { _, value in sortingReminder.refresh(language: value) }
            .onAppear { store.isPremiumUnlocked = purchaseStore.isPremiumUnlocked }
            .onChange(of: purchaseStore.isPremiumUnlocked) { _, value in store.isPremiumUnlocked = value }
            .onChange(of: phase) { _, value in if value == .active { library.scheduleRefresh(); sortingReminder.refresh(language: store.appLanguage) } }
    }
}

private struct PhotoHomeActionKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
private struct PhotoHomeGenerationKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var returnToPhotoHome: () -> Void {
        get { self[PhotoHomeActionKey.self] }
        set { self[PhotoHomeActionKey.self] = newValue }
    }
    var photoHomeGeneration: Int {
        get { self[PhotoHomeGenerationKey.self] }
        set { self[PhotoHomeGenerationKey.self] = newValue }
    }
}

enum MainTab: Hashable { case photos, groups, home, me }

struct MainTabView: View {
    @EnvironmentObject private var store: DreamStore
    @State private var selectedTab: MainTab = .photos
    @State private var photoHomeGeneration = 0
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Group {
        #if targetEnvironment(macCatalyst)
        NavigationSplitView {
            List {
                sidebar(.photos, title: c("照片", "Photos"), icon: "photo")
                sidebar(.groups, title: c("分组", "Albums"), icon: "folder")
                sidebar(.home, title: c("梦想画册", "Dream albums"), icon: "book")
                sidebar(.me, title: c("我的", "Me"), icon: "person.crop.circle")
            }.navigationTitle(c("梦想相册", "Dream Album"))
        } detail: {
            switch selectedTab {
            case .photos: NavigationStack { DailyPhotoInboxView().libraryErrorAlert() }
            case .groups: NavigationStack { PhotoGroupsView() }
            case .home: NavigationStack { DreamGalleryView() }
            case .me: SettingsView()
            }
        }
        #else
        VStack(spacing: 0) {
            ZStack {
                screen(.photos) { NavigationStack { DailyPhotoInboxView().libraryErrorAlert() } }
                screen(.groups) { NavigationStack { PhotoGroupsView() } }
                screen(.home) { NavigationStack { DreamGalleryView() } }
                screen(.me) { SettingsView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                tab(.photos, title: c("照片", "Photos"), icon: "photo", identifier: "tab.photos")
                tab(.groups, title: c("分组", "Albums"), icon: "square.grid.2x2", identifier: "tab.groups")
                tab(.home, title: c("梦想画册", "Dream albums"), icon: "book", identifier: "tab.dreams")
                tab(.me, title: c("我的", "Me"), icon: "person.crop.circle", identifier: "tab.me")
            }
            .padding(.top, 8).background(LibraryStyle.background)
            .overlay(alignment: .top) { Divider() }
        }.background(LibraryStyle.background)
        #endif
        }
        .environment(\.photoHomeGeneration, photoHomeGeneration)
        .environment(\.returnToPhotoHome, {
            selectedTab = .photos
            photoHomeGeneration += 1
        })
    }
    private func screen<Content: View>(_ tab: MainTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .environment(\.libraryScreenActive, selectedTab == tab)
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
            .zIndex(selectedTab == tab ? 1 : 0)
    }
    private func tab(_ tab: MainTab, title: String, icon: String, identifier: String) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: selectedTab == tab ? icon + ".fill" : icon).font(.system(size: 21, weight: .regular))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selectedTab == tab ? LibraryStyle.mint : Color.gray)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }
    private func sidebar(_ tab: MainTab, title: String, icon: String) -> some View {
        Button { selectedTab = tab } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .foregroundStyle(selectedTab == tab ? LibraryStyle.mint : .white)
        }.buttonStyle(.plain)
    }

}
