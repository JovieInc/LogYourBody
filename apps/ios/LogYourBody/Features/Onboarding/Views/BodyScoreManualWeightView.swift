import SwiftUI

struct BodyScoreManualWeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var weightFieldFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "What’s your most recent weight?",
            subtitle: "Helps us calculate lean mass and Body Score.",
            onBack: { viewModel.goBack() },
            content: {
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        OnboardingSegmentedControl(options: WeightUnit.allCases, selection: weightUnitBinding)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(viewModel.weightFieldTitle)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(Color.appTextSecondary)

                            TextField(viewModel.weightPlaceholder, text: Binding(
                                get: { viewModel.manualWeightText },
                                set: { viewModel.updateManualWeightText($0) }
                            ))
                            .keyboardType(.decimalPad)
                            .focused($weightFieldFocused)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.appCard.opacity(0.65))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(weightFieldBorderColor)
                            )
                        }

                        OnboardingCaptionText(text: viewModel.weightHelperText, alignment: .leading)
                            .foregroundStyle(Color.appTextSecondary)
                    }

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Why we ask")
                                .font(OnboardingTypography.headline)
                                .foregroundStyle(Color.appText)

                            Text("Weight plus body fat unlocks lean-mass insights for your Body Score.")
                                .font(OnboardingTypography.body)
                                .foregroundStyle(Color.appTextSecondary)

                            FFMIInfoLink()
                                .padding(.top, 4)
                        }
                    }
                }
            },
            footer: {
                Button("Continue") {
                    viewModel.persistManualWeightEntry()
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueWeight)
                .opacity(continueButtonOpacity)
            }
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.weightFieldFocused = true
            }
        }
    }

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { viewModel.weightUnit },
            set: { viewModel.setWeightUnit($0) }
        )
    }

    private var continueButtonOpacity: Double {
        viewModel.canContinueWeight ? 1 : 0.4
    }

    private var weightFieldBorderColor: Color {
        if weightFieldFocused {
            return Color.appPrimary
        }
        return Color.appBorder.opacity(0.4)
    }
}

#Preview {
    BodyScoreManualWeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
