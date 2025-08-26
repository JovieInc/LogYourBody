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
    
    var body: some View {
        ZStack {
            // Atom: Background
            Color.appBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Molecule: Auth Header
                    AuthHeader(
                        title: "LogYourBody",
                        subtitle: "Track your fitness journey"
                    )
                    .padding(.top, 80)
                    .padding(.bottom, 50)
                    
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
                                await authManager.signInWithAppleOAuth()
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
    }
    
    private func login() {
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
