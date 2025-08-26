//
// StandardButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - Button Style Enum

enum StandardButtonStyle {
    case primary
    case secondary
    case tertiary
    case destructive
    case ghost
}

// MARK: - Button Size Enum

enum ButtonSize {
    case small
    case medium
    case large
    
    var height: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 44
        case .large: return 56
        }
    }
    
    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 24
        }
    }
    
    var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }
}

// MARK: - Standard Button
// Legacy wrapper for BaseButton - use BaseButton directly for new code

struct StandardButton: View {
    let title: String
    let icon: String?
    let style: StandardButtonStyle
    let size: ButtonSize
    let isLoading: Bool
    let fullWidth: Bool
    let action: () -> Void
    
    init(
        _ title: String,
        icon: String? = nil,
        style: StandardButtonStyle = .primary,
        size: ButtonSize = .medium,
        isLoading: Bool = false,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }
    
    var body: some View {
        BaseButton(
            title,
            configuration: ButtonConfiguration(
                style: style.baseStyle,
                size: size.baseSize,
                isLoading: isLoading,
                fullWidth: fullWidth,
                icon: icon
            ),
            action: action
        )
    }
}

// MARK: - StandardButtonStyle Extension

extension StandardButtonStyle {
    var baseStyle: ButtonConfiguration.ButtonStyleVariant {
        switch self {
        case .primary: return .primary
        case .secondary: return .secondary
        case .tertiary: return .tertiary
        case .destructive: return .destructive
        case .ghost: return .ghost
        }
    }
}

// MARK: - ButtonSize Extension

extension ButtonSize {
    var baseSize: ButtonConfiguration.ButtonSizeVariant {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        }
    }
}

// MARK: - Icon Button
// Legacy wrapper for BaseIconButton - use BaseIconButton directly for new code

struct IconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    
    init(
        icon: String,
        size: CGFloat = 24,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.action = action
    }
    
    var body: some View {
        BaseIconButton(
            icon: icon,
            size: size,
            style: .outlined,
            action: action
        )
    }
}

// MARK: - Text Button
// Legacy wrapper for BaseButton - use BaseButton directly for new code

struct TextButton: View {
    let title: String
    let color: Color?
    let action: () -> Void
    
    init(
        _ title: String,
        color: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.action = action
    }
    
    var body: some View {
        BaseButton(
            title,
            configuration: ButtonConfiguration(
                style: .ghost,
                size: .custom(
                    height: 20,
                    padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0),
                    fontSize: 13
                ),
                hapticFeedback: .selection
            ),
            action: action
        )
    }
}

// MARK: - Floating Action Button
// Custom FAB implementation - consider using BaseIconButton for simpler cases

struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.appPrimary)
                        .shadow(
                            color: Color.appPrimary.opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

// MARK: - Preview

struct StandardButton_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            VStack(spacing: 20) {
                // Primary buttons
                StandardButton("Get Started", style: .primary) {}
                StandardButton("Continue", icon: "arrow.right", style: .primary) {}
                StandardButton("Loading", style: .primary, isLoading: true) {}
                
                // Secondary buttons
                StandardButton("Learn More", style: .secondary) {}
                StandardButton("Upload", icon: "arrow.up", style: .secondary) {}
                
                // Tertiary buttons
                StandardButton("Cancel", style: .tertiary) {}
                
                // Destructive button
                StandardButton("Delete", icon: "trash", style: .destructive) {}
                
                // Ghost button
                StandardButton("Skip", style: .ghost) {}
                
                // Size variations
                StandardButton("Small", size: .small) {}
                StandardButton("Medium", size: .medium) {}
                StandardButton("Large", size: .large) {}
                
                // Full width
                StandardButton("Full Width", style: .primary, fullWidth: true) {}
                
                // Icon buttons
                HStack {
                    IconButton(icon: "plus") {}
                    IconButton(icon: "camera") {}
                    IconButton(icon: "gear") {}
                }
                
                // Text button
                TextButton("Forgot password?") {}
                
                // Floating action button
                FloatingActionButton(icon: "plus") {}
            }
            .padding()
            .background(Color.black)
        }
    }
}
