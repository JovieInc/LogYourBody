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
}
