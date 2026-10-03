//
// Color+Theme.swift
// LogYourBody
//
import SwiftUI

public extension Color {
    // MARK: - Jovie canonical surface tokens
    //
    // These are intentionally neutral. Accent colour is reserved for metric meaning
    // and system state; primary actions use the high-contrast white-on-black pair.
    static let jovieCanvas = Color(hex: JoviePalette.canvasHex)
    static let jovieSurface = Color(hex: JoviePalette.cardHex)
    static let jovieSurfaceElevated = Color(hex: JoviePalette.elevatedHex)
    static let jovieHairline = Color(hex: JoviePalette.floatingHex)
    static let jovieText = Color(hex: "#F7F7F8")
    static let jovieTextSecondary = Color(hex: "#A7A7AD")
    static let jovieAction = Color.white
    static let jovieActionText = Color.black
    static let jovieMetricAccent = Color(hex: JoviePalette.ionHex)

    // MARK: - Core accents (palette-core-accents-v1)
    static let jovieIon = Color(hex: JoviePalette.ionHex)
    static let joviePulse = Color(hex: JoviePalette.pulseHex)
    static let jovieUltra = Color(hex: JoviePalette.ultraHex)
    static let jovieGold = Color(hex: JoviePalette.goldHex)
    static let jovieCream = Color(hex: JoviePalette.creamHex)

    // MARK: - Primary Colors
    static let linearPurple = Color(hex: JoviePalette.ultraHex)
    static let linearBlue = Color(hex: JoviePalette.ionHex)
    static let linearAccent = Color(hex: JoviePalette.ultraHex)

    // MARK: - Background Colors
    static let linearBg = Color(hex: JoviePalette.shellHex)  // Noir Ion shell
    static let linearCard = Color(hex: JoviePalette.cardHex)  // Noir Ion card
    static let linearBorder = Color(hex: JoviePalette.floatingHex)  // Subtle borders

    // MARK: - Text Colors
    static let linearText = Color(hex: "#F7F8F8")
    static let linearTextSecondary = Color(hex: "#9CA0A8")
    static let linearTextTertiary = Color(hex: "#8B8E95")  // Updated for WCAG AA compliance (4.5:1 contrast ratio)

    // MARK: - Liquid Glass Dark Mode (Apple Health-inspired)
    static let liquidBg = Color(hex: JoviePalette.canvasHex)  // Noir Ion canvas
    static let liquidTextPrimary = Color(hex: "#F5F5F7")  // Off-white for reduced eye strain
    static let liquidAccent = Color(hex: JoviePalette.ionHex)  // Ion blue accent

    // MARK: - Semantic Colors
    static let success = Color(hex: JoviePalette.ionHex)  // Success is blue, never green
    static let warning = Color(hex: JoviePalette.goldHex)
    static let error = Color(hex: JoviePalette.errorHex)

    // MARK: - Metric Detail Palette
    static let metricCanvas = Color(hex: JoviePalette.canvasHex)
    static let metricCard = Color(hex: JoviePalette.cardHex)
    static let metricSurface = Color(hex: JoviePalette.shellHex)
    static let metricAccent = Color(hex: JoviePalette.ionHex)  // Ion blue primary
    static let metricChartLine = Color(hex: JoviePalette.ionHex)  // Ion blue for primary series
    static let metricChartFillTop = Color(hex: "#3011AFFF")  // Ion blue @ ~18% opacity (ARGB)
    static let metricChartFillBottom = Color(hex: "#0011AFFF")  // Ion blue @ 0% opacity (ARGB)
    static let metricDeltaPositive = Color(hex: JoviePalette.ionHex)  // Positive is blue, never green
    static let metricDeltaNegative = Color(hex: JoviePalette.errorHex)
    static let metricTextPrimary = Color(hex: "#FFFFFF")
    static let metricTextSecondary = Color(hex: "#9AA0AA")
    static let metricTextTertiary = Color(hex: "#6E737C")
    static let metricCardBorder = Color(hex: JoviePalette.floatingHex)
    static let metricGridMajor = Color(hex: JoviePalette.floatingHex)
    static let metricGridMinor = Color(hex: JoviePalette.elevatedHex)
    static let metricAccentSteps = Color(hex: JoviePalette.goldHex)
    static let metricAccentWeight = Color(hex: JoviePalette.ultraHex)
    static let metricAccentBodyFat = Color(hex: JoviePalette.pulseHex)
    static let metricAccentFFMI = Color(hex: JoviePalette.ultraHex)
    static let metricAccentWaist = Color(hex: JoviePalette.ionHex)

    // MARK: - State Colors
    static let linearDisabled = Color(hex: JoviePalette.floatingHex)
    static let linearDisabledText = Color(hex: "#5A5A5A")

    // MARK: - App Specific (Aliases for consistency)
    static let appBackground = jovieCanvas
    static let appCard = jovieSurface
    static let appBorder = jovieHairline
    static let appPrimary = jovieMetricAccent
    static let appSurfaceSecondary = jovieSurface
    static let appText = jovieText
    static let appTextPrimary = jovieText
    static let appTextSecondary = jovieTextSecondary
    static let appTextTertiary = linearTextTertiary
    static let appDisabled = linearDisabled
    static let appDisabledText = linearDisabledText
    static let appSuccess = success
    static let appWarning = warning
    static let appError = error
    static let appInfo = appPrimary
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
