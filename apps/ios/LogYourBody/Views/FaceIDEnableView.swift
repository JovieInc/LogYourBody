//
//  FaceIDEnableView.swift
//  LogYourBody
//
//  Guided flow for enabling Face ID lock from Settings.
//

import SwiftUI
import LocalAuthentication

struct FaceIDEnableView: View {
    @Environment(\.dismiss) private var dismiss

    let onEnabled: () -> Void

    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var currentContext: LAContext?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                header
                description
                Spacer(minLength: 0)
                if showError {
                    errorCallout
                }
                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAuthenticating)
        .onDisappear {
            currentContext?.invalidate()
            currentContext = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enable Face ID for LogYourBody")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.appText)
            Text("Use Face ID to lock the app and keep your data private.")
                .font(.system(size: 16))
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Required to open LogYourBody", systemImage: "lock.fill")
            Label("You can turn this off in Settings", systemImage: "gear")
        }
        .font(.system(size: 15))
        .foregroundColor(.appTextSecondary)
        .labelStyle(FaceIDBulletedLabelStyle())
    }

    private var errorCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 18))
                Text("Couldn't enable Face ID. Try again or use your passcode.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appText)
            }

            BaseButton(
                "Try Again",
                configuration: ButtonConfiguration(style: .secondary, fullWidth: true)
            ) {
                triggerFaceID(isRetry: true)
            }
            .accessibilityLabel("Try Face ID again to enable the lock")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 16) {
            BaseButton(
                "Turn On Face ID",
                configuration: ButtonConfiguration(fullWidth: true, isLoading: isAuthenticating)
            ) {
                guard !isAuthenticating else { return }
                triggerFaceID()
            }
            .accessibilityLabel("Turn on Face ID for LogYourBody")
            .disabled(isAuthenticating)

            Button {
                dismiss()
            } label: {
                Text("Not Now")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss without enabling Face ID")
        }
    }

    private func triggerFaceID(isRetry: Bool = false) {
        if !isRetry {
            showError = false
        }
        isAuthenticating = true

        let context = LAContext()
        context.localizedCancelTitle = "Not Now"
        context.localizedFallbackTitle = ""
        currentContext?.invalidate()
        currentContext = context

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            finish(with: false)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Enable Face ID for LogYourBody"
        ) { success, _ in
            Task { @MainActor in
                finish(with: success)
            }
        }
    }

    @MainActor
    private func finish(with success: Bool) {
        isAuthenticating = false
        currentContext = nil
        if success {
            showError = false
            HapticManager.shared.notification(type: .success)
            onEnabled()
            dismiss()
        } else {
            showError = true
            HapticManager.shared.notification(type: .error)
        }
    }
}

private struct FaceIDBulletedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appPrimary)
                .padding(.top, 2)
            configuration.title
        }
    }
}

#Preview {
    FaceIDEnableView(onEnabled: {})
        .preferredColorScheme(.dark)
}
