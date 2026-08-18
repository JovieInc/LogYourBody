import SwiftUI

struct BodyScoreAccountCreationView: View {
    @Environment(\.theme)
    private var theme

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @AccessibilityFocusState private var accountCreationErrorFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "Create your account.",
            subtitle: "Continue with Apple to protect your Body Score and sync it across devices.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .account),
            screen: .verifyAccount,
            content: {
                VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                    OnboardingTextFieldRow(
                        title: "Email address",
                        placeholder: "you@domain.com",
                        text: Binding(
                            get: { viewModel.emailAddress },
                            set: { viewModel.emailAddress = $0 }
                        ),
                        keyboardType: .emailAddress
                    )

                    OnboardingCaptionText(
                        text: "Apple confirms your identity. You can review this email later in your profile.",
                        alignment: .leading
                    )

                    if let error = viewModel.accountCreationError {
                        Text(error)
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(theme.colors.error)
                            .accessibilityFocused($accountCreationErrorFocused)
                    }
                }
            },
            footer: {
                Button(action: submit) {
                    HStack(spacing: 8) {
                        if viewModel.isCreatingAccount {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.background))
                        } else {
                            Image(systemName: "apple.logo")
                        }
                        Text(viewModel.isCreatingAccount ? "Opening Apple…" : "Continue with Apple")
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueAccountCreation || viewModel.isCreatingAccount)
                .jovieTouchTarget()
                .accessibilityValue(viewModel.isCreatingAccount ? "Creating account" : "")
            }
        )
        .onChange(of: viewModel.accountCreationError) { _, error in
            accountCreationErrorFocused = error != nil
        }
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
