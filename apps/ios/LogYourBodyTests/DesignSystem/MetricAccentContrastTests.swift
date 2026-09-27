//
// MetricAccentContrastTests.swift
// LogYourBodyTests
//

import SwiftUI
import UIKit
import XCTest
@testable import LogYourBody

/// WCAG 2.2 contrast guard for the semantic foreground/background pairs used by
/// `MetricSummaryCard` and other metric surfaces (JOV-6093). Small metric labels
/// must clear 4.5:1; meaningful non-text accents must clear 3:1.
final class MetricAccentContrastTests: XCTestCase {
    private let colors = DefaultTheme().colors

    // MARK: - WCAG math

    private func channel(_ c: CGFloat) -> CGFloat {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func relativeLuminance(
        _ color: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            "token must resolve to sRGB",
            file: file,
            line: line
        )
        XCTAssertEqual(
            alpha, 1, accuracy: 0.001,
            "text tokens must be opaque; composite foregrounds are not audited here",
            file: file,
            line: line
        )
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrast(
        _ foreground: Color,
        _ background: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        let foregroundLuminance = relativeLuminance(foreground, file: file, line: line)
        let backgroundLuminance = relativeLuminance(background, file: file, line: line)
        let light = max(foregroundLuminance, backgroundLuminance)
        let dark = min(foregroundLuminance, backgroundLuminance)
        return (light + 0.05) / (dark + 0.05)
    }

    private func assertContrast(
        _ foreground: Color,
        on backgrounds: [Color],
        minimum: CGFloat,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for background in backgrounds {
            XCTAssertGreaterThanOrEqual(
                contrast(foreground, background, file: file, line: line),
                minimum,
                "\(name) must clear \(minimum):1 on card surface and canvas",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Metric label accents (small text → 4.5:1)

    func testMetricAccentTokensClearSmallTextContrastOnDarkSurfaces() {
        let surfaces = [colors.surface, colors.background]
        assertContrast(colors.accentViolet, on: surfaces, minimum: 4.5, name: "accentViolet")
        assertContrast(colors.accentPink, on: surfaces, minimum: 4.5, name: "accentPink")
        assertContrast(colors.accentTeal, on: surfaces, minimum: 4.5, name: "accentTeal")
        assertContrast(colors.accentOrange, on: surfaces, minimum: 4.5, name: "accentOrange")
        assertContrast(colors.accentGreen, on: surfaces, minimum: 4.5, name: "accentGreen")
    }

    // MARK: - Text hierarchy (small text → 4.5:1)

    func testTextHierarchyClearsSmallTextContrastOnDarkSurfaces() {
        let surfaces = [colors.surface, colors.surfaceSecondary, colors.background]
        assertContrast(colors.text, on: surfaces, minimum: 4.5, name: "text")
        assertContrast(colors.textSecondary, on: surfaces, minimum: 4.5, name: "textSecondary")
    }

    // MARK: - Meaningful non-text graphics (3:1)

    func testTertiaryTextAndStateColorsClearGraphicContrast() {
        let surfaces = [colors.surface, colors.background]
        assertContrast(colors.textTertiary, on: surfaces, minimum: 3, name: "textTertiary")
        assertContrast(colors.success, on: surfaces, minimum: 3, name: "success")
        assertContrast(colors.error, on: surfaces, minimum: 3, name: "error")
        assertContrast(colors.info, on: surfaces, minimum: 3, name: "info")
    }

    // MARK: - Guard self-check

    func testBlackOnBlackFixtureFailsTheGuard() {
        XCTAssertLessThan(contrast(.black, Color(hex: JoviePalette.surfaceHex)), 4.5)
        XCTAssertLessThan(contrast(.black, Color(hex: JoviePalette.canvasHex)), 4.5)
    }
}
