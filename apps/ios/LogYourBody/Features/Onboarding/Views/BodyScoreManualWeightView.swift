import SwiftUI

struct BodyScoreManualWeightView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var weightFieldFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "What’s your most recent weight?",
            subtitle: "Helps us calculate lean mass and Body Score.",
            onBack: { viewModel.goBack() }
        ) {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Weight (lbs)")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)

                    TextField("175", text: Binding(
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
                            .stroke(weightFieldFocused ? Color.appPrimary : Color.appBorder.opacity(0.4))
                    )

                    OnboardingCaptionText(text: "Use your most accurate reading from the past week.", alignment: .leading)
                }

                OnboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why we ask")
                            .font(OnboardingTypography.headline)
                            .foregroundStyle(Color.appText)

                        Text("Weight plus body fat lets us calculate lean mass, FFMI, and your Body Score.")
                            .font(OnboardingTypography.body)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        } footer: {
            Button("Continue") {
                viewModel.persistManualWeightEntry()
                viewModel.goToNextStep()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(!viewModel.canContinueWeight)
            .opacity(viewModel.canContinueWeight ? 1 : 0.4)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.weightFieldFocused = true
            }
        }
    }
}

#Preview {
    BodyScoreManualWeightView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
