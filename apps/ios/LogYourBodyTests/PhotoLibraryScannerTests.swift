//
// PhotoLibraryScannerTests.swift
// LogYourBodyTests
//
// Coverage boundary: PhotoLibraryScanner has no injection seam at the Photos
// vendor boundary — fetchPhotos calls PHAsset.fetchAssets directly, analysis
// uses a hard-wired PHCachingImageManager, and ScannedPhoto requires a concrete
// PHAsset (no public initializer, not fabricatable in tests). That makes the
// fetch/analyze/group pipeline (and PhotoGroup.suggestedPrimary) untestable
// without an app-source refactor (protocol-typed fetcher + value-typed photo
// model), which is out of scope for a visibility-only seam. These tests pin
// the pure criteria/metadata contracts and the authorization-state mapping.
//
import XCTest
import Photos
@testable import LogYourBody

final class PhotoLibraryScannerTests: XCTestCase {
    // MARK: - Scan criteria contract

    func testDefaultCriteriaMatchesDocumentedContract() {
        let criteria = PhotoScanCriteria(dateRange: nil)

        XCTAssertNil(criteria.dateRange)
        XCTAssertEqual(criteria.minimumDaysBetween, 3)
        XCTAssertEqual(criteria.minimumResolution, CGSize(width: 1_000, height: 1_000))
        XCTAssertNil(criteria.preferredCameraType)
        XCTAssertTrue(criteria.preferPortraitOrientation)
        XCTAssertEqual(criteria.minimumConfidence, 0.7)
        XCTAssertTrue(criteria.excludeScreenshots)
        XCTAssertFalse(criteria.excludeEdited)
        XCTAssertTrue(criteria.excludeLandscape)
    }

    func testDefaultFactoryCriteriaCoversLastTwoYearsEndingNow() {
        let before = Date()
        let criteria = PhotoScanCriteria.default
        let after = Date()

        let range = criteria.dateRange
        XCTAssertNotNil(range)
        guard let range else { return }

        // End tracks "now" at construction time.
        XCTAssertGreaterThanOrEqual(range.end, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(range.end, after.addingTimeInterval(1))

        // Start is exactly two calendar years before the end.
        let years = Calendar.current.dateComponents([.year], from: range.start, to: range.end).year
        XCTAssertEqual(years, 2)
    }

    // MARK: - Authorization-state mapping

    func testAppAuthorizationStateMapsEveryVendorStatus() {
        XCTAssertEqual(PhotoLibraryScanner.appAuthorizationState(from: .authorized), .authorized)
        XCTAssertEqual(PhotoLibraryScanner.appAuthorizationState(from: .limited), .authorized)
        XCTAssertEqual(PhotoLibraryScanner.appAuthorizationState(from: .notDetermined), .notDetermined)
        XCTAssertEqual(PhotoLibraryScanner.appAuthorizationState(from: .denied), .denied)
        XCTAssertEqual(PhotoLibraryScanner.appAuthorizationState(from: .restricted), .restricted)
    }

    func testScannerAuthorizationStatusTracksLiveVendorStatus() {
        // Environment-independent: whatever PHPhotoLibrary reports, the scanner
        // must reflect the mapped equivalent.
        let vendorStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        XCTAssertEqual(
            PhotoLibraryScanner.shared.authorizationStatus,
            PhotoLibraryScanner.appAuthorizationState(from: vendorStatus)
        )
    }

    func testScanWithoutAuthorizationStaysIdle() async throws {
        let scanner = PhotoLibraryScanner.shared
        guard scanner.authorizationStatus != .authorized else {
            throw XCTSkip("Photo library is authorized for the test host in this environment")
        }

        await scanner.scanPhotoLibrary()

        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(scanner.scanProgress, 0)
        XCTAssertTrue(scanner.scannedPhotos.isEmpty)
        XCTAssertTrue(scanner.photoGroups.isEmpty)
    }

    // MARK: - Metadata contract

    func testPhotoMetadataRoundTripsFilterInputs() {
        let metadata = ScannedPhoto.PhotoMetadata(
            location: nil,
            cameraType: .front,
            isScreenshot: true,
            hasBeenEdited: false
        )

        XCTAssertNil(metadata.location)
        XCTAssertEqual(metadata.cameraType, .front)
        XCTAssertTrue(metadata.isScreenshot)
        XCTAssertFalse(metadata.hasBeenEdited)
        XCTAssertNotEqual(ScannedPhoto.CameraType.front, .back)
        XCTAssertNotEqual(ScannedPhoto.CameraType.back, .unknown)
    }
}
