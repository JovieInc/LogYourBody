import SwiftUI

struct BodyScoreRevealView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        if let result = viewModel.bodyScoreResult {
            OnboardingPageTemplate(
                title: "Your Body Score",
                subtitle: result.statusTagline,
                showsBackButton: false
            ) {
                VStack(spacing: 24) {
                    scoreCard(result: result)

                    statGrid(result: result)

                    targetCard(result: result)
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
                .fill(LinearGradient(colors: [Color.appPrimary, Color.appPrimary.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
