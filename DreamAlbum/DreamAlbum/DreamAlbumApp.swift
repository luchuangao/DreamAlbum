import SwiftUI

@main
struct DreamAlbumApp: App {
    @StateObject private var store = DreamStore()
    @StateObject private var library: PhotoLibraryStore
    @StateObject private var sortingReminder: PhotoSortingReminder

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-dailyInboxFixture") {
            _library = StateObject(wrappedValue: DailyInboxFixture.makeStore())
            let defaults = UserDefaults(suiteName: "dream_album.reminder.uitests")!
            if ProcessInfo.processInfo.arguments.contains("-resetDailyFixture") { defaults.removePersistentDomain(forName: "dream_album.reminder.uitests") }
            _sortingReminder = StateObject(wrappedValue: PhotoSortingReminder(defaults: defaults, service: FixtureSortingNotifications()))
        } else {
            _library = StateObject(wrappedValue: PhotoLibraryStore())
            _sortingReminder = StateObject(wrappedValue: PhotoSortingReminder())
        }
        #else
        _library = StateObject(wrappedValue: PhotoLibraryStore())
        _sortingReminder = StateObject(wrappedValue: PhotoSortingReminder())
        #endif
    }
    @StateObject private var purchaseStore = PurchaseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(library)
                .environmentObject(purchaseStore)
                .environmentObject(sortingReminder)
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}
