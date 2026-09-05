//
// PhotoLibraryScannerTests.swift
// LogYourBodyTests
//
// Discovery tests inject asset metadata, a recording image manager, and a
// monotonic clock. They exercise the production analysis loop without reading
// or changing the user's photo library. Authorization tests remain read-only.
//
import XCTest
import Photos
import Combine
import UIKit
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

private final class SyntheticScanAsset: PHAsset, @unchecked Sendable {
    override var pixelWidth: Int { 1_200 }
    override var pixelHeight: Int { 1_600 }
    override var creationDate: Date? {
        Calendar.current.date(from: DateComponents(year: 2_026, month: 9, day: 5, hour: 8))
    }
    override var location: CLLocation? { nil }
}

private final class RecordingScanImageManager: PHImageManager {
    var requests = 0

    override func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        resultHandler: @escaping (UIImage?, [AnyHashable: Any]?) -> Void
    ) -> PHImageRequestID {
        requests += 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 16)).image { _ in }
        resultHandler(image, nil)
        return PHImageRequestID(requests)
    }
}

extension PhotoLibraryScannerTests {
    @MainActor
    func testMetadataScanOfThousandAssetsDoesNotDecodeAndThrottlesProgress() async {
        let manager = RecordingScanImageManager()
        var elapsed: TimeInterval = 0
        let scanner = PhotoLibraryScanner(
            imageManager: manager,
            metadataProvider: { _ in
                ScannedPhoto.PhotoMetadata(location: nil, cameraType: .unknown,
                                           isScreenshot: false, hasBeenEdited: false)
            },
            metadataScanEnabled: { true },
            monotonicTime: { elapsed += 0.001; return elapsed }
        )
        var publications: [Double] = []
        let subscription = scanner.$scanProgress.dropFirst().sink { publications.append($0) }
        let assets = (0..<1_000).map { _ in SyntheticScanAsset() }

        let photos = await scanner.analyzePhotos(assets, criteria: PhotoScanCriteria(dateRange: nil))

        XCTAssertEqual(photos.count, 1_000)
        XCTAssertEqual(photos.first?.confidence ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertEqual(Set(photos.map(\.confidence)).count, 1, "Metadata ranking must be deterministic")
        XCTAssertEqual(manager.requests, 0, "Discovery must use asset metadata without requesting pixels")
        XCTAssertFalse(publications.isEmpty)
        XCTAssertLessThanOrEqual(publications.count, 10, "At most ten intermediate updates per simulated second")
        XCTAssertEqual(publications, publications.sorted())
        withExtendedLifetime(subscription) {}
    }
}


extension PhotoLibraryScannerTests {
    @MainActor
    func testDisabledMetadataGatePreservesLegacyDiscovery() async {
        let manager = RecordingScanImageManager()
        let scanner = PhotoLibraryScanner(
            imageManager: manager,
            metadataProvider: { _ in
                ScannedPhoto.PhotoMetadata(location: nil, cameraType: .unknown,
                                           isScreenshot: false, hasBeenEdited: false)
            },
            metadataScanEnabled: { false }
        )
        let photos = await scanner.analyzePhotos([SyntheticScanAsset()], criteria: PhotoScanCriteria(dateRange: nil))
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(manager.requests, 1)
    }

    @MainActor
    func testMetadataScanFiltersScreenshotsWithoutDecodingOrOverpublishing() async {
        let manager = RecordingScanImageManager()
        var elapsed: TimeInterval = 0
        let scanner = PhotoLibraryScanner(
            imageManager: manager,
            metadataProvider: { _ in
                ScannedPhoto.PhotoMetadata(location: nil, cameraType: .unknown,
                                           isScreenshot: true, hasBeenEdited: false)
            },
            metadataScanEnabled: { true },
            monotonicTime: { elapsed += 0.001; return elapsed }
        )
        var publications = 0
        let subscription = scanner.$scanProgress.dropFirst().sink { _ in publications += 1 }
        let photos = await scanner.analyzePhotos(
            (0..<1_000).map { _ in SyntheticScanAsset() }, criteria: PhotoScanCriteria(dateRange: nil)
        )
        XCTAssertTrue(photos.isEmpty)
        XCTAssertEqual(manager.requests, 0)
        XCTAssertGreaterThan(publications, 0)
        XCTAssertLessThanOrEqual(publications, 10)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testMetadataOptimizationPreservesExplicitThumbnailAndImportImageRequests() async {
        let manager = RecordingScanImageManager()
        let scanner = PhotoLibraryScanner(imageManager: manager, metadataScanEnabled: { true })
        let asset = SyntheticScanAsset()
        let thumbnail = await scanner.loadThumbnail(for: asset)
        let fullImage = await scanner.loadFullImage(for: asset)
        XCTAssertNotNil(thumbnail)
        XCTAssertNotNil(fullImage)
        XCTAssertEqual(manager.requests, 2)
    }
}
