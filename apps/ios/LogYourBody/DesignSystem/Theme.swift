//
// Theme.swift
// LogYourBody
//
import SwiftUI
import UIKit

protocol Theme {
    var colors: ColorTheme { get }
    var typography: TypographyTheme { get }
    var spacing: SpacingTheme { get }
    var radius: RadiusTheme { get }
    var animation: AnimationTheme { get }
    var haptics: HapticsTheme { get }
}

// MARK: - Color Theme

struct ColorTheme {
    // MARK: - Semantic Colors

    // Background
    let background: Color
    let backgroundSecondary: Color
    let backgroundTertiary: Color

    // Surface
    let surface: Color
    let surfaceSecondary: Color
    let surfaceTertiary: Color

    // Primary
    let primary: Color
    let primaryMuted: Color
    let primarySubtle: Color

    // Text
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let textQuaternary: Color

    // Borders
    let border: Color
    let borderSecondary: Color
    let borderFocused: Color

    // States
    let success: Color
    let warning: Color
    let error: Color
    let info: Color

    // Interactive
    let interactive: Color
    let interactiveHover: Color
    let interactivePressed: Color
    let interactiveDisabled: Color
}

// MARK: - Typography Theme

struct TypographyTheme {
    // Display
    let displayLarge: Font
    let displayMedium: Font
    let displaySmall: Font

    // Headline
    let headlineLarge: Font
    let headlineMedium: Font
    let headlineSmall: Font

    // Body
    let bodyLarge: Font
    let bodyMedium: Font
    let bodySmall: Font

    // Label
    let labelLarge: Font
    let labelMedium: Font
    let labelSmall: Font

    // Caption
    let captionLarge: Font
    let captionMedium: Font
    let captionSmall: Font

    // Special
    let monospace: Font
    let monospaceLarge: Font
}

// MARK: - Spacing Theme

struct SpacingTheme {
    let xxxs: CGFloat = 2
    let xxs: CGFloat = 4
    let xs: CGFloat = 8
    let sm: CGFloat = 12
    let md: CGFloat = 16
    let lg: CGFloat = 24
    let xl: CGFloat = 32
    let xxl: CGFloat = 48
    let xxxl: CGFloat = 64

    // Semantic spacing
    let elementSpacing: CGFloat = 8
    let sectionSpacing: CGFloat = 24
    let screenPadding: CGFloat = 16
    let cardPadding: CGFloat = 16
    let listItemSpacing: CGFloat = 12
}

// MARK: - Radius Theme

struct RadiusTheme {
    let none: CGFloat = 0
    let xs: CGFloat = 4
    let sm: CGFloat = 6
    let md: CGFloat = 8
    let lg: CGFloat = 12
    let xl: CGFloat = 16
    let xxl: CGFloat = 24
    let full: CGFloat = 9_999

    // Semantic radius
    let button: CGFloat = 12
    let card: CGFloat = 12
    let input: CGFloat = 8
    let chip: CGFloat = 16
    let avatar: CGFloat = 9_999
}

// MARK: - Animation Theme

struct AnimationTheme {
    let ultraFast: Animation = .easeInOut(duration: 0.1)
    let fast: Animation = .easeInOut(duration: 0.2)
    let medium: Animation = .easeInOut(duration: 0.3)
    let slow: Animation = .easeInOut(duration: 0.5)

    let spring: Animation = .spring(response: 0.4, dampingFraction: 0.8)
    let springBouncy: Animation = .spring(response: 0.5, dampingFraction: 0.7)
    let springSmooth: Animation = .spring(response: 0.6, dampingFraction: 0.9)

    let interactive: Animation = .spring(response: 0.3, dampingFraction: 0.8)
}

// MARK: - Haptics Theme

