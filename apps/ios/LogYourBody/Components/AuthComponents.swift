//
// AuthComponents.swift
// LogYourBody
//
import SwiftUI

struct AuthBackground: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.95),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Auth Title
struct AuthTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Auth Text Field
struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 17))
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Auth Button
struct AuthButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(title: String, isLoading: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? Color.white : Color.white.opacity(0.3))
            .foregroundColor(isEnabled ? .black : .white.opacity(0.6))
            .cornerRadius(28)
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Auth Social Button
struct AuthSocialButton: View {
    let provider: SocialProvider
    let action: () -> Void

    enum SocialProvider {
        case apple
        case google

        var title: String {
            switch self {
            case .apple: return "Continue with Apple"
            case .google: return "Continue with Google"
            }
        }

        var icon: String {
            switch self {
            case .apple: return "apple.logo"
            case .google: return "globe"
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.system(size: 20))

                Text(provider.title)
                    .font(.system(size: 17, weight: .medium))

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
        }
    }
}

// MARK: - Auth Link
struct AuthLink: View {
    let text: String
    let linkText: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .foregroundColor(.white.opacity(0.6))

            Button(action: action) {
                Text(linkText)
                    .foregroundColor(.white)
                    .underline()
            }
        }
        .font(.system(size: 15))
    }
}

// MARK: - Auth Divider
struct AuthDivider: View {
    let text: String = "or"

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Auth Container
struct AuthContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(spacing: 32) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 60)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Auth Error Alert
struct AuthErrorAlert: ViewModifier {
    @Binding var showError: Bool
    let errorMessage: String

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
    }
}

extension View {
    func authErrorAlert(showError: Binding<Bool>, message: String) -> some View {
        modifier(AuthErrorAlert(showError: showError, errorMessage: message))
    }
}

// MARK: - Auth Loading Overlay
struct AuthLoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)

            if isLoading {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)

                    Text(message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.8))
                )
            }
        }
    }
}

extension View {
    func authLoadingOverlay(isLoading: Bool, message: String = "Loading...") -> some View {
        modifier(AuthLoadingOverlay(isLoading: isLoading, message: message))
    }
}
