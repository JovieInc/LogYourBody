//
// LoginView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isRetrying = false
    @State private var showPreAuthOnboarding = false
    @State private var navigateToSignUp = false

    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Show Clerk initialization status banner
                    if !authManager.isClerkLoaded {
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
                        subtitle: "Track your fitness journey"
                    )
                    .padding(.top, authManager.isClerkLoaded ? 80 : 20)
                    .padding(.bottom, 24)

                    preAuthOnboardingCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 26)

                    // Organism: Login Form
                    LoginForm(
                        email: $email,
                        password: $password,
                        isLoading: $isLoading,
                        onLogin: login,
                        onForgotPassword: {
                            // Navigate to forgot password
                        },
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
                            .font(.system(size: 15))
                            .foregroundColor(.appTextSecondary)

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
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showPreAuthOnboarding) {
            PreAuthBodyScoreOnboardingContainer {
                navigateToSignUp = true
            }
        }
    }

    private var sessionStatusBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.appTextSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Session expired")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appText)

                Text("Your session ended. Please sign in again to continue.")
                    .font(.system(size: 13))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.black.opacity(0.25))
        .cornerRadius(12)
    }

    // Clerk status banner
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

    private func login() {
        // Check if Clerk is ready
        guard authManager.isClerkLoaded else {
            errorMessage = "Authentication service is not ready. Please wait or tap retry."
            showError = true
            return
        }

        // Prevent multiple submissions
        guard !isLoading else { return }

        isLoading = true

        Task { @MainActor in
            do {
                try await AuthManager.shared.login(
                    email: self.email,
                    password: self.password
                )
                // Reset loading state on success
                isLoading = false
            } catch {
                errorMessage = "Invalid email or password. Please try again."
                showError = true
                isLoading = false
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
