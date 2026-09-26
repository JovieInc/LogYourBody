//
// HomeV2SettingsDetailViews.swift
// LogYourBody
//
import SwiftUI

/// Subscription (Pencil S2): the plan, two quiet rows, what is included,
/// one Manage in App Store action.
struct HomeV2SubscriptionView: View {
    let isSubscribed: Bool
    let planText: String
    let renewsText: String?
    let onBack: () -> Void
    let onChangePlan: () -> Void
    let onRestore: () async -> Bool
    let onManage: () -> Void

    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HomeV2SettingsHeader(title: HomeV2SettingsCopy.subscription, identifier: "home_v2_subscription", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                        Text(isSubscribed ? HomeV2SettingsCopy.pro : HomeV2SettingsCopy.free)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.progressValue / 2, weight: .bold, relativeTo: .title)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                            .accessibilityIdentifier("home_v2_subscription_plan")
                        if let renewsText {
                            Text(renewsText)
                                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        }
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.vertical, HomeV2Tokens.Space.margin)

                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.changePlan,
                        value: isSubscribed ? planText : nil,
                        identifier: "home_v2_subscription_change"
                    ) { onChangePlan() }
                    .overlay(alignment: .top) { HomeV2Hairline() }
                    HomeV2SettingsRow(
                        title: HomeV2SettingsCopy.restorePurchases,
                        identifier: "home_v2_subscription_restore"
                    ) { restore() }

                    if let restoreMessage {
                        Text(restoreMessage)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .padding(.horizontal, HomeV2Tokens.Space.inset)
                            .padding(.top, HomeV2Tokens.Space.row)
                            .accessibilityIdentifier("home_v2_subscription_restore_message")
                    }

                    HomeV2SettingsGroupLabel(title: HomeV2SettingsCopy.included)
                    let included = [HomeV2SettingsCopy.included1, HomeV2SettingsCopy.included2, HomeV2SettingsCopy.included3]
                    ForEach(included, id: \.self) { line in
                        Text(line)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                            .padding(.horizontal, HomeV2Tokens.Space.margin)
                            .padding(.vertical, HomeV2Tokens.Space.tight / 2)
                    }
                }
            }

            HomeV2Dock(
                title: isSubscribed ? HomeV2SettingsCopy.manageInAppStore : HomeV2SettingsCopy.startFreeTrial,
                identifier: "home_v2_subscription_manage",
                action: isSubscribed ? onManage : onChangePlan
            )
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task { @MainActor in
            let restored = await onRestore()
            isRestoring = false
            restoreMessage = restored ? HomeV2SettingsCopy.restored : HomeV2SettingsCopy.restoreFailed
        }
    }
}

/// Units (Pencil S3): the weight unit is the one choice; height and
/// circumference follow it; body fat is always a percentage.
struct HomeV2UnitsView: View {
    @Binding var system: MeasurementSystem
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HomeV2SettingsHeader(title: HomeV2SettingsCopy.units, identifier: "home_v2_units", onBack: onBack)

