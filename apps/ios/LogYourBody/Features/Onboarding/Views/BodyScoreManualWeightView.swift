import SwiftUI

struct BodyScoreManualWeightView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var weightFieldFocused: Bool
    @AccessibilityFocusState private var weightErrorFocused: Bool
    @State private var weightError: String?
    @State private var showWhyWeAsk = false

    var body: some View {
        OnboardingPageTemplate(
            title: "What’s your most recent weight?",
            subtitle: "Helps us calculate lean mass and Body Score.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .manualWeight),
            content: {
                VStack(spacing: JovieTokens.sectionGap) {
                    VStack(alignment: .leading, spacing: 16) {
                        OnboardingSegmentedControl(options: WeightUnit.allCases, selection: weightUnitBinding)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(viewModel.weightFieldTitle)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(theme.colors.textSecondary)

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
                            .frame(minHeight: JovieTokens.controlHeight)
                            .systemBGlassSurface(
                                cornerRadius: theme.radius.input,
                                tint: weightFieldFocused ? theme.colors.primary : theme.colors.text,
                                tintOpacity: weightFieldFocused ? 0.07 : 0.03,
                                borderColor: weightFieldBorderColor,
                                borderOpacity: 1
                            )
                            .overlay(
                                HStack {
                                    Spacer()
                                    Text(viewModel.weightUnit == .kilograms ? "kg" : "lb")
                                        .font(OnboardingTypography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                        .padding(.trailing, 20)
                                }
                            )
                            .accessibilityLabel(viewModel.weightFieldTitle)
                            .accessibilityHint("Enter your most recent weight.")

                            HStack(spacing: 12) {
                                Button {
                                    nudgeWeight(by: -stepAmount)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(.body, design: .default).weight(.medium))
                                        .foregroundStyle(theme.colors.text)
                                        .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                                        .systemBGlassSurface(
                                            cornerRadius: 16,
                                            tint: theme.colors.text,
                                            tintOpacity: 0.03,
                                            borderColor: theme.colors.border,
                                            borderOpacity: 0.55
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Decrease weight by \(stepDescription)")

                                Button {
                                    nudgeWeight(by: stepAmount)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(.body, design: .default).weight(.medium))
                                        .foregroundStyle(theme.colors.text)
                                        .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                                        .systemBGlassSurface(
                                            cornerRadius: 16,
                                            tint: theme.colors.text,
                                            tintOpacity: 0.05,
                                            borderColor: theme.colors.border,
                                            borderOpacity: 0.65
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Increase weight by \(stepDescription)")
                            }
                        }

                        if let error = weightError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(theme.colors.error)
                                .accessibilityFocused($weightErrorFocused)
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Weight plus body fat unlocks lean-mass insights for your Body Score.")
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(theme.colors.textSecondary)

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
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueWeight)
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
        .onChange(of: weightError) { _, error in
            weightErrorFocused = error != nil
        }
    }

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { viewModel.weightUnit },
            set: { viewModel.setWeightUnit($0) }
        )
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
            return theme.colors.primary
        }
        return theme.colors.border.opacity(0.65)
    }

    private var stepDescription: String {
        "\(BodyScoreManualWeightView.format(stepAmount)) \(viewModel.weightUnit == .kilograms ? "kilograms" : "pounds")"
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

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
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
