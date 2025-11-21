import SwiftUI

struct BodyScoreBodyFatChoiceView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private let options: [(title: String, subtitle: String, source: BodyFatInputSource, icon: String)] = [
        ("I know my %", "From scans, smart scales, or DEXA.", .manualValue, "checkmark.circle"),
        ("I’ll eyeball it", "Use visual reference photos to estimate.", .visualEstimate, "eye.fill")
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
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.appCard.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.appBorder.opacity(0.4))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Skip for now") {
                        viewModel.updateBodyFatSource(.unspecified)
                        viewModel.goToNextStep()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
        )
    }
}

#Preview {
    BodyScoreBodyFatChoiceView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
