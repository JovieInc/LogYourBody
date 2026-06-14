import SwiftUI

struct DailyWeighInReminderPromptView: View {
    @ObservedObject private var notificationManager: NotificationManager
    @State private var reminderTime: Date
    @State private var isRequesting = false

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

    var body: some View {
        OnboardingPageTemplate(
            title: "Want a daily nudge at 7am?",
            subtitle: "Log your weight once a day so your trend stays useful.",
            showsBackButton: false,
            content: {
                VStack(alignment: .leading, spacing: 18) {
                    reminderIcon

                    DatePicker(
                        "Reminder time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.appCard.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.appBorder.opacity(0.45))
                    )
                    .accessibilityIdentifier("daily_reminder_time_picker")

                    OnboardingBulletList(
                        items: [
                            OnboardingBulletItem(
                                iconName: "clock.fill",
                                text: "One reminder per day at your chosen time."
                            ),
                            OnboardingBulletItem(
                                iconName: "slider.horizontal.3",
                                text: "Change or turn it off anytime in Settings."
                            )
                        ]
                    )
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button {
                        requestReminder()
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Enable reminder")
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("daily_reminder_enable_button")

                    Button("Not now") {
                        notificationManager.skipDailyWeighInPrompt()
                        onComplete()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("daily_reminder_skip_button")
                }
            }
        )
        .task {
            await notificationManager.refreshAuthorizationStatus()
        }
    }

    private var reminderIcon: some View {
        ZStack {
            Circle()
                .fill(Color.appPrimary.opacity(0.16))
                .frame(width: 76, height: 76)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func requestReminder() {
        guard !isRequesting else { return }
        isRequesting = true

        Task {
            _ = await notificationManager.requestDailyWeighInReminder(at: reminderTime)
            await MainActor.run {
                isRequesting = false
                onComplete()
            }
        }
    }
}

#Preview {
    DailyWeighInReminderPromptView()
}
