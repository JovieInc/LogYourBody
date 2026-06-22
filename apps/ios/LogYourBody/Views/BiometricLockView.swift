//
// BiometricLockView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI

struct BiometricLockView: View {
    @Binding var isUnlocked: Bool
    @State private var isAuthenticating = false
    @State private var hasAttemptedOnce = false
    @State private var authenticationTimer: Timer?
    @State private var haloRotation: Double = 0
    @State private var haloPulse = false
    private let biometricAuthenticator: BiometricAuthenticating = LocalBiometricAuthenticationAdapter.shared

    private var biometricType: BiometricAuthView.BiometricType {
        biometricAuthenticator.availableBiometryType().authViewType
    }

    private var biometricScanningText: String {
        switch biometricType {
        case .faceID:
            return "Scanning your face…"
        case .touchID:
            return "Reading your fingerprint…"
        }
    }

    private var biometricReadyText: String {
        "\(biometricType.title) is ready"
    }

    private var biometricPromptText: String {
        switch biometricType {
        case .faceID:
            return "Look at your iPhone to continue"
        case .touchID:
            return "Touch the sensor to continue"
        }
    }

    private var biometricProtectionText: String {
        "Your data stays encrypted on this device. \(biometricType.title) adds another lock on LogYourBody."
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
            biometricAuthenticator.cancelCurrentAuthentication()
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
                Text(isAuthenticating ? biometricScanningText : biometricReadyText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.linearText)

                Text(biometricPromptText)
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

            Text(biometricProtectionText)
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
                    Text("Protected by \(biometricType.title)")
                        .font(.system(size: 14))
                        .foregroundColor(.linearTextSecondary)
                }
                .padding(.bottom, 8)
            }
        )
    }

    private func authenticate() {
        authenticationTimer?.invalidate()
        isAuthenticating = true

        Task {
            let result = await biometricAuthenticator.authenticate(
                reason: "Unlock LogYourBody",
                cancelTitle: nil,
                fallbackTitle: "",
                timeout: 5
            )

            await MainActor.run {
                authenticationTimer?.invalidate()
                isAuthenticating = false

                switch result {
                case .success, .unavailable:
                    withAnimation(.easeOut(duration: 0.3)) {
                        isUnlocked = true
                    }
                case .failure:
                    hasAttemptedOnce = true
                }
            }
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
