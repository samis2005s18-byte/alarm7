import Observation
import StoreKit

/// StoreKit 2 subscription state: loads the two plans, buys, restores, and
/// tracks whether the user currently has an active Pro subscription.
@MainActor @Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    static let monthlyID = "alarm7.pro.monthly"
    static let yearlyID = "alarm7.pro.yearly"   // must match the ID in App Store Connect
    /// Pro isn't on sale yet: the paywall shows "Coming soon" and nothing can
    /// be bought. Flip to true once the subscriptions exist in App Store Connect.
    static let purchasesEnabled = false

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    private init() {
        // Purchases made outside the paywall (renewals, Ask to Buy approvals, other devices).
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    /// Call once at launch and whenever the paywall opens.
    func start() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.yearlyID])
            errorMessage = products.isEmpty ? "Plans aren't available right now." : nil
        } catch {
            errorMessage = "Couldn't load plans: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .pending:
                errorMessage = "Purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro { errorMessage = "No active subscription found to restore." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Entitlements

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            errorMessage = "Purchase couldn't be verified."
            return
        }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  [Self.monthlyID, Self.yearlyID].contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = true
        }
        isPro = active
    }
}
