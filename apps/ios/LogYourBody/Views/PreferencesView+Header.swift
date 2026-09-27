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

        SettingsSection(header: "Account") {
            SettingsNavigationLink(
                icon: "person.crop.circle",
                title: "Profile",
                subtitle: "Personal details and profile photo",
                accessibilityIdentifier: "settings_profile_link",
                titleAccessibilityIdentifier: "home_v2_settings_profile"
            ) {
                SettingsDetailScreen(title: "Profile") {
                    accountSection
                    profileSection
                }
                .confirmationDialog(
                    "Log out of LogYourBody?",
                    isPresented: $showingLogoutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Log Out", role: .destructive) {
                        Task {
                            await authManager.logout()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            SettingsNavigationLink(
                icon: "crown.fill",
                title: "Subscription",
                subtitle: accountSubscriptionSummary,
                accessibilityIdentifier: "settings_account_subscription_link",
                titleAccessibilityIdentifier: "home_v2_settings_subscription"
            ) {
                SettingsDetailScreen(title: "Account & subscription", accessibilityIdentifier: "home_v2_subscription") {
                    subscriptionSection
                    changePlanSection
                    advancedSection
                    subscriptionBenefitsSection
                    securitySection
                }
            }
        }

        SettingsSection(header: "Data") {
            integrationsLauncherRow

            SettingsNavigationLink(
                icon: "target",
                title: "Tracking",
                subtitle: "Body composition targets and reminders",
                accessibilityIdentifier: "settings_tracking_link"
            ) {
                SettingsDetailScreen(title: "Tracking") {
                    trackingGoalsSection
                    remindersSection
                }
                .worldClassScreen(.trackingAndGoals)
            }
            SettingsNavigationLink(
                icon: "globe",
                title: "Units",
                subtitle: HomeV2SettingsCopy.unitsText(currentSystem),
                accessibilityIdentifier: "home_v2_settings_units"
            ) {
                SettingsDetailScreen(title: "Units", accessibilityIdentifier: "home_v2_units") {
                    unitSettingsSection
                }
            }
            SettingsNavigationLink(
                icon: "scope",
                title: "Target",
                subtitle: goalValueText(for: .weight),
                accessibilityIdentifier: "home_v2_settings_target"
            ) {
                SettingsDetailScreen(title: "Target", accessibilityIdentifier: "home_v2_target") {
                    targetSettingsSection
                }
            }
            SettingsNavigationLink(
                icon: "bell.badge",
                title: "Reminders",
                subtitle: dailyReminderSubtitle,
                accessibilityIdentifier: "home_v2_settings_reminders"
            ) {
                SettingsDetailScreen(
                    title: "Reminders",
                    accessibilityIdentifier: "home_v2_reminders",
                    backIdentifier: "home_v2_reminders_back"
                ) {
                    remindersSection
                }
                .worldClassScreen(.dailyReminder)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home_v2_reminders")
            }
            SettingsNavigationLink(
                icon: "figure.walk",
                title: "Activity",
                subtitle: "Daily step goal"
            ) {
                SettingsDetailScreen(title: "Activity") {
                    SettingsSection(header: "Daily activity") {
                        stepGoalRow
                    }
                }
            }
        }

        SettingsSection(header: "Privacy & data") {
            SettingsToggleRow(
                icon: "faceid",
                title: "Face ID lock",
                isOn: $biometricLockEnabled
            )
            .accessibilityIdentifier("home_v2_settings_face_id")

            SettingsNavigationLink(
                icon: "square.and.arrow.down",
                title: "Export data",
                accessibilityIdentifier: "home_v2_settings_export"
            ) {
                ExportDataView()
                    .environmentObject(authManager)
            }
            SettingsNavigationLink(
                icon: "trash",
                title: "Delete account",
                accessibilityIdentifier: "home_v2_settings_delete",
                tintColor: Color.appError
            ) {
                DeleteAccountView()
                    .environmentObject(authManager)
            }
            SettingsNavigationLink(
                icon: "hand.raised",
                title: "Privacy & data",
                subtitle: "Photo handling and account actions",
                accessibilityIdentifier: "settings_privacy_data_link"
            ) {
                SettingsDetailScreen(title: "Privacy & data") {
                    photosSection
                    dangerSection
                }
                .worldClassScreen(.privacyAndData)
            }
        }
    }

    var unitSettingsSection: some View {
        SettingsSection(header: "Units", footer: HomeV2SettingsCopy.unitsNote) {
            measurementSystemSection
            SettingsRow(
                title: HomeV2SettingsCopy.height,
                titleAccessibilityIdentifier: "home_v2_units_height",
                value: HomeV2SettingsCopy.heightUnitText(currentSystem)
            )
            SettingsRow(
                title: HomeV2SettingsCopy.bodyFat,
                titleAccessibilityIdentifier: "home_v2_units_body_fat",
                value: "%"
            )
            SettingsRow(
                title: HomeV2SettingsCopy.circumference,
                titleAccessibilityIdentifier: "home_v2_units_circumference",
                value: HomeV2SettingsCopy.circumferenceUnitText(currentSystem)
            )
        }
    }

    var targetSettingsSection: some View {
        SettingsSection(header: "Targets", footer: HomeV2SettingsCopy.targetNote) {
            goalRow(for: .weight, titleAccessibilityIdentifier: "home_v2_target_weight")
            goalRow(for: .bodyFat, titleAccessibilityIdentifier: "home_v2_target_body_fat")
            if customWeightGoalKilograms != nil || customBodyFatGoal != nil {
                SettingsButtonRow(
                    title: HomeV2SettingsCopy.removeTarget,
                    titleAccessibilityIdentifier: "home_v2_target_remove",
                    action: resetToDefaults
                )
                .accessibilityIdentifier("home_v2_target_remove")
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
        .accessibilityIdentifier(WorldClassScreen.settings.accessibilityIdentifier)
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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(subscriptionManager.isSubscribed ? Color.appSuccess : Color.appWarning)
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
                HStack(spacing: 8) {
                    Circle()
                        .fill(subscriptionManager.isSubscribed ? Color.appSuccess : Color.appWarning)
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
