//
// ExternalServicePortsTests.swift
// LogYourBodyTests
//
import AVFoundation
import LocalAuthentication
import Photos
import UIKit
import XCTest
@testable import LogYourBody

final class ExternalServicePortsTests: XCTestCase {
    // MARK: - Protocol convenience extensions

    func testAnalyticsConvenienceMethodsForwardNilProperties() throws {
        let tracker = FakeAnalyticsTracker()

        tracker.identify(userId: "user-1")
        tracker.track(event: "photo_uploaded")

        let identified = try XCTUnwrap(tracker.identified.first)
        XCTAssertEqual(identified.userId, "user-1")
        XCTAssertNil(identified.properties)

        let tracked = try XCTUnwrap(tracker.tracked.first)
        XCTAssertEqual(tracked.event, "photo_uploaded")
        XCTAssertNil(tracked.properties)
    }

    func testGlp1DoseLogsConvenienceUsesDefaultLimitOfOneHundred() async throws {
        let provider = FakeGlp1RemoteDataProvider()

        let logs = try await provider.fetchGlp1DoseLogs(userId: "user-7")

        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(provider.recordedLimits, [100])
        XCTAssertEqual(provider.recordedUserIds, ["user-7"])
    }

    // MARK: - Port type mappings

    func testBiometryTypeMapsToAuthViewType() {
        XCTAssertEqual(AppBiometryType.touchID.authViewType, .touchID)
        XCTAssertEqual(AppBiometryType.faceID.authViewType, .faceID)
        XCTAssertEqual(AppBiometryType.none.authViewType, .faceID)
    }

    // MARK: - Adapter delegation to vendor objects

    func testBiometricAdapterMirrorsVendorAvailability() {
        let context = LAContext()
        var error: NSError?
        let expected: AppBiometryType
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                expected = .faceID
            case .touchID:
                expected = .touchID
            default:
                expected = .none
            }
        } else {
            expected = .none
        }

        XCTAssertEqual(LocalBiometricAuthenticationAdapter().availableBiometryType(), expected)
    }

    func testCancelAuthenticationWithoutActiveSessionIsSafeNoOp() {
        // BiometricLockView calls cancelCurrentAuthentication() from .onDisappear,
        // including when no authentication was ever started.
        let adapter = LocalBiometricAuthenticationAdapter()
        adapter.cancelCurrentAuthentication()
        adapter.cancelCurrentAuthentication()

        XCTAssertEqual(adapter.availableBiometryType(), LocalBiometricAuthenticationAdapter().availableBiometryType())
    }

    func testPhotoLibraryAdapterMirrorsVendorAuthorizationStatus() {
        let vendorStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        XCTAssertEqual(
            LivePhotoLibraryAdapter().authorizationStatus(),
            expectedAuthorizationState(for: vendorStatus)
        )
    }

    func testDeleteAssetsWithNoIdentifiersCompletesWithoutTouchingLibrary() async throws {
        // Empty input must short-circuit before any PHPhotoLibrary.performChanges call.
        try await LivePhotoLibraryAdapter().deleteAssets(localIdentifiers: [])
    }

    func testCameraAdapterMirrorsVendorAuthorizationStatusAndAvailability() {
        let vendorStatus = AVCaptureDevice.authorizationStatus(for: .video)

        XCTAssertEqual(
            LiveCameraAuthorizationAdapter().authorizationStatus(),
            expectedAuthorizationState(for: vendorStatus)
        )
        XCTAssertEqual(
            LiveCameraAuthorizationAdapter().isCameraAvailable,
            UIImagePickerController.isSourceTypeAvailable(.camera)
        )
    }

    // MARK: - Camera capture coordinator

    func testCameraCoordinatorDeliversCapturedImage() {
        var captured: [UIImage] = []
        let view = PlatformCameraCaptureView(onImageCaptured: { captured.append($0) })
        let coordinator = view.makeCoordinator()
        let image = makeTestImage()

        coordinator.imagePickerController(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: [.originalImage: image]
        )

        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured.first === image)
    }

    func testCameraCoordinatorIgnoresPickerResultWithoutOriginalImage() {
        var captured: [UIImage] = []
        let view = PlatformCameraCaptureView(onImageCaptured: { captured.append($0) })
        let coordinator = view.makeCoordinator()

        coordinator.imagePickerController(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: [:]
        )

        XCTAssertTrue(captured.isEmpty)
    }

    func testCameraCoordinatorCancelDoesNotDeliverImage() {
        var captured: [UIImage] = []
        let view = PlatformCameraCaptureView(onImageCaptured: { captured.append($0) })
        let coordinator = view.makeCoordinator()

        coordinator.imagePickerControllerDidCancel(UIImagePickerController())

        XCTAssertTrue(captured.isEmpty)
    }

    // MARK: - Helpers

    private func expectedAuthorizationState(for status: PHAuthorizationStatus) -> AppAuthorizationState {
        switch status {
        case .authorized, .limited:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func expectedAuthorizationState(for status: AVAuthorizationStatus) -> AppAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 8, height: 8)))
        }
    }
}

private final class FakeAnalyticsTracker: AnalyticsTracking {
    private(set) var identified: [(userId: String?, properties: [String: String]?)] = []
    private(set) var tracked: [(event: String, properties: [String: String]?)] = []

    func start() { }

    func identify(userId: String?, properties: [String: String]?) {
        identified.append((userId: userId, properties: properties))
    }

    func track(event: String, properties: [String: String]?) {
        tracked.append((event: event, properties: properties))
    }

    func reset() { }

    func isFeatureEnabled(flagKey: String) -> Bool {
        false
    }
}

private final class FakeGlp1RemoteDataProvider: Glp1RemoteDataProviding {
    private(set) var recordedLimits: [Int] = []
    private(set) var recordedUserIds: [String] = []

    func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication] {
        []
    }

    func fetchGlp1DoseLogs(userId: String, limit: Int) async throws -> [Glp1DoseLog] {
        recordedUserIds.append(userId)
        recordedLimits.append(limit)
        return []
    }
}
