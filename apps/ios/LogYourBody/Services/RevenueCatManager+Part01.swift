import Foundation
import Combine
import RevenueCat
import SwiftUI

extension RevenueCatManager {
// MARK: - Cached Properties

    var cachedIsSubscribed: Bool {
        get { userDefaults.bool(forKey: DefaultsKey.isSubscribed) }
        set { userDefaults.set(newValue, forKey: DefaultsKey.isSubscribed) }
    }

var lastFetchTimestamp: Double {
        get { userDefaults.double(forKey: DefaultsKey.lastFetchTimestamp) }
        set { userDefaults.set(newValue, forKey: DefaultsKey.lastFetchTimestamp) }
    }

var cachedSubscriptionAnalyticsPhase: String {
        get {
            userDefaults.string(forKey: DefaultsKey.subscriptionAnalyticsPhase)
                ?? RevenueCatSubscriptionAnalyticsPhase.none.rawValue
        }
        set { userDefaults.set(newValue, forKey: DefaultsKey.subscriptionAnalyticsPhase) }
    }

var cachedSubscriptionAnalyticsAppUserId: String {
        get { userDefaults.string(forKey: DefaultsKey.subscriptionAnalyticsAppUserId) ?? "" }
        set { userDefaults.set(newValue, forKey: DefaultsKey.subscriptionAnalyticsAppUserId) }
    }

var cachedTrialExpirationTimestamp: Double {
        get { userDefaults.double(forKey: DefaultsKey.trialExpirationTimestamp) }
        set { userDefaults.set(newValue, forKey: DefaultsKey.trialExpirationTimestamp) }
    }

// MARK: - Configuration

