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


final class ProgressPhotoAttachPolicyTests: XCTestCase {
    func testProgressPhotoAttachStateCopyCoversCoreStates() {
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .empty), "Choose a photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .ready), "Ready to attach")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .processing), "Processing photo")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .success), "Photo added")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .permissionDenied), "Permission needed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusTitle(for: .failed("Upload failed")), "Photo failed")
        XCTAssertEqual(ProgressPhotoAttachPolicy.statusMessage(for: .failed("Upload failed")), "Upload failed")
    }

    func testProgressPhotoAttachTargetCopyDistinguishesAttachAndCreate() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: true,
                targetDate: date
            ).hasPrefix("Attaches to")
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.targetCopy(
                hasTargetMetric: false,
                targetDate: date
            ).hasPrefix("Adds to")
        )
    }

    func testProgressPhotoAttachCameraPolicyRequiresAvailableAuthorizedCamera() {
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .authorized
            )
        )
        XCTAssertTrue(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .notDetermined
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: false,
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            ProgressPhotoAttachPolicy.canUseCamera(
                isAvailable: true,
                authorizationStatus: .denied
            )
        )
    }

    func testProgressPhotoAttachBusyStateOnlyComesFromLocalProcessingStatus() {
        XCTAssertTrue(ProgressPhotoAttachPolicy.isBusy(status: .processing))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .empty))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .ready))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .success))
        XCTAssertFalse(ProgressPhotoAttachPolicy.isBusy(status: .failed("Upload failed")))
    }
}
