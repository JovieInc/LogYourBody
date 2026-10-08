//
// CoreDataAndPhotoPolicyTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


final class HealthKitAuthorizationPolicyTests: XCTestCase {
    func testIntegrationDirectoryDefaultsOffAndUsesTheRolloutGate() {
        var requestedGate: String?
        XCTAssertFalse(IntegrationStatusPolicy.isEnabled(arguments: []) {
            requestedGate = $0
            return false
        })
        XCTAssertEqual(requestedGate, "lyb_integrations_directory_v1")
        XCTAssertTrue(IntegrationStatusPolicy.isEnabled(arguments: []) { _ in true })
    }

    func testConfirmedReadAccessKeepsReadOnlyHealthKitAccessUsableWhenSharingIsDenied() {
        XCTAssertTrue(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingDenied,
                hasConfirmedReadAccess: true
            )
        )
    }

    func testDeniedSharingWithoutConfirmedReadAccessIsNotAuthorized() {
        XCTAssertFalse(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingDenied,
                hasConfirmedReadAccess: false
            )
        )
    }

    func testShareAuthorizationIsEnoughWithoutStoredPromptState() {
        XCTAssertTrue(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .sharingAuthorized,
                hasConfirmedReadAccess: false
            )
        )
    }

    func testUndeterminedStatusWithoutCompletedRequestIsNotAuthorized() {
        XCTAssertFalse(
            HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: .notDetermined,
                hasConfirmedReadAccess: false
            )
        )
    }

    func testMacAvailabilityWinsOverStoredAuthorizationAndSyncPreferences() {
        for requestCompleted in [false, true] {
            for syncEnabled in [false, true] {
                let state = IntegrationStatusPolicy.health(
                    available: false, onMac: true, requestCompleted: requestCompleted, syncEnabled: syncEnabled
                )
                XCTAssertEqual(state.status, "Use on iPhone")
                XCTAssertTrue(state.detail.contains("supported iPhone or iPad"))
            }
        }
    }

    func testCompletedHealthRequestDoesNotClaimReadAuthorization() {
        let state = IntegrationStatusPolicy.health(
            available: true, onMac: false, requestCompleted: true, syncEnabled: true
        )
        XCTAssertEqual(state.status, "Sync enabled")
        XCTAssertTrue(state.detail.contains("controls which data is shared"))
        XCTAssertFalse(state.status.contains("Connected"))
    }

    func testUnrequestedHealthAccessDoesNotInheritDefaultSyncPreference() {
        let state = IntegrationStatusPolicy.health(
            available: true, onMac: false, requestCompleted: false, syncEnabled: true
        )
        XCTAssertEqual(state.status, "Set up access")
    }

    func testPausingSyncDoesNotClaimHealthPermissionWasRevoked() {
        let state = IntegrationStatusPolicy.health(
            available: true, onMac: false, requestCompleted: true, syncEnabled: false
        )
        XCTAssertEqual(state.status, "Sync paused")
        XCTAssertTrue(state.detail.contains("controls which data is shared"))
    }

    func testUnsupportedDeviceDoesNotPresentSetupAsAvailable() {
        XCTAssertEqual(IntegrationStatusPolicy.health(
            available: false, onMac: false, requestCompleted: false, syncEnabled: true
        ).status, "Unavailable")
    }
}
