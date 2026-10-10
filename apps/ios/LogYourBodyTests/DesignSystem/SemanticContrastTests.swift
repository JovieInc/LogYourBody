//
// SemanticContrastTests.swift
// LogYourBodyTests
//
// WCAG 2.2 contrast guard for the canonical semantic color pairs
// (JOV-6093). Small text must reach 4.5:1; meaningful non-text
// graphics must reach 3:1. Deliberately failing fixture included so
// the guard is proven to catch black-on-black pairs.
//

import SwiftUI
import XCTest
@testable import LogYourBody

final class SemanticContrastTests: XCTestCase {
    private let theme = DefaultTheme()

    // MARK: - WCAG helpers

    private func relativeLuminance(_ color: Color) -> Double {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func channel(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrastRatio(_ foreground: Color, _ background: Color) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func assertContrast(
        _ foreground: Color,
        _ name: String,
        on backgrounds: [(Color, String)],
        minimum: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (background, backgroundName) in backgrounds {
            let ratio = contrastRatio(foreground, background)
            XCTAssertGreaterThanOrEqual(
                ratio,
                minimum,
                "\(name) on \(backgroundName) is \(String(format: "%.2f", ratio)):1 (minimum \(minimum):1)",
                file: file,
                line: line
            )
        }
    }

    private var darkSurfaces: [(Color, String)] {
        [
            (theme.colors.background, "background"),
            (theme.colors.surface, "surface"),
            (theme.colors.surfaceSecondary, "surfaceSecondary"),
            (theme.colors.surfaceTertiary, "surfaceTertiary")
        ]
    }

    private var metricSurfaces: [(Color, String)] {
        [
            (Color.metricCard, "metricCard"),
            (Color.metricSurface, "metricSurface"),
            (Color.metricCanvas, "metricCanvas")
        ]
    }

    // MARK: - Text tiers

    func testPrimaryAndSecondaryTextMeetAAOnAllDarkSurfaces() {
        assertContrast(theme.colors.text, "text", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.textSecondary, "textSecondary", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.textTertiary, "textTertiary", on: darkSurfaces, minimum: 4.5)
    }

    // MARK: - Metric accents (labels + meaningful graphics)

    func testThemeAccentsMeetAAOnDarkSurfaces() {
        assertContrast(theme.colors.accentViolet, "accentViolet", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.accentPink, "accentPink", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.accentTeal, "accentTeal", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.accentOrange, "accentOrange", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.accentGreen, "accentGreen", on: darkSurfaces, minimum: 4.5)
    }

    func testMetricAccentPaletteMeetsAAOnMetricSurfaces() {
        // These back MetricSummaryCard labels and chart strokes.
        assertContrast(Color.metricAccentSteps, "metricAccentSteps", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricAccentWeight, "metricAccentWeight", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricAccentBodyFat, "metricAccentBodyFat", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricAccentFFMI, "metricAccentFFMI", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricAccentWaist, "metricAccentWaist", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricDeltaPositive, "metricDeltaPositive", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricDeltaNegative, "metricDeltaNegative", on: metricSurfaces, minimum: 4.5)
    }

    func testMetricTextPaletteMeetsAAOnMetricSurfaces() {
        assertContrast(Color.metricTextPrimary, "metricTextPrimary", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricTextSecondary, "metricTextSecondary", on: metricSurfaces, minimum: 4.5)
        assertContrast(Color.metricTextTertiary, "metricTextTertiary", on: metricSurfaces, minimum: 4.5)
    }

    // MARK: - State colors used as text/icons

    func testStateColorsMeetAAOnDarkSurfaces() {
        assertContrast(theme.colors.success, "success", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.warning, "warning", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.error, "error", on: darkSurfaces, minimum: 4.5)
        assertContrast(theme.colors.info, "info", on: darkSurfaces, minimum: 4.5)
    }

    // MARK: - Primary action pair

    func testPrimaryActionPairMeetsAA() {
        assertContrast(Color.jovieActionText, "jovieActionText", on: [(Color.jovieAction, "jovieAction")], minimum: 4.5)
        assertContrast(Color.jovieText, "jovieText", on: [(Color.jovieCanvas, "jovieCanvas"), (Color.jovieSurface, "jovieSurface")], minimum: 4.5)
        assertContrast(Color.jovieTextSecondary, "jovieTextSecondary", on: [(Color.jovieCanvas, "jovieCanvas"), (Color.jovieSurface, "jovieSurface")], minimum: 4.5)
    }

    // MARK: - Negative fixture: the guard must fail black-on-black

    func testBlackOnBlackFixtureFailsTheGuard() {
        let ratio = contrastRatio(Color.black, Color.black)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
        XCTAssertLessThan(ratio, 4.5, "Guard must reject a black-on-black pair")
    }

    // MARK: - Source guards: label dimming and launch-path usage

    func testMetricSummaryCardDoesNotDimSemanticLabelColors() throws {
        let source = try String(contentsOf: metricSummaryCardURL(), encoding: .utf8)
        XCTAssertFalse(
            source.contains("accentColor.opacity(0.8)"),
            "MetricSummaryCard must render its accent label at full opacity"
        )
        XCTAssertFalse(
            source.contains("secondaryTextColor.opacity("),
            "MetricSummaryCard must not dim secondary text or the affordance chevron"
        )
    }

    func testMetricSummaryCardIsUsedOnLaunchStatsSurface() throws {
        let sectionURL = iOSDirectory
            .appendingPathComponent("LogYourBody")
            .appendingPathComponent("Views")
            .appendingPathComponent("DashboardMetricsSection.swift")
        let source = try String(contentsOf: sectionURL, encoding: .utf8)
        XCTAssertTrue(source.contains("MetricSummaryCard("))
        XCTAssertTrue(source.contains("theme.colors.accentViolet"))
        XCTAssertTrue(source.contains("theme.colors.accentPink"))
        XCTAssertTrue(source.contains("theme.colors.accentTeal"))
        XCTAssertTrue(source.contains("theme.colors.accentOrange"))
    }

    private var iOSDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func metricSummaryCardURL() -> URL {
        iOSDirectory
            .appendingPathComponent("LogYourBody")
            .appendingPathComponent("DesignSystem")
            .appendingPathComponent("Organisms")
            .appendingPathComponent("MetricSummaryCard.swift")
    }
}
