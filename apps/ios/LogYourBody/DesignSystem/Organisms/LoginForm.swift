//
// LoginForm.swift
// LogYourBody
//
import SwiftUI

// MARK: - LoginForm Organism

struct LoginForm: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var isLoading: Bool
    
    let onLogin: () -> Void
    let onForgotPassword: () -> Void
    let onAppleSignIn: () -> Void
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Email Field
            AuthFormField(
                label: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never
            )
            .onSubmit {
                focusedField = .password
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                AuthFormField(
                    label: "Password",
                    text: $password,
                    isSecure: true,
                    textContentType: .password
                )
                .onSubmit {
                    if isFormValid {
                        onLogin()
                    }
                }
                
                // Forgot Password Link
                HStack {
                    Spacer()
                    DSAuthLink(title: "Forgot password?", action: onForgotPassword)
                }
            }
            
            // Login Button
            DSAuthButton(
                title: "Sign in",
                style: .primary,
                isLoading: isLoading,
                isEnabled: isFormValid,
                action: onLogin
            )
            
            // Divider
            DSAuthDivider()
            
            // Apple Sign In
            SocialLoginButton(
                provider: .apple,
                action: onAppleSignIn
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            AuthHeader(
                title: "LogYourBody",
                subtitle: "Track your fitness journey"
            )
            .padding(.top, 80)
            
            LoginForm(
                email: .constant(""),
                password: .constant(""),
                isLoading: .constant(false),
                onLogin: {},
                onForgotPassword: {},
                onAppleSignIn: {}
            )
            .padding(.horizontal, 24)
        }
    }
    .background(Color.appBackground)
}
