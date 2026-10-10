//
// RevenueCatManager.swift
// LogYourBody
//
// Handles all RevenueCat subscription management and in-app purchases
//
import Foundation
import Combine
import RevenueCat
import SwiftUI

struct CachedPaywallOfferingDisplay: Codable, Equatable {
    struct PackageDisplay: Codable, Equatable {
        let packageIdentifier: String
        let productIdentifier: String
        let localizedPrice: String
        let billingPeriod: String
        let trialText: String?
    }

    let generatedAt: Date
    let packages: [PackageDisplay]

    var preferredPackage: PackageDisplay? {
        packages.first { $0.packageIdentifier == ProductRegistry.Paywall.annualPackageID }
            ?? packages.first { $0.billingPeriod == "year" }
            ?? packages.first { $0.packageIdentifier == ProductRegistry.Paywall.monthlyPackageID }
            ?? packages.first
    }

    var isEmpty: Bool {
        packages.isEmpty
    }
}

struct PaywallPackageDisplay: Identifiable, Equatable {
    let id: String
    let packageIdentifier: String
    let productIdentifier: String
    let planTitle: String
    let localizedPrice: String
    let billingPeriod: String
    let billingPeriodSuffix: String
    let summaryText: String
    let trialText: String?
    let savingsBadgeText: String?
    let purchaseButtonTitle: String
    let accessibilityIdentifierSuffix: String
}

enum PaywallSavingsPolicy {
    static func monthlyEquivalent(annualPrice: Decimal) -> NSDecimalNumber? {
        let annual = NSDecimalNumber(decimal: annualPrice)
        guard annual.compare(NSDecimalNumber.zero) == .orderedDescending else {
            return nil
        }

        return annual.dividing(by: NSDecimalNumber(value: 12))
    }

    static func savingsPercent(monthlyPrice: Decimal, annualPrice: Decimal) -> Int? {
        let monthly = NSDecimalNumber(decimal: monthlyPrice)
        let annual = NSDecimalNumber(decimal: annualPrice)

        guard monthly.compare(NSDecimalNumber.zero) == .orderedDescending,
              annual.compare(NSDecimalNumber.zero) == .orderedDescending else {
            return nil
        }

        let fullYearAtMonthlyPrice = monthly.multiplying(by: NSDecimalNumber(value: 12))
        guard fullYearAtMonthlyPrice.compare(annual) == .orderedDescending else {
            return nil
        }

        let rawPercent = fullYearAtMonthlyPrice
            .subtracting(annual)
            .dividing(by: fullYearAtMonthlyPrice)
            .multiplying(by: NSDecimalNumber(value: 100))

        let roundedPercent = rawPercent.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )

        return max(roundedPercent.intValue, 0)
    }
}

enum RevenueCatSubscriptionAnalyticsPhase: String {
    case none
    case trial
    case paid
    case expiredUnpaid = "expired_unpaid"
}

enum RevenueCatTrialAnalyticsEvent: String {
    case trialStart = "trial_start"
    case trialConvertedToPaid = "trial_converted_to_paid"
    case trialExpiredUnpaid = "trial_expired_unpaid"
}

struct RevenueCatSubscriptionAnalyticsTransition {
    static func event(
        from previousPhase: RevenueCatSubscriptionAnalyticsPhase,
        to currentPhase: RevenueCatSubscriptionAnalyticsPhase
    ) -> RevenueCatTrialAnalyticsEvent? {
        switch (previousPhase, currentPhase) {
        case (.trial, .paid):
            return .trialConvertedToPaid
        case (.trial, .expiredUnpaid):
            return .trialExpiredUnpaid
        case (_, .trial) where previousPhase != .trial:
            return .trialStart
        default:
            return nil
        }
    }
}

struct RevenueCatEntitlementSnapshot: Equatable {
    let isActive: Bool
    let expirationDate: Date?
    let periodType: PeriodType
    let willRenew: Bool
    let productIdentifier: String
    let unsubscribeDetectedAt: Date?
}

struct RevenueCatCustomerSnapshot {
    let customerInfo: CustomerInfo?
    let originalAppUserId: String
    let entitlement: RevenueCatEntitlementSnapshot?

    init(
        customerInfo: CustomerInfo? = nil,
        originalAppUserId: String,
        entitlement: RevenueCatEntitlementSnapshot?
    ) {
        self.customerInfo = customerInfo
        self.originalAppUserId = originalAppUserId
        self.entitlement = entitlement
    }

    init(customerInfo: CustomerInfo, entitlementID: String) {
        let entitlement = customerInfo.entitlements[entitlementID]
        self.init(
            customerInfo: customerInfo,
            originalAppUserId: customerInfo.originalAppUserId,
            entitlement: entitlement.map {
                RevenueCatEntitlementSnapshot(
                    isActive: $0.isActive,
                    expirationDate: $0.expirationDate,
                    periodType: $0.periodType,
                    willRenew: $0.willRenew,
                    productIdentifier: $0.productIdentifier,
                    unsubscribeDetectedAt: $0.unsubscribeDetectedAt
                )
            }
        )
    }
}

