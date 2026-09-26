//
// JovieTokensTests.swift
// LogYourBodyTests
//
import SwiftUI
import XCTest
@testable import LogYourBody

final class JovieTokensTests: XCTestCase {
    func testSharedGeometryTokensStayStable() {
        XCTAssertEqual(JovieTokens.screenInset, 20)
        XCTAssertEqual(JovieTokens.compactInset, 16)
        XCTAssertEqual(JovieTokens.tightGap, 8)
        XCTAssertEqual(JovieTokens.sectionGap, 28)
        XCTAssertEqual(JovieTokens.itemGap, 12)
        XCTAssertEqual(JovieTokens.cardRadius, 20)
        XCTAssertEqual(JovieTokens.controlRadius, 16)
    }

    func testHitTargetsStayAtLeastFortyFourPoints() {
        XCTAssertEqual(JovieTokens.minimumHitTarget, 44)
        XCTAssertEqual(JovieTokens.compactControlHeight, 44)
        XCTAssertEqual(JovieTokens.controlHeight, 52)
        XCTAssertGreaterThanOrEqual(JovieTokens.compactControlHeight, JovieTokens.minimumHitTarget)
        XCTAssertGreaterThanOrEqual(JovieTokens.controlHeight, JovieTokens.minimumHitTarget)
    }

    func testLockedAtomsStayLocked() {
        // native-swift-locked-atoms-v1: ActionButton 32 / 510 / r999, type 28 / 620.
        XCTAssertEqual(JovieTokens.actionControlHeight, 32)
        XCTAssertEqual(JovieTokens.actionLabelWeight, .medium)
        XCTAssertEqual(JovieTokens.actionRadius, 999)
        XCTAssertEqual(JovieTokens.displayTypeSize, 28)
        XCTAssertEqual(JovieTokens.displayTypeWeight, .semibold)
        XCTAssertGreaterThanOrEqual(JovieTokens.minimumHitTarget, 44)
    }

    func testMotionAndHairlineTokensStayStable() {
        XCTAssertEqual(JovieTokens.hairlineOpacity, 0.72)
        XCTAssertEqual(JovieTokens.ambientAccentOpacity, 0.08)
        XCTAssertEqual(JovieTokens.subtleDuration, 0.15)
        XCTAssertEqual(JovieTokens.cinematicDuration, 0.42)
    }

    func testDarkOnlyCanvasPaletteMatchesNoirIonLadder() {
        // night-dj-harmony-v1: page -> main -> rail -> card -> dropdown -> modal
        XCTAssertEqual(JoviePalette.canvasHex, "#030407")
        XCTAssertEqual(JoviePalette.shellHex, "#06080D")
        XCTAssertEqual(JoviePalette.panelHex, "#0A0D16")
        XCTAssertEqual(JoviePalette.cardHex, "#0F1420")
        XCTAssertEqual(JoviePalette.elevatedHex, "#151B2A")
        XCTAssertEqual(JoviePalette.floatingHex, "#1B2436")
        XCTAssertEqual(JoviePalette.surfaceHex, JoviePalette.cardHex)
        XCTAssertEqual(JoviePalette.raisedHex, JoviePalette.floatingHex)
    }

    func testCoreAccentsMatchPaletteLock() {
        // palette-core-accents-v1: blue / hot pink / purple, one gold, one error.
        XCTAssertEqual(JoviePalette.ionHex, "#11AFFF")
        XCTAssertEqual(JoviePalette.pulseHex, "#FF48D2")
        XCTAssertEqual(JoviePalette.ultraHex, "#A982FF")
        XCTAssertEqual(JoviePalette.goldHex, "#FFC857")
        XCTAssertEqual(JoviePalette.errorHex, "#FF677D")
        XCTAssertEqual(JoviePalette.creamHex, "#F5F4F0")
    }

    func testSuccessIsBlueNeverGreen() {
        let theme = DefaultTheme()
        XCTAssertEqual(theme.colors.success, Color(hex: JoviePalette.ionHex))
        XCTAssertEqual(theme.colors.error, Color(hex: JoviePalette.errorHex))
        XCTAssertEqual(theme.colors.warning, Color(hex: JoviePalette.goldHex))
        XCTAssertEqual(Color.success, Color(hex: JoviePalette.ionHex))
        XCTAssertEqual(Color.metricDeltaPositive, Color(hex: JoviePalette.ionHex))
        XCTAssertNotEqual(Color.success, Color.green)
    }

    func testCanvasLadderIsMonotonicallyLighter() {
        let ladder = [
            JoviePalette.canvasHex, JoviePalette.shellHex, JoviePalette.panelHex,
            JoviePalette.cardHex, JoviePalette.elevatedHex, JoviePalette.floatingHex
        ]
        let luminance = ladder.map { hex -> Int in
            let digits = hex.dropFirst()
            return Int(digits, radix: 16) ?? -1
        }
        XCTAssertEqual(luminance, luminance.sorted())
        XCTAssertEqual(Set(luminance).count, ladder.count)
    }

    func testChatComposerGeometryUsesSharedTokens() {
        XCTAssertEqual(ChatComposerGeometry.multilineTextHeightThreshold, JovieTokens.sectionGap)
        XCTAssertTrue(ChatComposerGeometry.isMultiline(textHeight: JovieTokens.sectionGap + 1))
        XCTAssertFalse(ChatComposerGeometry.isMultiline(textHeight: JovieTokens.sectionGap))
        XCTAssertEqual(
            ChatComposerGeometry.cornerRadius(isMultiline: true),
            JovieTokens.controlRadius
        )
        XCTAssertEqual(
            ChatComposerGeometry.cornerRadius(isMultiline: false),
            JovieTokens.controlHeight
        )
        XCTAssertNil(ChatComposerGeometry.transitionAnimation(reduceMotion: true))
        XCTAssertNotNil(ChatComposerGeometry.transitionAnimation(reduceMotion: false))
    }
}