struct HapticsTheme {
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// MARK: - Default Theme Implementation

struct DefaultTheme: Theme {
    let colors = ColorTheme(
        // Background
        background: Color(hex: "#111111"),
        backgroundSecondary: Color(hex: "#0A0A0A"),
        backgroundTertiary: Color(hex: "#050505"),

        // Surface
        surface: Color(hex: "#1A1A1A"),
        surfaceSecondary: Color(hex: "#222222"),
        surfaceTertiary: Color(hex: "#2A2A2A"),

        // Primary
        primary: Color(hex: "#5B63D3"),
        primaryMuted: Color(hex: "#5B63D3").opacity(0.8),
        primarySubtle: Color(hex: "#5B63D3").opacity(0.3),

        // Text
        text: Color(hex: "#F7F8F8"),
        textSecondary: Color(hex: "#9CA0A8"),
        textTertiary: Color(hex: "#6E7178"),
        textQuaternary: Color(hex: "#4A4D52"),

        // Borders
        border: Color(hex: "#2A2A2A"),
        borderSecondary: Color(hex: "#222222"),
        borderFocused: Color(hex: "#5B63D3"),

        // States
        success: Color(hex: "#4CAF50"),
        warning: Color(hex: "#FF9800"),
        error: Color(hex: "#F44336"),
        info: Color(hex: "#2196F3"),

        // Interactive
        interactive: Color(hex: "#5B63D3"),
        interactiveHover: Color(hex: "#6B73E3"),
        interactivePressed: Color(hex: "#4B53C3"),
        interactiveDisabled: Color(hex: "#5B63D3").opacity(0.4)
    )

    let typography = TypographyTheme(
        // Display
        displayLarge: .system(size: 48, weight: .bold, design: .rounded),
        displayMedium: .system(size: 36, weight: .bold, design: .rounded),
        displaySmall: .system(size: 32, weight: .semibold, design: .rounded),

        // Headline
        headlineLarge: .system(size: 28, weight: .semibold, design: .rounded),
        headlineMedium: .system(size: 24, weight: .semibold, design: .rounded),
        headlineSmall: .system(size: 20, weight: .semibold, design: .rounded),

        // Body
        bodyLarge: .system(size: 18, weight: .regular, design: .rounded),
        bodyMedium: .system(size: 16, weight: .regular, design: .rounded),
        bodySmall: .system(size: 14, weight: .regular, design: .rounded),

        // Label
        labelLarge: .system(size: 16, weight: .medium, design: .rounded),
        labelMedium: .system(size: 14, weight: .medium, design: .rounded),
        labelSmall: .system(size: 12, weight: .medium, design: .rounded),

        // Caption
        captionLarge: .system(size: 13, weight: .regular, design: .rounded),
        captionMedium: .system(size: 12, weight: .regular, design: .rounded),
        captionSmall: .system(size: 11, weight: .regular, design: .rounded),

        // Special
        monospace: .system(size: 16, weight: .regular, design: .monospaced),
        monospaceLarge: .system(size: 24, weight: .semibold, design: .monospaced)
    )

    let spacing = SpacingTheme()
    let radius = RadiusTheme()
    let animation = AnimationTheme()
    let haptics = HapticsTheme()
}

// MARK: - Theme Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = DefaultTheme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}

// MARK: - Convenience Extensions

extension View {
    func cardStyle() -> some View {
        self.modifier(CardStyleModifier())
    }

    func surfaceStyle() -> some View {
        self.modifier(SurfaceStyleModifier())
    }
}

// MARK: - Common View Modifiers

struct CardStyleModifier: ViewModifier {
    @Environment(\.theme)
    var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.surface)
            .cornerRadius(theme.radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.card)
                    .stroke(theme.colors.border, lineWidth: 1)
            )
    }
}

struct SurfaceStyleModifier: ViewModifier {
    @Environment(\.theme)
    var theme

    func body(content: Content) -> some View {
        content
            .background(theme.colors.surface)
            .cornerRadius(theme.radius.md)
    }
}

// MARK: - Preview Helpers

struct ThemePreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .theme(DefaultTheme())
            .preferredColorScheme(.dark)
    }
}
