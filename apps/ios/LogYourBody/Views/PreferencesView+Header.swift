//
// PreferencesView+Header.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var settingsLauncher: some View {
        VStack(spacing: theme.spacing.sectionSpacing) {
            heroHeader

            SettingsSection(header: "Personal") {
                VStack(spacing: 0) {
                    SettingsNavigationLink(
                        icon: "person.crop.circle",
                        title: "Profile",
                        subtitle: "Personal details and profile photo"
                    ) {
                        SettingsDetailScreen(title: "Profile") {
                            VStack(spacing: theme.spacing.sectionSpacing) {
                                accountSection
                                profileSection
                            }
                        }
                    }
                    .accessibilityIdentifier("settings_profile_link")

                    DSDivider().insetted(16)

                    SettingsNavigationLink(
                        icon: "target",
                        title: "Tracking",
                        subtitle: "Goals, units, and reminders"
                    ) {
                        SettingsDetailScreen(title: "Tracking") {
                            VStack(spacing: theme.spacing.sectionSpacing) {
                                trackingGoalsSection
                                remindersSection
                            }
                        }
                    }
                    .accessibilityIdentifier("settings_tracking_link")

                    DSDivider().insetted(16)

                    integrationsLauncherRow
                        .accessibilityIdentifier("settings_integrations_link")
                }
            }

            SettingsSection(header: "Account & data") {
                VStack(spacing: 0) {
                    SettingsNavigationLink(
                        icon: "person.badge.key",
                        title: "Account & subscription",
                        subtitle: accountSubscriptionSummary
                    ) {
                        SettingsDetailScreen(title: "Account & subscription") {
                            VStack(spacing: theme.spacing.sectionSpacing) {
                                subscriptionSection
                                advancedSection
                                securitySection
                            }
                        }
                    }
                    .accessibilityIdentifier("settings_account_subscription_link")

                    DSDivider().insetted(16)

                    SettingsNavigationLink(
                        icon: "hand.raised",
                        title: "Privacy & data",
                        subtitle: "Photo handling and account deletion"
                    ) {
                        SettingsDetailScreen(title: "Privacy & data") {
                            VStack(spacing: theme.spacing.sectionSpacing) {
                                photosSection
                                dangerSection
                            }
                        }
                    }
                    .accessibilityIdentifier("settings_privacy_data_link")
                }
            }
        }
    }

    var accountSubscriptionSummary: String {
        if let plan = subscriptionPlanDisplay {
            return "\(subscriptionStatusText) · \(plan)"
        }
        return subscriptionStatusText
    }

    var heroHeader: some View {
        VStack(spacing: theme.spacing.md) {
            HStack(alignment: .center, spacing: theme.spacing.md) {
                heroAvatar

                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(userDisplayName)
                        .font(theme.typography.headlineMedium)
                        .foregroundColor(theme.colors.text)

                    Text(userEmail)
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if let memberSinceText {
                        Text(memberSinceText)
                            .font(theme.typography.captionMedium)
                            .foregroundColor(theme.colors.textSecondary)
                    }
                }

                Spacer()
            }

            statusBadge
        }
        .padding(theme.spacing.md)
        .systemBGlassSurface(
            cornerRadius: theme.radius.card,
            tint: theme.colors.text,
            tintOpacity: 0.05,
            borderColor: theme.colors.border,
            borderOpacity: 0.75
        )
    }

    var compactHeader: some View {
        VStack(spacing: 0) {
            HStack {
                heroAvatarSmall
                Text(userDisplayName)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, theme.spacing.screenPadding)
            .padding(.top, topSafeArea + theme.spacing.xs)
            .padding(.bottom, theme.spacing.sm)
            .background(theme.colors.background.opacity(0.95))
            .opacity(scrollOffset < -60 ? 1 : 0)
        }
        .ignoresSafeArea(edges: .top)
        .animation(theme.animation.fast, value: scrollOffset)
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
                    .fill(theme.colors.background.opacity(0.58))
                    .frame(width: 72, height: 72)

                ProgressView(value: avatarUploadProgress)
                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.text))
                    .scaleEffect(0.8)
            }
        }
    }

    var heroAvatarSmall: some View {
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
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
                    .frame(width: 32, height: 32)
            }
        }
    }

    var statusBadge: some View {
        HStack(spacing: theme.spacing.xs) {
            Circle()
                .fill(subscriptionManager.isSubscribed ? theme.colors.success : theme.colors.warning)
                .frame(width: 8, height: 8)

            Text(subscriptionStatusText)
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.textSecondary)

            if let planDisplay = subscriptionPlanDisplay {
                Text("•")
                    .foregroundColor(theme.colors.textTertiary)
                Text(planDisplay)
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    var avatarPlaceholder: some View {
        Circle()
            .fill(theme.colors.surfaceTertiary)
            .overlay(
                Text(userInitials)
                    .font(theme.typography.headlineMedium)
                    .foregroundColor(theme.colors.text)
            )
    }
}
