//
// LoginForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - LoginForm Organism

struct LoginForm: View {
    @Binding var email: String
    @Binding var isLoading: Bool

    let showsAppleSignIn: Bool
    let onLogin: () -> Void
    let onAppleSignIn: () -> Void

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private var isFormValid: Bool {
        isValidEmail
    }

    var body: some View {
        VStack(spacing: 20) {
            AuthFormField(
                label: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )
            .accessibilityIdentifier("login_email_field")
            .onSubmit {
                if isFormValid {
                    onLogin()
                }
            }

            Text("We'll email you a one-time code to sign you in.")
                .font(.system(size: 13))
                .foregroundColor(.appTextSecondary)

            // Login Button
            BaseButton(
                "Email me a code",
                configuration: ButtonConfiguration(
                    style: .custom(background: .appCard, foreground: .appText),
                    isLoading: isLoading,
                    isEnabled: isFormValid,
                    fullWidth: true,
                    cornerRadius: 9_999
                ),
                action: onLogin
            )
            .accessibilityIdentifier("login_email_code_button")

            if showsAppleSignIn {
                DSAuthDivider()

                SocialLoginButton(
                    provider: .apple,
                    action: onAppleSignIn
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            AuthHeader(
                title: "LogYourBody",
                subtitle: "Track your fitness journey"
            )
            .padding(.top, 80)

            LoginForm(
                email: .constant(""),
                isLoading: .constant(false),
                showsAppleSignIn: false,
                onLogin: {},
                onAppleSignIn: {}
            )
            .padding(.horizontal, 24)
        }
    }
    .background(Color.appBackground)
}
