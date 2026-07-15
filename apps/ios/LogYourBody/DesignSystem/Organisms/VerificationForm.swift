//
// VerificationForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - VerificationForm Organism

struct VerificationForm: View {
    @Environment(\.theme) private var theme
    @Binding var verificationCode: String
    @Binding var isLoading: Bool

    let email: String
    let onVerify: () -> Void
    let onResend: () -> Void

    @State private var timeRemaining: Int = 60
    @State private var timerActive = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
            // Instructions
            VStack(spacing: 8) {
                Text("We sent a 6-digit code to")
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)

                Text(email)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)
                    .accessibilityIdentifier("email_verification_pending_email")
            }
            .multilineTextAlignment(.center)

            // OTP Field
            OTPField(
                code: $verificationCode,
                length: 6,
                accessibilityIdentifier: "email_verification_code_field",
                onComplete: { _ in
                    if !isLoading {
                        onVerify()
                    }
                }
            )

            // Verify Button
            BaseButton(
                "Verify",
                configuration: ButtonConfiguration(
                    style: .custom(background: .white, foreground: .black),
                    isLoading: isLoading,
                    isEnabled: verificationCode.count == 6,
                    fullWidth: true
                ),
                action: onVerify
            )
            .accessibilityIdentifier("email_verification_verify_button")

            // Resend Code
            VStack(spacing: 4) {
                if timerActive && timeRemaining > 0 {
                    Text("Resend code in \(timeRemaining)s")
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)
                        .accessibilityIdentifier("email_verification_resend_timer")
                } else {
                    HStack(spacing: 4) {
                        Text("Didn't receive code?")
                            .font(theme.typography.bodySmall)
                            .foregroundColor(theme.colors.textSecondary)

                        DSAuthLink(title: "Resend") {
                            onResend()
                            resetTimer()
                        }
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            if timerActive && timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timerActive = false
            }
        }
    }

    private func resetTimer() {
        timeRemaining = 60
        timerActive = true
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        AuthHeader(
            title: "Verify Email",
            subtitle: "Enter the 6-digit code"
        )
        .padding(.top, 40)

        VerificationForm(
            verificationCode: .constant(""),
            isLoading: .constant(false),
            email: "john@example.com",
            onVerify: {},
            onResend: {}
        )
        .padding(.horizontal, 24)

        Spacer()
    }
    .background(Color.appBackground)
}
