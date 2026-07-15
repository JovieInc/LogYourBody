import SwiftUI

struct BodyScoreBodyFatChoiceView: View {
    @Environment(\.theme)
    private var theme

    @ObservedObject var viewModel: OnboardingFlowViewModel

    private let options: [(title: String, subtitle: String, source: BodyFatInputSource, icon: String)] = [
        ("I know my %", "From a scan, smart scale, or DEXA.", .manualValue, "checkmark.circle"),
        ("I’ll eyeball it", "Use reference photos to estimate.", .visualEstimate, "eye.fill")
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "How do you want to estimate body fat?",
            subtitle: "Pick whichever feels most accurate.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatChoice),
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
                            .systemBGlassSurface(
                                cornerRadius: 24,
                                tint: theme.colors.text,
                                tintOpacity: 0.035,
                                borderColor: theme.colors.border,
                                borderOpacity: 0.6
                            )
                        }
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
