//
// DSAuthButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSAuthButton Atom
// Legacy wrapper for BaseButton - use BaseButton directly for new code

struct DSAuthButton: View {
    enum Style {
        case primary
        case secondary
        case social
        
        var baseStyle: ButtonConfiguration.ButtonStyleVariant {
            switch self {
            case .primary:
                return .custom(background: .white, foreground: .black)
            case .secondary:
                return .custom(background: Color(.systemGray6), foreground: .appText)
            case .social:
                return .social
            }
        }
    }
    
    let title: String
    let style: Style
    let icon: String?
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    init(
        title: String,
        style: Style = .primary,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        BaseButton(
            title,
            configuration: ButtonConfiguration(
                style: style.baseStyle,
                size: .medium,
                isLoading: isLoading,
                isEnabled: isEnabled,
                fullWidth: true,
                icon: icon
            ),
            action: action
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DSAuthButton(
            title: "Sign In",
            style: .primary,
            action: {}
        )
        
        DSAuthButton(
            title: "Sign In",
            style: .primary,
            isLoading: true,
            action: {}
        )
        
        DSAuthButton(
            title: "Continue with Apple",
            style: .social,
            icon: "apple.logo",
            action: {}
        )
        
        DSAuthButton(
            title: "Sign Up",
            style: .secondary,
            action: {}
        )
        
        DSAuthButton(
            title: "Disabled",
            style: .primary,
            isEnabled: false,
            action: {}
        )
    }
    .padding()
    .background(Color.appBackground)
}
