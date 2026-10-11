//
// HomeV2Tokens.swift
// LogYourBody
//
import SwiftUI

/// Geometry and type for the v2 surfaces, mirrored from the LogYourBody iOS
/// .pen tokens. Colours live in `HomeV2Palette` (Theme.swift, a token home).
enum HomeV2Tokens {
    typealias Colors = HomeV2Palette

    enum Metric {
        static let weight = Colors.ion
        static let bodyFat = Colors.ultra
        static let ffmi = Colors.mint
        static let steps = Colors.orange
    }

    enum TypeSize {
        static let heroPhoto: CGFloat = 38
        static let heroMetricFirst: CGFloat = 84
        static let progressValue: CGFloat = 72
        static let lead: CGFloat = 18
        static let sheetValue: CGFloat = 60
        static let sheetTitle: CGFloat = 22
        static let title: CGFloat = 16
        static let body: CGFloat = 15
        static let secondary: CGFloat = 14
        static let caption: CGFloat = 13
        static let small: CGFloat = 12
    }

    enum Space {
        static let dayZeroTop: CGFloat = 72
        static let heroTop: CGFloat = 40
        static let margin: CGFloat = 24
        static let inset: CGFloat = 20
        static let compact: CGFloat = 16
        static let row: CGFloat = 12
        static let tight: CGFloat = 8
        static let hairline: CGFloat = 1
    }

    static let photoAspectRatio: CGFloat = 4.0 / 5.0
    static let rowHeight: CGFloat = 52
    static let chartHeight: CGFloat = 150
    static let progressChartHeight: CGFloat = 180
    static let rowHeightWithSubline: CGFloat = 60
    static let thumbSize = CGSize(width: 32, height: 40)
    static let thumbRadius: CGFloat = 8
    static let photoSlotHeight: CGFloat = 128
    static let photoSlotRadius: CGFloat = 12
}
