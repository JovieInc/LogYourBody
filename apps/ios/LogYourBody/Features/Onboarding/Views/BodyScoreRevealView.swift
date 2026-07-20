import SwiftUI

enum BodyScoreRevealPolicy {
    /// Comparison-group copy follows the entered sex at birth, with a neutral
    /// fallback when no sex was provided.
    static func percentileGroupLabel(for sex: BiologicalSex?) -> String {
        switch sex {
        case .male:
            return "men your age and height"
        case .female:
            return "women your age and height"
        default:
            return "people your age and height"
        }
    }

    /// The body-fat range is framed as a "Target" until the individualized
    /// aesthetic goals gate re-labels it as a "Reference".
    static func referenceText(
        range: BodyScoreResult.ReferenceRange,
        usesIndividualizedAestheticGoals: Bool
    ) -> String {
        let label = usesIndividualizedAestheticGoals ? "Reference" : "Target"
        let lowerBound = Int(range.lowerBound)
        let upperBound = Int(range.upperBound)
        return "\(label): \(lowerBound)–\(upperBound)% (\(range.label))"
    }

    static func referenceAccessibilityText(
        range: BodyScoreResult.ReferenceRange,
        usesIndividualizedAestheticGoals: Bool
    ) -> String {
        let label = usesIndividualizedAestheticGoals ? "Reference" : "Target"
        let lowerBound = Int(range.lowerBound)
        let upperBound = Int(range.upperBound)
        return "\(label) body fat: \(lowerBound) to \(upperBound) percent. \(range.label)."
    }

    /// Builds the share-card payload from the onboarding input, converting
    /// weight into the preferred measurement system and falling back to "--"
    /// when a metric is missing.
    static func makeSharePayload(input: BodyScoreInput, result: BodyScoreResult) -> BodyScoreSharePayload {
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
        if let bodyFat = input.bodyFat.percentage {
            bodyFatValue = String(format: "%.1f", bodyFat)
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
            deltaText: nil,
            bodyFatPercentage: input.bodyFat.percentage,
            gender: input.sex?.rawValue,
            photoImage: nil
        )
    }
}

struct BodyScoreRevealView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var animateScore = false
    @State private var isSharePresented = false
    @State private var sharePayload: BodyScoreSharePayload?
    @State private var featureGateRefreshToken = UUID()
    @AccessibilityFocusState private var scoreFocused: Bool

    private var percentileGroupLabel: String {
        BodyScoreRevealPolicy.percentileGroupLabel(for: viewModel.bodyScoreInput.sex)
    }

    private var usesIndividualizedAestheticGoals: Bool {
        _ = featureGateRefreshToken

        return AppServicePorts.analyticsTracker.isFeatureEnabled(
            flagKey: AppFeatureGate.individualizedAestheticGoals
        )
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
                            .animation(reduceMotion ? nil : theme.animation.spring, value: animateScore)
                            .accessibilityFocused($scoreFocused)

                        statRow(result: result, groupLabel: percentileGroupLabel)
                            .opacity(animateScore ? 1 : 0)
                            .offset(y: animateScore ? 0 : 12)
                            .animation(
                                reduceMotion ? nil : theme.animation.fast.delay(0.1),
                                value: animateScore
                            )

                        referencePill(result: result)
                            .opacity(animateScore ? 1 : 0)
                            .offset(y: animateScore ? 0 : 16)
                            .animation(
                                reduceMotion ? nil : theme.animation.fast.delay(0.15),
                                value: animateScore
                            )
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
        .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
            featureGateRefreshToken = UUID()
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
                .font(theme.typography.displayLarge)
                .monospacedDigit()
                .foregroundStyle(theme.colors.text)

            Text("Starting point")
                .font(theme.typography.labelMedium)
                .foregroundStyle(theme.colors.textSecondary)

            Text("Based on FFMI, body fat %, and trends.")
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body Score \(result.score). \(result.statusTagline)")
    }

    private func statRow(result: BodyScoreResult, groupLabel: String) -> some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        ffmiLabel(result: result)
                        Spacer()
                        percentileLabel(result: result)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ffmiLabel(result: result)
                        percentileLabel(result: result)
                    }
                }

                Text("Compared with \(groupLabel).")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func referencePill(result: BodyScoreResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(theme.colors.primary)

            Text(referenceText(result: result))
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .systemBGlassSurface(
            cornerRadius: theme.radius.full,
            tint: theme.colors.text,
            tintOpacity: 0.035,
            borderColor: theme.colors.border,
            borderOpacity: 0.55
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(referenceAccessibilityText(result: result))
    }

    private func referenceText(result: BodyScoreResult) -> String {
        BodyScoreRevealPolicy.referenceText(
            range: result.bodyFatReferenceRange,
            usesIndividualizedAestheticGoals: usesIndividualizedAestheticGoals
        )
    }

    private func referenceAccessibilityText(result: BodyScoreResult) -> String {
        BodyScoreRevealPolicy.referenceAccessibilityText(
            range: result.bodyFatReferenceRange,
            usesIndividualizedAestheticGoals: usesIndividualizedAestheticGoals
        )
    }

    private func makeSharePayload(from result: BodyScoreResult) -> BodyScoreSharePayload? {
        BodyScoreRevealPolicy.makeSharePayload(input: viewModel.bodyScoreInput, result: result)
    }

    private func triggerRevealFeedback() {
        if reduceMotion {
            animateScore = true
        } else {
            withAnimation(theme.animation.spring) {
                animateScore = true
            }
        }
        DispatchQueue.main.async {
            scoreFocused = true
        }
        HapticManager.shared.successAction()
    }

    private func ffmiLabel(result: BodyScoreResult) -> some View {
        Text("FFMI \(String(format: "%.1f", result.ffmi)) — \(result.ffmiStatus)")
            .font(OnboardingTypography.body)
            .foregroundStyle(theme.colors.text)
    }

    private func percentileLabel(result: BodyScoreResult) -> some View {
        Text("Lean percentile \(String(format: "%.0f", result.leanPercentile))")
            .font(OnboardingTypography.body)
            .foregroundStyle(theme.colors.textSecondary)
    }
}

#Preview {
    let result = BodyScoreResult(
        score: 82,
        ffmi: 21.4,
        leanPercentile: 78,
        ffmiStatus: "Advanced",
        bodyFatReferenceRange: .init(lowerBound: 10, upperBound: 15, label: "Lean"),
        statusTagline: "Solid base. Room to tighten up."
    )
    let vm = OnboardingFlowViewModel()
    vm.bodyScoreResult = result
    return BodyScoreRevealView(viewModel: vm)
        .preferredColorScheme(.dark)
}
