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
                        scoreHero(result: result)
                            .scaleEffect(animateScore ? 1 : 0.9)
                            .opacity(animateScore ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: animateScore)

                        statRow(result: result, groupLabel: percentileGroupLabel)
                            .opacity(animateScore ? 1 : 0)
                            .offset(y: animateScore ? 0 : 12)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: animateScore)

                        targetPill(result: result)
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

                        OnboardingTextButton(title: "Retake inputs") {
                            viewModel.goBack()
                        }

                        OnboardingTextButton(title: "Share my score") {
                            sharePayload = makeSharePayload(from: result)
                            isSharePresented = sharePayload != nil
                        }
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

    private func scoreHero(result: BodyScoreResult) -> some View {
        VStack(spacing: 8) {
            Text("\(result.score)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appText)

            Text("Starting point")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.appTextSecondary)

            Text("Based on FFMI, body fat %, and trends.")
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statRow(result: BodyScoreResult, groupLabel _: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("FFMI \(String(format: "%.1f", result.ffmi)) — \(result.ffmiStatus)")
                .font(OnboardingTypography.body)
                .foregroundStyle(Color.appText)

            Spacer()

            Text("Lean %ile \(String(format: "%.0f", result.leanPercentile))")
                .font(OnboardingTypography.body)
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    private func targetPill(result: BodyScoreResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appPrimary)

            Text("Target: \(Int(result.targetBodyFat.lowerBound))–\(Int(result.targetBodyFat.upperBound))% (\(result.targetBodyFat.label))")
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.appCard.opacity(0.6))
        )
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
