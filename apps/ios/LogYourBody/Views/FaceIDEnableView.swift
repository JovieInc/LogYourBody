//
//  FaceIDEnableView.swift
//  LogYourBody
//
//  Guided flow for enabling the device biometric lock from Settings.
//
import SwiftUI

struct FaceIDEnableView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onEnabled: () -> Void

    @State private var isAuthenticating = false
    @State private var showError = false
    @AccessibilityFocusState private var errorFocused: Bool

    private let biometricAuthenticator: BiometricAuthenticating = LocalBiometricAuthenticationAdapter.shared

    var body: some View {
        NavigationStack {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        content
                            .padding(.vertical, JovieTokens.sectionGap)
                    }
                } else {
                    content
                }
            }
            .padding(.horizontal, JovieTokens.screenInset)
            .background(Color.jovieCanvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionButtons
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.top, JovieTokens.itemGap)
                    .padding(.bottom, JovieTokens.itemGap)
                    .background(Color.jovieCanvas)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAuthenticating)
        .onDisappear {
            biometricAuthenticator.cancelCurrentAuthentication()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
            header
            privacyDetails

            if showError {
                errorCallout
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "faceid")
                .font(.system(.largeTitle, design: .default).weight(.medium))
                .foregroundStyle(Color.jovieText)
                .frame(width: 64, height: 64)
                .background(Color.jovieSurfaceElevated, in: Circle())
                .overlay(Circle().stroke(Color.jovieHairline, lineWidth: 1))
                .accessibilityHidden(true)

            Text("Enable Face ID")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.jovieText)

            Text("Use Face ID to add a privacy lock when you open LogYourBody.")
                .font(.body)
                .foregroundStyle(Color.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyDetails: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            FaceIDDetailRow(
                title: "Required when opening the app",
                icon: "lock.fill"
            )
            FaceIDDetailRow(
                title: "You can turn this off in Settings",
                icon: "gearshape.fill"
            )
        }
        .padding(JovieTokens.cardRadius - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlRadius,
            tint: .white,
            tintOpacity: 0.02,
            borderColor: .jovieHairline
        )
    }

    private var errorCallout: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Label("Couldn’t enable Face ID", systemImage: "exclamationmark.triangle.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.jovieText)

            Text("Try again, or come back to this from Settings later.")
                .font(.body)
                .foregroundStyle(Color.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again") {
                triggerFaceID(isRetry: true)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.jovieText)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .jovieTouchTarget()
            .accessibilityHint("Starts Face ID setup again")
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlRadius,
            tint: Color.orange,
            tintOpacity: 0.08,
            borderColor: Color.orange.opacity(0.55)
        )
        .accessibilityFocused($errorFocused)
    }

    private var actionButtons: some View {
        VStack(spacing: JovieTokens.itemGap) {
            BaseButton(
                "Turn on Face ID",
                configuration: ButtonConfiguration(
                    style: .custom(background: .jovieAction, foreground: .jovieActionText),
                    isLoading: isAuthenticating,
                    fullWidth: true,
                    icon: "faceid"
                )
            ) {
                triggerFaceID()
            }
            .disabled(isAuthenticating)
            .accessibilityHint("Requires Face ID before enabling the app lock")

            Button("Not now", action: dismiss.callAsFunction)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.jovieTextSecondary)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                .buttonStyle(.plain)
                .jovieTouchTarget()
                .accessibilityHint("Dismisses without enabling the lock")
        }
    }

    private func triggerFaceID(isRetry: Bool = false) {
        if !isRetry {
            showError = false
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true

        Task {
            let result = await biometricAuthenticator.authenticate(
                reason: "Enable Face ID for LogYourBody",
                cancelTitle: "Not now",
                fallbackTitle: "",
                timeout: nil
            )
            await finish(with: result == .success)
        }
    }

    @MainActor
    private func finish(with success: Bool) {
        isAuthenticating = false
        if success {
            showError = false
            HapticManager.shared.notification(type: .success)
            onEnabled()
            dismiss()
        } else {
            showError = true
            errorFocused = true
            HapticManager.shared.notification(type: .error)
        }
    }
}

private struct FaceIDDetailRow: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.body)
            .foregroundStyle(Color.jovieTextSecondary)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    FaceIDEnableView(onEnabled: {})
        .preferredColorScheme(.dark)
}
