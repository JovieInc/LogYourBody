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

    /// Population ranges describe a comparison reference, never a personal target.
    static func referenceText(range: BodyScoreResult.ReferenceRange) -> String {
        let lowerBound = Int(range.lowerBound)
        let upperBound = Int(range.upperBound)
        return "Reference: \(lowerBound)–\(upperBound)% (\(range.label))"
    }

    static func referenceAccessibilityText(range: BodyScoreResult.ReferenceRange) -> String {
        let lowerBound = Int(range.lowerBound)
        let upperBound = Int(range.upperBound)
        return "Reference body fat: \(lowerBound) to \(upperBound) percent. \(range.label)."
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

/// The first-run composition summary: weight split into fat mass and lean mass,
/// with the body-fat source named so an estimate is never presented as a measurement.
struct FatVsMuscleSummary: Equatable {
    let fatText: String
    let leanText: String
    let unitText: String
    let bodyFatPercentText: String
    let fatFraction: Double
    let sourceText: String

    init?(input: BodyScoreInput) {
        guard let weightKg = input.weight.inKilograms, weightKg > 0,
              let bodyFat = input.bodyFat.percentage, bodyFat > 0, bodyFat < 100 else {
            return nil
        }
        let fraction = bodyFat / 100
        let displayWeight: Double
        switch input.measurementPreference {
        case .metric:
            displayWeight = weightKg
            unitText = "kg"
        case .imperial:
            displayWeight = weightKg * 2.20462
            unitText = "lb"
        }
        let fat = (displayWeight * fraction).rounded()
        fatText = String(format: "%.0f", fat)
        leanText = String(format: "%.0f", displayWeight.rounded() - fat)
        bodyFatPercentText = String(format: "%.0f%%", bodyFat)
        fatFraction = fraction
        sourceText = Self.sourceText(for: input.bodyFat.source)
    }

    static func sourceText(for source: BodyFatInputSource) -> String {
        switch source {
        case .scan:
            return "Body fat from your scan"
        case .healthKit:
            return "Body fat from Apple Health"
        case .manualValue:
            return "Body fat you entered"
        case .visualEstimate:
            return "Body fat is a visual estimate"
        case .unspecified:
            return "Body fat source not recorded"
        }
    }

    var accessibilityLabel: String {
        "Fat \(fatText) \(unitText). Lean mass \(leanText) \(unitText). Body fat \(bodyFatPercentText). \(sourceText)."
    }
}

struct BodyScoreRevealView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var isRevealed = false
    @AccessibilityFocusState private var summaryFocused: Bool

    var body: some View {
        Group {
            if let summary = FatVsMuscleSummary(input: viewModel.bodyScoreInput) {
                OnboardingPageTemplate(
                    title: "Here’s your fat vs lean mass.",
                    subtitle: "Calculated from weight and body fat. Lean mass includes more than muscle.",
                    showsBackButton: false,
                    progress: viewModel.progress(for: .bodyScore),
                    screen: .bodyScoreReveal
                ) {
                    VStack(spacing: 20) {
                        massRow(summary: summary)
                            .scaleEffect(isRevealed ? 1 : 0.94)
                            .opacity(isRevealed ? 1 : 0)
                            .animation(reduceMotion ? nil : theme.animation.spring, value: isRevealed)
                            .accessibilityFocused($summaryFocused)

                        compositionBar(summary: summary)
                            .opacity(isRevealed ? 1 : 0)
                            .animation(reduceMotion ? nil : theme.animation.fast.delay(0.1), value: isRevealed)

                        if let changeText {
                            changeLine(changeText)
                                .opacity(isRevealed ? 1 : 0)
                                .animation(reduceMotion ? nil : theme.animation.fast.delay(0.12), value: isRevealed)
                        }

                        sourceLine(summary: summary)
                            .opacity(isRevealed ? 1 : 0)
                            .animation(reduceMotion ? nil : theme.animation.fast.delay(0.15), value: isRevealed)
                    }
                } footer: {
                    VStack(spacing: 12) {
                        Button("Continue") {
                            viewModel.goToNextStep()
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .accessibilityIdentifier("body_score_reveal_continue_button")

                        OnboardingTextButton(title: "Edit my numbers") {
                            viewModel.goBack()
                        }
                    }
                }
            } else {
                BodyScoreLoadingView(viewModel: viewModel)
            }
        }
        .onAppear {
            guard FatVsMuscleSummary(input: viewModel.bodyScoreInput) != nil else { return }
            triggerRevealFeedback()
        }
    }

    private var changeText: String? {
        viewModel.scanImport.flatMap {
            ScanChangePolicy.changeText(for: $0, system: viewModel.bodyScoreInput.measurementPreference)
        }
    }

    private func changeLine(_ text: String) -> some View {
        OnboardingCard {
            Text(text)
                .font(OnboardingTypography.body)
                .foregroundStyle(theme.colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("body_score_reveal_scan_change")
    }

    private func massRow(summary: FatVsMuscleSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            massColumn(label: "Fat", value: summary.fatText, unit: summary.unitText, tint: theme.colors.accentPink)
            massColumn(label: "Lean mass", value: summary.leanText, unit: summary.unitText, tint: theme.colors.info)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityIdentifier("body_score_reveal_fat_vs_muscle")
    }

    private func massColumn(label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(label)
            } icon: {
                Circle().fill(tint).frame(width: 8, height: 8)
            }
            .font(theme.typography.labelMedium)
            .foregroundStyle(theme.colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(theme.typography.displayLarge)
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(theme.typography.labelLarge)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compositionBar(summary: FatVsMuscleSummary) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule(style: .continuous)
                    .fill(theme.colors.accentPink)
                    .frame(width: max(proxy.size.width * summary.fatFraction - 1, 4))
                Capsule(style: .continuous)
                    .fill(theme.colors.info)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func sourceLine(summary: FatVsMuscleSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(theme.colors.textSecondary)
            Text("\(summary.bodyFatPercentText) body fat. \(summary.sourceText).")
                .font(OnboardingTypography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body_score_reveal_source")
    }

    private func triggerRevealFeedback() {
        if reduceMotion {
            isRevealed = true
        } else {
            withAnimation(theme.animation.spring) {
                isRevealed = true
            }
        }
        DispatchQueue.main.async {
            summaryFocused = true
        }
        HapticManager.shared.successAction()
    }
}

#Preview {
    let vm = OnboardingFlowViewModel()
    vm.bodyScoreInput.weight = WeightValue(value: 182, unit: .pounds)
    vm.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .manualValue)
    vm.bodyScoreResult = BodyScoreResult(
        score: 82,
        ffmi: 21.4,
        leanPercentile: 78,
        ffmiStatus: "Advanced",
        bodyFatReferenceRange: .init(lowerBound: 10, upperBound: 15, label: "Lean"),
        statusTagline: "Solid base. Room to tighten up."
    )
    return BodyScoreRevealView(viewModel: vm)
        .preferredColorScheme(.dark)
}
