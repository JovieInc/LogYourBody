import SwiftUI

struct TrainingRestTimerView: View {
    let countdown: TrainingRestCountdown
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = countdown.remaining(at: context.date)
            VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                HStack {
                    Label("Rest", systemImage: "timer")
                    Spacer()
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .monospacedDigit()
                        .accessibilityLabel("\(remaining) seconds remaining")
                        .accessibilityIdentifier("training_rest_timer")
                }
                .font(.headline)
                Text(remaining > 0 ? "Adjust this timer to suit you." : "Timer elapsed · readiness not assessed")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                if remaining > 0 {
                    HStack {
                        Button("−15s") { onAdjust(-15) }
                            .accessibilityLabel("Reduce rest by 15 seconds")
                            .accessibilityIdentifier("training_rest_decrease")
                            .disabled(countdown.duration <= TrainingRestPolicy.durationRange.lowerBound)
                        Button("+15s") { onAdjust(15) }
                            .accessibilityLabel("Increase rest by 15 seconds")
                            .accessibilityIdentifier("training_rest_increase")
                            .disabled(countdown.duration >= TrainingRestPolicy.durationRange.upperBound)
                        Spacer()
                        Button("Skip", action: onSkip)
                            .accessibilityIdentifier("training_rest_skip")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(JovieTokens.compactInset)
            .foregroundStyle(theme.colors.text)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
        }
    }
}
