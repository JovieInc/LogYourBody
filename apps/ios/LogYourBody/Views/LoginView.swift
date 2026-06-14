//
// LoginView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(\.theme)
    private var theme

    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isRetrying = false
    @State private var navigateToSignUp = false
    @State private var showsAppleSignIn = AuthSurfacePolicy.defaultShowsAppleSignIn

    var body: some View {
        ZStack {
            background
            scrollContent
        }
        .navigationBarHidden(true)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .onAppear {
            AnalyticsService.shared.track(event: "login_view")
            refreshAppleSignInVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
            refreshAppleSignInVisibility()
        }
    }

    private var background: some View {
        // Atom: Background
        theme.colors.background
            .ignoresSafeArea()
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Show Clerk initialization status banner
                if shouldShowClerkStatusBanner {
                    clerkStatusBanner
                        .padding(.top, 20)
                        .padding(.horizontal, 24)
                }

                if authManager.lastExitReason == .sessionExpired {
                    sessionStatusBanner
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                }

                // Molecule: Auth Header
                AuthHeader(
                    title: "LogYourBody",
                    subtitle: "Log your body in under 10 seconds."
                )
                .padding(.top, shouldShowClerkStatusBanner ? 20 : 80)
                .padding(.bottom, 24)

                // Organism: Login Form
                LoginForm(
                    email: $email,
                    isLoading: $isLoading,
                    showsAppleSignIn: showsAppleSignIn,
                    onLogin: login,
                    onAppleSignIn: {
                        Task {
                            await authManager.handleAppleSignIn()
                        }
                    }
                )
                .padding(.horizontal, 24)

                // Molecule: Sign Up Link
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)

                    DSAuthNavigationLink(
                        title: "Sign up",
                        destination: SignUpView()
                    )
                }
                .padding(.top, 20)

                NavigationLink(
                    destination: SignUpView(),
                    isActive: $navigateToSignUp
                ) {
                    EmptyView()
                }
                .hidden()

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var shouldShowClerkStatusBanner: Bool {
        !authManager.isClerkLoaded || authManager.clerkInitError != nil
    }

    private func refreshAppleSignInVisibility() {
        let gateEnabled = AnalyticsService.shared.isFeatureEnabled(
            flagKey: Constants.appleSignInEnabledFlagKey
        )
        showsAppleSignIn = AuthSurfacePolicy.shouldShowAppleSignIn(gateEnabled: gateEnabled)
    }

    private var sessionStatusBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(theme.colors.warning)

            VStack(alignment: .leading, spacing: 4) {
                Text("Session expired")
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.text)

                Text("Your session ended. Please sign in again to continue.")
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .systemBGlassSurface(
            cornerRadius: theme.radius.lg,
            tint: theme.colors.warning,
            tintOpacity: 0.06,
            borderColor: theme.colors.warning,
            borderOpacity: 0.24
        )
    }

    // Clerk status banner
    private var clerkStatusBanner: some View {
        VStack(spacing: 12) {
            if let error = authManager.clerkInitError {
                // Error state
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(theme.colors.error)
                        Text("Connection Error")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.text)
                        Spacer()
                    }

                    Text(error)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: retryClerkInit) {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.background))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRetrying ? "Retrying..." : "Retry Connection")
                                .font(theme.typography.labelMedium)
                        }
                        .foregroundColor(theme.colors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.colors.text)
                        )
                    }
                    .disabled(isRetrying)
                }
                .padding(16)
                .systemBGlassSurface(
                    cornerRadius: theme.radius.lg,
                    tint: theme.colors.error,
                    tintOpacity: 0.08,
                    borderColor: theme.colors.error,
                    borderOpacity: 0.32
                )
            } else {
                // Loading state
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.info))
                        Text("Connecting to authentication service...")
                            .font(theme.typography.captionLarge)
                            .foregroundColor(theme.colors.textSecondary)
                        Spacer()
                    }
                }
                .padding(16)
                .systemBGlassSurface(
                    cornerRadius: theme.radius.lg,
                    tint: theme.colors.info,
                    tintOpacity: 0.08,
                    borderColor: theme.colors.info,
                    borderOpacity: 0.3
                )
            }
        }
    }

    private func retryClerkInit() {
        isRetrying = true
        Task {
            await authManager.retryClerkInitialization()
            isRetrying = false
        }
    }

    private func login() {
        // Check if Clerk is ready
        guard authManager.isClerkLoaded else {
            errorMessage = authManager.authServiceNotReadyMessage
            showError = true
            return
        }

        // Prevent multiple submissions
        guard !isLoading else { return }

        isLoading = true

        AnalyticsService.shared.track(
            event: "login_attempt",
            properties: [
                "method": "email_otp"
            ]
        )

        Task { @MainActor in
            do {
                try await AuthManager.shared.login(
                    email: self.email,
                    password: ""
                )
                // Reset loading state on success
                isLoading = false
            } catch {
                errorMessage = authManager.loginErrorMessage(for: error)
                showError = true
                isLoading = false

                AnalyticsService.shared.track(
                    event: "login_failed",
                    properties: [
                        "method": "email_otp"
                    ]
                )
            }
        }
    }
}


#Preview {
    NavigationView {
        LoginView()
            .environmentObject(AuthManager.shared)
    }
}
