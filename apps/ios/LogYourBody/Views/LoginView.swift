//
// LoginView.swift
// LogYourBody
//

import SwiftUI

struct LoginView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var authManager: AuthManager
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 72)

                VStack(spacing: JovieTokens.sectionGap) {
                    AuthHeader(
                        title: "Your body, over time.",
                        subtitle: "Private body-composition tracking that takes seconds, not another habit to manage."
                    )
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: reduceMotion || hasAppeared ? 0 : 8)

                    VStack(spacing: JovieTokens.itemGap) {
                        appleSignInControl

                        Text("Apple is the fastest way back to your private history.")
                            .font(theme.typography.captionLarge)
                            .foregroundColor(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)

                        if let providerError = authManager.authProviderInitError {
                            VStack(spacing: JovieTokens.itemGap) {
                                Text(providerError)
                                    .font(theme.typography.captionLarge)
                                    .foregroundColor(theme.colors.error)
                                    .multilineTextAlignment(.center)

                                BaseButton(
                                    "Retry connection",
                                    configuration: ButtonConfiguration(
                                        style: .secondary,
                                        size: .small,
                                        fullWidth: true
                                    ),
                                    action: {
                                        Task { await authManager.retryAuthProviderInitialization() }
                                    }
                                )
                            }
                        }
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: reduceMotion || hasAppeared ? 0 : 8)
                }
                .frame(maxWidth: 430)
                .padding(.horizontal, JovieTokens.screenInset)

                Spacer(minLength: 72)

                VStack(spacing: 2) {
                    Text("By continuing, you agree to our")
                    HStack(spacing: 4) {
                        DSAuthLink(title: "Terms") { showTerms = true }
                        Text("and")
                        DSAuthLink(title: "Privacy Policy") { showPrivacy = true }
                    }
                }
                .font(theme.typography.captionSmall)
                .foregroundColor(theme.colors.textSecondary)
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.bottom, JovieTokens.compactInset)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showTerms) {
            NavigationStack { LegalDocumentView(documentType: .terms) }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { LegalDocumentView(documentType: .privacy) }
        }
        .onAppear {
            AppServicePorts.analyticsTracker.track(event: "login_view")
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: JovieTokens.subtleDuration)) {
                    hasAppeared = true
                }
            }
        }
        .worldClassScreen(.signIn)
    }

    private var appleSignInControl: some View {
        Button(action: authenticate) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.background)
                } else {
                    Image(systemName: "apple.logo")
                }

                Text(isLoading ? "Opening Apple…" : "Continue with Apple")
                    .font(theme.typography.labelLarge)
            }
            .foregroundColor(theme.colors.background)
            .frame(maxWidth: .infinity)
            .frame(minHeight: JovieTokens.controlHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .background(theme.colors.text, in: Capsule(style: .continuous))
        .jovieTouchTarget()
        .disabled(isLoading || !authManager.isAuthProviderReady)
        .accessibilityIdentifier("continueWithAppleButton")
        .accessibilityHint("Starts Sign in with Apple through Jovie Better Auth.")
    }

    private func authenticate() {
        guard !isLoading else { return }
        isLoading = true
        AppServicePorts.analyticsTracker.track(
            event: "login_attempt",
            properties: ["method": "apple"]
        )

        Task { @MainActor in
            defer { isLoading = false }
            do {
                try await authManager.signInWithApple()
            } catch AuthError.cancelled {
                return
            } catch {
                errorMessage = authManager.loginErrorMessage(for: error)
                showError = true
                AppServicePorts.analyticsTracker.track(
                    event: "login_failed",
                    properties: ["method": "apple"]
                )
            }
        }
    }
}

#Preview {
    NavigationStack { LoginView().environmentObject(AuthManager.shared) }
}
