//
// Theme.swift
// LogYourBody
//
import SwiftUI
import UIKit

protocol Theme {
    var colors: ColorTheme { get }
    var materials: MaterialTheme { get }
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

    // Accents
    let accentViolet: Color
    let accentPink: Color
    let accentTeal: Color
    let accentOrange: Color
    let accentGreen: Color

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

// MARK: - Material Theme

struct MaterialTheme {
    let glassUltraThin: Material = .ultraThin
    let glassThin: Material = .thin
    let glassRegular: Material = .regular
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
    let xs: CGFloat = 2
    let sm: CGFloat = 4
    let md: CGFloat = 10
    let lg: CGFloat = 14
    let xl: CGFloat = 48
    let xxl: CGFloat = 48
    let full: CGFloat = 48

    // Semantic radius
    let button: CGFloat = 48
    let card: CGFloat = 14
    let input: CGFloat = 10
    let chip: CGFloat = 48
    let avatar: CGFloat = 48
}

// MARK: - Animation Theme

struct AnimationTheme {
    let subtle: Animation = .easeInOut(duration: 0.15)
    let cinematic: Animation = .easeInOut(duration: 0.42)

    let ultraFast: Animation = .easeInOut(duration: 0.15)
    let fast: Animation = .easeInOut(duration: 0.15)
    let medium: Animation = .easeInOut(duration: 0.42)
    let slow: Animation = .easeInOut(duration: 0.42)

    let spring: Animation = .spring(response: 0.42, dampingFraction: 0.8)
    let springBouncy: Animation = .spring(response: 0.42, dampingFraction: 0.7)
    let springSmooth: Animation = .spring(response: 0.42, dampingFraction: 0.9)

    let interactive: Animation = .easeInOut(duration: 0.15)
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
        background: Color(hex: "#000000"),
        backgroundSecondary: Color(hex: "#0b0b0b"),
        backgroundTertiary: Color(hex: "#111111"),

        // Surface
        surface: Color(hex: "#0b0b0b"),
        surfaceSecondary: Color(hex: "#141414"),
        surfaceTertiary: Color(hex: "#1f1f1f"),

        // Primary
        primary: Color(hex: "#2563FF"),
        primaryMuted: Color(hex: "#2563FF").opacity(0.8),
        primarySubtle: Color(hex: "#2563FF").opacity(0.3),

        // Accents
        accentViolet: Color(hex: "#8b1eff"),
        accentPink: Color(hex: "#d61a7f"),
        accentTeal: Color(hex: "#0f9b8e"),
        accentOrange: Color(hex: "#ff9800"),
        accentGreen: Color(hex: "#2f9e44"),

        // Text
        text: Color(hex: "#F7F8F8"),
        textSecondary: Color(hex: "#9CA0A8"),
        textTertiary: Color(hex: "#6E7178"),
        textQuaternary: Color(hex: "#4A4D52"),

        // Borders
        border: Color(hex: "#1f1f1f"),
        borderSecondary: Color(hex: "#141414"),
        borderFocused: Color(hex: "#2563FF"),

        // States
        success: Color(hex: "#2F9E44"),
        warning: Color(hex: "#ff9800"),
        error: Color(hex: "#F3122D"),
        info: Color(hex: "#2563FF"),

        // Interactive
        interactive: Color(hex: "#2563FF"),
        interactiveHover: Color(hex: "#3b74ff"),
        interactivePressed: Color(hex: "#1d4ed8"),
        interactiveDisabled: Color(hex: "#2563FF").opacity(0.4)
    )

    let materials = MaterialTheme()
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

    func systemBGlassSurface(
        cornerRadius: CGFloat? = nil,
        tint: Color = .white,
        tintOpacity: Double = 0.035,
        borderColor: Color? = nil,
        borderOpacity: Double = 1,
        borderWidth: CGFloat = 1,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            SystemBGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                tintOpacity: tintOpacity,
                borderColor: borderColor,
                borderOpacity: borderOpacity,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
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

private struct SystemBGlassSurfaceModifier: ViewModifier {
    @Environment(\.theme)
    private var theme

    let cornerRadius: CGFloat?
    let tint: Color
    let tintOpacity: Double
    let borderColor: Color?
    let borderOpacity: Double
    let borderWidth: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        let radius = cornerRadius ?? theme.radius.card
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .background(
                shape
                    .fill(theme.materials.glassUltraThin)
                    .overlay(
                        shape
                            .fill(tint.opacity(tintOpacity))
                    )
            )
            .overlay(
                shape
                    .stroke(
                        (borderColor ?? theme.colors.border).opacity(borderOpacity),
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
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
