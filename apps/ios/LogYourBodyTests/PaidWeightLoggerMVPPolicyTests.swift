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


final class PaidWeightLoggerMVPPolicyTests: XCTestCase {
    func testWeightSaveRequiresValidInput() {
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "12",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertFalse(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "999",
                unit: "lbs",
                isSaving: false
            )
        )
        XCTAssertTrue(
            PaidWeightLoggerMVPPolicy.canSaveWeight(
                weightText: "182.4",
                unit: "lbs",
                isSaving: false
            )
        )
    }

    func testWeightValidationMessageExplainsInvalidRange() {
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "12", unit: "lbs"),
            "Enter a weight between 70 and 660 lbs"
        )
        XCTAssertNil(
            PaidWeightLoggerMVPPolicy.validationMessage(weightText: "182.4", unit: "lbs")
        )
    }

    func testSyncStatusCopyAvoidsRawPendingState() {
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .idle, pendingCount: 1),
            "Pending sync"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .offline, pendingCount: 1),
            "Saved offline"
        )
        XCTAssertEqual(
            PaidWeightLoggerMVPPolicy.syncStatusText(status: .error("No auth session"), pendingCount: 1),
            "Sync needs retry"
        )
    }
}
