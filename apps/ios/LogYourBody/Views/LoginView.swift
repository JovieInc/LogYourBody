//
// LoginView.swift
// LogYourBody
//

import SwiftUI

struct LoginView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var authManager: AuthManager
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AuthHeader(
                    title: "LogYourBody",
                    subtitle: "Your body, clearly tracked."
                )

                VStack(spacing: 14) {
                    Button(action: authenticate) {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(theme.colors.background)
                            } else {
                                Image(systemName: "message.fill")
                            }

                            Text(isLoading ? "Opening secure sign in…" : "Continue with phone")
                                .font(theme.typography.labelLarge)
                        }
                        .foregroundColor(theme.colors.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule(style: .continuous).fill(theme.colors.text))
                    }
                    .disabled(isLoading || !authManager.isAuthProviderReady)
                    .accessibilityIdentifier("continueWithPhoneButton")

                    Text("We’ll text you a one-time code. No password needed.")
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)

                    if let providerError = authManager.authProviderInitError {
                        VStack(spacing: 10) {
                            Text(providerError)
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.error)
                                .multilineTextAlignment(.center)

                            Button("Retry") {
                                Task { await authManager.retryAuthProviderInitialization() }
                            }
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.text)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)

                Spacer()

                HStack(spacing: 5) {
                    Text("By continuing, you agree to our")
                    Button("Terms") { showTerms = true }
                    Text("and")
                    Button("Privacy Policy") { showPrivacy = true }
                }
                .font(theme.typography.captionSmall)
                .foregroundColor(theme.colors.textSecondary)
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showTerms) {
            NavigationStack { LegalDocumentView(documentType: .terms) }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { LegalDocumentView(documentType: .privacy) }
        }
        .onAppear {
            AppServicePorts.analyticsTracker.track(event: "login_view")
        }
    }

    private func authenticate() {
        guard !isLoading else { return }
        isLoading = true
        AppServicePorts.analyticsTracker.track(
            event: "login_attempt",
            properties: ["method": "sms_otp"]
        )

        Task { @MainActor in
            defer { isLoading = false }
            do {
                try await authManager.signInWithPhone()
            } catch AuthError.cancelled {
                return
            } catch {
                errorMessage = authManager.loginErrorMessage(for: error)
                showError = true
                AppServicePorts.analyticsTracker.track(
                    event: "login_failed",
                    properties: ["method": "sms_otp"]
                )
            }
        }
    }
}

#Preview {
    NavigationStack { LoginView().environmentObject(AuthManager.shared) }
}
