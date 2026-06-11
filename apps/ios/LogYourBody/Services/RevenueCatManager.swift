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
        packages.first { $0.packageIdentifier == "$rc_annual" }
            ?? packages.first { $0.billingPeriod == "year" }
            ?? packages.first { $0.packageIdentifier == "$rc_monthly" }
            ?? packages.first
    }

    var isEmpty: Bool {
        packages.isEmpty
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

@MainActor
class RevenueCatManager: NSObject, ObservableObject {
    static let shared = RevenueCatManager()

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
    @Published private(set) var cachedPaywallOfferingDisplay: CachedPaywallOfferingDisplay?

    // MARK: - Cached Properties (AppStorage)

    /// Cached subscription status for faster app startup
    @AppStorage("revenuecat_isSubscribed") private var cachedIsSubscribed: Bool = false

    /// Timestamp of last successful customer info fetch
    @AppStorage("revenuecat_lastFetchTimestamp") private var lastFetchTimestamp: Double = 0

    /// Last locally observed subscription analytics phase for idempotent trial funnel events.
    @AppStorage("revenuecat_subscriptionAnalyticsPhase") private var cachedSubscriptionAnalyticsPhase: String =
        RevenueCatSubscriptionAnalyticsPhase.none.rawValue

    /// RevenueCat app user associated with the cached analytics phase.
    @AppStorage("revenuecat_subscriptionAnalyticsAppUserId") private var cachedSubscriptionAnalyticsAppUserId: String = ""

    /// Last observed trial expiration used to classify canceled trials after they expire.
    @AppStorage("revenuecat_trialExpirationTimestamp") private var cachedTrialExpirationTimestamp: Double = 0

    // MARK: - Constants

    /// The entitlement identifier that grants pro access
    /// IMPORTANT: This must match the entitlement lookup_key in RevenueCat dashboard
    private let proEntitlementID = Constants.proEntitlementID

    /// Cache expiry duration (24 hours)
    private let cacheExpiryDuration: TimeInterval = 24 * 60 * 60

    /// Last successful paywall offering display snapshot.
    private let cachedPaywallOfferingDisplayKey = "revenuecat_cachedPaywallOfferingDisplay"

    /// Flag to track if SDK has been configured
    private var isConfigured: Bool = false

    #if DEBUG
    /// Keeps the paywall unavailable-state fixture deterministic without touching production purchase paths.
    private var shouldForceOfferingsUnavailableForUITests = false
    #endif

    // MARK: - Initialization

    override private init() {
        super.init()
        // print("💰 RevenueCatManager initialized")

        // Load cached subscription status for instant UI update
        self.isSubscribed = cachedIsSubscribed
        self.cachedPaywallOfferingDisplay = loadCachedPaywallOfferingDisplay()
        // print("💰 Loaded cached subscription status: \(cachedIsSubscribed)")
    }

    // MARK: - Configuration

    /// Configure RevenueCat SDK - call this on app launch
    /// Note: Does NOT fetch customer info immediately to avoid blocking UI
    nonisolated func configure(apiKey: String) {
        Task { @MainActor in
            // print("💰 Configuring RevenueCat SDK")

            // Configure SDK
            Purchases.logLevel = .debug
            Purchases.configure(withAPIKey: apiKey)

            // Set up delegate to listen for customer info updates
            Purchases.shared.delegate = self

            // Mark configured only after delegate wiring finishes to avoid race conditions
            self.markAsConfigured()

            // print("💰 RevenueCat SDK configured successfully")
        }
    }

    /// Mark SDK as configured after delegate setup completes
    @MainActor
    func markAsConfigured() {
        isConfigured = true
        // print("✅ SDK marked as configured")
    }

    /// Identify the user with their Clerk user ID
    func identifyUser(userId: String) async {
        guard isConfigured else {
            // print("⚠️ SDK not configured yet, skipping identifyUser()")
            return
        }

        // print("💰 Identifying user: \(userId)")

        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run {
                self.updateSubscriptionStatus(customerInfo: customerInfo)
            }
            // print("💰 User identified successfully")
        } catch {
            let appError = AppError.billing(operation: "identifyUser", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "identifyUser",
                screen: nil,
                userId: userId
            )
            ErrorReporter.shared.capture(appError, context: context)

            await MainActor.run {
                self.errorMessage = "Failed to link account: \(error.localizedDescription)"
            }
        }
    }

    /// Log out the current user (call this on sign out)
    func logoutUser() async {
        // print("💰 Logging out user")

        guard isConfigured else {
            customerInfo = nil
            isSubscribed = false
            cachedIsSubscribed = false
            currentOffering = nil
            resetSubscriptionAnalyticsCache()
            return
        }

        do {
            _ = try await Purchases.shared.logOut()
            await MainActor.run {
                self.customerInfo = nil
                self.isSubscribed = false
                self.cachedIsSubscribed = false
                self.currentOffering = nil
                self.resetSubscriptionAnalyticsCache()
            }
        } catch {
            let appError = AppError.billing(operation: "logoutUser", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "logoutUser",
                screen: nil,
                userId: nil
            )
            ErrorReporter.shared.capture(appError, context: context)
        }
    }

    // MARK: - Subscription Status

    /// Refresh customer info and subscription status
    func refreshCustomerInfo() async {
        guard isConfigured else {
            // print("⚠️ SDK not configured yet, skipping refreshCustomerInfo()")
            return
        }

        // print("💰 Refreshing customer info")

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            await MainActor.run {
                self.updateSubscriptionStatus(customerInfo: customerInfo)
                // print("💰 Subscription status: \(self.isSubscribed ? "Active" : "Inactive")")
            }
        } catch {
            let appError = AppError.billing(operation: "refreshCustomerInfo", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "refreshCustomerInfo",
                screen: nil,
                userId: nil
            )
            ErrorReporter.shared.capture(appError, context: context)

            await MainActor.run {
                self.isSubscribed = false
            }
        }
    }

    /// Check if user has active subscription
    var hasActiveSubscription: Bool {
        return isSubscribed
    }

    /// Get subscription expiration date
    var subscriptionExpirationDate: Date? {
        return customerInfo?.entitlements[proEntitlementID]?.expirationDate
    }

    /// Check if subscription is in trial period
    var isInTrialPeriod: Bool {
        return customerInfo?.entitlements[proEntitlementID]?.periodType == .trial
    }

    // MARK: - Offerings & Purchases

    /// Fetch available offerings from RevenueCat
    func fetchOfferings() async {
        #if DEBUG
        if shouldForceOfferingsUnavailableForUITests {
            currentOffering = nil
            errorMessage = "Failed to load subscription options"
            return
        }
        #endif

        // Wait for SDK to be configured (with timeout)
        var retries = 0
        while !isConfigured && retries < 50 {
            // print("⚠️ SDK not configured yet, waiting... (retry \(retries + 1)/50)")
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            retries += 1
        }

        guard isConfigured else {
            // print("❌ SDK not configured after timeout, cannot fetch offerings")
            await MainActor.run {
                self.errorMessage = "Service not ready. Please try again."
            }
            return
        }

        // print("💰 Fetching offerings")

        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.currentOffering = offerings.current
                if let current = offerings.current {
                    self.cachePaywallOfferingDisplay(from: current)
                }
                // print("💰 Fetched \(offerings.all.count) offerings")

                // Debug: Print details about current offering
                if let current = offerings.current {
                    // print("💰 Current offering: \(current.identifier)")
                    // print("💰 Available packages: \(current.availablePackages.count)")
                    for _ in current.availablePackages {
                        // print("  📦 Package: \(package.identifier)")
                        // print("     Price: \(package.localizedPriceString)")
                        // print("     Product: \(package.storeProduct.productIdentifier)")
                    }
                } else {
                    // print("⚠️ No current offering available")
                }
            }
        } catch {
            let appError = AppError.billing(operation: "fetchOfferings", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "fetchOfferings",
                screen: nil,
                userId: nil
            )
            ErrorReporter.shared.capture(appError, context: context)

            await MainActor.run {
                self.errorMessage = "Failed to load subscription options"
            }
        }
    }

    /// Purchase a package
    func purchase(package: Package) async -> Bool {
        // print("💰 Attempting purchase: \(package.identifier)")

        await MainActor.run {
            self.isPurchasing = true
            self.errorMessage = nil
        }

        do {
            let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)

            await MainActor.run {
                self.updateSubscriptionStatus(customerInfo: customerInfo)
                self.isPurchasing = false
            }

            // print("💰 Purchase successful!")
            return true
        } catch let error as ErrorCode {
            if error != .purchaseCancelledError {
                let appError = AppError.billing(operation: "purchase", underlying: error)
                let context = ErrorContext(
                    feature: "billing",
                    operation: "purchase",
                    screen: "PaywallView",
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: context)
            }

            await MainActor.run {
                self.isPurchasing = false

                switch error {
                case .purchaseCancelledError:
                    // print("💰 Purchase cancelled by user")
                    // Don't show error for user cancellation
                    break
                case .storeProblemError:
                    self.errorMessage = "There was a problem with the App Store. Please try again."
                case .purchaseNotAllowedError:
                    self.errorMessage = "Purchases are not allowed on this device."
                case .purchaseInvalidError:
                    self.errorMessage = "Purchase failed. Please try again."
                default:
                    self.errorMessage = "Purchase failed: \(error.localizedDescription)"
                }

                // print("❌ Purchase failed: \(error.localizedDescription)")
            }
            return false
        } catch {
            let appError = AppError.billing(operation: "purchase", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "purchase",
                screen: "PaywallView",
                userId: nil
            )
            ErrorReporter.shared.capture(appError, context: context)

            await MainActor.run {
                self.isPurchasing = false
                self.errorMessage = "An unexpected error occurred"
            }
            // print("❌ Unexpected purchase error: \(error.localizedDescription)")
            return false
        }
    }

    /// Restore previous purchases
    func restorePurchases() async -> Bool {
        // print("💰 Restoring purchases")

        await MainActor.run {
            self.isPurchasing = true
            self.errorMessage = nil
        }

        guard isConfigured else {
            await MainActor.run {
                self.isPurchasing = false
                self.errorMessage = "Service not ready. Please try again."
            }
            return false
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()

            await MainActor.run {
                self.updateSubscriptionStatus(customerInfo: customerInfo)
                self.isPurchasing = false
            }

            if isSubscribed {
                // print("💰 Purchases restored successfully")
                return true
            } else {
                await MainActor.run {
                    self.errorMessage = "No active subscriptions found"
                }
                return false
            }
        } catch {
            let appError = AppError.billing(operation: "restorePurchases", underlying: error)
            let context = ErrorContext(
                feature: "billing",
                operation: "restorePurchases",
                screen: "PaywallView",
                userId: nil
            )
            ErrorReporter.shared.capture(appError, context: context)

            await MainActor.run {
                self.isPurchasing = false
                self.errorMessage = "Failed to restore purchases"
            }
            // print("❌ Failed to restore purchases: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Subscription Management

    /// Get the annual package from current offering
    var annualPackage: Package? {
        return currentOffering?.annual
    }

    /// Format price for display
    func formatPrice(package: Package) -> String {
        return package.localizedPriceString
    }

    /// Get trial duration text
    func getTrialDurationText(package: Package) -> String? {
        guard let introPrice = package.storeProduct.introductoryDiscount else {
            return nil
        }

        if introPrice.paymentMode == .freeTrial {
            return "\(introPrice.subscriptionPeriod.value) \(introPrice.subscriptionPeriod.unit.description) free"
        }

        return nil
    }

    func cachePaywallOfferingDisplay(_ display: CachedPaywallOfferingDisplay) {
        guard !display.isEmpty else {
            return
        }

        cachedPaywallOfferingDisplay = display

        do {
            let data = try JSONEncoder().encode(display)
            UserDefaults.standard.set(data, forKey: cachedPaywallOfferingDisplayKey)
        } catch {
            ErrorReporter.shared.capture(
                AppError.billing(operation: "cachePaywallOfferingDisplay", underlying: error),
                context: ErrorContext(
                    feature: "billing",
                    operation: "cachePaywallOfferingDisplay",
                    screen: "PaywallView",
                    userId: nil
                )
            )
        }
    }

    #if DEBUG
    func applyCachedPaywallOfferingUITestFixture() {
        shouldForceOfferingsUnavailableForUITests = true
        currentOffering = nil
        errorMessage = "Failed to load subscription options"

        cachePaywallOfferingDisplay(
            CachedPaywallOfferingDisplay(
                generatedAt: Date(),
                packages: [
                    CachedPaywallOfferingDisplay.PackageDisplay(
                        packageIdentifier: "$rc_annual",
                        productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                        localizedPrice: "$79.99",
                        billingPeriod: "year",
                        trialText: "3 days free"
                    ),
                    CachedPaywallOfferingDisplay.PackageDisplay(
                        packageIdentifier: "$rc_monthly",
                        productIdentifier: "com.logyourbody.app.pro1.monthly.3daytrial",
                        localizedPrice: "$9.99",
                        billingPeriod: "month",
                        trialText: "3 days free"
                    )
                ]
            )
        )
    }
    #endif

    // MARK: - Private Helper Methods

    private func cachePaywallOfferingDisplay(from offering: Offering) {
        let packageDisplays = offering.availablePackages.map { package in
            CachedPaywallOfferingDisplay.PackageDisplay(
                packageIdentifier: package.identifier,
                productIdentifier: package.storeProduct.productIdentifier,
                localizedPrice: package.localizedPriceString,
                billingPeriod: billingPeriodLabel(for: package),
                trialText: getTrialDurationText(package: package)
            )
        }

        cachePaywallOfferingDisplay(
            CachedPaywallOfferingDisplay(
                generatedAt: Date(),
                packages: packageDisplays
            )
        )
    }

    private func loadCachedPaywallOfferingDisplay() -> CachedPaywallOfferingDisplay? {
        guard let data = UserDefaults.standard.data(forKey: cachedPaywallOfferingDisplayKey) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedPaywallOfferingDisplay.self, from: data)
    }

    private func billingPeriodLabel(for package: Package) -> String {
        let identifier = "\(package.identifier) \(package.storeProduct.productIdentifier)".lowercased()

        if identifier.contains("annual") || identifier.contains("year") {
            return "year"
        }

        if identifier.contains("month") {
            return "month"
        }

        if identifier.contains("week") {
            return "week"
        }

        return ""
    }

    /// Update subscription status and cache it for faster app startup
    /// Call this method whenever customerInfo is updated to keep cache in sync
    private func updateSubscriptionStatus(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let entitlement = customerInfo.entitlements[proEntitlementID]
        let isActive = entitlement?.isActive == true
        trackTrialAnalyticsIfNeeded(customerInfo: customerInfo, entitlement: entitlement, now: Date())
        self.isSubscribed = isActive
        self.cachedIsSubscribed = isActive
        self.lastFetchTimestamp = Date().timeIntervalSince1970
        // print("💰 Updated subscription status: \(isActive) (cached)")
    }

    /// Check if cache is expired (older than 24 hours)
    var isCacheExpired: Bool {
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - lastFetchTimestamp) > cacheExpiryDuration
    }

    private func trackTrialAnalyticsIfNeeded(
        customerInfo: CustomerInfo,
        entitlement: EntitlementInfo?,
        now: Date
    ) {
        resetSubscriptionAnalyticsCacheIfNeeded(for: customerInfo.originalAppUserId)

        let previousPhase = RevenueCatSubscriptionAnalyticsPhase(rawValue: cachedSubscriptionAnalyticsPhase) ?? .none
        let currentPhase = subscriptionAnalyticsPhase(
            entitlement: entitlement,
            previousPhase: previousPhase,
            now: now
        )

        if let event = RevenueCatSubscriptionAnalyticsTransition.event(from: previousPhase, to: currentPhase) {
            AnalyticsService.shared.track(
                event: event.rawValue,
                properties: trialAnalyticsProperties(
                    customerInfo: customerInfo,
                    entitlement: entitlement,
                    previousPhase: previousPhase,
                    currentPhase: currentPhase
                )
            )
        }

        persistSubscriptionAnalyticsPhase(
            currentPhase,
            appUserId: customerInfo.originalAppUserId,
            entitlement: entitlement
        )
    }

    private func resetSubscriptionAnalyticsCacheIfNeeded(for appUserId: String) {
        guard !cachedSubscriptionAnalyticsAppUserId.isEmpty,
              cachedSubscriptionAnalyticsAppUserId != appUserId else {
            return
        }

        resetSubscriptionAnalyticsCache()
    }

    private func resetSubscriptionAnalyticsCache() {
        cachedSubscriptionAnalyticsPhase = RevenueCatSubscriptionAnalyticsPhase.none.rawValue
        cachedSubscriptionAnalyticsAppUserId = ""
        cachedTrialExpirationTimestamp = 0
    }

    private func subscriptionAnalyticsPhase(
        entitlement: EntitlementInfo?,
        previousPhase: RevenueCatSubscriptionAnalyticsPhase,
        now: Date
    ) -> RevenueCatSubscriptionAnalyticsPhase {
        guard let entitlement else {
            return .none
        }

        if entitlement.isActive {
            return entitlement.periodType == .trial ? .trial : .paid
        }

        guard previousPhase == .trial else {
            return .none
        }

        let expirationTimestamp = entitlement.expirationDate?.timeIntervalSince1970
            ?? cachedTrialExpirationTimestamp

        guard expirationTimestamp > 0 else {
            return .none
        }

        return now.timeIntervalSince1970 >= expirationTimestamp ? .expiredUnpaid : .trial
    }

    private func persistSubscriptionAnalyticsPhase(
        _ phase: RevenueCatSubscriptionAnalyticsPhase,
        appUserId: String,
        entitlement: EntitlementInfo?
    ) {
        cachedSubscriptionAnalyticsPhase = phase.rawValue
        cachedSubscriptionAnalyticsAppUserId = appUserId

        if phase == .trial, let expirationDate = entitlement?.expirationDate {
            cachedTrialExpirationTimestamp = expirationDate.timeIntervalSince1970
        } else if phase != .trial {
            cachedTrialExpirationTimestamp = 0
        }
    }

    private func trialAnalyticsProperties(
        customerInfo: CustomerInfo,
        entitlement: EntitlementInfo?,
        previousPhase: RevenueCatSubscriptionAnalyticsPhase,
        currentPhase: RevenueCatSubscriptionAnalyticsPhase
    ) -> [String: String] {
        var properties = [
            "entitlement_id": proEntitlementID,
            "previous_phase": previousPhase.rawValue,
            "current_phase": currentPhase.rawValue,
            "app_user_id": customerInfo.originalAppUserId
        ]

        if let entitlement {
            properties["is_active"] = String(entitlement.isActive)
            properties["will_renew"] = String(entitlement.willRenew)
            properties["period_type"] = periodTypeName(entitlement.periodType)
            properties["product_identifier"] = entitlement.productIdentifier

            if let expirationDate = entitlement.expirationDate {
                properties["expiration_at"] = ISO8601DateFormatter().string(from: expirationDate)
            }

            if let unsubscribeDetectedAt = entitlement.unsubscribeDetectedAt {
                properties["unsubscribe_detected_at"] = ISO8601DateFormatter().string(from: unsubscribeDetectedAt)
            }
        } else if cachedTrialExpirationTimestamp > 0 {
            properties["expiration_at"] = ISO8601DateFormatter().string(
                from: Date(timeIntervalSince1970: cachedTrialExpirationTimestamp)
            )
        }

        return properties
    }

    private func periodTypeName(_ periodType: PeriodType) -> String {
        switch periodType {
        case .normal:
            return "normal"
        case .intro:
            return "intro"
        case .trial:
            return "trial"
        case .prepaid:
            return "prepaid"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - PurchasesDelegate

extension RevenueCatManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            // print("💰 Received updated customer info")
            self.updateSubscriptionStatus(customerInfo: customerInfo)
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
