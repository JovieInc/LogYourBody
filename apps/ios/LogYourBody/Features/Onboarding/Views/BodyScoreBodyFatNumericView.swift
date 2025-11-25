import SwiftUI

struct BodyScoreBodyFatNumericView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var percentageFieldFocused: Bool
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

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHelp.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Not sure your %?")
                                    .font(OnboardingTypography.caption)
                            }
                            .foregroundStyle(Color.appPrimary)
                        }
                        .buttonStyle(.plain)

                        if showHelp {
                            Text("You can go back and choose visual estimate instead. We’ll guide you with reference photos.")
                                .font(OnboardingTypography.body)
                                .foregroundStyle(Color.appTextSecondary)
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
                        .font(.system(size: 18, weight: .semibold))
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
