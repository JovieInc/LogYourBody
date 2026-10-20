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

    func testEmptyReadDoesNotEstablishDenialOrReadAccess() {
        let resolution = HealthKitAuthorizationPolicy.resolve(
            writeAuthorized: false,
            probes: [
                .bodyMass: .empty,
                .bodyFatPercentage: .empty,
                .height: .empty
            ],
            requestSucceeded: true
        )

        XCTAssertFalse(resolution.treatsEmptyReadAsDenial)
        XCTAssertFalse(resolution.shouldPresentAccessNeededAlert)
        XCTAssertTrue(resolution.confirmedReadKinds.isEmpty)
        XCTAssertFalse(resolution.grantsEveryRequestedReadKind)
        XCTAssertFalse(resolution.canUseHealthKit)
        XCTAssertEqual(resolution.record, .emptyNotDenial)
        XCTAssertEqual(
            HealthKitAuthorizationPolicy.connectFollowUp(resolution),
            .showInconclusiveRead
        )
        XCTAssertEqual(
            HealthKitAuthorizationPolicy.onboardingFollowUp(resolution),
            .manualAfterEmptyRead
        )
        XCTAssertEqual(
            HealthKitAuthorizationPolicy.onboardingAnalyticsEvent(.manualAfterEmptyRead),
            "onboarding_health_import_no_samples"
        )
        let status = resolution.statusText
        XCTAssertFalse(status.localizedCaseInsensitiveContains("denied"))
        XCTAssertFalse(status.localizedCaseInsensitiveContains("not authorized"))
        XCTAssertTrue(status.contains("not a denial"))
    }

    func testWriteAuthorizationDoesNotGrantEveryRequestedReadType() {
        let resolution = HealthKitAuthorizationPolicy.resolve(
            writeAuthorized: true,
            probes: [
                .bodyMass: .empty,
                .bodyFatPercentage: .empty,
                .height: .empty
            ],
            requestSucceeded: true
        )

        XCTAssertTrue(resolution.writeAuthorized)
        XCTAssertTrue(resolution.canUseHealthKit)
        XCTAssertTrue(resolution.confirmedReadKinds.isEmpty)
        XCTAssertFalse(resolution.grantsEveryRequestedReadKind)
        XCTAssertFalse(resolution.treatsEmptyReadAsDenial)
        XCTAssertEqual(resolution.record, .writeOnly)
        XCTAssertFalse(resolution.statusText.localizedCaseInsensitiveContains("denied"))
    }

    func testOneReadableSampleConfirmsOnlyThatType() {
        let resolution = HealthKitAuthorizationPolicy.resolve(
            writeAuthorized: false,
            probes: [
                .bodyMass: .found,
                .bodyFatPercentage: .empty,
                .height: .failed
            ],
            requestSucceeded: true
        )

        XCTAssertEqual(resolution.confirmedReadKinds, [.bodyMass])
        XCTAssertFalse(resolution.grantsEveryRequestedReadKind)
        XCTAssertFalse(resolution.treatsEmptyReadAsDenial)
        XCTAssertFalse(resolution.shouldPresentAccessNeededAlert)
        XCTAssertTrue(resolution.canUseHealthKit)
        XCTAssertEqual(resolution.record, .partialSample)
        XCTAssertTrue(resolution.statusText.contains("weight"))
        XCTAssertFalse(resolution.statusText.contains("body fat"))
        XCTAssertFalse(resolution.statusText.contains("steps"))
    }

    func testFailedAuthorizationRequestIsNotDescribedAsAReadDenial() {
        let resolution = HealthKitAuthorizationPolicy.resolve(
            writeAuthorized: false,
            probes: [:],
            requestSucceeded: false
        )

        XCTAssertFalse(resolution.canUseHealthKit)
        XCTAssertEqual(
            HealthKitAuthorizationPolicy.connectFollowUp(resolution),
            .showRequestFailure
        )
        XCTAssertEqual(
            HealthKitAuthorizationPolicy.onboardingFollowUp(resolution),
            .manualAfterRequestFailure
        )
        XCTAssertFalse(resolution.statusText.localizedCaseInsensitiveContains("denied"))
        XCTAssertTrue(resolution.statusText.contains("could not be opened"))
    }
}
