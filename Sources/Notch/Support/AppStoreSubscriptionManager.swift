import Foundation
import StoreKit

/// Loads products, purchases, and **Pro** entitlement via **StoreKit 2** (Mac App Store).
///
/// 1. In App Store Connect, create an auto-renewable subscription whose Product ID matches
///    ``NotchAppStoreProductIDs/proSubscription``.
/// 2. For local testing without Connect, add a **StoreKit Configuration** file in Xcode and
///    assign the same product ID.
@MainActor
final class AppStoreSubscriptionManager: ObservableObject {
    static let shared = AppStoreSubscriptionManager()

    @Published private(set) var isProEntitled = false
    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private var transactionUpdates: Task<Void, Never>?

    private init() {
        transactionUpdates = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.handle(transactionResult: update)
            }
        }

        Task { await refreshEntitlements() }
    }

    /// Call when the subscription UI appears so price strings are available.
    func loadOfferings() async {
        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [NotchAppStoreProductIDs.proSubscription])
            subscriptionProduct = products.first
            if products.isEmpty {
                lastErrorMessage = "No subscription product returned. Check App Store Connect or StoreKit config."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if NotchAppStoreProductIDs.matchesProSubscription(transaction.productID) {
                entitled = true
                break
            }
        }
        isProEntitled = entitled
    }

    func purchaseSubscription() async {
        lastErrorMessage = nil
        if subscriptionProduct == nil {
            await loadOfferings()
        }
        guard let product = subscriptionProduct else {
            lastErrorMessage = "Subscription is not available."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await process(verification: verification, reportUnverifiedToUser: true)
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        await process(verification: transactionResult, reportUnverifiedToUser: false)
    }

    private func process(verification: VerificationResult<Transaction>, reportUnverifiedToUser: Bool) async {
        switch verification {
        case .verified(let transaction):
            guard NotchAppStoreProductIDs.matchesProSubscription(transaction.productID) else { return }
            await transaction.finish()
            await refreshEntitlements()
        case .unverified:
            if reportUnverifiedToUser {
                lastErrorMessage = "Could not verify the purchase with the App Store."
            }
        }
    }
}

enum NotchAppStoreProductIDs {
    /// Must match the auto-renewable subscription ID in App Store Connect.
    static let proSubscription = "dev.notch.pro"

    static func matchesProSubscription(_ productID: String) -> Bool {
        productID == proSubscription
    }
}
