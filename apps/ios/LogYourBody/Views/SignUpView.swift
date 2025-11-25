//
// SignUpView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
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
        }
    }

    private var background: some View {
        // Atom: Background
        Color.appBackground
            .ignoresSafeArea()
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                navigationBar

                // Show Clerk initialization status banner
                if !authManager.isClerkLoaded {
                    clerkStatusBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                // Molecule: Auth Header
                AuthHeader(
                    title: "Create Account",
                    subtitle: "Start tracking your fitness progress"
                )
                .padding(.top, authManager.isClerkLoaded ? 20 : 12)
                .padding(.bottom, 40)

                // Organism: Sign Up Form
                SignUpForm(
                    email: $email,
                    password: $password,
                    isLoading: $isLoading,
                    agreedToTerms: $agreedToTerms,
                    agreedToPrivacy: $agreedToPrivacy,
                    agreedToHealthDisclaimer: $agreedToHealthDisclaimer,
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
                        .font(.system(size: 15))
                        .foregroundColor(.appTextSecondary)

                    Button("Sign in") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appPrimary)
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var navigationBar: some View {
        // Navigation Bar
        HStack {
            Button(action: { dismiss() }, label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20))
                    .foregroundColor(.appText)
                    .frame(width: 44, height: 44)
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
                            .foregroundColor(.red)
                        Text("Connection Error")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.appText)
                        Spacer()
                    }

                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: retryClerkInit) {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRetrying ? "Retrying..." : "Retry Connection")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isRetrying)
                }
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            } else {
                // Loading state
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Connecting to authentication service...")
                            .font(.system(size: 14))
                            .foregroundColor(.appTextSecondary)
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
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
                "method": "password"
            ]
        )

        Task { @MainActor in
            do {
                try await authManager.signUp(email: email, password: password, name: "")
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
                        "method": "password"
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
