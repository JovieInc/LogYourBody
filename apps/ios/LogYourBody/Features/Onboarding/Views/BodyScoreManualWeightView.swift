import SwiftUI

struct BodyScoreManualWeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var weightFieldFocused: Bool
    @State private var weightError: String?

    var body: some View {
        OnboardingPageTemplate(
            title: "What’s your most recent weight?",
            subtitle: "Helps us calculate lean mass and Body Score.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .manualWeight),
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
                            .submitLabel(.done)
                            .onSubmit {
                                weightFieldFocused = false
                            }
                            .onChange(of: viewModel.manualWeightText) { _, newValue in
                                validateWeight(newValue)
                            }
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

                        if let error = weightError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(Color.red)
                        } else {
                            OnboardingCaptionText(text: viewModel.weightHelperText, alignment: .leading)
                                .foregroundStyle(Color.appTextSecondary)
                        }
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
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        weightFieldFocused = false
                    }
                }
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

    private func validateWeight(_ value: String) {
        guard !value.isEmpty else {
            weightError = nil
            return
        }

        guard let numeric = Double(value) else {
            weightError = "Enter a valid number."
            return
        }

        let poundsEquivalent: Double
        if viewModel.weightUnit == .kilograms {
            poundsEquivalent = numeric * 2.2046226218
        } else {
            poundsEquivalent = numeric
        }

        if poundsEquivalent < 70 {
            if viewModel.weightUnit == .kilograms {
                weightError = "Enter at least 32 kg (about 70 lbs)."
            } else {
                weightError = "Enter at least 70 lbs (about 32 kg)."
            }
        } else {
            weightError = nil
        }
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
