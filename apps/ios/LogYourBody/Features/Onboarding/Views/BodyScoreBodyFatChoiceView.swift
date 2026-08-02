import SwiftUI

struct BodyScoreBodyFatChoiceView: View {
    @Environment(\.theme)
    private var theme

    @ObservedObject var viewModel: OnboardingFlowViewModel

    private let options: [(title: String, subtitle: String, source: BodyFatInputSource, icon: String)] = [
        ("Enter a measured value", "From a scan, smart scale, calipers, or DEXA.", .manualValue, "checkmark.circle"),
        ("Choose an estimated range", "Use neutral descriptions without comparing bodies.", .visualEstimate, "eye.fill")
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "How do you know your body fat?",
            subtitle: "Choose the closest source. You can replace an estimate with a measured value anytime.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatChoice),
            screen: .bodyFatMethod,
            content: {
                VStack(spacing: 20) {
                    ForEach(options, id: \.title) { option in
                        Button {
                            viewModel.updateBodyFatSource(option.source)
                            DispatchQueue.main.async {
                                viewModel.goToNextStep()
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: option.icon)
                                    .font(.system(.title3, design: .rounded).weight(.semibold))
                                    .foregroundStyle(theme.colors.primary)
                                    .frame(width: JovieTokens.minimumHitTarget)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(OnboardingTypography.headline)
                                        .foregroundStyle(theme.colors.text)

                                    Text(option.subtitle)
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            .padding(20)
                            .background(
                                theme.colors.surface,
                                in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                    .stroke(theme.colors.border.opacity(JovieTokens.hairlineOpacity), lineWidth: 1)
                            }
                        }
                        .accessibilityIdentifier("body_score_onboarding_body_fat_\(option.source == .manualValue ? "manual" : "visual")_button")
                        .buttonStyle(.plain)
                        .jovieTouchTarget()
                        .accessibilityLabel("\(option.title). \(option.subtitle)")
                        .accessibilityHint("Continues to the next step.")
                    }

                    Button("Skip for now") {
                        viewModel.updateBodyFatSource(.unspecified)
                        viewModel.goToNextStep()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(theme.colors.error)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
        )
    }
}

#Preview {
    BodyScoreBodyFatChoiceView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
