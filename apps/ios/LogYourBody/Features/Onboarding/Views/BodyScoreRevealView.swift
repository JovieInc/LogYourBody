import SwiftUI

struct BodyScoreRevealView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var animateScore = false
    @State private var isSharePresented = false
    @State private var sharePayload: BodyScoreSharePayload?

    private var percentileGroupLabel: String {
        let sex = viewModel.bodyScoreInput.sex
        switch sex {
        case .male:
            return "men your age and height"
        case .female:
            return "women your age and height"
        default:
            return "people your age and height"
        }
    }

    var body: some View {
        Group {
            if let result = viewModel.bodyScoreResult {
                OnboardingPageTemplate(
                    title: "Your Body Score",
                    subtitle: result.statusTagline,
                    showsBackButton: false,
                    progress: viewModel.progress(for: .bodyScore)
                ) {
                    VStack(spacing: 20) {
                        scoreCard(result: result)
                            .scaleEffect(animateScore ? 1 : 0.9)
                            .opacity(animateScore ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: animateScore)

                        statGrid(result: result, groupLabel: percentileGroupLabel)
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
                        Button("See my next steps") {
                            viewModel.goToNextStep()
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())

                        Button("Retake inputs") {
                            viewModel.goBack()
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())

                        Button("Share my score") {
                            sharePayload = makeSharePayload(from: result)
                            isSharePresented = sharePayload != nil
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
        .sheet(isPresented: $isSharePresented) {
            if let payload = sharePayload {
                BodyScoreShareSheet(payload: payload)
            }
        }
    }

    private func scoreCard(result: BodyScoreResult) -> some View {
        VStack(spacing: 10) {
            Text("Starting point")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.white.opacity(0.9))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(result.score)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text("/ 100")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            OnboardingCaptionText(
                text: "We'll raise this as you log training and nutrition.",
                alignment: .center
            )
            .foregroundStyle(Color.white.opacity(0.9))

            OnboardingCaptionText(
                text: "Based on FFMI, body fat %, and progress trends.",
                alignment: .center
            )
            .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
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

    private func statGrid(result: BodyScoreResult, groupLabel: String) -> some View {
        HStack(spacing: 16) {
            statTile(
                title: "FFMI",
                value: String(format: "%.1f", result.ffmi),
                message: "\(result.ffmiStatus) vs \(groupLabel)"
            )
            statTile(
                title: "Lean %ile",
                value: String(format: "%.0f", result.leanPercentile),
                message: "vs \(groupLabel)"
            )
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
                Text("Optional target range (advanced)")
                    .font(OnboardingTypography.headline)
                    .foregroundStyle(Color.appText)

                Text("\(Int(result.targetBodyFat.lowerBound))% - \(Int(result.targetBodyFat.upperBound))% • \(result.targetBodyFat.label)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.appPrimary)

                Text("We'll adjust this over time based on your progress.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    private func makeSharePayload(from result: BodyScoreResult) -> BodyScoreSharePayload? {
        let input = viewModel.bodyScoreInput

        let system = input.measurementPreference

        let weightValue: String
        let weightUnit: String

        if let weightKg = input.weight.inKilograms {
            switch system {
            case .metric:
                weightValue = String(format: "%.1f", weightKg)
                weightUnit = "kg"
            case .imperial:
                let pounds = weightKg * 2.20462
                weightValue = String(format: "%.1f", pounds)
                weightUnit = "lbs"
            }
        } else {
            weightValue = "--"
            weightUnit = system == .metric ? "kg" : "lbs"
        }

        let bodyFatValue: String
        if let bf = input.bodyFat.percentage {
            bodyFatValue = String(format: "%.1f", bf)
        } else {
            bodyFatValue = "--"
        }

        return BodyScoreSharePayload(
            score: result.score,
            scoreText: "\(result.score)",
            tagline: result.statusTagline,
            ffmiValue: String(format: "%.1f", result.ffmi),
            ffmiCaption: result.ffmiStatus,
            bodyFatValue: bodyFatValue,
            bodyFatCaption: "%",
            weightValue: weightValue,
            weightCaption: weightUnit,
            deltaText: nil
        )
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
