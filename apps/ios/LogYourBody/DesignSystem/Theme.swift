//
// Theme.swift
// LogYourBody
//
import SwiftUI
import UIKit

/// The single set of geometry and interaction values for production iPhone UI.
/// Keep these semantic values at the shared boundary instead of creating another
/// screen-specific spacing or control system.
enum JovieTokens {
    static let screenInset: CGFloat = 20
    static let compactInset: CGFloat = 16
    static let sectionGap: CGFloat = 24
    static let itemGap: CGFloat = 12
    static let minimumHitTarget: CGFloat = 44
    static let controlHeight: CGFloat = 48
    static let compactControlHeight: CGFloat = 44
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let subtleDuration: Double = 0.15
    static let cinematicDuration: Double = 0.42
}

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
    let screenPadding: CGFloat = JovieTokens.screenInset
    let cardPadding: CGFloat = 16
    let listItemSpacing: CGFloat = 12
}

// MARK: - Radius Theme

struct RadiusTheme {
    let none: CGFloat = 0
    let xs: CGFloat = 2
    let sm: CGFloat = 4
    let md: CGFloat = 12
    let lg: CGFloat = 16
    let xl: CGFloat = 48
    let xxl: CGFloat = 48
    let full: CGFloat = 48

    // Semantic radius
    let button: CGFloat = 48
    let card: CGFloat = JovieTokens.cardRadius
    let input: CGFloat = JovieTokens.controlRadius
    let chip: CGFloat = 48
    let avatar: CGFloat = 48
}

// MARK: - Animation Theme

struct AnimationTheme {
    let subtle: Animation = .easeInOut(duration: JovieTokens.subtleDuration)
    let cinematic: Animation = .easeInOut(duration: JovieTokens.cinematicDuration)

    let ultraFast: Animation = .easeInOut(duration: JovieTokens.subtleDuration)
    let fast: Animation = .easeInOut(duration: JovieTokens.subtleDuration)
    let medium: Animation = .easeInOut(duration: JovieTokens.cinematicDuration)
    let slow: Animation = .easeInOut(duration: JovieTokens.cinematicDuration)

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
        primary: .jovieAction,
        primaryMuted: .jovieAction.opacity(0.82),
        primarySubtle: .jovieAction.opacity(0.12),

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
        border: .jovieHairline,
        borderSecondary: Color(hex: "#1A1A1C"),
        borderFocused: .jovieAction.opacity(0.72),

        // States
        success: Color(hex: "#2F9E44"),
        warning: Color(hex: "#ff9800"),
        error: Color(hex: "#F3122D"),
        info: .jovieMetricAccent,

        // Interactive
        interactive: .jovieAction,
        interactiveHover: .jovieAction,
        interactivePressed: .jovieAction.opacity(0.82),
        interactiveDisabled: .jovieAction.opacity(0.35)
    )

    let materials = MaterialTheme()
    let typography = TypographyTheme(
        // Display
        displayLarge: .system(.largeTitle, design: .rounded).weight(.bold),
        displayMedium: .system(.title, design: .rounded).weight(.bold),
        displaySmall: .system(.title2, design: .rounded).weight(.semibold),

        // Headline
        headlineLarge: .system(.title2, design: .default).weight(.semibold),
        headlineMedium: .system(.title3, design: .default).weight(.semibold),
        headlineSmall: .system(.headline, design: .default).weight(.semibold),

        // Body
        bodyLarge: .system(.body, design: .default),
        bodyMedium: .system(.callout, design: .default),
        bodySmall: .system(.subheadline, design: .default),

        // Label
        labelLarge: .system(.body, design: .default).weight(.semibold),
        labelMedium: .system(.subheadline, design: .default).weight(.semibold),
        labelSmall: .system(.footnote, design: .default).weight(.semibold),

        // Caption
        captionLarge: .system(.footnote, design: .default),
        captionMedium: .system(.caption, design: .default),
        captionSmall: .system(.caption2, design: .default),

        // Special
        monospace: .system(.body, design: .monospaced),
        monospaceLarge: .system(.title3, design: .monospaced).weight(.semibold)
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

    /// Expands a visual control to Apple's minimum recommended hit target without
    /// forcing surrounding layout to use a one-off frame.
    func jovieTouchTarget() -> some View {
        contentShape(Rectangle())
            .frame(
                minWidth: JovieTokens.minimumHitTarget,
                minHeight: JovieTokens.minimumHitTarget
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
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

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
                Group {
                    if reduceTransparency {
                        shape.fill(theme.colors.surface)
                    } else {
                        shape
                            .fill(theme.materials.glassUltraThin)
                            .overlay(
                                shape
                                    .fill(tint.opacity(tintOpacity))
                            )
                    }
                }
            )
            .overlay(
                shape
                    .stroke(
                        (borderColor ?? theme.colors.border).opacity(borderOpacity),
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: theme.colors.background.opacity(shadowOpacity),
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
