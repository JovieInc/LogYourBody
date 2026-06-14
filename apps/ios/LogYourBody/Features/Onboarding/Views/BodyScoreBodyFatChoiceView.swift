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
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.appPrimary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(OnboardingTypography.headline)
                                        .foregroundStyle(Color.appText)

                                    Text(option.subtitle)
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.appTextSecondary)
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
