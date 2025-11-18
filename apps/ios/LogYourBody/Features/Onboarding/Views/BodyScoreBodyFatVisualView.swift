import SwiftUI

struct BodyScoreBodyFatVisualView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private struct VisualEstimate: Identifiable {
        let id = UUID()
        let percentage: Double
        let label: String
        let description: String
        let imageName: String
    }

    private var estimates: [VisualEstimate] {
        [
            .init(percentage: 10, label: "Athletic", description: "Visible abs, sharp muscle separation.", imageName: "figure.run"),
            .init(percentage: 15, label: "Lean", description: "Flat midsection with light definition.", imageName: "figure.strengthtraining.traditional"),
            .init(percentage: 20, label: "Balanced", description: "Soft definition, steady energy.", imageName: "figure.core.training"),
            .init(percentage: 25, label: "Building", description: "Comfortable, ready to tighten up.", imageName: "figure.walk"),
            .init(percentage: 30, label: "Rebuilding", description: "Focusing on consistency and momentum.", imageName: "bed.double")
        ]
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Pick the closest match",
            subtitle: "Use the cues to estimate your body fat.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 16) {
                ForEach(estimates) { estimate in
                    Button {
                        viewModel.selectVisualBodyFat(estimate.percentage)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: estimate.imageName)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(viewModel.selectedVisualBodyFat == estimate.percentage ? Color.appPrimary : Color.appTextSecondary)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(estimate.label)
                                        .font(OnboardingTypography.headline)
                                        .foregroundStyle(Color.appText)
                                    Spacer()
                                    Text("\(Int(estimate.percentage))%")
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                }

                                Text(estimate.description)
                                    .font(OnboardingTypography.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(viewModel.selectedVisualBodyFat == estimate.percentage ? Color.appPrimary.opacity(0.15) : Color.appCard.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(viewModel.selectedVisualBodyFat == estimate.percentage ? Color.appPrimary : Color.appBorder.opacity(0.4), lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            Button("Continue") {
                viewModel.goToNextStep()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(!viewModel.canContinueBodyFatVisual)
            .opacity(viewModel.canContinueBodyFatVisual ? 1 : 0.4)
        }
    }
}

#Preview {
    BodyScoreBodyFatVisualView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
