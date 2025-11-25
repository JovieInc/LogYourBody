import SwiftUI

struct BodyScoreBasicsView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @State private var showWhyWeAsk = false
    private var continueButtonOpacity: Double {
        viewModel.canContinueBasics ? 1 : 0.4
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Sex at birth",
            subtitle: "For accurate comparisons only.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .basics),
            content: {
                VStack(spacing: 24) {
                    OnboardingFormSection {
                        HStack(spacing: 16) {
                            ForEach(BiologicalSex.allCases, id: \.self) { sex in
                                OnboardingOptionButton(
                                    title: sex.description,
                                    subtitle: nil,
                                    isSelected: viewModel.bodyScoreInput.sex == sex,
                                    action: {
                                        handleSexSelection(sex)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showWhyWeAsk.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Why we ask")
                                    .font(OnboardingTypography.caption)
                            }
                            .foregroundStyle(Color.appPrimary)
                        }
                        .buttonStyle(.plain)

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
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBasics)
                .opacity(continueButtonOpacity)
            }
        )
    }

    private func handleSexSelection(_ sex: BiologicalSex) {
        let previousSex = viewModel.bodyScoreInput.sex
        viewModel.updateSex(sex)

        guard previousSex != sex else { return }

        let delay: TimeInterval = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if viewModel.canContinueBasics && viewModel.currentStep == .basics {
                viewModel.goToNextStep()
            }
        }
    }
}

#Preview {
    BodyScoreBasicsView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
