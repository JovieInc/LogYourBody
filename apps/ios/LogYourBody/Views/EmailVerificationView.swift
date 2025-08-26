//
// EmailVerificationView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import Foundation

struct EmailVerificationView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header Icon
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.linearPurple, .linearBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 80)
                        .padding(.bottom, 12)
                    
                    // Molecule: Auth Header
                    AuthHeader(
                        title: "Verify Your Email",
                        subtitle: "We've sent a verification code to your email address"
                    )
                    .padding(.bottom, 50)
                    
                    // Organism: Verification Form
                    VerificationForm(
                        verificationCode: $verificationCode,
                        isLoading: $isLoading,
                        email: "", // TODO: Add public getter for pending email in AuthManager
                        onVerify: verifyCode,
                        onResend: resendCode
                    )
                    .padding(.horizontal, 24)
                    
                    // Success/Error Messages
                    if let successMessage = successMessage {
                        Text(successMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                            .padding(.top, 12)
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.top, 12)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarHidden(true)
    }
    
    private func verifyCode() {
        guard !isLoading, verificationCode.count == 6 else { return }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task { @MainActor in
            do {
                try await authManager.verifyEmail(code: verificationCode)
                successMessage = "Email verified successfully!"
                // Navigation will be handled by AuthManager
            } catch {
                errorMessage = "Invalid verification code. Please try again."
                isLoading = false
            }
        }
    }
    
    private func resendCode() {
        errorMessage = nil
        successMessage = nil
        
        Task { @MainActor in
            do {
                try await authManager.resendVerificationEmail()
                successMessage = "A new verification code has been sent to your email."
            } catch {
                errorMessage = "Failed to resend code. Please try again."
            }
        }
    }
}

// MARK: - Preview

#Preview {
    EmailVerificationView()
        .environmentObject(AuthManager.shared)
}
