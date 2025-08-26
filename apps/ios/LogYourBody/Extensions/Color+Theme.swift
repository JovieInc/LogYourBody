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
    static let linearTextTertiary = Color(hex: "#6E7178")
    
    // MARK: - Semantic Colors
    static let success = Color(hex: "#4CAF50")
    static let warning = Color(hex: "#FF9800")
    static let error = Color(hex: "#F44336")
    
    // MARK: - App Specific
    static let appBackground = linearBg
    static let appCard = linearCard
    static let appBorder = linearBorder
    static let appPrimary = linearPurple
    static let appText = linearText
    static let appTextSecondary = linearTextSecondary
    static let appTextTertiary = linearTextTertiary
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
