//
// HomeV2Tokens.swift
// LogYourBody
//
import SwiftUI

/// Jovie design-system values for the v2 surfaces, mirrored from the
/// LogYourBody iOS .pen tokens. The legacy `JoviePalette` keeps serving the
/// gate-off screens until they migrate.
enum HomeV2Tokens {
    enum Colors {
        static let canvas = Color(hex: "#030406")
        static let shell = Color(hex: "#07080A")
        static let card = Color(hex: "#131417")
        static let elevated = Color(hex: "#1A1B1E")
        static let floating = Color(hex: "#232427")
        static let ink = Color(hex: "#F5F7FB")
        static let secondary = Color(hex: "#A0A5AF")
        static let muted = Color(hex: "#8F95A0")
        static let quiet = Color(hex: "#7D8593")
        static let border = Color(hex: "#A8B0C3").opacity(0.10)
        static let borderStrong = Color(hex: "#A8B0C3").opacity(0.20)
        static let ion = Color(hex: "#11AFFF")
        static let ultra = Color(hex: "#8E56F5")
        static let mint = Color(hex: "#3FFA8B")
        static let orange = Color(hex: "#FF7800")
        static let red = Color(hex: "#F72A36")
    }

    enum Metric {
        static let weight = Colors.ion
        static let bodyFat = Colors.ultra
        static let ffmi = Colors.mint
        static let steps = Colors.orange
    }

    enum TypeSize {
        static let heroPhoto: CGFloat = 38
        static let heroMetricFirst: CGFloat = 64
        static let title: CGFloat = 16
        static let body: CGFloat = 15
        static let secondary: CGFloat = 14
        static let caption: CGFloat = 13
        static let small: CGFloat = 12
    }

    enum Space {
        static let inset: CGFloat = 20
        static let compact: CGFloat = 16
        static let row: CGFloat = 12
        static let tight: CGFloat = 8
        static let hairline: CGFloat = 1
    }

    static let photoAspectRatio: CGFloat = 4.0 / 5.0
    static let rowHeight: CGFloat = 52
    static let rowHeightWithSubline: CGFloat = 60
    static let thumbSize = CGSize(width: 32, height: 40)
    static let thumbRadius: CGFloat = 8
}
