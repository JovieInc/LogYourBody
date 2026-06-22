import Foundation
import Combine
import RevenueCat
import SwiftUI

extension RevenueCatManager {
func loadCachedPaywallOfferingDisplay() -> CachedPaywallOfferingDisplay? {
        guard let data = userDefaults.data(forKey: DefaultsKey.cachedPaywallOfferingDisplay) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedPaywallOfferingDisplay.self, from: data)
    }

func billingPeriodLabel(for package: Package) -> String {
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
    func updateSubscriptionStatus(customer: RevenueCatCustomerSnapshot) {
        self.customerInfo = customer.customerInfo
        let entitlement = customer.entitlement
        let isActive = entitlement?.isActive == true
        self.currentEntitlementSnapshot = entitlement
        trackTrialAnalyticsIfNeeded(customer: customer, entitlement: entitlement, now: Date())
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

func trackTrialAnalyticsIfNeeded(
        customer: RevenueCatCustomerSnapshot,
        entitlement: RevenueCatEntitlementSnapshot?,
        now: Date
    ) {
        resetSubscriptionAnalyticsCacheIfNeeded(for: customer.originalAppUserId)

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
                    customer: customer,
                    entitlement: entitlement,
                    previousPhase: previousPhase,
                    currentPhase: currentPhase
                )
            )
        }

        persistSubscriptionAnalyticsPhase(
            currentPhase,
            appUserId: customer.originalAppUserId,
            entitlement: entitlement
        )
    }

func resetSubscriptionAnalyticsCacheIfNeeded(for appUserId: String) {
        guard !cachedSubscriptionAnalyticsAppUserId.isEmpty,
              cachedSubscriptionAnalyticsAppUserId != appUserId else {
            return
        }

        resetSubscriptionAnalyticsCache()
    }

func resetSubscriptionAnalyticsCache() {
        cachedSubscriptionAnalyticsPhase = RevenueCatSubscriptionAnalyticsPhase.none.rawValue
        cachedSubscriptionAnalyticsAppUserId = ""
        cachedTrialExpirationTimestamp = 0
    }

func clearLocalSubscriptionState() {
        customerInfo = nil
        isSubscribed = false
        cachedIsSubscribed = false
        currentOffering = nil
        currentEntitlementSnapshot = nil
        resetSubscriptionAnalyticsCache()
    }

func subscriptionAnalyticsPhase(
        entitlement: RevenueCatEntitlementSnapshot?,
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

func persistSubscriptionAnalyticsPhase(
        _ phase: RevenueCatSubscriptionAnalyticsPhase,
        appUserId: String,
        entitlement: RevenueCatEntitlementSnapshot?
    ) {
        cachedSubscriptionAnalyticsPhase = phase.rawValue
        cachedSubscriptionAnalyticsAppUserId = appUserId

        if phase == .trial, let expirationDate = entitlement?.expirationDate {
            cachedTrialExpirationTimestamp = expirationDate.timeIntervalSince1970
        } else if phase != .trial {
            cachedTrialExpirationTimestamp = 0
        }
    }

func trialAnalyticsProperties(
        customer: RevenueCatCustomerSnapshot,
        entitlement: RevenueCatEntitlementSnapshot?,
        previousPhase: RevenueCatSubscriptionAnalyticsPhase,
        currentPhase: RevenueCatSubscriptionAnalyticsPhase
    ) -> [String: String] {
        var properties = [
            "entitlement_id": proEntitlementID,
            "previous_phase": previousPhase.rawValue,
            "current_phase": currentPhase.rawValue,
            "app_user_id": customer.originalAppUserId
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

func periodTypeName(_ periodType: PeriodType) -> String {
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
