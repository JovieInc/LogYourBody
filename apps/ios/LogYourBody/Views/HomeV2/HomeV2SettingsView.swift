//
// HomeV2SettingsView.swift
// LogYourBody
//
import SwiftUI

enum HomeV2SettingsCopy {
    static let title = "Settings"
    static let account = "Account"
    static let data = "Data"
    static let privacy = "Privacy"
    static let profile = "Profile"
    static let subscription = "Subscription"
    static let appleHealth = "Apple Health"
    static let units = "Units"
    static let target = "Target"
    static let reminders = "Reminders"
    static let faceIDLock = "Face ID lock"
    static let exportData = "Export data"
    static let deleteAccount = "Delete account"
    static let connected = "Connected"
    static let off = "Off"
    static let on = "On"
    static let notSet = "Not set"
    static let free = "Free"
    static let pro = "Pro"
    static let proAnnual = "Pro, annual"
    static let proMonthly = "Pro, monthly"
    static let changePlan = "Change plan"
    static let restorePurchases = "Restore purchases"
    static let restored = "Purchases restored."
    static let restoreFailed = "Nothing to restore for this Apple ID."
    static let included = "Included"
    static let manageInAppStore = "Manage in App Store"
    static let startFreeTrial = "Start free trial"
    static let weight = "Weight"
    static let height = "Height"
    static let bodyFat = "Body fat"
    static let circumference = "Circumference"
    static let unitsNote = "Apple Health keeps its own units. LogYourBody converts when it reads."
    static let targetWeight = "Target weight"
    static let bodyFatTarget = "Body fat target"
    static let targetNote = "Your target is yours. It's used to show pace and to flag when a phase has likely gone on too long."
    static let removeTarget = "Remove target"
    static let weighInReminder = "Weigh-in reminder"
    static let time = "Time"
    static let days = "Days"
    static let everyDay = "Every day"
    static let remindersNote = "One notification, then quiet. No streaks, no nudges."
    static let notificationsOff = "Notifications are off for LogYourBody in iOS Settings."
    static let included1 = "Unlimited progress photos and compare"
    static let included2 = "Body-fat, lean mass and FFMI trends"
    static let included3 = "Phase insights that tell you when to stop cutting"

    static func renews(on date: String, price: String?) -> String {
        guard let price else { return "Renews \(date)" }
        return "Renews \(date) for \(price)"
    }

    static func planText(isSubscribed: Bool, productIdentifier: String?) -> String {
        guard isSubscribed else { return free }
        let lowercased = (productIdentifier ?? "").lowercased()
        if lowercased.contains("annual") || lowercased.contains("year") { return proAnnual }
        if lowercased.contains("month") { return proMonthly }
        return pro
    }

    static func unitsText(_ system: MeasurementSystem) -> String {
        "\(HomeV2Copy.displayUnit(system)), %"
    }

    static func heightUnitText(_ system: MeasurementSystem) -> String {
        system == .metric ? "cm" : "ft, in"
    }

    static func circumferenceUnitText(_ system: MeasurementSystem) -> String {
        system == .metric ? "cm" : "in"
    }
}

/// What the settings table shows on its right side.
struct HomeV2SettingsValues {
    let profileName: String
    let planText: String
    let healthText: String
    let unitsText: String
    let targetText: String
    let remindersText: String
}

enum HomeV2SettingsRoute: String, Identifiable, Hashable {
    case profile
    case subscription
    case appleHealth
    case units
    case target
    case reminders
    case exportData
    case deleteAccount

    var id: String { rawValue }

    static let allRoutes: [HomeV2SettingsRoute] = [
        .profile, .subscription, .appleHealth, .units, .target, .reminders, .exportData, .deleteAccount
    ]
}

/// A settings row: label, value on the right, chevron. 50pt, hairline below.
struct HomeV2SettingsRow: View {
    let title: String
    var value: String?
    var isDestructive = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(isDestructive ? HomeV2Tokens.Colors.red : HomeV2Tokens.Colors.ink)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                if let value {
                    Text(value)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityIdentifier(identifier)
    }
}

struct HomeV2SettingsGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .padding(.top, HomeV2Tokens.Space.compact)
            .padding(.bottom, HomeV2Tokens.Space.tight)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The settings header shared by S1–S6: back, centered title, balance.
struct HomeV2SettingsHeader: View {
    let title: String
    let identifier: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("\(identifier)_back")

            Text(title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)

            Color.clear
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(minHeight: JovieTokens.compactControlHeight)
    }
}

/// Settings (Pencil S1): one grouped table, values on the right, no CTA.
struct HomeV2SettingsView: View {
    let values: HomeV2SettingsValues
    @Binding var faceIDLock: Bool
    let onBack: () -> Void
    let onRoute: (HomeV2SettingsRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HomeV2SettingsHeader(title: HomeV2SettingsCopy.title, identifier: "home_v2_settings", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeV2SettingsGroupLabel(title: HomeV2SettingsCopy.account)
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.profile,
                        value: values.profileName,
                        identifier: "home_v2_settings_profile"
                    ) { onRoute(.profile) }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.subscription,
                        value: values.planText,
                        identifier: "home_v2_settings_subscription"
                    ) { onRoute(.subscription) }

                    HomeV2SettingsGroupLabel(title: HomeV2SettingsCopy.data)
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.appleHealth,
                        value: values.healthText,
                        identifier: "home_v2_settings_health"
                    ) { onRoute(.appleHealth) }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.units,
                        value: values.unitsText,
                        identifier: "home_v2_settings_units"
                    ) { onRoute(.units) }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.target,
                        value: values.targetText,
                        identifier: "home_v2_settings_target"
                    ) { onRoute(.target) }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.reminders,
                        value: values.remindersText,
                        identifier: "home_v2_settings_reminders"
                    ) { onRoute(.reminders) }

                    HomeV2SettingsGroupLabel(title: HomeV2SettingsCopy.privacy)
                    Toggle(isOn: $faceIDLock) {
                        Text(HomeV2SettingsCopy.faceIDLock)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                    }
                    .tint(HomeV2Tokens.Colors.ion)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .frame(minHeight: 50)
                    .overlay(alignment: .bottom) { HomeV2Hairline() }
                    .accessibilityIdentifier("home_v2_settings_face_id")
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.exportData,
                        identifier: "home_v2_settings_export"
                    ) { onRoute(.exportData) }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.deleteAccount,
                        isDestructive: true,
                        identifier: "home_v2_settings_delete"
                    ) { onRoute(.deleteAccount) }
                }
                .overlay(alignment: .top) { HomeV2Hairline() }
            }
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}
