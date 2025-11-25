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
    @State private var haloRotation: Double = 0
    @State private var haloPulse = false

    private var biometricType: BiometricAuthView.BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .faceID // Default to Face ID for unknown state
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
            Color.liquidBg
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.linearPurple.opacity(0.35),
                    Color.linearBlue.opacity(0.25),
                    Color.liquidBg
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.liquidAccent.opacity(0.35), Color.clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 30)
                .offset(x: -80, y: -120)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.appPrimary.opacity(0.25), Color.clear]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 30)
                .offset(x: 120, y: 180)

            if hasAttemptedOnce && !isAuthenticating {
                BiometricAuthView(
                    biometricType: biometricType,
                    onAuthenticate: authenticate,
                    onUsePassword: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isUnlocked = true
                        }
                    }
                )
                .padding(.horizontal, 16)
            } else {
                lockSurface
                    .padding(.horizontal, 24)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                haloPulse.toggle()
            }

            withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                haloRotation = 360
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                authenticate()
            }
        }
        .onDisappear {
            authenticationTimer?.invalidate()
        }
    }

    private var lockSurface: some View {
        VStack(spacing: 32) {
            VStack(spacing: 6) {
                Text("Secure Access")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.linearTextSecondary)

                Text("Unlock with \(biometricType.title)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.linearText)
            }

            ZStack {
                Circle()
                    .stroke(Color.appPrimary.opacity(0.15), lineWidth: 18)
                    .frame(width: 190, height: 190)

                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [Color.appPrimary, Color.linearBlue, Color.appPrimary]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(haloRotation))
                    .frame(width: 190, height: 190)

                Circle()
                    .fill(
                        .ultraThinMaterial
                    )
                    .frame(width: 140, height: 140)
                    .overlay(
                        Image(systemName: biometricType.icon)
                            .font(.system(size: 54))
                            .foregroundColor(.linearText)
                    )
                    .scaleEffect(haloPulse ? 1.02 : 0.98)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: haloPulse)
            }

            VStack(spacing: 6) {
                Text(isAuthenticating ? "Scanning your face…" : "Face ID is ready")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.linearText)

                Text("Look at your iPhone to continue")
                    .font(.system(size: 15))
                    .foregroundColor(.linearTextSecondary)
            }

            HStack {
                Capsule()
                    .fill(Color.appPrimary.opacity(0.2))
                    .frame(width: 50, height: 6)

                Capsule()
                    .fill(Color.appPrimary.opacity(0.5))
                    .frame(width: 140, height: 6)

                Capsule()
                    .fill(Color.appPrimary.opacity(0.2))
                    .frame(width: 50, height: 6)
            }
            .opacity(isAuthenticating ? 1 : 0.4)

            Text("Your data stays encrypted on this device. Face ID adds another lock on LogYourBody.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(.linearTextTertiary)
                .padding(.horizontal, 10)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Color.liquidBg.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.appPrimary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.appPrimary.opacity(0.25), radius: 30, x: 0, y: 20)
        )
        .overlay(
            VStack {
                Spacer()

                HStack {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.linearTextSecondary)
                    Text("Protected by Face ID")
                        .font(.system(size: 14))
                        .foregroundColor(.linearTextSecondary)
                }
                .padding(.bottom, 8)
            }
        )
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
