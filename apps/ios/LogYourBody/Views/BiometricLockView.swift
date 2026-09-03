//
//  BiometricLockView.swift
//  LogYourBody
//
import SwiftUI

enum BiometricLockPolicy {
    /// A new authentication attempt only starts while no attempt is in flight.
    static func canStartAuthentication(isAuthenticating: Bool) -> Bool {
        !isAuthenticating
    }

    /// A successful scan unlocks; biometrics being unavailable on the device
    /// must not lock the user out. An explicit failure keeps the lock.
    static func shouldUnlock(after result: BiometricAuthenticationResult) -> Bool {
        switch result {
        case .success, .unavailable:
            return true
        case .failure:
            return false
        }
    }

    /// The retry/passcode fallback is offered only after a completed failed
    /// attempt — never before the first attempt or while one is in flight.
    static func showsFallbackOptions(hasAttemptedOnce: Bool, isAuthenticating: Bool) -> Bool {
        hasAttemptedOnce && !isAuthenticating
    }
}

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
        .worldClassScreen(.biometricLock)
    }

    @ViewBuilder
    private var lockContent: some View {
        if BiometricLockPolicy.showsFallbackOptions(
            hasAttemptedOnce: hasAttemptedOnce,
            isAuthenticating: isAuthenticating
        ) {
            BiometricAuthView(
                biometricType: biometricType,
                onAuthenticate: authenticate
            )
        } else {
            lockSurface
        }
    }

    private var lockSurface: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            VStack(spacing: 8) {
                Text("Unlock LogYourBody")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.jovieText)
                    .multilineTextAlignment(.center)

                Text("Confirm it’s you with \(biometricType.title) or your device passcode.")
                    .font(.body)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Image(systemName: biometricType.icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.jovieText)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
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

            Label("This lock blocks access until device-owner authentication succeeds.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Color.jovieTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: 440)
        .accessibilityElement(children: .contain)
    }

    private func authenticate() {
        guard BiometricLockPolicy.canStartAuthentication(isAuthenticating: isAuthenticating) else { return }
        isAuthenticating = true

        Task {
            let result = await biometricAuthenticator.authenticate(
                reason: "Unlock LogYourBody",
                cancelTitle: nil,
                fallbackTitle: "Use Passcode",
                timeout: 15,
                allowsDevicePasscode: true
            )

            await MainActor.run {
                isAuthenticating = false

                if BiometricLockPolicy.shouldUnlock(after: result) {
                    unlock()
                } else {
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
