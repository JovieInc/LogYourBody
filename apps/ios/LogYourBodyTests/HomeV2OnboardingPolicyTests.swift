//
// HomeV2OnboardingPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

@MainActor
final class HomeV2OnboardingPolicyTests: XCTestCase {
    func testOnboardingGateIsSeparateFromHome() {
        var askedKey: String?
        XCTAssertTrue(
            HomeV2Policy.isOnboardingV2Enabled(arguments: [], isGateEnabled: { key in
                askedKey = key
                return true
            })
        )
        XCTAssertEqual(askedKey, "onboarding_v2_focus")
        XCTAssertFalse(
            HomeV2Policy.isOnboardingV2Enabled(arguments: [HomeV2Policy.fixtureArgument], isGateEnabled: { _ in false }),
            "Home's fixture does not open the first run"
        )
    }

    #if DEBUG
    func testOnboardingFixtureForcesTheGate() {
        XCTAssertTrue(
            HomeV2Policy.isOnboardingV2Enabled(arguments: [HomeV2Policy.onboardingFixtureArgument], isGateEnabled: { _ in false })
        )
    }
    #endif

    func testCopyKeepsPricesOutAndTargetsHonest() {
        XCTAssertEqual(HomeV2OnboardingCopy.included.count, 3)
        for line in HomeV2OnboardingCopy.included {
            XCTAssertFalse(line.contains("$"), "Prices come from the store, never from copy")
        }
        XCTAssertEqual(HomeV2OnboardingCopy.targetNote, "Weight from Apple Health is measured. Body fat is estimated.")
        XCTAssertEqual(HomeV2OnboardingCopy.targetRangeError(unit: "kg"), "Enter a weight between 20 and 500 kg.")
        XCTAssertEqual(HomeV2OnboardingCopy.stepsCount, 3)
    }
}
