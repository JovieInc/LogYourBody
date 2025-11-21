//
// SignUpView.swift
// LogYourBody
//
// Refactored using Atomic Design principles
//
import SwiftUI
import AuthenticationServices
import SafariServices

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
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
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
                        termsURL: URL(string: "https://logyourbody.com/terms")!,
                        privacyURL: URL(string: "https://logyourbody.com/privacy")!,
                        healthDisclaimerURL: URL(string: "https://logyourbody.com/health-disclaimer")!
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
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showTermsSheet) {
            SafariView(url: URL(string: "https://logyourbody.com/terms")!)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPrivacySheet) {
            SafariView(url: URL(string: "https://logyourbody.com/privacy")!)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showHealthDisclaimerSheet) {
            SafariView(url: URL(string: "https://logyourbody.com/health-disclaimer")!)
                .ignoresSafeArea()
        }
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
            errorMessage = "Authentication service is not ready. Please wait or tap retry."
            showError = true
            return
        }

        // Prevent multiple submissions
        guard !isLoading else { return }

        isLoading = true

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
                    // Check if it's a password strength error
                    if error.localizedDescription.contains("not strong enough") {
                        errorMessage = (
                            "Please choose a stronger password. Use at least 8 characters " +
                                "with a mix of uppercase, lowercase, and numbers or symbols."
                        )
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    showError = true
                }
            }
        }
    }
}

// MARK: - Safari View Wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = .white
        controller.preferredBarTintColor = UIColor(Color.appBackground)
        controller.dismissButtonStyle = .close

        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationView {
        SignUpView()
            .environmentObject(AuthManager.shared)
    }
}
