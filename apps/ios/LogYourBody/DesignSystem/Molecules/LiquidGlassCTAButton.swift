//
// LiquidGlassCTAButton.swift
// LogYourBody
//
// Molecule: Liquid Glass CTA Button
// This is a specialized button molecule that uses BaseButton with liquid glass styling
//
import SwiftUI

struct LiquidGlassCTAButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let text: String
    let icon: String?
    let action: () -> Void
    let isEnabled: Bool

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
                    background: reduceTransparency
                        ? (isEnabled ? Color.white : Color.white.opacity(0.18))
                        : Color.clear,
                    foreground: isEnabled ? .black : .white.opacity(0.5)
                ),
                size: .medium,
                isEnabled: isEnabled,
                fullWidth: true,
                icon: icon,
                iconPosition: .trailing
            ),
            action: action
        )
        .background {
            if !reduceTransparency {
                Capsule(style: .continuous)
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.12))
            }
        }
        .overlay {
            if isEnabled && !reduceTransparency {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
        }
        .clipShape(Capsule(style: .continuous))
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
                    background: Color.clear,
                    foreground: Color.white.opacity(0.84)
                ),
                size: .small,
                isEnabled: true,
                fullWidth: false
            ),
            action: action
        )
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlHeight,
            tint: .white,
            tintOpacity: 0.04,
            borderColor: .white,
            borderOpacity: 0.18
        )
        .clipShape(Capsule(style: .continuous))
    }
}

// MARK: - View Modifier for existing buttons

struct LiquidGlassCTAModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(.headline, design: .default).weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: JovieTokens.controlHeight)
            .jovieTouchTarget()
            .foregroundColor(isEnabled ? .black : .white.opacity(0.5))
            .background(backgroundView)
            .overlay(overlayView)
            .clipShape(Capsule(style: .continuous))
            .animation(reduceMotion ? nil : theme.animation.fast, value: isEnabled)
    }

    @ViewBuilder private var backgroundView: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(isEnabled ? Color.white : Color.white.opacity(0.18))
        } else if isEnabled {
            Capsule(style: .continuous)
                .fill(Color.white)
        } else {
            Capsule(style: .continuous)
                .fill(theme.materials.glassUltraThin)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    @ViewBuilder private var overlayView: some View {
        if isEnabled && !reduceTransparency {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
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
