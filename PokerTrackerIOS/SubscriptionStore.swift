//
//  SubscriptionStore.swift
//  PokerTrackerIOS
//
//  StoreKit 2 subscription: $1.99/month with 1 month free trial (Premium).
//  Create product "pro_monthly" (or full ID) in App Store Connect with introductory offer.
//

import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    /// Product ID — must match App Store Connect (e.g. "pro_monthly" or "com.yourapp.pokertracker.pro_monthly")
    static let proMonthlyProductID = "pro_monthly"
    static var fullyQualifiedProductID: String? {
        Bundle.main.bundleIdentifier.map { "\($0).\(proMonthlyProductID)" }
    }
    static var candidateProductIDs: [String] {
        var ids = [proMonthlyProductID]
        if let fullyQualifiedProductID, fullyQualifiedProductID != proMonthlyProductID {
            ids.append(fullyQualifiedProductID)
        }
        return ids
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var updateListenerTask: Task<Void, Never>?

    init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedState()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            products = try await Product.products(for: Self.candidateProductIDs)
            if products.isEmpty {
                errorMessage = "Subscription product not found. Configure in App Store Connect."
            }
        } catch {
            errorMessage = error.localizedDescription
            products = []
        }
        isLoading = false
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            refreshSubscriptionState()
            await updatePurchasedState()
            await transaction.finish()
            return transaction
        case .userCancelled:
            return nil
        case .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        do {
            try await AppStore.sync()
            await updatePurchasedState()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func updatePurchasedState() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        purchasedProductIDs = ids
        refreshSubscriptionState()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await updatePurchasedState()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let t):
            return t
        }
    }

    private func refreshSubscriptionState() {
        isSubscribed = purchasedProductIDs.contains(where: Self.matchesProMonthlyProductID)
    }

    var proMonthlyProduct: Product? {
        products.first { Self.matchesProMonthlyProductID($0.id) }
    }

    /// Human-readable subscription summary (e.g. "$1.99/month, 1 month free")
    var subscriptionDisplayPrice: String? {
        guard let p = proMonthlyProduct else { return nil }
        var text = recurringPriceDescription(for: p)
        if let intro = p.subscription?.introductoryOffer {
            switch intro.paymentMode {
            case .freeTrial:
                text += ", \(countedPeriodDescription(for: intro.period)) free trial"
            default:
                break
            }
        }
        return text
    }

    func recurringPriceDescription(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        return "\(product.displayPrice)/\(periodDescription(for: period))"
    }

    func purchaseFooterText(for product: Product) -> String {
        let recurringPrice = recurringPriceDescription(for: product)
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Then \(recurringPrice). Cancel anytime."
        }
        return "\(recurringPrice). Cancel anytime."
    }

    /// Call from UI when purchase or other operations fail, or to clear the message.
    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    private static func matchesProMonthlyProductID(_ productID: String) -> Bool {
        productID == proMonthlyProductID || productID.hasSuffix(".\(proMonthlyProductID)")
    }

    private func periodDescription(for period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day:
            unit = period.value == 1 ? "day" : "days"
        case .week:
            unit = period.value == 1 ? "week" : "weeks"
        case .month:
            unit = period.value == 1 ? "month" : "months"
        case .year:
            unit = period.value == 1 ? "year" : "years"
        @unknown default:
            unit = period.value == 1 ? "period" : "periods"
        }

        if period.value == 1 {
            return unit
        }
        return "\(period.value) \(unit)"
    }

    private func countedPeriodDescription(for period: Product.SubscriptionPeriod) -> String {
        if period.value == 1 {
            return "1 \(periodDescription(for: period))"
        }
        return periodDescription(for: period)
    }
}

enum StoreError: Error {
    case failedVerification
}
