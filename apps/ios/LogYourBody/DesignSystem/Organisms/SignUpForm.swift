//
// SignUpForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - SignUpForm Organism

struct SignUpForm: View {
    @Binding var email: String
    @Binding var isLoading: Bool
    @Binding var agreedToTerms: Bool
    @Binding var agreedToPrivacy: Bool
    @Binding var agreedToHealthDisclaimer: Bool

    let onSignUp: () -> Void
    let onAppleSignIn: () -> Void
    let onTapTerms: (() -> Void)?
    let onTapPrivacy: (() -> Void)?
    let onTapHealthDisclaimer: (() -> Void)?

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private var isFormValid: Bool {
        isValidEmail &&
            agreedToTerms &&
            agreedToPrivacy &&
            agreedToHealthDisclaimer
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
                if isFormValid {
                    onSignUp()
                }
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
