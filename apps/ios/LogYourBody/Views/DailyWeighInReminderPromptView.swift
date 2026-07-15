import SwiftUI
import UIKit
import UserNotifications

struct DailyWeighInReminderPromptView: View {
    @ObservedObject private var notificationManager: NotificationManager
    @Environment(\.openURL) private var openURL
    @State private var reminderTime: Date
    @State private var isRequesting = false
    @State private var showPermissionRecovery = false

    let onComplete: () -> Void

    init(
        notificationManager: NotificationManager,
        onComplete: @escaping () -> Void = {}
    ) {
        self.notificationManager = notificationManager
        self.onComplete = onComplete
        _reminderTime = State(initialValue: notificationManager.dailyWeighInReminderDate)
    }

    @MainActor
    init(onComplete: @escaping () -> Void = {}) {
        self.init(notificationManager: NotificationManager.shared, onComplete: onComplete)
    }

    private var notificationsDenied: Bool {
        notificationManager.authorizationStatus == .denied
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Set a daily weigh-in reminder",
            subtitle: "Choose a time that works for you. You can change or turn it off anytime in Settings.",
            showsBackButton: false,
            content: {
                VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                    reminderIcon
                    reminderTimePicker

                    Text("One reminder per day helps keep your weight trend useful.")
                        .font(.subheadline)
                        .foregroundColor(.jovieTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if notificationsDenied || showPermissionRecovery {
                        permissionRecoveryNotice
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button {
                        requestReminder()
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .tint(.jovieActionText)
                        } else {
                            Text("Enable reminder")
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("daily_reminder_enable_button")
                    .accessibilityHint("Requests permission and schedules a daily reminder at the selected time.")

                    Button("Not now") {
                        notificationManager.skipDailyWeighInPrompt()
                        onComplete()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("daily_reminder_skip_button")
                    .accessibilityHint("Continues without a daily reminder.")
                }
            }
        )
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
        .alert("Notifications are unavailable", isPresented: $showPermissionRecovery) {
            if notificationsDenied {
                Button("Open Settings") {
                    openAppSettings()
                }
            }
            Button("Not now", role: .cancel) {
                onComplete()
            }
        } message: {
            Text(
                notificationsDenied
                    ? "Notifications are turned off for LogYourBody. You can enable them in Settings."
                    : "LogYourBody could not schedule your reminder. You can try again or continue without one."
            )
        }
    }

    private var reminderTimePicker: some View {
        DatePicker(
            "Reminder time",
            selection: $reminderTime,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.compact)
        .font(.body.weight(.medium))
        .foregroundColor(.jovieText)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .fill(Color.jovieSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .stroke(Color.jovieHairline, lineWidth: 1)
        )
        .accessibilityIdentifier("daily_reminder_time_picker")
    }

    private var permissionRecoveryNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundColor(.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.jovieText)

                Text("Enable notifications in Settings to receive this reminder.")
                    .font(.footnote)
                    .foregroundColor(.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings") {
                    openAppSettings()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.jovieText)
                .frame(minHeight: JovieTokens.minimumHitTarget)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .fill(Color.jovieSurfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .stroke(Color.warning.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var reminderIcon: some View {
        Image(systemName: "bell.badge.fill")
            .font(.system(.title, design: .default).weight(.semibold))
            .foregroundStyle(Color.jovieText)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Color.jovieSurfaceElevated))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func requestReminder() {
        guard !isRequesting else { return }
        isRequesting = true

        Task { @MainActor in
            let enabled = await notificationManager.requestDailyWeighInReminder(at: reminderTime)
            isRequesting = false

            if enabled {
                onComplete()
            } else {
                showPermissionRecovery = true
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Notifications could not be enabled. Review the available recovery options."
                )
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

#Preview {
    DailyWeighInReminderPromptView()
}
