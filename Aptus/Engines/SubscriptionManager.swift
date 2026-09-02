//
//  SubscriptionManager.swift
//  Aptus
//
//  StoreKit 2 subscription state for Aptus Pro. Observable singleton the whole app
//  binds to via `SubscriptionManager.shared`. Loads the two auto-renewable products,
//  drives purchase/restore, and keeps `isPro` current by listening to
//  `Transaction.updates` for the lifetime of the app. The entitlement is cached in
//  UserDefaults so a returning user stays Pro while offline (re-verified once StoreKit
//  reports current entitlements).
//
//  COMPLIANCE:
//   - 3.1.1 — purchases go through StoreKit only; `restore()` is exposed for the paywall.
//   - 3.1.2 — pricing/trial come straight from `Product` (localized, authoritative).
//
//  iOS: StoreKit 2 is iOS 15+. The app targets iOS 18, so the APIs are always
//  available; the explicit `if #available(iOS 15.0, *)` guards are kept per spec and
//  make the intent obvious. Pure StoreKit — no third-party dependencies.
//

import Foundation
import StoreKit

@MainActor
public final class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()

    // MARK: Product IDs (shared with the ASC setup guide)
    public enum ProductID {
        public static let monthly = "com.robertapolk.Aptus.pro.monthly"
        public static let yearly  = "com.robertapolk.Aptus.pro.yearly"
        public static var all: [String] { [monthly, yearly] }
    }

    // MARK: Published state
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var isPro: Bool = false
    @Published public private(set) var purchaseInFlight: Bool = false
    @Published public private(set) var lastErrorMessage: String?

    private let entitlementKey = "aptus.pro.entitled.v1"
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Optimistic offline read — corrected by `refreshEntitlements()` on launch.
        isPro = UserDefaults.standard.bool(forKey: entitlementKey)
    }

    /// Call once at app launch. Starts the transaction listener, loads products, and
    /// verifies current entitlements. Safe to call more than once (listener guarded).
    public func start() {
        guard #available(iOS 15.0, *) else { return }
        if updatesTask == nil {
            updatesTask = listenForTransactions()
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: Convenience accessors

    public var monthlyProduct: Product? {
        products.first { $0.id == ProductID.monthly }
    }
    public var yearlyProduct: Product? {
        products.first { $0.id == ProductID.yearly }
    }

    // MARK: Loading

    public func loadProducts() async {
        guard #available(iOS 15.0, *) else { return }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            // Stable order: monthly first, then yearly.
            self.products = loaded.sorted { $0.price < $1.price }
        } catch {
            self.lastErrorMessage = "Couldn't load subscription options. Please try again."
        }
    }

    // MARK: Purchase / restore

    public func purchase(_ product: Product) async {
        guard #available(iOS 15.0, *) else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = verifiedTransaction(verification) {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    lastErrorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Your purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = "Purchase failed. Please try again."
        }
    }

    /// Restores purchases. StoreKit 2 keeps entitlements in sync automatically, but the
    /// paywall's explicit "Restore" (required by Guideline 3.1.1) forces a sync + recheck.
    public func restore() async {
        guard #available(iOS 15.0, *) else { return }
        do {
            try await AppStore.sync()
        } catch {
            lastErrorMessage = "Restore failed. Please try again."
        }
        await refreshEntitlements()
    }

    // MARK: Entitlement verification

    /// Recomputes `isPro` from StoreKit's current entitlements and caches it.
    @available(iOS 15.0, *)
    public func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(result) else { continue }
            if ProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil {
                // For a subscription, currentEntitlements only yields non-expired ones.
                entitled = true
            }
        }
        setPro(entitled)
    }

    @available(iOS 15.0, *)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if let transaction = await self.verifiedTransaction(update) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    @available(iOS 15.0, *)
    private func verifiedTransaction(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let safe): return safe
        case .unverified: return nil
        }
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: entitlementKey)
    }
}
