//
// BiometricLockView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    @Binding var isUnlocked: Bool
    @State private var isAuthenticating = false
    @State private var hasAttemptedOnce = false
    @State private var authenticationTimer: Timer?
    
    private var biometricType: BiometricAuthView.BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .faceID // Default
        }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .faceID
        }
    }
    
    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()
            
            if hasAttemptedOnce && !isAuthenticating {
                // Organism: Biometric Auth View with manual trigger
                BiometricAuthView(
                    biometricType: biometricType,
                    onAuthenticate: authenticate,
                    onUsePassword: {
                        // Skip biometric and unlock
                        withAnimation(.easeOut(duration: 0.3)) {
                            isUnlocked = true
                        }
                    }
                )
            } else {
                // Simple loading state while authenticating
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: biometricType.icon)
                        .font(.system(size: 60))
                        .foregroundColor(.appTextTertiary)
                        .opacity(0.6)
                        .scaleEffect(isAuthenticating ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAuthenticating)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            // Small delay to let the UI settle before biometric prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                authenticate()
            }
        }
        .onDisappear {
            // Clean up timer if view disappears
            authenticationTimer?.invalidate()
        }
    }
    
    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        
        // Configure context for no fallback button
        context.localizedFallbackTitle = ""
        
        // Cancel any existing timer
        authenticationTimer?.invalidate()
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            isAuthenticating = true
            
            // Set a timeout to prevent indefinite blocking
            authenticationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                DispatchQueue.main.async {
                    if self.isAuthenticating {
                        // Timeout reached, cancel authentication
                        context.invalidate()
                        self.isAuthenticating = false
                        self.hasAttemptedOnce = true
                    }
                }
            }
            
            let reason = "Unlock LogYourBody"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    self.authenticationTimer?.invalidate()
                    self.isAuthenticating = false
                    
                    if success {
                        withAnimation(.easeOut(duration: 0.3)) {
                            self.isUnlocked = true
                        }
                    } else {
                        // Show the retry UI
                        self.hasAttemptedOnce = true
                    }
                }
            }
        } else {
            // No biometric available, just unlock
            isUnlocked = true
        }
    }
}

// MARK: - Preview

#Preview("Face ID") {
    BiometricLockView(isUnlocked: .constant(false))
}

#Preview("Unlocked") {
    BiometricLockView(isUnlocked: .constant(true))
}
