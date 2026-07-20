//
// BackgroundPhotoUploadServiceTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

@MainActor
final class BackgroundPhotoUploadServiceTests: XCTestCase {
    private let service = BackgroundPhotoUploadService.shared

    override func setUp() async throws {
        try await super.setUp()
        service.cancelAllUploads()
        service.reset()
    }

    override func tearDown() async throws {
        service.cancelAllUploads()
        service.reset()
        try await super.tearDown()
    }

    func testInitialStateIsEmptyAndReadyToUpload() {
        XCTAssertEqual(service.pendingCount, 0)
        XCTAssertEqual(service.completedCount, 0)
        XCTAssertEqual(service.failedCount, 0)
        XCTAssertEqual(service.totalCount, 0)
        XCTAssertFalse(service.isUploading)
        XCTAssertNil(service.currentUploadingPhoto)
        XCTAssertEqual(service.totalProgress, 0.0)
        XCTAssertEqual(service.uploadSummary, "Ready to upload photos")
    }

    func testStartProcessingQueueWithEmptyQueueDoesNotStartUploading() {
        service.startProcessingQueue()

        XCTAssertFalse(service.isUploading)
        XCTAssertNil(service.currentUploadingPhoto)
        XCTAssertEqual(service.uploadSummary, "Ready to upload photos")
    }

    func testCancelAllUploadsClearsInFlightState() {
        service.isUploading = true
        service.totalProgress = 0.5

        service.cancelAllUploads()

        XCTAssertFalse(service.isUploading)
        XCTAssertNil(service.currentUploadingPhoto)
        XCTAssertEqual(service.totalProgress, 0.0)
        XCTAssertTrue(service.uploadQueue.isEmpty)
        XCTAssertEqual(service.uploadSummary, "Ready to upload photos")
    }

    func testResetClearsPublishedQueueState() {
        service.isUploading = true
        service.totalProgress = 0.75

        service.reset()

        XCTAssertFalse(service.isUploading)
        XCTAssertNil(service.currentUploadingPhoto)
        XCTAssertEqual(service.totalProgress, 0.0)
        XCTAssertEqual(service.uploadSummary, "Ready to upload photos")
    }
}
