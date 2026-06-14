//
// SignUpView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @Environment(\.theme)
    private var theme

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var agreedToTerms = false
    @State private var agreedToPrivacy = false
    @State private var agreedToHealthDisclaimer = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @State private var showHealthDisclaimerSheet = false
    @State private var isRetrying = false
    @State private var showsAppleSignIn = AuthSurfacePolicy.defaultShowsAppleSignIn

    var body: some View {
        ZStack {
            background
            scrollContent
        }
        .navigationBarHidden(true)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showTermsSheet) {
            NavigationView {
                LegalDocumentView(documentType: .terms)
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationView {
                LegalDocumentView(documentType: .privacy)
            }
        }
        .sheet(isPresented: $showHealthDisclaimerSheet) {
            NavigationView {
                LegalDocumentView(documentType: .healthDisclosure)
            }
        }
        .onAppear {
            AnalyticsService.shared.track(event: "signup_view")
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
                navigationBar

                // Show Clerk initialization status banner
                if shouldShowClerkStatusBanner {
                    clerkStatusBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                // Molecule: Auth Header
                AuthHeader(
                    title: "Create Account",
                    subtitle: "Start tracking your fitness progress"
                )
                .padding(.top, shouldShowClerkStatusBanner ? 12 : 20)
                .padding(.bottom, 40)

                // Organism: Sign Up Form
                SignUpForm(
                    email: $email,
                    isLoading: $isLoading,
                    agreedToTerms: $agreedToTerms,
                    agreedToPrivacy: $agreedToPrivacy,
                    agreedToHealthDisclaimer: $agreedToHealthDisclaimer,
                    showsAppleSignIn: showsAppleSignIn,
                    onSignUp: signUp,
                    onAppleSignIn: {
                        Task {
                            await authManager.handleAppleSignIn()
                        }
                    },
                    onTapTerms: {
                        showTermsSheet = true
                    },
                    onTapPrivacy: {
                        showPrivacySheet = true
                    },
                    onTapHealthDisclaimer: {
                        showHealthDisclaimerSheet = true
                    }
                )
                .padding(.horizontal, 24)

                // Sign In Link
                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.textSecondary)

                    Button("Sign in") {
                        dismiss()
                    }
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.primary)
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var shouldShowClerkStatusBanner: Bool {
        !authManager.isClerkLoaded || authManager.clerkInitError != nil
    }

    private func refreshAppleSignInVisibility() {
        showsAppleSignIn = AuthSurfacePolicy.shouldShowAppleSignIn()
    }

    private var navigationBar: some View {
        // Navigation Bar
        HStack {
            Button(action: { dismiss() }, label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.colors.text)
                    .frame(width: 44, height: 44)
                    .systemBGlassSurface(
                        cornerRadius: theme.radius.full,
                        tint: theme.colors.text,
                        tintOpacity: 0.045,
                        borderColor: theme.colors.border,
                        borderOpacity: 0.55
                    )
            })

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // Clerk status banner (same as LoginView)
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

    private func signUp() {
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
            event: "signup_attempt",
            properties: [
                "method": "email_otp"
            ]
        )

        Task { @MainActor in
            do {
                try await authManager.signUp(email: email, password: "", name: "")
                // Reset loading state on success
                isLoading = false
            } catch {
                isLoading = false
                // If we need verification, the AuthManager will handle navigation
                if authManager.needsEmailVerification {
                    // Email verification screen will show automatically
                } else {
                    errorMessage = authManager.signUpErrorMessage(for: error)
                    showError = true
                }

                AnalyticsService.shared.track(
                    event: "signup_failed",
                    properties: [
                        "method": "email_otp"
                    ]
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        SignUpView()
            .environmentObject(AuthManager.shared)
    }
}
