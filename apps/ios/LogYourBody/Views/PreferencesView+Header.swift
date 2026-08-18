//
// PreferencesView+Header.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    @ViewBuilder
    var settingsLauncher: some View {
        Section {
            heroHeader
        }

        SettingsSection(header: "Personal") {
            SettingsNavigationLink(
                icon: "person.crop.circle",
                title: "Profile",
                subtitle: "Personal details and profile photo"
            ) {
                SettingsDetailScreen(title: "Profile") {
                    accountSection
                    profileSection
                }
            }
            .accessibilityIdentifier("settings_profile_link")

            SettingsNavigationLink(
                icon: "target",
                title: "Tracking",
                subtitle: "Goals, units, and reminders"
            ) {
                SettingsDetailScreen(title: "Tracking") {
                    trackingGoalsSection
                    remindersSection
                }
                .worldClassScreen(.trackingAndGoals)
            }
            .accessibilityIdentifier("settings_tracking_link")

            integrationsLauncherRow
                .accessibilityIdentifier("settings_integrations_link")
        }

        SettingsSection(header: "Account & data") {
            SettingsNavigationLink(
                icon: "person.badge.key",
                title: "Account & subscription",
                subtitle: accountSubscriptionSummary
            ) {
                SettingsDetailScreen(title: "Account & subscription") {
                    subscriptionSection
                    advancedSection
                    securitySection
                }
            }
            .accessibilityIdentifier("settings_account_subscription_link")

            SettingsNavigationLink(
                icon: "hand.raised",
                title: "Privacy & data",
                subtitle: "Photo handling and account deletion"
            ) {
                SettingsDetailScreen(title: "Privacy & data") {
                    photosSection
                    dangerSection
                }
                .worldClassScreen(.privacyAndData)
            }
            .accessibilityIdentifier("settings_privacy_data_link")
        }
    }

    var accountSubscriptionSummary: String {
        if let plan = subscriptionPlanDisplay {
            return "\(subscriptionStatusText) · \(plan)"
        }
        return subscriptionStatusText
    }

    var heroHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    heroAvatar
                    heroIdentityText
                    statusBadge
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        heroAvatar
                        heroIdentityText
                        Spacer(minLength: 0)
                    }

                    statusBadge
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    var heroIdentityText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(userDisplayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(userEmail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            if let memberSinceText {
                Text(memberSinceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var statusBadge: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(subscriptionManager.isSubscribed ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(subscriptionStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let planDisplay = subscriptionPlanDisplay {
                        Text(planDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(subscriptionManager.isSubscribed ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(subscriptionStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let planDisplay = subscriptionPlanDisplay {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(planDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    var heroAvatar: some View {
        ZStack {
            if let profileAvatarURLString,
               let url = URL(string: profileAvatarURLString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
                    .frame(width: 72, height: 72)
            }

            if isUploadingPhoto {
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: 72, height: 72)

                ProgressView(value: avatarUploadProgress)
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
            }
        }
        .accessibilityHidden(true)
    }

    var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .overlay(
                Text(userInitials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            )
    }
}
