//
// SignUpForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - SignUpForm Organism

struct SignUpForm: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var isLoading: Bool
    @Binding var agreedToTerms: Bool
    @Binding var agreedToPrivacy: Bool
    @Binding var agreedToHealthDisclaimer: Bool

    let onSignUp: () -> Void
    let onAppleSignIn: () -> Void
    let onTapTerms: (() -> Void)?
    let onTapPrivacy: (() -> Void)?
    let onTapHealthDisclaimer: (() -> Void)?

    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    private var isFormValid: Bool {
        !email.isEmpty &&
            password.count >= 8 &&
            hasUpperAndLower &&
            hasNumberOrSymbol &&
            agreedToTerms &&
            agreedToPrivacy &&
            agreedToHealthDisclaimer
    }

    private var hasUpperAndLower: Bool {
        password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
            password.rangeOfCharacter(from: .lowercaseLetters) != nil
    }

    private var hasNumberOrSymbol: Bool {
        password.rangeOfCharacter(from: .decimalDigits) != nil ||
            password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Email Field
            AuthFormField(
                label: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )
            .onSubmit {
                focusedField = .password
            }

            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                AuthFormField(
                    label: "Password",
                    text: $password,
                    placeholder: "••••••••",
                    isSecure: true,
                    textContentType: .newPassword
                )
                .onSubmit {
                    if isFormValid {
                        onSignUp()
                    }
                }

                PasswordStrengthIndicator(password: password)
            }

            // Privacy Consent
            VStack(spacing: 16) {
                AuthConsentCheckbox(
                    isChecked: $agreedToTerms,
                    text: "LogYourBody's terms of service",
                    linkText: "Terms of Service",
                    onLinkTap: onTapTerms
                )

                AuthConsentCheckbox(
                    isChecked: $agreedToPrivacy,
                    text: "How we handle your data",
                    linkText: "Privacy Policy",
                    onLinkTap: onTapPrivacy
                )

                AuthConsentCheckbox(
                    isChecked: $agreedToHealthDisclaimer,
                    text: "Important health information",
                    linkText: "Health Disclaimer",
                    onLinkTap: onTapHealthDisclaimer
                )
            }

            // Sign Up Button
            BaseButton(
                "Create Account",
                configuration: ButtonConfiguration(
                    style: .custom(background: .white, foreground: .black),
                    isLoading: isLoading,
                    isEnabled: isFormValid,
                    fullWidth: true
                ),
                action: onSignUp
            )

            // Divider
            DSAuthDivider()

            // Apple Sign In
            SocialLoginButton(
                provider: .apple,
                action: onAppleSignIn
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            AuthHeader(
                title: "Create Account",
                subtitle: "Start tracking your fitness journey"
            )
            .padding(.top, 40)

            SignUpForm(
                email: .constant(""),
                password: .constant(""),
                isLoading: .constant(false),
                agreedToTerms: .constant(false),
                agreedToPrivacy: .constant(false),
                agreedToHealthDisclaimer: .constant(false),
                onSignUp: {},
                onAppleSignIn: {},
                onTapTerms: nil,
                onTapPrivacy: nil,
                onTapHealthDisclaimer: nil
            )
            .padding(.horizontal, 24)
        }
    }
    .background(Color.appBackground)
}
