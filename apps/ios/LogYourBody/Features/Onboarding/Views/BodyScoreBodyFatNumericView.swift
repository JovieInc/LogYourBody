import SwiftUI

struct BodyScoreBodyFatNumericView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var percentageFieldFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "Enter your body fat %",
            subtitle: "You can update this anytime.",
            onBack: { viewModel.goBack() }
        ) {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.appCard.opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(percentageFieldFocused ? Color.appPrimary : Color.appBorder.opacity(0.4))
                    )

                    OnboardingCaptionText(text: "Most smart scales, DEXA, or caliper tests provide this number.", alignment: .leading)
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
        } footer: {
            Button("Continue") {
                viewModel.persistBodyFatPercentageEntry()
                viewModel.goToNextStep()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(!viewModel.canContinueBodyFatNumeric)
            .opacity(viewModel.canContinueBodyFatNumeric ? 1 : 0.4)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.percentageFieldFocused = true
            }
        }
    }
}

#Preview {
    BodyScoreBodyFatNumericView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
