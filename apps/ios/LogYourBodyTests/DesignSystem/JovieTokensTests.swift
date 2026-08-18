//
// JovieTokensTests.swift
// LogYourBodyTests
//
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

    func testMotionAndHairlineTokensStayStable() {
        XCTAssertEqual(JovieTokens.hairlineOpacity, 0.72)
        XCTAssertEqual(JovieTokens.ambientAccentOpacity, 0.08)
        XCTAssertEqual(JovieTokens.subtleDuration, 0.15)
        XCTAssertEqual(JovieTokens.cinematicDuration, 0.42)
    }

    func testDarkOnlyCanvasPaletteMatchesJovieSurfaces() {
        XCTAssertEqual(JoviePalette.canvasHex, "#08090A")
        XCTAssertEqual(JoviePalette.surfaceHex, "#0F1011")
        XCTAssertEqual(JoviePalette.elevatedHex, "#17171A")
        XCTAssertEqual(JoviePalette.raisedHex, "#1C1C1E")
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
