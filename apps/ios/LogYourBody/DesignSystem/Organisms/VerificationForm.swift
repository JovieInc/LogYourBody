//
// VerificationForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - VerificationForm Organism

struct VerificationForm: View {
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
                Text("We've sent a verification code to")
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                
                Text(email)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appText)
            }
            .multilineTextAlignment(.center)
            
            // OTP Field
            OTPField(
                code: $verificationCode,
                length: 6,
                onComplete: { _ in
                    if !isLoading {
                        onVerify()
                    }
                }
            )
            
            // Verify Button
            DSAuthButton(
                title: "Verify",
                style: .primary,
                isLoading: isLoading,
                isEnabled: verificationCode.count == 6,
                action: onVerify
            )
            
            // Resend Code
            VStack(spacing: 4) {
                if timerActive && timeRemaining > 0 {
                    Text("Resend code in \(timeRemaining)s")
                        .font(.system(size: 14))
                        .foregroundColor(.appTextSecondary)
                } else {
                    HStack(spacing: 4) {
                        Text("Didn't receive code?")
                            .font(.system(size: 14))
                            .foregroundColor(.appTextSecondary)
                        
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
