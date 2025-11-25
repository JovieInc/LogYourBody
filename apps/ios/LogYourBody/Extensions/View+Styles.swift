//
// View+Styles.swift
// LogYourBody
//
//
import SwiftUI
import UIKit

struct ModernTextFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.appCard.opacity(0.5))
            )
            .foregroundColor(.appText)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isFocused ? Color.appPrimary : Color.appBorder,
                        lineWidth: 1
                    )
            )
            .focused($isFocused)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Linear-Inspired Primary Button Style
// NOTE: Temporarily using ViewModifier instead of ButtonStyle due to compilation issues
struct ModernPrimaryButtonModifier: ViewModifier {
    @Environment(\.isEnabled)
    var isEnabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Color.appPrimary.opacity(isEnabled ? 1 : 0.5)
            )
            .cornerRadius(6)
    }
}

// MARK: - Secondary Button Style
struct ModernSecondaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.appTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
            .background(
                Color.appCard.opacity(0.3)
            )
            .cornerRadius(6)
    }
}

// MARK: - Modern Card Style
struct ModernCardStyle: ViewModifier {
    var noPadding: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(noPadding ? 0 : 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCard.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.appBorder.opacity(0.3),
                                        Color.appBorder.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: Color.black.opacity(0.05),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

// MARK: - Glassmorphism Style
struct GlassmorphismStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appCard.opacity(0.2))
                    .background(
                        Color.appCard.opacity(0.1)
                            .blur(radius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
    }
}

// MARK: - Subtle Shadow
struct SubtleShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black.opacity(0.04),
                radius: 8,
                x: 0,
                y: 2
            )
            .shadow(
                color: Color.black.opacity(0.02),
                radius: 4,
                x: 0,
                y: 1
            )
    }
}

struct StandardErrorAlert: ViewModifier {
    let isPresented: Binding<Bool>
    let message: String

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: isPresented
        ) {
            Button("OK") {
                isPresented.wrappedValue = false
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func modernPrimaryButtonStyle() -> some View {
        self.modifier(ModernPrimaryButtonModifier())
    }

    func modernSecondaryButtonStyle() -> some View {
        self.modifier(ModernSecondaryButtonModifier())
    }

    func modernCardStyle(noPadding: Bool = false) -> some View {
        modifier(ModernCardStyle(noPadding: noPadding))
    }

    func modernTextFieldStyle() -> some View {
        modifier(ModernTextFieldModifier())
    }

    func glassmorphism() -> some View {
        modifier(GlassmorphismStyle())
    }

    func subtleShadow() -> some View {
        modifier(SubtleShadow())
    }

    func standardErrorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        modifier(StandardErrorAlert(isPresented: isPresented, message: message))
    }

    // Haptic feedback helper
    func withHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
}

// MARK: - Animation Extensions
extension Animation {
    static var smooth: Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
    }

    static var bouncy: Animation {
        .spring(response: 0.5, dampingFraction: 0.6)
    }

    static var gentle: Animation {
        .easeInOut(duration: 0.3)
    }
}
