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
                    
                    // Molecule: Auth Header
                    AuthHeader(
                        title: "Create Account",
                        subtitle: "Start tracking your fitness progress"
                    )
                    .padding(.top, 20)
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
                                await authManager.signInWithAppleOAuth()
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
    
    private func signUp() {
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
                        errorMessage = "Please choose a stronger password. Use at least 8 characters with a mix of uppercase, lowercase, and numbers or symbols."
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
