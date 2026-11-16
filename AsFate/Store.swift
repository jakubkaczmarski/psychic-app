import StoreKit

/// Fate+ subscriptions with StoreKit 2: loads the products, buys and restores them, and keeps
/// `AppState.isPlus` in sync with the App Store's verified entitlements.
///
/// The product IDs must match the auto-renewable subscriptions in App Store Connect (one group,
/// "Fate+"). `AsFate.storekit` defines the same products for testing: run the **AsFate**
/// scheme from Xcode and purchases go through that file, without App Store Connect or charges.
@MainActor
final class Store: ObservableObject {
    static let yearlyID = "com.jakubkaczmarski.asfate.plus.yearly"
    static let weeklyID = "com.jakubkaczmarski.asfate.plus.weekly"
    static let productIDs = [yearlyID, weeklyID]

    @Published private(set) var products: [String: Product] = [:]
    /// The user can still get the yearly plan's free trial (one per Apple ID per subscription group).
    @Published private(set) var trialEligible = true
    /// Products were requested and the App Store returned none (offline, or not set up yet).
    @Published private(set) var unavailable = false
    @Published private(set) var hasPlus = false

    private var onChange: ((Bool) -> Void)?
    private var updates: Task<Void, Never>?

    /// Call once at launch. `onChange` gets every entitlement check, starting with this launch's.
    func start(onChange: @escaping (Bool) -> Void) {
        guard updates == nil else { return }
        self.onChange = onChange
        // Renewals, refunds, Ask to Buy approvals and purchases made on other devices.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            unavailable = list.isEmpty
            if let yearly = products[Self.yearlyID], let subscription = yearly.subscription {
                trialEligible = await subscription.isEligibleForIntroOffer
            }
        } catch {
            unavailable = true
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = true
        }
        hasPlus = active
        onChange?(active)
    }

    enum PurchaseOutcome {
        case purchased(Transaction)
        case cancelled
        /// Waiting for approval (Ask to Buy, or a payment that needs action).
        case pending
        case failed(reason: String)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed(reason: "unverified") }
                await transaction.finish()
                await refreshEntitlements()
                return .purchased(transaction)
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed(reason: "unknown")
            }
        } catch {
            return .failed(reason: Self.reason(error))
        }
    }

    enum RestoreOutcome { case restored, nothingFound, cancelled, failed(reason: String) }

    /// Asks the App Store for this Apple ID's purchases (may show a sign-in sheet).
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(reason: Self.reason(error))
        }
        await refreshEntitlements()
        return hasPlus ? .restored : .nothingFound
    }

    /// A short category for analytics, without any personal details.
    private static func reason(_ error: Error) -> String {
        switch error {
        case StoreKitError.networkError: return "network"
        case StoreKitError.userCancelled: return "cancelled"
        case StoreKitError.notAvailableInStorefront: return "notInStorefront"
        case StoreKitError.notEntitled: return "notEntitled"
        case StoreKitError.systemError: return "system"
        case is Product.PurchaseError: return "purchaseError"
        default: return "other"
        }
    }
}

extension Product {
    /// "3 days free" when this subscription starts with a free trial, otherwise nil.
    var freeTrialText: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "day"
        }
        return "\(period.value) \(unit)\(period.value == 1 ? "" : "s") free"
    }
}
