//
// PreferencesView+RemindersSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var remindersSection: some View {
        SettingsSection(header: "Reminders") {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: "bell.badge.fill",
                    title: "Daily weigh-in",
                    isOn: dailyWeighInReminderBinding,
                    subtitle: dailyReminderSubtitle
                )
                .accessibilityIdentifier("settings_daily_weigh_in_reminder_toggle")

                if notificationManager.isDailyWeighInReminderEnabled {
                    DSDivider().insetted(16)

                    DatePicker(
                        "Reminder time",
                        selection: $dailyReminderDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
                    .onChange(of: dailyReminderDate) { _, newValue in
                        Task {
                            await notificationManager.updateDailyWeighInReminderTime(to: newValue)
                        }
                    }
                    .accessibilityIdentifier("settings_daily_weigh_in_reminder_time_picker")
                }
            }
        }
    }

    var integrationsSection: some View {
        SettingsSection(header: "Integrations") {
            SettingsNavigationLink(
                icon: "square.stack.3d.up.fill",
                title: "Integrations",
                subtitle: "Connect Apple Health and other services."
            ) {
                IntegrationsView()
            }
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
                        }
                    }
                }
            }
        )
    }
}
