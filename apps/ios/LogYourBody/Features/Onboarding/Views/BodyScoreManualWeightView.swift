import SwiftUI

struct BodyScoreManualWeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var weightFieldFocused: Bool
    @State private var weightError: String?
    @State private var showWhyWeAsk = false

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
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.appCard.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(weightFieldBorderColor)
                            )
                            .overlay(
                                HStack {
                                    Spacer()
                                    Text(viewModel.weightUnit == .kilograms ? "kg" : "lb")
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                        .padding(.trailing, 20)
                                }
                            )

                            HStack(spacing: 12) {
                                Button {
                                    nudgeWeight(by: -stepAmount)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.appText)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(Color.appCard.opacity(0.6))
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    nudgeWeight(by: stepAmount)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.appText)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(Color.appCard.opacity(0.8))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let error = weightError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(Color.red)
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Weight plus body fat unlocks lean-mass insights for your Body Score.")
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(Color.appTextSecondary)

                                FFMIInfoLink()
                                    .padding(.top, 2)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            },
            footer: {
                Button {
                    viewModel.persistManualWeightEntry()
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold))
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

    private var stepAmount: Double {
        viewModel.weightUnit == .kilograms ? 0.5 : 1
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

    private func nudgeWeight(by amount: Double) {
        let currentText = viewModel.manualWeightText
        let existingFromInput = Double(currentText)
        let existingFromModel: Double?
        if viewModel.weightUnit == .kilograms {
            existingFromModel = viewModel.bodyScoreInput.weight.inKilograms
        } else {
            existingFromModel = viewModel.bodyScoreInput.weight.inPounds
        }

        let baseline = existingFromInput ?? existingFromModel ?? 0
        let newValue = max(0, baseline + amount)

        let formatted: String
        if newValue == floor(newValue) {
            formatted = String(format: "%.0f", newValue)
        } else {
            formatted = String(format: "%.1f", newValue)
        }

        viewModel.updateManualWeightText(formatted)
        validateWeight(formatted)
    }
}

#Preview {
    BodyScoreManualWeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
