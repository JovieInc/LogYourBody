//
// PreferencesView+SecuritySubscriptionSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var securitySection: some View {
        SettingsSection(header: "Security") {
            VStack(spacing: 0) {
                changePasswordRow
                DSDivider().insetted(16)
                activeSessionsRow
            }
        }
    }

    var changePasswordRow: some View {
        SettingsNavigationLink(
            icon: "lock.rotation",
            title: "Change password",
            subtitle: "Update your password."
        ) {
            ChangePasswordView()
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
            VStack(spacing: 0) {
                subscriptionStatusRow

                if let renewal = subscriptionRenewalText {
                    DSDivider().insetted(16)
                    subscriptionRenewalRow(renewal: renewal)
                }

                DSDivider().insetted(16)
                manageSubscriptionRow
            }
        }
    }

    var subscriptionStatusRow: some View {
        SettingsRow(
            icon: "crown.fill",
            title: subscriptionStatusText,
            subtitle: subscriptionPlanDisplay,
            tintColor: subscriptionManager.isSubscribed ? nil : theme.colors.warning
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
                subtitle: "Opens App Store",
                showChevron: true
            )
        }
        .buttonStyle(.plain)
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