enum RevenueCatPurchasingError: Error, Equatable {
    case purchaseCancelled
    case storeProblem
    case purchaseNotAllowed
    case purchaseInvalid
    case unexpected(String)

    static func from(_ error: Error) -> RevenueCatPurchasingError {
        guard let errorCode = error as? ErrorCode else {
            return .unexpected(error.localizedDescription)
        }

        switch errorCode {
        case .purchaseCancelledError:
            return .purchaseCancelled
        case .storeProblemError:
            return .storeProblem
        case .purchaseNotAllowedError:
            return .purchaseNotAllowed
        case .purchaseInvalidError:
            return .purchaseInvalid
        default:
            return .unexpected(error.localizedDescription)
        }
    }
}

enum RevenueCatCustomerInfoRead: Equatable {
    case cached
    case current(expectedAppUserID: String)
}

enum RevenueCatCustomerInfoError: Error {
    case identityChanged
}

@MainActor
protocol RevenueCatPurchasesProtocol: AnyObject {
    func configure(apiKey: String, delegate: PurchasesDelegate)
    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot
    func logOut() async throws
    func customerInfo(entitlementID: String, read: RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot
    func offerings() async throws -> Offerings
    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot
    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot
}

@MainActor
final class LiveRevenueCatPurchasesClient: RevenueCatPurchasesProtocol {
    func configure(apiKey: String, delegate: PurchasesDelegate) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = delegate
    }

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        let (customerInfo, _) = try await Purchases.shared.logIn(userId)
        return RevenueCatCustomerSnapshot(customerInfo: customerInfo, entitlementID: entitlementID)
    }

    func logOut() async throws {
        _ = try await Purchases.shared.logOut()
    }

    func customerInfo(entitlementID: String, read: RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot {
        try await Self.readCustomerInfo(
            read: read,
            currentAppUserID: { Purchases.shared.appUserID },
            fetch: { policy in
                let customerInfo = try await Purchases.shared.customerInfo(fetchPolicy: policy)
                return RevenueCatCustomerSnapshot(customerInfo: customerInfo, entitlementID: entitlementID)
            }
        )
    }

    static func readCustomerInfo(
        read: RevenueCatCustomerInfoRead,
        currentAppUserID: () -> String,
        fetch: (CacheFetchPolicy) async throws -> RevenueCatCustomerSnapshot
    ) async throws -> RevenueCatCustomerSnapshot {
        let expectedAppUserID: String?
        let policy: CacheFetchPolicy
        switch read {
        case .cached:
            expectedAppUserID = nil
            policy = .default
        case .current(let subject):
            expectedAppUserID = subject
            policy = .fetchCurrent
        }
        if let expectedAppUserID, currentAppUserID() != expectedAppUserID {
            throw RevenueCatCustomerInfoError.identityChanged
        }
        let customer = try await fetch(policy)
        if let expectedAppUserID, currentAppUserID() != expectedAppUserID {
            throw RevenueCatCustomerInfoError.identityChanged
        }
        return customer
    }

    func offerings() async throws -> Offerings {
        try await Purchases.shared.offerings()
    }

    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        do {
            let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)
            return RevenueCatCustomerSnapshot(customerInfo: customerInfo, entitlementID: entitlementID)
        } catch {
            throw RevenueCatPurchasingError.from(error)
        }
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            return RevenueCatCustomerSnapshot(customerInfo: customerInfo, entitlementID: entitlementID)
        } catch {
            throw RevenueCatPurchasingError.from(error)
        }
    }
}

@MainActor
class RevenueCatManager: NSObject, ObservableObject {
    static let shared = RevenueCatManager()

    enum DefaultsKey {
        static let isSubscribed = Constants.revenueCatIsSubscribedKey
        static let lastFetchTimestamp = "revenuecat_lastFetchTimestamp"
        static let subscriptionAnalyticsPhase = "revenuecat_subscriptionAnalyticsPhase"
        static let subscriptionAnalyticsAppUserId = "revenuecat_subscriptionAnalyticsAppUserId"
        static let trialExpirationTimestamp = "revenuecat_trialExpirationTimestamp"
        static let cachedPaywallOfferingDisplay = "revenuecat_cachedPaywallOfferingDisplay"
    }

    // MARK: - Published Properties

    /// Whether the user has an active subscription
    @Published var isSubscribed: Bool = false

    /// Current customer info from RevenueCat
    @Published var customerInfo: CustomerInfo?

    /// Available offerings (products) from RevenueCat
    @Published var currentOffering: Offering?

    /// Loading state for purchases
    @Published var isPurchasing: Bool = false

    /// Error message for display
    @Published var errorMessage: String?

    /// Last successfully loaded offering shape, used only for display when offerings fail to load.
    @Published var cachedPaywallOfferingDisplay: CachedPaywallOfferingDisplay?

    // MARK: - Constants

