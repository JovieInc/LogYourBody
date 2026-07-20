import SwiftUI

enum ManualWeightEntryPolicy {
    /// Inline validation for the weight field: empty input clears the error,
    /// unparseable input asks for a number, and anything under the 70 lb
    /// floor (converted for metric entry) shows a unit-specific message.
    static func validationError(for text: String, unit: WeightUnit) -> String? {
        guard !text.isEmpty else { return nil }

        guard let numeric = Double(text) else {
            return "Enter a valid number."
        }

        let poundsEquivalent = unit == .kilograms ? numeric * 2.2046226218 : numeric
        guard poundsEquivalent < 70 else { return nil }

        switch unit {
        case .kilograms:
            return "Enter at least 32 kg (about 70 lbs)."
        case .pounds:
            return "Enter at least 70 lbs (about 32 kg)."
        }
    }

    /// Plus/minus buttons nudge by half a kilogram or a whole pound.
    static func stepAmount(for unit: WeightUnit) -> Double {
        unit == .kilograms ? 0.5 : 1
    }

    /// A nudge starts from the typed text, falls back to the stored value,
    /// never goes below zero, and keeps whole numbers integer-formatted.
    static func nudgeText(currentText: String, storedValue: Double?, amount: Double) -> String {
        let baseline = Double(currentText) ?? storedValue ?? 0
        let newValue = max(0, baseline + amount)

        if newValue == floor(newValue) {
            return String(format: "%.0f", newValue)
        }
        return String(format: "%.1f", newValue)
    }
}

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
                .accessibilityIdentifier("body_score_onboarding_manual_weight_continue_button")
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
        ManualWeightEntryPolicy.stepAmount(for: viewModel.weightUnit)
    }

    private func validateWeight(_ value: String) {
        weightError = ManualWeightEntryPolicy.validationError(for: value, unit: viewModel.weightUnit)
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
        let storedValue: Double?
        if viewModel.weightUnit == .kilograms {
            storedValue = viewModel.bodyScoreInput.weight.inKilograms
        } else {
            storedValue = viewModel.bodyScoreInput.weight.inPounds
        }

        let formatted = ManualWeightEntryPolicy.nudgeText(
            currentText: viewModel.manualWeightText,
            storedValue: storedValue,
            amount: amount
        )

        viewModel.updateManualWeightText(formatted)
        validateWeight(formatted)
    }
}

#Preview {
    BodyScoreManualWeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
