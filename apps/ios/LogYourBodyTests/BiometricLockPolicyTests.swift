//
// BiometricLockPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class BiometricLockPolicyTests: XCTestCase {
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
