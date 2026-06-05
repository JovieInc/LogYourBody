//
// SocialLoginButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - SocialLoginButton Molecule

struct SocialLoginButton: View {
    enum Provider {
        case apple
        case google
        case facebook

        var title: String {
            switch self {
            case .apple:
                return "Continue with Apple"
            case .google:
                return "Continue with Google"
            case .facebook:
                return "Continue with Facebook"
            }
        }

        var icon: String {
            switch self {
            case .apple:
                return "apple.logo"
            case .google:
                return "globe"
            case .facebook:
                return "f.circle.fill"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .apple:
                return Color.metricSurface
            case .google:
                return Color.metricSurface
            case .facebook:
                return Color(red: 0.258, green: 0.406, blue: 0.697)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .apple, .google:
                return .appText
            case .facebook:
                return .white
            }
        }

        var borderColor: Color {
            switch self {
            case .apple, .google:
                return Color.white.opacity(0.14)
            case .facebook:
                return Color.clear
            }
        }

        var borderWidth: CGFloat {
            switch self {
            case .apple, .google:
                return 1
            case .facebook:
                return 0
            }
        }
    }

    let provider: Provider
    let isLoading: Bool
    let action: () -> Void

    init(
        provider: Provider,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.provider = provider
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        BaseButton(
            provider.title,
            configuration: ButtonConfiguration(
                style: .custom(
                    background: provider.backgroundColor,
                    foreground: provider.foregroundColor
                ),
                size: .medium,
                isLoading: isLoading,
                fullWidth: true,
                icon: provider.icon,
                cornerRadius: 9_999
            ),
            action: action
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9_999, style: .continuous)
                .stroke(provider.borderColor, lineWidth: provider.borderWidth)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        SocialLoginButton(provider: .apple) {
            // Action
        }

        SocialLoginButton(provider: .google) {
            // Action
        }

        SocialLoginButton(provider: .facebook) {
            // Action
        }

        SocialLoginButton(provider: .apple, isLoading: true) {
            // Action
        }
    }
    .padding()
    .background(Color.appBackground)
}
