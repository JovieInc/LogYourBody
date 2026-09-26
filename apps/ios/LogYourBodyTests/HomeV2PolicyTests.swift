//
// HomeV2PolicyTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

@MainActor
final class HomeV2PolicyTests: XCTestCase {
    func testGateOffWithoutFixtureArgumentKeepsHomeV2Off() {
        XCTAssertFalse(
            HomeV2Policy.isEnabled(
                arguments: ["-lybUITestPhotoTimelineHUDFixture"],
                isGateEnabled: { _ in false }
            )
        )
    }

    func testStatsigGateEnablesHomeV2ByItsKey() {
        var askedKey: String?
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [], isGateEnabled: { key in
                askedKey = key
                return true
            })
        )
        XCTAssertEqual(askedKey, "home_v2_photo_first")
    }

    #if DEBUG
    func testFixtureArgumentsEnableHomeV2WithoutTheGate() {
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.fixtureArgument], isGateEnabled: { _ in false })
        )
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.photoFixtureArgument], isGateEnabled: { _ in false })
        )
    }
    #endif

    func testChangeSentenceReadsAsASentence() {
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: -1.8, unit: "lb"), "Down 1.8 lb in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: 0.4, unit: "kg"), "Up 0.4 kg in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: 0.02, unit: "lb"), "No change in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: nil, unit: "lb"), "No 30-day trend yet")
    }

    func testCompactChangeNeverFallsBackToABareUnit() {
        XCTAssertEqual(HomeV2Copy.compactChange(delta: -0.9, unit: "pts"), "−0.9 pts")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: 0.2, unit: ""), "+0.2")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: 0.0, unit: "pts"), "No change")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: nil, unit: "pts"), "No 30-day trend")
    }

    func testAspectFillCropCoversTheTargetAndCentersTheOverflow() {
        let tall = AspectFillCropper.fillRect(imageSize: CGSize(width: 400, height: 500), in: CGSize(width: 393, height: 439))
        XCTAssertEqual(tall.width, 393, accuracy: 0.01)
        XCTAssertEqual(tall.height, 491.25, accuracy: 0.01)
        XCTAssertEqual(tall.midY, 219.5, accuracy: 0.01)

        let wide = AspectFillCropper.fillRect(imageSize: CGSize(width: 1_000, height: 500), in: CGSize(width: 393, height: 491))
        XCTAssertEqual(wide.height, 491, accuracy: 0.01)
        XCTAssertEqual(wide.width, 982, accuracy: 0.01)
        XCTAssertEqual(wide.midX, 196.5, accuracy: 0.01)

        let cropped = AspectFillCropper.crop(UIImage(), to: CGSize(width: 40, height: 50))
        XCTAssertEqual(cropped.size, CGSize(width: 40, height: 50))
    }

    func testStageKeepsFourByFiveWhenItFitsAndGivesUpHeightOnShortScreens() {
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 390, height: 647), 487.5, accuracy: 0.01)
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 375, height: 470), 320, accuracy: 0.01)
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 320, height: 300), 200, accuracy: 0.01)
    }
}
