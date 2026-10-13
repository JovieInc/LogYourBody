//
// PreferencesView+RemindersSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var remindersSection: some View {
        SettingsSection(header: "Reminders") {
            SettingsToggleRow(
                icon: "bell.badge.fill",
                title: "Daily weigh-in",
                titleAccessibilityIdentifier: "home_v2_reminders_toggle",
                isOn: dailyWeighInReminderBinding,
                subtitle: dailyReminderSubtitle
            )
            .accessibilityIdentifier("settings_daily_weigh_in_reminder_toggle")

            if notificationManager.isDailyWeighInReminderEnabled {
                DatePicker(selection: $dailyReminderDate, displayedComponents: .hourAndMinute) {
                    Text("Reminder time")
                        .accessibilityIdentifier("home_v2_reminders_time")
                }
                .datePickerStyle(.compact)
                .onChange(of: dailyReminderDate) { _, newValue in
                    Task {
                        await notificationManager.updateDailyWeighInReminderTime(to: newValue)
                    }
                }
                .accessibilityIdentifier("settings_daily_weigh_in_reminder_time_picker")

                SettingsRow(
                    title: HomeV2SettingsCopy.days,
                    titleAccessibilityIdentifier: "home_v2_reminders_days",
                    value: HomeV2SettingsCopy.everyDay
                )
            }

            Text(HomeV2SettingsCopy.remindersNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("home_v2_reminders_note")
        }
    }

    var integrationsLauncherRow: some View {
        SettingsNavigationLink(
            icon: "square.stack.3d.up.fill",
            title: "Integrations",
            subtitle: "Apple Health, imports, and export",
            accessibilityIdentifier: "settings_integrations_link",
            titleAccessibilityIdentifier: "home_v2_settings_health"
        ) {
            IntegrationsView()
        }
    }

    var dailyReminderSubtitle: String {
        if notificationManager.isDailyWeighInReminderEnabled {
            return "On at \(notificationManager.dailyWeighInDisplayTime)"
        }

        if notificationManager.authorizationStatus == .denied {
            return "Off. Enable notifications in iOS Settings."
        }

        return "Off"
    }

    var dailyWeighInReminderBinding: Binding<Bool> {
        Binding(
            get: {
                notificationManager.isDailyWeighInReminderEnabled
            },
            set: { isEnabled in
                HapticManager.shared.selection()
                Task {
                    let didApply = await notificationManager.setDailyWeighInReminderEnabled(isEnabled)
                    await MainActor.run {
                        dailyReminderDate = notificationManager.dailyWeighInReminderDate
                        if isEnabled && !didApply {
                            HapticManager.shared.notification(type: .warning)
                            showingNotificationSettingsAlert = true
                        }
                    }
                }
            }
        )
    }
}
