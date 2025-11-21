import SwiftUI

struct BodyScoreAccountCreationView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var passwordFieldFocused: Bool

    var body: some View {
        OnboardingPageTemplate(
            title: "Create your account",
            subtitle: "Use your email and a secure password to save progress.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .account),
            content: {
                VStack(spacing: 24) {
                    summaryCard
                    secureField
                    passwordRules
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        Text("Create account")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueAccountCreation || viewModel.isCreatingAccount)
                .opacity(viewModel.canContinueAccountCreation ? 1 : 0.4)

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

    private var summaryCard: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Email")
                    .font(OnboardingTypography.caption)
                    .foregroundStyle(Color.appTextSecondary)

                Text(viewModel.emailAddress)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.appText)

                Text("You can change this later in settings.")
                    .font(OnboardingTypography.body)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Password")
                .font(OnboardingTypography.caption)
                .foregroundStyle(Color.appTextSecondary)

            SecureField("••••••••", text: Binding(
                get: { viewModel.accountPassword },
                set: { viewModel.accountPassword = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($passwordFieldFocused)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.appCard.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(passwordFieldFocused ? Color.appPrimary : Color.appBorder.opacity(0.4))
            )
        }
    }

    private var passwordRules: some View {
        VStack(alignment: .leading, spacing: 8) {
            ruleRow(
                text: "At least 8 characters",
                satisfied: viewModel.accountPasswordHasMinLength
            )
            ruleRow(
                text: "Mix of uppercase & lowercase",
                satisfied: viewModel.accountPasswordHasUpperAndLowercase
            )
            ruleRow(
                text: "At least one number or symbol",
                satisfied: viewModel.accountPasswordHasNumberOrSymbol
            )
        }
    }

    private func ruleRow(text: String, satisfied: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(satisfied ? Color.appPrimary : Color.appBorder)
            Text(text)
                .font(OnboardingTypography.caption)
                .foregroundStyle(satisfied ? Color.appText : Color.appTextSecondary)
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
