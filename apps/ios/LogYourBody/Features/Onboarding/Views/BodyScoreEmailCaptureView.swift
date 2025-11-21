import SwiftUI

struct BodyScoreEmailCaptureView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var emailFieldFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "Want to save your score?",
            subtitle: "Drop your email to sync progress across devices.",
            onBack: { viewModel.goBack() },
            content: {
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Email address")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.appTextSecondary)

                        TextField("you@domain.com", text: Binding(
                            get: { viewModel.emailAddress },
                            set: { viewModel.emailAddress = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)
                        .focused($emailFieldFocused)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.appCard.opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(emailFieldStrokeColor)
                        )

                        OnboardingCaptionText(
                            text: "We’ll send your Body Score and keep progress synced.",
                            alignment: .leading
                        )
                    }

                    OnboardingCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Privacy first")
                                .font(OnboardingTypography.headline)
                                .foregroundStyle(Color.appText)

                            Text("No spam. Unsubscribe anytime. Used only to save your Body Score journey.")
                                .font(OnboardingTypography.body)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                }
            },
            footer: {
                Button("Continue") {
                    viewModel.persistEmailCapture()
                    viewModel.goToNextStep()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueEmailCapture)
                .opacity(continueButtonOpacity)
            }
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.emailFieldFocused = true
            }
        }
    }
}

private extension BodyScoreEmailCaptureView {
    var continueButtonOpacity: Double {
        viewModel.canContinueEmailCapture ? 1 : 0.4
    }

    var emailFieldStrokeColor: Color {
        if emailFieldFocused {
            return Color.appPrimary
        }
        return Color.appBorder.opacity(0.4)
    }
}

#Preview {
    BodyScoreEmailCaptureView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
