//
// RevenueCatManager.swift
// LogYourBody
//
// Handles all RevenueCat subscription management and in-app purchases
//
import Foundation
import Combine
import RevenueCat

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

    // MARK: - Constants

    /// The entitlement identifier that grants pro access
    /// IMPORTANT: This must match the entitlement lookup_key in RevenueCat dashboard
    private let proEntitlementID = "Premium"

    // MARK: - Initialization

    private override init() {
        print("💰 RevenueCatManager initialized")
    }

    // MARK: - Configuration

    /// Configure RevenueCat SDK - call this on app launch
    /// Note: Does NOT fetch customer info immediately to avoid blocking UI
    nonisolated func configure(apiKey: String) {
        print("💰 Configuring RevenueCat SDK")

        // Configure SDK
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)

        // Set up delegate to listen for customer info updates
        Purchases.shared.delegate = self

        // Note: refreshCustomerInfo() should be called separately after UI is ready
    }

    /// Identify the user with their Clerk user ID
    func identifyUser(userId: String) async {
        print("💰 Identifying user: \(userId)")

        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isSubscribed = customerInfo.entitlements[proEntitlementID]?.isActive == true
            }
            print("💰 User identified successfully")
        } catch {
            print("❌ Failed to identify user: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = "Failed to link account: \(error.localizedDescription)"
            }
        }
    }

    /// Log out the current user (call this on sign out)
    func logoutUser() async {
        print("💰 Logging out user")

        do {
            _ = try await Purchases.shared.logOut()
            await MainActor.run {
                self.customerInfo = nil
                self.isSubscribed = false
                self.currentOffering = nil
            }
        } catch {
            print("❌ Failed to log out user: \(error.localizedDescription)")
        }
    }

    // MARK: - Subscription Status

    /// Refresh customer info and subscription status
    func refreshCustomerInfo() async {
        print("💰 Refreshing customer info")

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            await MainActor.run {
                self.customerInfo = customerInfo
                self.isSubscribed = customerInfo.entitlements[proEntitlementID]?.isActive == true
                print("💰 Subscription status: \(self.isSubscribed ? "Active" : "Inactive")")
            }
        } catch {
            print("❌ Failed to refresh customer info: \(error.localizedDescription)")
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
        print("💰 Fetching offerings")

        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.currentOffering = offerings.current
                print("💰 Fetched \(offerings.all.count) offerings")
            }
        } catch {
            print("❌ Failed to fetch offerings: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = "Failed to load subscription options"
            }
        }
    }

    /// Purchase a package
    func purchase(package: Package) async -> Bool {
        print("💰 Attempting purchase: \(package.identifier)")

        await MainActor.run {
            self.isPurchasing = true
            self.errorMessage = nil
        }

        do {
            let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)

            await MainActor.run {
                self.customerInfo = customerInfo
                self.isSubscribed = customerInfo.entitlements[proEntitlementID]?.isActive == true
                self.isPurchasing = false
            }

            print("💰 Purchase successful!")
            return true

        } catch let error as ErrorCode {
            await MainActor.run {
                self.isPurchasing = false

                switch error {
                case .purchaseCancelledError:
                    print("💰 Purchase cancelled by user")
                    // Don't show error for user cancellation
                case .storeProblemError:
                    self.errorMessage = "There was a problem with the App Store. Please try again."
                case .purchaseNotAllowedError:
                    self.errorMessage = "Purchases are not allowed on this device."
                case .purchaseInvalidError:
                    self.errorMessage = "Purchase failed. Please try again."
                default:
                    self.errorMessage = "Purchase failed: \(error.localizedDescription)"
                }

                print("❌ Purchase failed: \(error.localizedDescription)")
            }
            return false
        } catch {
            await MainActor.run {
                self.isPurchasing = false
                self.errorMessage = "An unexpected error occurred"
            }
            print("❌ Unexpected purchase error: \(error.localizedDescription)")
            return false
        }
    }

    /// Restore previous purchases
    func restorePurchases() async -> Bool {
        print("💰 Restoring purchases")

        await MainActor.run {
            self.isPurchasing = true
            self.errorMessage = nil
        }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()

            await MainActor.run {
                self.customerInfo = customerInfo
                self.isSubscribed = customerInfo.entitlements[proEntitlementID]?.isActive == true
                self.isPurchasing = false
            }

            if isSubscribed {
                print("💰 Purchases restored successfully")
                return true
            } else {
                await MainActor.run {
                    self.errorMessage = "No active subscriptions found"
                }
                return false
            }

        } catch {
            await MainActor.run {
                self.isPurchasing = false
                self.errorMessage = "Failed to restore purchases"
            }
            print("❌ Failed to restore purchases: \(error.localizedDescription)")
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
}

// MARK: - PurchasesDelegate

extension RevenueCatManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            print("💰 Received updated customer info")
            self.customerInfo = customerInfo
            self.isSubscribed = customerInfo.entitlements[self.proEntitlementID]?.isActive == true
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
