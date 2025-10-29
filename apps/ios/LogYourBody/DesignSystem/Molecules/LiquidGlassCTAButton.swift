//
// LiquidGlassCTAButton.swift
// LogYourBody
//
// Molecule: Liquid Glass CTA Button
// This is a specialized button molecule that uses BaseButton with liquid glass styling
//
import SwiftUI

struct LiquidGlassCTAButton: View {
    let text: String
    let icon: String?
    let action: () -> Void
    let isEnabled: Bool
    
    // Convenience initializers
    init(
        text: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true
    ) {
        self.text = text
        self.icon = nil
        self.action = action
        self.isEnabled = isEnabled
    }
    
    init(
        text: String,
        icon: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true
    ) {
        self.text = text
        self.icon = icon
        self.action = action
        self.isEnabled = isEnabled
    }
    
    var body: some View {
        BaseButton(
            text,
            configuration: ButtonConfiguration(
                style: .custom(
                    background: liquidGlassBackground,
                    foreground: isEnabled ? .black : .white.opacity(0.5)
                ),
                size: .large,
                isEnabled: isEnabled,
                fullWidth: true,
                icon: icon,
                iconPosition: .trailing
            ),
            action: action
        )
        .overlay(liquidGlassOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    
    // MARK: - Styling Components
    
    private var liquidGlassBackground: Color {
        if #available(iOS 18.0, *) {
            if isEnabled {
                return Color.white
            } else {
                return Color.white.opacity(0.1)
            }
        } else {
            return isEnabled ? Color.white : Color.white.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private var liquidGlassOverlay: some View {
        if isEnabled {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Secondary CTA Style

struct LiquidGlassSecondaryCTAButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        BaseButton(
            text,
            configuration: ButtonConfiguration(
                style: .custom(
                    background: Color.white.opacity(0.1),
                    foreground: Color.white.opacity(0.7)
                ),
                size: .custom(
                    height: 44,
                    padding: EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24),
                    fontSize: 15
                ),
                isEnabled: true,
                fullWidth: false
            ),
            action: action
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - View Modifier for existing buttons

struct LiquidGlassCTAModifier: ViewModifier {
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundColor(isEnabled ? .black : .white.opacity(0.5))
            .background(backgroundView)
            .overlay(overlayView)
            .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    
    @ViewBuilder private var backgroundView: some View {
        if #available(iOS 18.0, *) {
            if isEnabled {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Material.ultraThin)
                            .opacity(0.1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Material.ultraThin)
                            .opacity(0.2)
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    isEnabled ? Color.white : Color.white.opacity(0.1)
                )
        }
    }
    
    @ViewBuilder private var overlayView: some View {
        if isEnabled {
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Convenience Extensions

extension View {
    /// Apply the unified CTA button style to any button
    func liquidGlassCTAStyle(isEnabled: Bool = true) -> some View {
        self.modifier(LiquidGlassCTAModifier(isEnabled: isEnabled))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VStack(spacing: 24) {
            // Primary enabled
            LiquidGlassCTAButton(
                text: "Get Started",
                icon: "arrow.right",
                action: {},
                isEnabled: true
            )
            
            // Primary disabled
            LiquidGlassCTAButton(
                text: "Continue",
                icon: "arrow.right",
                action: {},
                isEnabled: false
            )
            
            // Secondary
            LiquidGlassSecondaryCTAButton(
                text: "Skip",
                action: {}
            )
            
            // Using modifier on existing button
            Button(
                action: {},
                label: {
                    Text("Custom Button")
                }
            )
            .liquidGlassCTAStyle(isEnabled: true)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
