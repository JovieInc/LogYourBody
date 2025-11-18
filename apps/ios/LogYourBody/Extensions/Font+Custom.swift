//
// Font+Custom.swift
// LogYourBody
//
import SwiftUI

extension Font {
    // MARK: - Display Fonts (SF Pro Rounded)
    static let appDisplay = Font.system(size: 48, weight: .bold, design: .rounded)
    static let appTitle = Font.system(size: 32, weight: .semibold, design: .rounded)
    static let appHeadline = Font.system(size: 24, weight: .semibold, design: .rounded)

    // MARK: - Body Fonts (SF Pro Rounded)
    static let appBodyLarge = Font.system(size: 18, weight: .regular, design: .rounded)
    static let appBody = Font.system(size: 16, weight: .regular, design: .rounded)
    static let appBodySmall = Font.system(size: 14, weight: .regular, design: .rounded)

    // MARK: - Caption Fonts (SF Pro Rounded)
    static let appCaption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let appCaptionBold = Font.system(size: 12, weight: .semibold, design: .rounded)

    // MARK: - Monospace (for numbers)
    static let appMonospace = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let appMonospaceLarge = Font.system(size: 24, weight: .semibold, design: .monospaced)
}