    /// Configure RevenueCat SDK - call this on app launch
    /// Note: Does NOT fetch customer info immediately to avoid blocking UI
    nonisolated func configure(apiKey: String) {
        Task { @MainActor in
            // print("💰 Configuring RevenueCat SDK")

            purchasesClient.configure(apiKey: apiKey, delegate: self)

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

/// Identify the customer with the shared identity subject.
    func identifyUser(userId: String) async {
        guard isConfigured else {
            // print("⚠️ SDK not configured yet, skipping identifyUser()")
            return
        }

        // print("💰 Identifying user: \(userId)")

        do {
            let customer = try await purchasesClient.logIn(userId: userId, entitlementID: proEntitlementID)
            await MainActor.run {
                self.updateSubscriptionStatus(customer: customer)
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
            clearLocalSubscriptionState()
            return
        }

        do {
            try await purchasesClient.logOut()
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

        clearLocalSubscriptionState()
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
            let customer = try await purchasesClient.customerInfo(entitlementID: proEntitlementID)
            await MainActor.run {
                self.updateSubscriptionStatus(customer: customer)
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
            // Do not revoke cached access on transient RevenueCat/App Store/network failures.
            // A later successful refresh with an inactive entitlement still invalidates access.
        }
    }

/// Check if user has active subscription
    var hasActiveSubscription: Bool {
        return isSubscribed
    }

/// Get subscription expiration date
    var subscriptionExpirationDate: Date? {
        return currentEntitlementSnapshot?.expirationDate
    }

/// Check if subscription is in trial period
    var isInTrialPeriod: Bool {
        return currentEntitlementSnapshot?.periodType == .trial
    }

var currentSubscriptionProductIdentifier: String? {
        currentEntitlementSnapshot?.productIdentifier
    }

var paywallPackages: [PaywallPackageDisplay] {
        let packages = primaryPaywallPackages
        let monthlyPackage = packages.first { billingPeriodLabel(for: $0) == "month" }

        return packages.map { package in
            makePaywallPackageDisplay(package: package, monthlyPackage: monthlyPackage)
        }
    }

var primaryPaywallPackages: [Package] {
        guard let offering = currentOffering else {
            return []
        }

        let monthly = offering.package(identifier: "$rc_monthly")
        let annual = offering.package(identifier: "$rc_annual")
        let primaryPackages = [monthly, annual].compactMap { $0 }

        if !primaryPackages.isEmpty {
            return primaryPackages
        }

        return Array(offering.availablePackages.prefix(1))
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
            let offerings = try await purchasesClient.offerings()
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

func purchase(packageIdentifier: String) async -> Bool {
        guard let package = currentOffering?.package(identifier: packageIdentifier)
            ?? currentOffering?.availablePackages.first(where: { $0.identifier == packageIdentifier }) else {
            await MainActor.run {
                self.errorMessage = "Subscription option unavailable. Please try again."
            }
            return false
        }

        return await purchase(package: package)
    }

/// Purchase a package
    func purchase(package: Package) async -> Bool {
        // print("💰 Attempting purchase: \(package.identifier)")

        await MainActor.run {
            self.isPurchasing = true
            self.errorMessage = nil
        }

        do {
            let customer = try await purchasesClient.purchase(
                package: package,
                entitlementID: proEntitlementID
            )

            await MainActor.run {
                self.updateSubscriptionStatus(customer: customer)
                self.isPurchasing = false
            }

            // print("💰 Purchase successful!")
            return true
        } catch let error as RevenueCatPurchasingError {
            if error != .purchaseCancelled {
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
                case .purchaseCancelled:
                    // print("💰 Purchase cancelled by user")
                    // Don't show error for user cancellation
                    break
                case .storeProblem:
                    self.errorMessage = "There was a problem with the App Store. Please try again."
                case .purchaseNotAllowed:
                    self.errorMessage = "Purchases are not allowed on this device."
                case .purchaseInvalid:
                    self.errorMessage = "Purchase failed. Please try again."
                case .unexpected(let message):
                    self.errorMessage = "Purchase failed: \(message)"
                }

                // print("❌ Purchase failed: \(error)")
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
            let customer = try await purchasesClient.restorePurchases(entitlementID: proEntitlementID)

            await MainActor.run {
                self.updateSubscriptionStatus(customer: customer)
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

func makePaywallPackageDisplay(
        package: Package,
        monthlyPackage: Package?
    ) -> PaywallPackageDisplay {
        let billingPeriod = billingPeriodLabel(for: package)
        let trialText = getTrialDurationText(package: package)
        let savingsText: String?

        if package.identifier == "$rc_annual",
           let monthlyPackage,
           let savingsPercent = PaywallSavingsPolicy.savingsPercent(
            monthlyPrice: monthlyPackage.storeProduct.price,
            annualPrice: package.storeProduct.price
           ) {
            savingsText = "Save \(savingsPercent)%"
        } else {
            savingsText = nil
        }

        return PaywallPackageDisplay(
            id: package.identifier,
            packageIdentifier: package.identifier,
            productIdentifier: package.storeProduct.productIdentifier,
            planTitle: planTitle(for: package),
            localizedPrice: formatPrice(package: package),
            billingPeriod: billingPeriod,
            billingPeriodSuffix: billingPeriodShortSuffix(for: package),
            summaryText: packageSummaryText(for: package),
            trialText: trialText,
            savingsBadgeText: savingsText,
            purchaseButtonTitle: trialText == nil ? "Subscribe" : "Start trial",
            accessibilityIdentifierSuffix: planIdentifierSuffix(for: package)
        )
    }

func billingPeriodShortSuffix(for package: Package) -> String {
        switch billingPeriodLabel(for: package) {
        case "year":
            return "/yr"
        case "month":
            return "/mo"
        case "week":
            return "/wk"
        default:
            return ""
        }
    }

func packageSummaryText(for package: Package) -> String {
        switch billingPeriodLabel(for: package) {
        case "year":
            if let monthlyEquivalent = annualMonthlyEquivalentText(for: package) {
                return "\(monthlyEquivalent)/mo, billed yearly"
            }
            return "Billed yearly"
        case "month":
            return "Billed monthly"
        case "week":
            return "Billed weekly"
        default:
            return "Billed by the App Store"
        }
    }

func planTitle(for package: Package) -> String {
        switch billingPeriodLabel(for: package) {
        case "year":
            return "Annual"
        case "month":
            return "Monthly"
        case "week":
            return "Weekly"
        default:
            return "Plan"
        }
    }

func planIdentifierSuffix(for package: Package) -> String {
        switch billingPeriodLabel(for: package) {
        case "year":
            return "annual"
        case "month":
            return "monthly"
        case "week":
            return "weekly"
        default:
            return "fallback"
        }
    }

func annualMonthlyEquivalentText(for package: Package) -> String? {
        guard package.identifier == "$rc_annual",
              let monthlyEquivalent = PaywallSavingsPolicy.monthlyEquivalent(annualPrice: package.storeProduct.price),
              let formatter = package.storeProduct.priceFormatter else {
            return nil
        }

        return formatter.string(from: monthlyEquivalent)
    }

func cachePaywallOfferingDisplay(_ display: CachedPaywallOfferingDisplay) {
        guard !display.isEmpty else {
            return
        }

        cachedPaywallOfferingDisplay = display

        do {
            let data = try JSONEncoder().encode(display)
            userDefaults.set(data, forKey: DefaultsKey.cachedPaywallOfferingDisplay)
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

func applyPaywallPlansUITestFixture() {
        shouldForceOfferingsUnavailableForUITests = false
        errorMessage = nil

        let monthlyProduct = TestStoreProduct(
            localizedTitle: "LogYourBody Pro Monthly",
            price: fixtureDecimal("9.99"),
            localizedPriceString: "$9.99",
            productIdentifier: "com.logyourbody.app.pro1.monthly.3daytrial",
            productType: .autoRenewableSubscription,
            localizedDescription: "Monthly LogYourBody Pro subscription",
            subscriptionGroupIdentifier: "logyourbody_pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .month),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let annualProduct = TestStoreProduct(
            localizedTitle: "LogYourBody Pro Annual",
            price: fixtureDecimal("69.99"),
            localizedPriceString: "$69.99",
            productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
            productType: .autoRenewableSubscription,
            localizedDescription: "Annual LogYourBody Pro subscription",
            subscriptionGroupIdentifier: "logyourbody_pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()
        let packages = [
            Package(
                identifier: "$rc_monthly",
                packageType: .monthly,
                storeProduct: monthlyProduct,
                offeringIdentifier: "ui_test_paywall",
                webCheckoutUrl: nil
            ),
            Package(
                identifier: "$rc_annual",
                packageType: .annual,
                storeProduct: annualProduct,
                offeringIdentifier: "ui_test_paywall",
                webCheckoutUrl: nil
            )
        ]
        let offering = Offering(
            identifier: "ui_test_paywall",
            serverDescription: "UI test paywall",
            availablePackages: packages,
            webCheckoutUrl: nil
        )

        currentOffering = offering
        cachePaywallOfferingDisplay(from: offering)
    }

func fixtureDecimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }
#endif

// MARK: - Private Helper Methods

    func cachePaywallOfferingDisplay(from offering: Offering) {
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
}
