import SwiftUI

struct BodyScoreAccountCreationView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel

    var body: some View {
        OnboardingPageTemplate(
            title: "Create your account",
            subtitle: "Use your email to create your account. We'll send a verification code to confirm it's you.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .account),
            content: {
                VStack(spacing: 20) {
                    OnboardingTextFieldRow(
                        title: "Email address",
                        placeholder: "you@domain.com",
                        text: Binding(
                            get: { viewModel.emailAddress },
                            set: { viewModel.emailAddress = $0 }
                        ),
                        keyboardType: .emailAddress
                    )
                }
            },
            footer: {
                Button(action: submit) {
                    if viewModel.isCreatingAccount {
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            if let status = viewModel.accountCreationStatusMessage {
                                Text(status)
                                    .font(OnboardingTypography.caption)
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                    } else {
                        Text("Create account")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueAccountCreation || viewModel.isCreatingAccount)
                .opacity(viewModel.canContinueAccountCreation ? 1 : 0.85)

                if let error = viewModel.accountCreationError {
                    Text(error)
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
        )
    }

    private func submit() {
        guard !viewModel.isCreatingAccount else { return }
        Task {
            await viewModel.createAccount(authManager: authManager)
        }
    }
}

#Preview {
    BodyScoreAccountCreationView(viewModel: OnboardingFlowViewModel())
        .environmentObject(AuthManager())
        .preferredColorScheme(.dark)
}
