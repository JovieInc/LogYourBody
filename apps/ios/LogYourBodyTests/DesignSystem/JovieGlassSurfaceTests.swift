//
// JovieGlassSurfaceTests.swift
// LogYourBodyTests
//
// Glass availability contract:
// 1. Reduce Transparency always uses an opaque surface fill.
// 2. iOS 26+ (when transparency is allowed) uses native `glassEffect`.
// 3. Older OS versions keep ultraThinMaterial + tint + hairline.
// These branches are policy, not a second glass system.
//
import SwiftUI
import XCTest
@testable import LogYourBody

final class JovieGlassSurfaceTests: XCTestCase {
    func testReduceTransparencyAlwaysSelectsSolidSurface() {
        XCTAssertEqual(
            JovieGlassSurface.style(reduceTransparency: true, isNativeGlassAvailable: true),
            .solid
        )
        XCTAssertEqual(
            JovieGlassSurface.style(reduceTransparency: true, isNativeGlassAvailable: false),
            .solid
        )
    }

    func testNativeGlassIsSelectedOnlyWhenAvailableAndTransparencyIsAllowed() {
        XCTAssertEqual(
            JovieGlassSurface.style(reduceTransparency: false, isNativeGlassAvailable: true),
            .nativeGlass
        )
        XCTAssertEqual(
            JovieGlassSurface.style(reduceTransparency: false, isNativeGlassAvailable: false),
            .materialFallback
        )
    }

    func testRuntimeAvailabilityMatchesIOS26Contract() {
        if #available(iOS 26.0, *) {
            XCTAssertTrue(JovieGlassSurface.isNativeGlassAvailable)
            XCTAssertEqual(
                JovieGlassSurface.style(reduceTransparency: false),
                .nativeGlass
            )
        } else {
            XCTAssertFalse(JovieGlassSurface.isNativeGlassAvailable)
            XCTAssertEqual(
                JovieGlassSurface.style(reduceTransparency: false),
                .materialFallback
            )
        }
    }

    func testSurfaceSpecDefaultsKeepExistingCallSitesNonInteractive() {
        let spec = JovieGlassSurfaceSpec(
            tint: .white,
            tintOpacity: 0.035,
            solidFill: Color(hex: JoviePalette.surfaceHex),
            fallbackMaterial: .ultraThin
        )

        XCTAssertFalse(spec.interactive)
        XCTAssertEqual(spec.tintOpacity, 0.035)
        XCTAssertEqual(spec.fallbackTintOpacity, 0.035)
    }

    func testLiquidGlassCardKeepsStableDefaults() {
        let card = LiquidGlassCard {
            EmptyView()
        }

        XCTAssertEqual(card.cornerRadius, 16)
        XCTAssertEqual(card.blurRadius, 24)
        XCTAssertEqual(card.padding, 16)
        XCTAssertTrue(card.showShadow)
        XCTAssertTrue(card.showHighlight)
    }

    func testGlassPillButtonKeepsStableInputs() {
        let button = GlassPillButton(icon: "plus.circle.fill", title: "Log Weight") {}

        XCTAssertEqual(button.icon, "plus.circle.fill")
        XCTAssertEqual(button.title, "Log Weight")
    }
}
