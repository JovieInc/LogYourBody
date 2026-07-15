import SwiftUI

struct BodyScoreBasicsView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var showWhyWeAsk = false

    var body: some View {
        OnboardingPageTemplate(
            title: "Sex at birth",
            subtitle: "For accurate comparisons only.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .basics),
            content: {
                VStack(spacing: JovieTokens.sectionGap) {
                    OnboardingFormSection {
                        VStack(spacing: 12) {
                            ForEach(BiologicalSex.allCases, id: \.self) { sex in
                                OnboardingOptionButton(
                                    title: sex.description,
                                    subtitle: nil,
                                    isSelected: viewModel.bodyScoreInput.sex == sex,
                                    action: {
                                        handleSexSelection(sex)
                                    }
                                )
                            }
                        }

                        Button {
                            toggleWhyWeAsk()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(.footnote, design: .default).weight(.semibold))
                                Text("Why we ask")
                                    .font(OnboardingTypography.caption)
                            }
                            .foregroundStyle(theme.colors.primary)
                        }
                        .buttonStyle(.plain)
                        .jovieTouchTarget()
                        .accessibilityValue(showWhyWeAsk ? "Expanded" : "Collapsed")

                        if showWhyWeAsk {
                            OnboardingInfoRow(
                                text: "We use sex at birth only to match you to the right comparison group—never for marketing."
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
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
                .disabled(!viewModel.canContinueBasics)
            }
        )
    }

    private func handleSexSelection(_ sex: BiologicalSex) {
        viewModel.updateSex(sex)
        HapticManager.shared.selection()
    }

    private func toggleWhyWeAsk() {
        if reduceMotion {
            showWhyWeAsk.toggle()
        } else {
            withAnimation(theme.animation.fast) {
                showWhyWeAsk.toggle()
            }
        }
    }
}

#Preview {
    BodyScoreBasicsView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
