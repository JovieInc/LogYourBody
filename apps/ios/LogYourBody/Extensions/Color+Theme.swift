//
// Color+Theme.swift
// LogYourBody
//
import SwiftUI

public extension Color {
    // MARK: - Primary Colors
    static let linearPurple = Color(hex: "#5B63D3")
    static let linearBlue = Color(hex: "#3B82F6")
    static let linearAccent = Color(hex: "#7C7CEA")

    // MARK: - Background Colors
    static let linearBg = Color(hex: "#111111")  // Premium near-black
    static let linearCard = Color(hex: "#1A1A1A")  // Slightly lighter for cards
    static let linearBorder = Color(hex: "#2A2A2A")  // Subtle borders

    // MARK: - Text Colors
    static let linearText = Color(hex: "#F7F8F8")
    static let linearTextSecondary = Color(hex: "#9CA0A8")
    static let linearTextTertiary = Color(hex: "#8B8E95")  // Updated for WCAG AA compliance (4.5:1 contrast ratio)

    // MARK: - Liquid Glass Dark Mode (Apple Health-inspired)
    static let liquidBg = Color(hex: "#000000")  // True black for OLED
    static let liquidTextPrimary = Color(hex: "#F5F5F7")  // Off-white for reduced eye strain
    static let liquidAccent = Color(hex: "#00AFFF")  // Splash-ring blue accent

    // MARK: - Semantic Colors
    static let success = Color(hex: "#4CAF50")
    static let warning = Color(hex: "#FF9800")
    static let error = Color(hex: "#F44336")

    // MARK: - State Colors
    static let linearDisabled = Color(hex: "#3A3A3A")
    static let linearDisabledText = Color(hex: "#5A5A5A")

    // MARK: - App Specific (Aliases for consistency)
    static let appBackground = linearBg
    static let appCard = linearCard
    static let appBorder = linearBorder
    static let appPrimary = linearPurple  // Note: linearPurple is the canonical name
    static let appText = linearText
    static let appTextSecondary = linearTextSecondary
    static let appTextTertiary = linearTextTertiary
    static let appDisabled = linearDisabled
    static let appDisabledText = linearDisabledText
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
