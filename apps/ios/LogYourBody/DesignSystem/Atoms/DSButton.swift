//
// DSButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - Design System Button Atom
// Legacy wrapper for BaseButton - use BaseButton directly for new code

struct DSButton: View {
    let title: String
    let style: ButtonStyle
    let size: ButtonSize
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case tertiary
        
        var baseStyle: ButtonConfiguration.ButtonStyleVariant {
            switch self {
            case .primary: return .primary
            case .secondary: return .secondary
            case .tertiary: return .tertiary
            }
        }
    }
    
    enum ButtonSize {
        case small
        case medium
        case large
        
        var baseSize: ButtonConfiguration.ButtonSizeVariant {
            switch self {
            case .small: return .small
            case .medium: return .medium
            case .large: return .large
            }
        }
    }
    
    var body: some View {
        BaseButton(
            title,
            configuration: ButtonConfiguration(
                style: style.baseStyle,
                size: size.baseSize
            ),
            action: action
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Primary buttons
        DSButton(title: "Primary Small", style: .primary, size: .small, action: {})
        DSButton(title: "Primary Medium", style: .primary, size: .medium, action: {})
        DSButton(title: "Primary Large", style: .primary, size: .large, action: {})
        
        // Secondary buttons
        DSButton(title: "Secondary Medium", style: .secondary, size: .medium, action: {})
        
        // Tertiary buttons
        DSButton(title: "Tertiary Medium", style: .tertiary, size: .medium, action: {})
    }
    .padding()
    .background(Color.appBackground)
}
