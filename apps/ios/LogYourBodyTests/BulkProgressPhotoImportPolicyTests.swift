//
// PhotoMetadataAndImportPolicyTests.swift
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


final class BulkProgressPhotoImportPolicyTests: XCTestCase {
    func testBulkProgressPhotoImportRequiresActivationEvidence() {
        XCTAssertFalse(BulkProgressPhotoImportPolicy.defaultShowsBulkImport)
        XCTAssertFalse(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: 0
            )
        )
    }

    func testBulkProgressPhotoImportUnlocksAfterActivationEvidence() {
        XCTAssertFalse(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: BulkProgressPhotoImportPolicy.activationProgressPhotoCount - 1
            )
        )
        XCTAssertTrue(
            BulkProgressPhotoImportPolicy.shouldShowBulkImport(
                existingProgressPhotoCount: BulkProgressPhotoImportPolicy.activationProgressPhotoCount
            )
        )
    }

    func testBulkProgressPhotoImportFooterExplainsLockedAndEnabledStates() {
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: false, existingProgressPhotoCount: 0),
            "Bulk import unlocks after you have added progress photos or request migration access."
        )
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: false, existingProgressPhotoCount: 1),
            "Bulk import unlocks after one more added progress photo or migration access."
        )
        XCTAssertEqual(
            BulkProgressPhotoImportPolicy.footerText(isEnabled: true, existingProgressPhotoCount: 0),
            "Import progress photos from your photo library."
        )
    }
}
