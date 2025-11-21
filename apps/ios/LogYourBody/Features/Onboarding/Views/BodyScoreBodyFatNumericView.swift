import SwiftUI

struct BodyScoreBodyFatNumericView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var percentageFieldFocused: Bool
    @State private var bodyFatError: String?

    var body: some View {
        OnboardingPageTemplate(
            title: "Enter your body fat %",
            subtitle: "You can update this anytime.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .bodyFatNumeric),
            content: {
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Body fat %")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.appTextSecondary)

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
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.appCard.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(percentageFieldStrokeColor)
                        )

                        if let error = bodyFatError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(Color.red)
                        } else {
                            OnboardingCaptionText(
                                text: "Most people fall between 4–60% body fat.",
                                alignment: .leading
                            )
                        }
                    }

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Need help?")
                                .font(OnboardingTypography.headline)
                                .foregroundStyle(Color.appText)

                            Text("Not sure? Hop back and choose visual estimate. We’ll guide you through reference photos.")
                                .font(OnboardingTypography.body)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                }
            },
            footer: {
                Button("Continue") {
                    viewModel.persistBodyFatPercentageEntry()
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueBodyFatNumeric)
                .opacity(continueButtonOpacity)
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
    }
}

#Preview {
    BodyScoreBodyFatNumericView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}

private extension BodyScoreBodyFatNumericView {
    var continueButtonOpacity: Double {
        viewModel.canContinueBodyFatNumeric ? 1 : 0.4
    }

    var percentageFieldStrokeColor: Color {
        if percentageFieldFocused {
            return Color.appPrimary
        }
        return Color.appBorder.opacity(0.4)
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
