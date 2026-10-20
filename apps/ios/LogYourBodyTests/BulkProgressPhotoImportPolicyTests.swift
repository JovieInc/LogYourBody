//
// PhotoMetadataAndImportPolicyTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import Photos
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

    func testBulkImportConfirmationMatchesSelectionAndIdleRules() {
        XCTAssertTrue(
            BulkPhotoImportPresentationPolicy.canConfirmImport(selectedCount: 2, isImporting: false)
        )
        XCTAssertFalse(
            BulkPhotoImportPresentationPolicy.canConfirmImport(selectedCount: 0, isImporting: false)
        )
        XCTAssertFalse(
            BulkPhotoImportPresentationPolicy.canConfirmImport(selectedCount: 2, isImporting: true)
        )
        XCTAssertTrue(NativeSheetPresentationPolicy.usesNativeNavigationChrome(.bulkPhotoImport))
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomGrabber(.bulkPhotoImport))
    }

    // MARK: - Manual library picks (LYB-82)

    func testMergeCandidatesOrdersNewestFirstAndDeduplicatesByAssetIdentifier() {
        let oldest = makeCandidate(identifier: "a", day: 1)
        let newest = makeCandidate(identifier: "b", day: 10)
        let duplicateOfOldest = makeCandidate(identifier: "a", day: 1, isManuallyPicked: true)
        let manual = makeCandidate(identifier: "c", day: 5, isManuallyPicked: true)

        let merged = BulkPhotoImportPresentationPolicy.mergeCandidates(
            scanned: [oldest, newest],
            manual: [manual, duplicateOfOldest]
        )

        XCTAssertEqual(merged.map { $0.asset.localIdentifier }, ["b", "c", "a"])
        XCTAssertFalse(merged.last?.isManuallyPicked ?? true, "A scanned suggestion wins over a duplicate manual pick")
    }

    func testManualCandidateMarksPickAndKeepsCaptureDate() {
        let scanner = PhotoLibraryScanner(
            metadataProvider: { _ in
                ScannedPhoto.PhotoMetadata(
                    location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
                )
            }
        )
        let asset = ManualPickAsset(identifier: "manual-1", day: 3)

        let candidate = scanner.manualCandidate(for: asset)

        XCTAssertTrue(candidate.isManuallyPicked)
        XCTAssertEqual(candidate.confidence, 1.0)
        XCTAssertEqual(candidate.date, asset.creationDate)
        XCTAssertEqual(candidate.asset.localIdentifier, "manual-1")
    }

    private func makeCandidate(identifier: String, day: Int, isManuallyPicked: Bool = false) -> ScannedPhoto {
        ScannedPhoto(
            asset: ManualPickAsset(identifier: identifier, day: day),
            date: Calendar.current.date(from: DateComponents(year: 2_026, month: 9, day: day)) ?? Date(),
            confidence: 0.8,
            metadata: ScannedPhoto.PhotoMetadata(
                location: nil, cameraType: .unknown, isScreenshot: false, hasBeenEdited: false
            ),
            isManuallyPicked: isManuallyPicked
        )
    }
}

private final class ManualPickAsset: PHAsset, @unchecked Sendable {
    private let identifier: String
    private let day: Int

    init(identifier: String, day: Int) {
        self.identifier = identifier
        self.day = day
        super.init()
    }

    override var localIdentifier: String { identifier }
    override var creationDate: Date? {
        Calendar.current.date(from: DateComponents(year: 2_026, month: 9, day: day))
    }
}
