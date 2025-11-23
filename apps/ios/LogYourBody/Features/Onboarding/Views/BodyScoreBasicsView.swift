import SwiftUI

struct BodyScoreBasicsView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    private var continueButtonOpacity: Double {
        viewModel.canContinueBasics ? 1 : 0.4
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Let’s dial in basics.",
            subtitle: "Keep it simple—these power your Body Score.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .basics),
            content: {
                VStack(spacing: 28) {
                    OnboardingFormSection(title: "Sex at birth", caption: "For accurate benchmarks only.") {
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

                        OnboardingInfoRow(text: "We use sex at birth only to match you to the right comparison group—never for marketing.")
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button {
                        viewModel.goToNextStep()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!viewModel.canContinueBasics)
                    .opacity(continueButtonOpacity)

                    OnboardingTextButton(title: "Back") {
                        viewModel.goBack()
                    }
                }
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