    /// The entitlement identifier that grants pro access
    /// IMPORTANT: This must match the entitlement lookup_key in RevenueCat dashboard
    static let entitlementID = Constants.proEntitlementID

    let proEntitlementID = RevenueCatManager.entitlementID

    /// Cache expiry duration (24 hours)
    let cacheExpiryDuration: TimeInterval = 24 * 60 * 60

    /// Flag to track if SDK has been configured
    var isConfigured: Bool = false

    let purchasesClient: RevenueCatPurchasesProtocol
    let userDefaults: UserDefaults
    var currentEntitlementSnapshot: RevenueCatEntitlementSnapshot?

    struct BillingSessionOwnership: Equatable {
        let subject: String?
        let generation: UInt64
    }

    private var billingSession = BillingSessionOwnership(subject: nil, generation: 0)
    private var pendingBillingSession: BillingSessionOwnership?
    private var delegateRefresh: DelegateRefresh?

    private final class DelegateRefresh {
        let ownership: BillingSessionOwnership
        var needsRefresh = false

        init(ownership: BillingSessionOwnership) {
            self.ownership = ownership
        }
    }

    func beginBillingSession(subject: String?) -> BillingSessionOwnership {
        // A fresh login, including the same subject, replaces pending billing work.
        billingSession = BillingSessionOwnership(subject: subject, generation: billingSession.generation &+ 1)
        pendingBillingSession = billingSession
        return billingSession
    }

    func finishBillingSession(_ ownership: BillingSessionOwnership) {
        guard pendingBillingSession == ownership else { return }
        pendingBillingSession = nil
    }

    func captureBillingSession() -> BillingSessionOwnership? {
        // The SDK may still hold the previous identity during login/logout.
        guard pendingBillingSession == nil else { return nil }
        return billingSession
    }

    func ownsBillingSession(_ ownership: BillingSessionOwnership) -> Bool {
        billingSession == ownership
    }

    /// Delegate payloads can belong to an earlier SDK identity. Read the current owner instead.
    func refreshForDelegate(appUserID: String) async {
        guard isConfigured, !Task.isCancelled, let ownership = captureBillingSession() else { return }
        guard let subject = ownership.subject, !subject.isEmpty, subject == appUserID else { return }
        if let delegateRefresh, delegateRefresh.ownership == ownership {
            delegateRefresh.needsRefresh = true
            return
        }
        let refresh = DelegateRefresh(ownership: ownership)
        delegateRefresh = refresh
        defer {
            if delegateRefresh === refresh { delegateRefresh = nil }
        }
        repeat {
            refresh.needsRefresh = false
            guard await performOwnedDelegateRefresh(refresh, subject: subject) else { return }
        } while refresh.needsRefresh
    }

    private func performOwnedDelegateRefresh(_ refresh: DelegateRefresh, subject: String) async -> Bool {
        guard ownsBillingSession(refresh.ownership), !Task.isCancelled, delegateRefresh === refresh else { return false }
        do {
            let customer = try await purchasesClient.customerInfo(
                entitlementID: proEntitlementID,
                read: .current(expectedAppUserID: subject)
            )
            guard ownsBillingSession(refresh.ownership), !Task.isCancelled, delegateRefresh === refresh else { return false }
            updateSubscriptionStatus(customer: customer)
            return true
        } catch {
            guard ownsBillingSession(refresh.ownership), !Task.isCancelled, delegateRefresh === refresh else { return false }
            // Preserve access on failure and drain only an explicitly coalesced notification.
            ErrorReporter.shared.capture(
                AppError.billing(operation: "delegateCustomerInfo", underlying: error),
                context: ErrorContext(feature: "billing", operation: "delegateCustomerInfo", screen: nil, userId: subject)
            )
            return true
        }
    }

    #if DEBUG
    /// Keeps the paywall unavailable-state fixture deterministic without touching production purchase paths.
    var shouldForceOfferingsUnavailableForUITests = false
    #endif

    // MARK: - Initialization

    override convenience init() {
        self.init(purchasesClient: LiveRevenueCatPurchasesClient(), userDefaults: .standard)
    }

    init(
        purchasesClient: RevenueCatPurchasesProtocol,
        userDefaults: UserDefaults = .standard
    ) {
        self.purchasesClient = purchasesClient
        self.userDefaults = userDefaults
        super.init()
        // print("💰 RevenueCatManager initialized")

        // Load cached subscription status for instant UI update
        self.isSubscribed = cachedIsSubscribed
        self.cachedPaywallOfferingDisplay = loadCachedPaywallOfferingDisplay()
        // print("💰 Loaded cached subscription status: \(cachedIsSubscribed)")
    }


    #if DEBUG


    #endif
}

typealias SubscriptionManager = RevenueCatManager

// MARK: - PurchasesDelegate

extension RevenueCatManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated _: CustomerInfo) {
        let appUserID = purchases.appUserID
        Task { @MainActor [weak self] in
            await self?.refreshForDelegate(appUserID: appUserID)
        }
    }
}

// MARK: - Helper Extensions

extension SubscriptionPeriod.Unit {
    var description: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}
