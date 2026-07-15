//
//  BiometricLockView.swift
//  LogYourBody
//
import SwiftUI

struct BiometricLockView: View {
    @Binding var isUnlocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isAuthenticating = false
    @State private var hasAttemptedOnce = false

    private let biometricAuthenticator: BiometricAuthenticating = LocalBiometricAuthenticationAdapter.shared

    private var biometricType: BiometricAuthView.BiometricType {
        biometricAuthenticator.availableBiometryType().authViewType
    }

    private var biometricScanningText: String {
        switch biometricType {
        case .faceID: "Scanning your face…"
        case .touchID: "Reading your fingerprint…"
        }
    }

    private var biometricPromptText: String {
        switch biometricType {
        case .faceID: "Look at your iPhone to continue."
        case .touchID: "Touch the sensor to continue."
        }
    }

    var body: some View {
        ZStack {
            Color.jovieCanvas.ignoresSafeArea()

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        lockContent
                            .padding(.vertical, JovieTokens.sectionGap)
                    }
                } else {
                    lockContent
                }
            }
            .padding(.horizontal, JovieTokens.screenInset)
        }
        .onAppear(perform: authenticate)
        .onDisappear {
            biometricAuthenticator.cancelCurrentAuthentication()
        }
    }

    @ViewBuilder
    private var lockContent: some View {
        if hasAttemptedOnce && !isAuthenticating {
            BiometricAuthView(
                biometricType: biometricType,
                onAuthenticate: authenticate,
                onUsePassword: unlock
            )
        } else {
            lockSurface
        }
    }

    private var lockSurface: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            VStack(spacing: 8) {
                Text("Secure access")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.jovieTextSecondary)

                Text("Unlock with \(biometricType.title)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.jovieText)
                    .multilineTextAlignment(.center)
            }

            Image(systemName: biometricType.icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.jovieText)
                .frame(width: 120, height: 120)
                .background(Color.jovieSurfaceElevated, in: Circle())
                .overlay(Circle().stroke(Color.jovieHairline, lineWidth: 1))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(isAuthenticating ? biometricScanningText : "\(biometricType.title) is ready")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.jovieText)

                Text(biometricPromptText)
                    .font(.body)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Label("Your data stays encrypted on this device.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Color.jovieTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
        .padding(JovieTokens.sectionGap)
        .frame(maxWidth: 440)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.cardRadius,
            tint: .white,
            tintOpacity: 0.025,
            borderColor: .jovieHairline
        )
        .accessibilityElement(children: .contain)
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true

        Task {
            let result = await biometricAuthenticator.authenticate(
                reason: "Unlock LogYourBody",
                cancelTitle: nil,
                fallbackTitle: "",
                timeout: 5
            )

            await MainActor.run {
                isAuthenticating = false

                switch result {
                case .success, .unavailable:
                    unlock()
                case .failure:
                    hasAttemptedOnce = true
                }
            }
        }
    }

    private func unlock() {
        if reduceMotion {
            isUnlocked = true
        } else {
            withAnimation(.easeOut(duration: JovieTokens.subtleDuration)) {
                isUnlocked = true
            }
        }
    }
}

#Preview("Face ID") {
    BiometricLockView(isUnlocked: .constant(false))
        .preferredColorScheme(.dark)
}

#Preview("Unlocked") {
    BiometricLockView(isUnlocked: .constant(true))
        .preferredColorScheme(.dark)
}