            VStack(alignment: .leading, spacing: 0) {
                Menu {
                    ForEach(MeasurementSystem.allCases, id: \.self) { candidate in
                        Button {
                            system = candidate
                            HapticManager.shared.selection()
                        } label: {
                            if candidate == system {
                                Label(HomeV2Copy.displayUnit(candidate), systemImage: "checkmark")
                            } else {
                                Text(HomeV2Copy.displayUnit(candidate))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: HomeV2Tokens.Space.tight) {
                        Text(HomeV2SettingsCopy.weight)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Spacer(minLength: HomeV2Tokens.Space.tight)
                        Text(HomeV2Copy.displayUnit(system))
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HomeV2Tokens.Colors.quiet)
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .overlay(alignment: .top) { HomeV2Hairline() }
                .overlay(alignment: .bottom) { HomeV2Hairline() }
                .accessibilityLabel("\(HomeV2SettingsCopy.weight), \(HomeV2Copy.displayUnit(system))")
                .accessibilityIdentifier("home_v2_units_weight")

                staticRow(HomeV2SettingsCopy.height, value: HomeV2SettingsCopy.heightUnitText(system))
                staticRow(HomeV2SettingsCopy.bodyFat, value: "%")
                staticRow(HomeV2SettingsCopy.circumference, value: HomeV2SettingsCopy.circumferenceUnitText(system))

                Text(HomeV2SettingsCopy.unitsNote)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.top, HomeV2Tokens.Space.row)
            }
            .padding(.top, HomeV2Tokens.Space.row)

            Spacer(minLength: 0)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func staticRow(_ title: String, value: String) -> some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            Text(title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Spacer(minLength: HomeV2Tokens.Space.tight)
            Text(value)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
    }
}

/// Target (Pencil S4): the targets that exist, the note, a quiet remove.
struct HomeV2TargetView: View {
    let weightTargetText: String
    let bodyFatTargetText: String
    let hasAnyTarget: Bool
    let onBack: () -> Void
    let onEditWeight: () -> Void
    let onEditBodyFat: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HomeV2SettingsHeader(title: HomeV2SettingsCopy.target, identifier: "home_v2_target", onBack: onBack)

            VStack(alignment: .leading, spacing: 0) {
                HomeV2SettingsRow(
                    title: HomeV2SettingsCopy.targetWeight,
                    value: weightTargetText,
                    identifier: "home_v2_target_weight",
                    action: onEditWeight
                )
                .overlay(alignment: .top) { HomeV2Hairline() }
                HomeV2SettingsRow(
                    title: HomeV2SettingsCopy.bodyFatTarget,
                    value: bodyFatTargetText,
                    identifier: "home_v2_target_body_fat",
                    action: onEditBodyFat
                )

                Text(HomeV2SettingsCopy.targetNote)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.top, HomeV2Tokens.Space.row)
            }
            .padding(.top, HomeV2Tokens.Space.row)

            Spacer(minLength: 0)

            if hasAnyTarget {
                Button(action: onRemove) {
                    Text(HomeV2SettingsCopy.removeTarget)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .medium, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, HomeV2Tokens.Space.compact)
                .accessibilityIdentifier("home_v2_target_remove")
            }
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

/// Reminders (Pencil S5): one weigh-in reminder, its time, then quiet.
struct HomeV2RemindersView: View {
    @ObservedObject var notificationManager: NotificationManager
    let onBack: () -> Void

    @State private var reminderDate = Date()
    @State private var showsNotificationsOff = false

    var body: some View {
        VStack(spacing: 0) {
            HomeV2SettingsHeader(title: HomeV2SettingsCopy.reminders, identifier: "home_v2_reminders", onBack: onBack)

            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: reminderBinding) {
                    Text(HomeV2SettingsCopy.weighInReminder)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                }
                .tint(HomeV2Tokens.Colors.ion)
                .padding(.horizontal, HomeV2Tokens.Space.inset)
                .frame(minHeight: 50)
                .overlay(alignment: .top) { HomeV2Hairline() }
                .overlay(alignment: .bottom) { HomeV2Hairline() }
                .accessibilityIdentifier("home_v2_reminders_toggle")

                if notificationManager.isDailyWeighInReminderEnabled {
                    HStack(spacing: HomeV2Tokens.Space.tight) {
                        Text(HomeV2SettingsCopy.time)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Spacer(minLength: HomeV2Tokens.Space.tight)
                        DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(HomeV2Tokens.Colors.ion)
                            .accessibilityIdentifier("home_v2_reminders_time")
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .frame(minHeight: 50)
                    .overlay(alignment: .bottom) { HomeV2Hairline() }

                    HStack(spacing: HomeV2Tokens.Space.tight) {
                        Text(HomeV2SettingsCopy.days)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Spacer(minLength: HomeV2Tokens.Space.tight)
                        Text(HomeV2SettingsCopy.everyDay)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    }
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .frame(minHeight: 50)
                    .overlay(alignment: .bottom) { HomeV2Hairline() }
                    .accessibilityElement(children: .combine)
                }

                Text(showsNotificationsOff ? HomeV2SettingsCopy.notificationsOff : HomeV2SettingsCopy.remindersNote)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.top, HomeV2Tokens.Space.row)
                    .accessibilityIdentifier("home_v2_reminders_note")
            }
            .padding(.top, HomeV2Tokens.Space.row)

            Spacer(minLength: 0)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { reminderDate = notificationManager.dailyWeighInReminderDate }
        .onChange(of: reminderDate) { _, newValue in
            Task { await notificationManager.updateDailyWeighInReminderTime(to: newValue) }
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { notificationManager.isDailyWeighInReminderEnabled },
            set: { isOn in
                HapticManager.shared.selection()
                Task { @MainActor in
                    let applied = await notificationManager.setDailyWeighInReminderEnabled(isOn)
                    reminderDate = notificationManager.dailyWeighInReminderDate
                    showsNotificationsOff = isOn && !applied
                }
            }
        )
    }
}
