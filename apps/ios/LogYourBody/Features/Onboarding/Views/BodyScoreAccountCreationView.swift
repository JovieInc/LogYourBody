import SwiftUI

struct BodyScoreAccountCreationView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var passwordFieldFocused: Bool
    @State private var hasEditedPassword: Bool = false

    var body: some View {
        OnboardingPageTemplate(
            title: "Create your account",
            subtitle: "Set a password so you can sign in on any device.",
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.appTextSecondary)

                        SecureField("••••••••", text: Binding(
                            get: { viewModel.accountPassword },
                            set: { newValue in
                                viewModel.accountPassword = newValue
                                if !newValue.isEmpty {
                                    hasEditedPassword = true
                                }
                            }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($passwordFieldFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.appCard.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(passwordFieldFocused ? Color.appPrimary : Color.appBorder.opacity(0.6))
                        )

                        if hasEditedPassword {
                            Text("8+ chars, upper+lower, number/symbol.")
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passwordFieldFocused = true
            }
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
