import SwiftUI

struct BodyScoreRevealView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var animateScore = false

    var body: some View {
        Group {
            if let result = viewModel.bodyScoreResult {
                OnboardingPageTemplate(
                    title: "Your Body Score",
                    subtitle: result.statusTagline,
                    showsBackButton: false
                ) {
                    VStack(spacing: 24) {
                        scoreCard(result: result)
                            .scaleEffect(animateScore ? 1 : 0.9)
                            .opacity(animateScore ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: animateScore)

                        statGrid(result: result)
                            .opacity(animateScore ? 1 : 0)
                            .offset(y: animateScore ? 0 : 12)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: animateScore)

                        targetCard(result: result)
                            .opacity(animateScore ? 1 : 0)
                            .offset(y: animateScore ? 0 : 16)
                            .animation(.easeOut(duration: 0.4).delay(0.15), value: animateScore)
                    }
                } footer: {
                    VStack(spacing: 12) {
                        Button("Save my progress") {
                            viewModel.goToNextStep()
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())

                        Button("Retake inputs") {
                            viewModel.goBack()
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                    }
                }
            } else {
                BodyScoreLoadingView(viewModel: viewModel)
            }
        }
        .onAppear {
            guard viewModel.bodyScoreResult != nil else { return }
            triggerRevealFeedback()
        }
        .onChange(of: viewModel.bodyScoreResult) { _, newValue in
            if newValue != nil {
                triggerRevealFeedback()
            } else {
                animateScore = false
            }
        }
    }

    private func scoreCard(result: BodyScoreResult) -> some View {
        VStack(spacing: 12) {
            Text("\(result.score)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            OnboardingCaptionText(text: "out of 100", alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.appPrimary,
                            Color.appPrimary.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func statGrid(result: BodyScoreResult) -> some View {
        HStack(spacing: 16) {
            statTile(title: "FFMI", value: String(format: "%.1f", result.ffmi), message: result.ffmiStatus)
            statTile(title: "Lean %ile", value: String(format: "%.0f", result.leanPercentile), message: "Among peers")
        }
    }

    private func statTile(title: String, value: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.appTextSecondary)

            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Color.appText)

            Text(message)
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder.opacity(0.4))
        )
    }

    private func targetCard(result: BodyScoreResult) -> some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Target body fat range")
                    .font(OnboardingTypography.headline)
                    .foregroundStyle(Color.appText)

                Text("\(Int(result.targetBodyFat.lowerBound))% - \(Int(result.targetBodyFat.upperBound))% • \(result.targetBodyFat.label)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.appPrimary)

                Text("We’ll coach you into this zone with smarter nutrition and training cues.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    private func triggerRevealFeedback() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            animateScore = true
        }
        HapticManager.shared.successAction()
    }
}

#Preview {
    let result = BodyScoreResult(
        score: 82,
        ffmi: 21.4,
        leanPercentile: 78,
        ffmiStatus: "Advanced",
        targetBodyFat: .init(lowerBound: 10, upperBound: 15, label: "Lean"),
        statusTagline: "Solid base. Room to tighten up."
    )
    let vm = OnboardingFlowViewModel()
    vm.bodyScoreResult = result
    return BodyScoreRevealView(viewModel: vm)
        .preferredColorScheme(.dark)
}
