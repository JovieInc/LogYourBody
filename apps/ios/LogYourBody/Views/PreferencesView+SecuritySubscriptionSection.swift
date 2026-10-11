//
// PreferencesView+SecuritySubscriptionSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var securitySection: some View {
        SettingsSection(header: "Security") {
            activeSessionsRow
        }
    }

    var activeSessionsRow: some View {
        SettingsNavigationLink(
            icon: "desktopcomputer",
            title: "Active sessions",
            subtitle: "Review devices signed in to your account."
        ) {
            SecuritySessionsView()
        }
    }

    var subscriptionSection: some View {
        SettingsSection(header: "Subscription") {
            subscriptionStatusRow

            if let renewal = subscriptionRenewalText {
                subscriptionRenewalRow(renewal: renewal)
            }

            manageSubscriptionRow
        }
    }

    var changePlanSection: some View {
        SettingsSection(header: "Plan") {
            SettingsButtonRow(
                icon: "arrow.up.forward.circle",
                title: subscriptionManager.isSubscribed ? "Change plan" : "See plans",
                titleAccessibilityIdentifier: "home_v2_subscription_change"
            ) {
                isShowingSettingsPaywall = true
            }
            .accessibilityIdentifier("home_v2_subscription_change")
        }
    }

    var subscriptionBenefitsSection: some View {
        SettingsSection(header: HomeV2SettingsCopy.included) {
            Label(HomeV2SettingsCopy.included1, systemImage: "photo.on.rectangle.angled")
            Label(HomeV2SettingsCopy.included2, systemImage: "chart.xyaxis.line")
            Label(HomeV2SettingsCopy.included3, systemImage: "arrow.up.right")
        }
    }

    var subscriptionStatusRow: some View {
        SettingsRow(
            icon: "crown.fill",
            title: subscriptionStatusText,
            titleAccessibilityIdentifier: "home_v2_subscription_plan",
            subtitle: subscriptionPlanDisplay,
            tintColor: subscriptionManager.isSubscribed ? nil : Color.appWarning
        )
        .accessibilityIdentifier("settings_subscription_status_row")
    }

    func subscriptionRenewalRow(renewal: String) -> some View {
        SettingsRow(
            icon: "calendar.badge.clock",
            title: "Renews",
            value: renewal
        )
    }

    var manageSubscriptionRow: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                openURL(url)
            }
        } label: {
            SettingsRow(
                icon: "creditcard.fill",
                title: "Manage subscription",
                titleAccessibilityIdentifier: "home_v2_subscription_manage",
                subtitle: "Opens App Store",
                showChevron: true
            )
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("settings_manage_subscription_button")
    }

    var subscriptionStatusText: String {
        if subscriptionManager.isSubscribed {
            if subscriptionManager.isInTrialPeriod {
                return "Active (Free Trial)"
            } else {
                return "Active"
            }
        } else {
            return "Inactive"
        }
    }

    var subscriptionPlanDisplay: String? {
        guard subscriptionManager.isSubscribed else { return nil }
        let productId = subscriptionManager.currentSubscriptionProductIdentifier ?? ""
        let lowercased = productId.lowercased()

        if lowercased.contains("annual") {
            return "Pro Annual"
        } else if lowercased.contains("month") {
            return "Pro Monthly"
        }
        return "LogYourBody Pro"
    }

    var subscriptionRenewalText: String? {
        guard let date = subscriptionManager.subscriptionExpirationDate else { return nil }
        return formatDate(date)
    }
}
