//
//  LiquidGlassCard.swift
//  LogYourBody
//
//  Liquid glass card component with backdrop blur and iOS native feel
//

import SwiftUI

/// Liquid glass card with backdrop blur, subtle highlights, and soft shadows
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let blurRadius: CGFloat
    let padding: CGFloat
    let showShadow: Bool
    let showHighlight: Bool

    init(
        cornerRadius: CGFloat = 16,
        blurRadius: CGFloat = 24,
        padding: CGFloat = 16,
        showShadow: Bool = true,
        showHighlight: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.blurRadius = blurRadius
        self.padding = padding
        self.showShadow = showShadow
        self.showHighlight = showHighlight
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base glass layer with backdrop blur + subtle white tint
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    // Subtle top inner highlight (enhanced for better gloss effect)
                    if showHighlight {
                        VStack {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 4)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }
                }
            )
            .shadow(
                color: showShadow ? Color.black.opacity(0.20) : .clear,
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

/// Compact glass card for smaller metrics (12pt radius)
struct CompactGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 8,
            blurRadius: 24,
            padding: 12,
            content: { content }
        )
    }
}

/// Hero glass card for main photo/avatar (16pt radius, uses regularMaterial)
struct HeroGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    // Use regularMaterial for viewport + subtle white tint
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    // Subtle top inner highlight (enhanced)
                    VStack {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 4)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            )
            .shadow(
                color: Color.black.opacity(0.25),
                radius: 16,
                x: 0,
                y: 8
            )
    }
}

/// Pill-style button with glass effect
struct GlassPillButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // HapticManager.shared.buttonTap()
            action()
        }, label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.black.opacity(0.2))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        })
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

/// Compact info chip with glass background
struct GlassChip: View {
    let icon: String?
    let text: String
    let color: Color

    init(icon: String? = nil, text: String, color: Color = .white) {
        self.icon = icon
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color.opacity(0.8))
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            color.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }
}

/// Frosted glass tab bar item
struct FrostedTabItem: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            // HapticManager.shared.buttonTap()
            action()
        }, label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#6EE7F0") : .white.opacity(0.55))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        })
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "#0B0D10")
            .ignoresSafeArea()

        VStack(spacing: 20) {
            LiquidGlassCard {
                Text("Liquid Glass Card")
                    .foregroundColor(.white)
            }

            CompactGlassCard {
                Text("Compact Glass")
                    .foregroundColor(.white)
            }

            GlassPillButton(icon: "plus.circle.fill", title: "Log Weight") {
                // print("Tapped")
            }

            GlassChip(icon: "flame.fill", text: "12.1% BF", color: .orange)
        }
        .padding()
    }
}
