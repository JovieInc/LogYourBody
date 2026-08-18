import SwiftUI

struct BodyScoreBodyFatVisualView: View {
    @Environment(\.theme)
    private var theme

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
            title: "Choose the closest range.",
            subtitle: "This is an estimate. You can replace it with a measured value anytime.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatVisual),
            screen: .visualEstimate,
            content: {
                VStack(spacing: JovieTokens.itemGap) {
                    ForEach(Self.visualEstimates) { estimate in
                        Button {
                            handleSelection(estimate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("\(Int(estimate.percentage))% \(estimate.label)")
                                        .font(OnboardingTypography.headline)
                                        .foregroundStyle(theme.colors.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    Spacer()

                                    Image(
                                        systemName: isSelected(estimate) ? "largecircle.fill.circle" : "circle"
                                    )
                                    .font(.system(.title3, design: .default).weight(.semibold))
                                    .foregroundStyle(
                                        isSelected(estimate)
                                            ? theme.colors.primary
                                            : theme.colors.textSecondary.opacity(0.6)
                                    )
                                }

                                if isSelected(estimate) {
                                    Text(estimate.description)
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight, alignment: .leading)
                            .background(
                                isSelected(estimate) ? theme.colors.surfaceSecondary : theme.colors.surface,
                                in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                                    .stroke(
                                        isSelected(estimate)
                                            ? theme.colors.text.opacity(0.9)
                                            : theme.colors.border.opacity(JovieTokens.hairlineOpacity),
                                        lineWidth: isSelected(estimate) ? 1.5 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .jovieTouchTarget()
                        .accessibilityLabel("\(Int(estimate.percentage)) percent, \(estimate.label). \(estimate.description)")
                        .accessibilityValue(isSelected(estimate) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(isSelected(estimate) ? .isSelected : [])
                    }
                }
            },
            footer: {
                Button {
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBodyFatVisual)
            }
        )
    }
}

extension BodyScoreBodyFatVisualView {
    private func isSelected(_ estimate: VisualEstimate) -> Bool {
        viewModel.selectedVisualBodyFat == estimate.percentage
    }

    private func handleSelection(_ estimate: VisualEstimate) {
        viewModel.selectVisualBodyFat(estimate.percentage)
        HapticManager.shared.selection()
    }
}

#Preview {
    BodyScoreBodyFatVisualView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
