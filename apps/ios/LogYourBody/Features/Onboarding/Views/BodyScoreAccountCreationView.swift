import SwiftUI

struct BodyScoreAccountCreationView: View {
    @Environment(\.theme)
    private var theme

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @AccessibilityFocusState private var accountCreationErrorFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "Create your account",
            subtitle: "Use your email to create your account. We'll send a verification code to confirm it's you.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .account),
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
                        text: "We’ll send a verification code to this address.",
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
                        }
                        Text(viewModel.isCreatingAccount ? "Creating account…" : "Create account")
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueAccountCreation || viewModel.isCreatingAccount)
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
