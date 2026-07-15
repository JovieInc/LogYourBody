import SwiftUI

struct BodyScoreBodyFatNumericView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var percentageFieldFocused: Bool
    @AccessibilityFocusState private var bodyFatErrorFocused: Bool
    @State private var bodyFatError: String?
    @State private var showHelp = false

    var body: some View {
        OnboardingPageTemplate(
            title: "Enter your body fat %",
            subtitle: "You can update this anytime.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatNumeric),
            content: {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Body fat %")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(theme.colors.textSecondary)

                        TextField("14.5", text: Binding(
                            get: { viewModel.bodyFatPercentageText },
                            set: { viewModel.bodyFatPercentageText = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .focused($percentageFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            percentageFieldFocused = false
                        }
                        .onChange(of: viewModel.bodyFatPercentageText) { _, newValue in
                            validateBodyFat(newValue)
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: JovieTokens.controlHeight)
                        .systemBGlassSurface(
                            cornerRadius: 20,
                            tint: percentageFieldFocused ? theme.colors.primary : theme.colors.text,
                            tintOpacity: percentageFieldFocused ? 0.07 : 0.03,
                            borderColor: percentageFieldStrokeColor,
                            borderOpacity: 1
                        )
                        .accessibilityLabel("Body fat percentage")
                        .accessibilityHint("Enter a value between 4 and 60 percent.")

                        if let error = bodyFatError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(theme.colors.error)
                                .accessibilityFocused($bodyFatErrorFocused)
                        } else {
                            OnboardingCaptionText(
                                text: "Most people fall between 4–60% body fat.",
                                alignment: .leading
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            toggleHelp()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(.footnote, design: .default).weight(.semibold))
                                Text("Not sure your %?")
                                    .font(OnboardingTypography.caption)
                            }
                            .foregroundStyle(theme.colors.primary)
                        }
                        .buttonStyle(.plain)
                        .jovieTouchTarget()
                        .accessibilityValue(showHelp ? "Expanded" : "Collapsed")

                        if showHelp {
                            Text("You can go back and choose visual estimate instead. We’ll guide you with reference photos.")
                                .font(OnboardingTypography.body)
                                .foregroundStyle(theme.colors.textSecondary)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            },
            footer: {
                Button {
                    viewModel.persistBodyFatPercentageEntry()
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBodyFatNumeric)
            }
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.percentageFieldFocused = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        percentageFieldFocused = false
                    }
                }
            }
        }
        .onChange(of: bodyFatError) { _, error in
            bodyFatErrorFocused = error != nil
        }
    }
}

#Preview {
    BodyScoreBodyFatNumericView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}

private extension BodyScoreBodyFatNumericView {
    var percentageFieldStrokeColor: Color {
        if percentageFieldFocused {
            return theme.colors.primary
        }
        return theme.colors.border.opacity(0.65)
    }

    private func toggleHelp() {
        if reduceMotion {
            showHelp.toggle()
        } else {
            withAnimation(theme.animation.fast) {
                showHelp.toggle()
            }
        }
    }

    private func validateBodyFat(_ value: String) {
        guard !value.isEmpty else {
            bodyFatError = nil
            return
        }

        guard let numeric = Double(value) else {
            bodyFatError = "Enter a valid percentage."
            return
        }

        if numeric < 4 || numeric > 60 {
            bodyFatError = "Enter a body fat between 4–60%."
        } else {
            bodyFatError = nil
        }
    }
}
