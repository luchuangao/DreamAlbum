import StoreKit
import SwiftUI

enum PremiumAccess: Equatable {
    case checking, free, unverified, legacy, purchased

    static let freeDailyReviewLimit = 20

    var isUnlocked: Bool { self == .legacy || self == .purchased }
    var reviewLimit: Int? { isUnlocked ? nil : Self.freeDailyReviewLimit }
    var canPurchase: Bool { self == .free }

    func allows(_ kind: CollageKind) -> Bool { kind == .grid || isUnlocked }
    func allowsExport(longEdge: Int) -> Bool { longEdge <= 2048 || isUnlocked }

    static func qualifiesForLegacyAccess(originalVersion: String, production: Bool, catalyst: Bool) -> Bool {
        guard production else { return false }
        if let build = Int(originalVersion) { return (1...25).contains(build) }
        // Catalyst can receive a marketing version for a Mac app transaction.
        guard catalyst, originalVersion.range(of: #"^1\.[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return false }
        return originalVersion.compare("1.3", options: .numeric) == .orderedAscending
    }
}

@MainActor
final class PurchaseStore: ObservableObject {
    static let premiumProductID = "com.luchuangao.mengxiangxiangce.premium"

    enum Message {
        case unavailable, purchaseFailed, pending, restoreFailed, nothingToRestore

        func text(_ language: AppLanguage) -> String {
            switch self {
            case .unavailable: AlbumCopy.pick(language, "暂时无法获取价格，请重试。", "Price unavailable. Please try again.")
            case .purchaseFailed: AlbumCopy.pick(language, "购买未完成，请重试。", "Purchase incomplete. Please try again.")
            case .pending: AlbumCopy.pick(language, "购买正在等待批准。", "Purchase is awaiting approval.")
            case .restoreFailed: AlbumCopy.pick(language, "暂时无法恢复，请重试。", "Could not restore purchases. Please try again.")
            case .nothingToRestore: AlbumCopy.pick(language, "当前 Apple 账户暂无可恢复的购买。", "No purchase to restore for this Apple Account.")
            }
        }
    }

    @Published private(set) var access: PremiumAccess = .checking
    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isLoadingPrice = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: Message?

    private var updatesTask: Task<Void, Never>?
    private var appAccess: PremiumAccess = .checking
    private var purchaseIDs: Set<UInt64> = []
    private var revokedPurchaseIDs: Set<UInt64> = []
    private var isRefreshing = false
    private var entitlementRevision = 0
    private let fixtureAccess: PremiumAccess?

    var isPremiumUnlocked: Bool { access.isUnlocked }

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        fixtureAccess = arguments.contains("-premiumFreeFixture") ? .free
            : arguments.contains("-premiumLegacyFixture") || arguments.contains("-dailyInboxFixture") ? .legacy : nil
        #else
        fixtureAccess = nil
        #endif
        if let fixtureAccess {
            access = fixtureAccess
            return
        }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.premiumProductID,
                      transaction.productType == .nonConsumable else { continue }
                self?.apply(transaction)
                await transaction.finish()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        guard premiumProduct == nil, !isLoadingPrice, !access.isUnlocked else { return }
        isLoadingPrice = true
        message = nil
        defer { isLoadingPrice = false }
        do {
            premiumProduct = try await Product.products(for: [Self.premiumProductID]).first { $0.type == .nonConsumable }
            if premiumProduct == nil { message = .unavailable }
        } catch {
            message = .unavailable
        }
    }

    func purchasePremium() async {
        guard !isBusy, access.canPurchase, let premiumProduct else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await premiumProduct.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result, Self.isValidPurchase(transaction) else {
                    message = .purchaseFailed
                    return
                }
                apply(transaction)
                await transaction.finish()
            case .pending: message = .pending
            case .userCancelled: break
            @unknown default: message = .purchaseFailed
            }
        } catch {
            message = .purchaseFailed
        }
    }

    func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refresh()
            if !access.isUnlocked { message = access.canPurchase ? .nothingToRestore : .restoreFailed }
        } catch {
            message = .restoreFailed
        }
    }

    func refresh() async {
        guard fixtureAccess == nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let appTransaction = Self.lookupAppAccess()
        await refreshEntitlements()
        let result = await appTransaction
        if result != .unverified || appAccess == .checking { appAccess = result }
        updateAccess()
    }

    private func refreshEntitlements() async {
        guard fixtureAccess == nil else { return }
        entitlementRevision += 1
        let revision = entitlementRevision
        var current: Set<UInt64> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.isValidPurchase(transaction) {
                current.insert(transaction.id)
            }
        }
        guard entitlementRevision == revision else { return }
        purchaseIDs = current.subtracting(revokedPurchaseIDs)
        updateAccess()
    }

    private func apply(_ transaction: StoreKit.Transaction) {
        entitlementRevision += 1
        if transaction.revocationDate != nil {
            revokedPurchaseIDs.insert(transaction.id)
            purchaseIDs.remove(transaction.id)
        } else if !revokedPurchaseIDs.contains(transaction.id) {
            purchaseIDs.insert(transaction.id)
        }
        updateAccess()
    }

    private func updateAccess() {
        access = purchaseIDs.isEmpty ? appAccess : .purchased
        if access.isUnlocked { message = nil }
    }

    private static func isValidPurchase(_ transaction: StoreKit.Transaction) -> Bool {
        transaction.productID == premiumProductID && transaction.productType == .nonConsumable
            && transaction.revocationDate == nil
    }

    private static func lookupAppAccess() async -> PremiumAccess {
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result,
              transaction.bundleID == Bundle.main.bundleIdentifier else { return .unverified }
        #if targetEnvironment(macCatalyst)
        let catalyst = true
        #else
        let catalyst = false
        #endif
        return PremiumAccess.qualifiesForLegacyAccess(originalVersion: transaction.originalAppVersion,
                                                      production: transaction.environment == .production,
                                                      catalyst: catalyst) ? .legacy : .free
    }
}
