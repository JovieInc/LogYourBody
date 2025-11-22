import SwiftUI

struct BodyScoreBodyFatVisualView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel

    private struct VisualEstimate: Identifiable {
        let percentage: Double
        let label: String
        let description: String
        let imageName: String
        var id: Double { percentage }
    }

    private static let visualEstimates: [VisualEstimate] = [
        .init(
            percentage: 10,
            label: "Athletic",
            description: "Visible abs, sharp muscle separation.",
            imageName: "figure.run"
        ),
        .init(
            percentage: 15,
            label: "Lean",
            description: "Flat midsection with light definition.",
            imageName: "figure.strengthtraining.traditional"
        ),
        .init(
            percentage: 20,
            label: "Balanced",
            description: "Soft definition, steady energy.",
            imageName: "figure.core.training"
        ),
        .init(
            percentage: 25,
            label: "Building",
            description: "Comfortable, ready to tighten up.",
            imageName: "figure.walk"
        ),
        .init(
            percentage: 30,
            label: "Rebuilding",
            description: "Focusing on consistency and momentum.",
            imageName: "bed.double"
        )
    ]

    var body: some View {
        OnboardingPageTemplate(
            title: "Pick the closest match",
            subtitle: "Use the cues to estimate your body fat.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatVisual),
            content: {
                VStack(spacing: 16) {
                    ForEach(Self.visualEstimates) { estimate in
                        Button {
                            handleSelection(estimate)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: estimate.imageName)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(iconColor(for: estimate))

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
                                    .fill(tileFillColor(for: estimate))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(tileStrokeColor(for: estimate), lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            },
            footer: {
                Button("Continue") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBodyFatVisual)
                .opacity(continueButtonOpacity)
            }
        )
    }
}

extension BodyScoreBodyFatVisualView {
    private var continueButtonOpacity: Double {
        if viewModel.canContinueBodyFatVisual {
            return 1
        }
        return 0.4
    }

    private func iconColor(for estimate: VisualEstimate) -> Color {
        if isSelected(estimate) {
            return Color.appPrimary
        }
        return Color.appTextSecondary
    }

    private func tileFillColor(for estimate: VisualEstimate) -> Color {
        if isSelected(estimate) {
            return Color.appPrimary.opacity(0.15)
        }
        return Color.appCard.opacity(0.6)
    }

    private func tileStrokeColor(for estimate: VisualEstimate) -> Color {
        if isSelected(estimate) {
            return Color.appPrimary
        }
        return Color.appBorder.opacity(0.4)
    }

    private func isSelected(_ estimate: VisualEstimate) -> Bool {
        viewModel.selectedVisualBodyFat == estimate.percentage
    }

    private func handleSelection(_ estimate: VisualEstimate) {
        let previousSelection = viewModel.selectedVisualBodyFat
        viewModel.selectVisualBodyFat(estimate.percentage)

        guard previousSelection != estimate.percentage else { return }

        let delay: TimeInterval = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if viewModel.canContinueBodyFatVisual && viewModel.currentStep == .bodyFatVisual {
                viewModel.goToNextStep()
            }
        }
    }
}

#Preview {
    BodyScoreBodyFatVisualView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
