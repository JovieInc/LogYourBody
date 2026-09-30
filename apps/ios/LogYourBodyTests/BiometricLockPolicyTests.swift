//
// BiometricLockPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class BiometricLockPolicyTests: XCTestCase {
    func testUITestArgumentCannotUnlockAPersonalUser() {
        XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestDisableBiometricLock", "-lybUITestPaidMVPFixture"],
            environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
            userId: "personal-user"
        ))
    }

    func testUITestArgumentRequiresAnXCTestConfiguration() {
        XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestDisableBiometricLock", "-lybUITestPaidMVPFixture"],
            environment: [:],
            userId: "ui_test_paid_mvp_user_123"
        ))
        XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestDisableBiometricLock", "-lybUITestPaidMVPFixture"],
            environment: ["XCTestConfigurationFilePath": "   "],
            userId: "ui_test_paid_mvp_user_123"
        ))
    }

    func testUITestArgumentRequiresAnExplicitFixtureAndMatchingUser() {
        for userId in [nil, "", "ui_test_unknown_user_123", "ui_test_photo_hud_user_123"] {
            XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
                arguments: ["-lybUITestDisableBiometricLock", "-lybUITestPaidMVPFixture"],
                environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
                userId: userId
            ))
        }
        XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestDisableBiometricLock"],
            environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
            userId: "ui_test_paid_mvp_user_123"
        ))
    }

    func testValidUITestFixtureCanUnlockOnlyADebugBuild() {
        let allowed = BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestDisableBiometricLock", "-lybUITestPaidMVPFixture"],
            environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
            userId: "ui_test_paid_mvp_user_123"
        )
        #if DEBUG
        XCTAssertTrue(allowed)
        #else
        XCTAssertFalse(allowed, "A production binary must ignore the biometric bypass argument")
        #endif
    }

    func testAllSupportedFixturesRequireTheirOwnSyntheticIdentity() {
        let fixtures = [
            "-lybUITestPaidMVPFixture": "paid_mvp",
            "-lybUITestWeightLoggerMVPFixture": "weight_logger",
            "-lybUITestPaywallFixture": "paywall",
            "-lybUITestPaywallPlansFixture": "paywall",
            "-lybUITestFullDashboardFixture": "full_dashboard",
            "-lybUITestPhotoTimelineHUDFixture": "photo_hud",
            "-lybUITestBodyScoreOnboardingFixture": "onboarding",
            "-lybUITestBodyScoreFirstPhotoFixture": "onboarding"
        ]
        for (fixture, slug) in fixtures {
            let allowed = BiometricLockPolicy.shouldDisableForUITests(
                arguments: ["-lybUITestDisableBiometricLock", fixture],
                environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
                userId: "ui_test_\(slug)_user_123"
            )
            #if DEBUG
            XCTAssertTrue(allowed, fixture)
            #else
            XCTAssertFalse(allowed, fixture)
            #endif
            XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
                arguments: ["-lybUITestDisableBiometricLock", fixture],
                environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
                userId: "ui_test_\(slug)_user_"
            ))
        }
    }

    func testValidFixtureStillRequiresTheExplicitBypassArgument() {
        XCTAssertFalse(BiometricLockPolicy.shouldDisableForUITests(
            arguments: ["-lybUITestPaidMVPFixture"],
            environment: ["XCTestConfigurationFilePath": "/tmp/ui-test.xctestconfiguration"],
            userId: "ui_test_paid_mvp_user_123"
        ))
    }

    func testBiometricLockUsesTheShippedEntryScreenIdentifier() {
        XCTAssertEqual(WorldClassScreen.biometricLock.flow, .entry)
        XCTAssertEqual(
            WorldClassScreen.biometricLock.accessibilityIdentifier,
            WorldClassScreen.allCases.first { $0 == .biometricLock }?.accessibilityIdentifier
        )
    }

    func testSuccessfulAuthenticationUnlocks() {
        XCTAssertTrue(BiometricLockPolicy.shouldUnlock(after: .success))
    }

    func testUnavailableBiometricsUnlocksRatherThanLockingUserOut() {
        XCTAssertTrue(BiometricLockPolicy.shouldUnlock(after: .unavailable))
    }

    func testFailedAuthenticationKeepsLock() {
        XCTAssertFalse(BiometricLockPolicy.shouldUnlock(after: .failure))
    }

    func testFallbackIsHiddenBeforeFirstAttempt() {
        XCTAssertFalse(
            BiometricLockPolicy.showsFallbackOptions(hasAttemptedOnce: false, isAuthenticating: false)
        )
    }

    func testFallbackIsHiddenWhileAttemptIsInFlight() {
        XCTAssertFalse(
            BiometricLockPolicy.showsFallbackOptions(hasAttemptedOnce: false, isAuthenticating: true)
        )
        XCTAssertFalse(
            BiometricLockPolicy.showsFallbackOptions(hasAttemptedOnce: true, isAuthenticating: true)
        )
    }

    func testFallbackIsOfferedAfterFailedAttemptCompletes() {
        XCTAssertTrue(
            BiometricLockPolicy.showsFallbackOptions(hasAttemptedOnce: true, isAuthenticating: false)
        )
    }

    func testNewAttemptCannotStartWhileOneIsInFlight() {
        XCTAssertFalse(BiometricLockPolicy.canStartAuthentication(isAuthenticating: true))
        XCTAssertTrue(BiometricLockPolicy.canStartAuthentication(isAuthenticating: false))
    }
}
