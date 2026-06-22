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


final class PhotoUploadBatchPolicyTests: XCTestCase {
    func testPhotoUploadBatchProgressHandlesEmptyAndCompletedCounts() {
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 0, totalCount: 0), 0)
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 1, totalCount: 4), 0.25)
        XCTAssertEqual(PhotoUploadBatchPolicy.progress(completedCount: 4, totalCount: 4), 1.0)
    }

    func testPhotoUploadBatchProgressTextCapsCurrentIndexAtTotal() {
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 0, totalCount: 0), "Processing photos")
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 0, totalCount: 3), "Processing 1 of 3")
        XCTAssertEqual(PhotoUploadBatchPolicy.progressText(processedCount: 3, totalCount: 3), "Processing 3 of 3")
    }

    func testPhotoUploadBatchSelectionCannotChangeWhileProcessing() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canChangeSelection(isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canChangeSelection(isProcessing: true))
    }

    func testPhotoUploadBatchStartsOnlyWhenIdleWithSelection() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 0, isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: true, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canStartUpload(selectedCount: 1, isSaving: false, isProcessing: true))
    }

    func testPhotoUploadBatchDismissesOnlyWhenIdle() {
        XCTAssertTrue(PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canDismiss(isSaving: true, isProcessing: false))
        XCTAssertFalse(PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: true))
    }

    func testPhotoUploadBatchDismissesOnlyAfterAllSelectedPhotosUpload() {
        XCTAssertTrue(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 3, totalCount: 3))
        XCTAssertFalse(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 2, totalCount: 3))
        XCTAssertFalse(PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 0, totalCount: 0))
    }

    func testPhotoUploadBatchFailureMessageDistinguishesPartialAndFullFailure() {
        XCTAssertEqual(
            PhotoUploadBatchPolicy.uploadFailureMessage(successfulCount: 0, totalCount: 2),
            "Photo upload failed. Please try again."
        )
        XCTAssertEqual(
            PhotoUploadBatchPolicy.uploadFailureMessage(successfulCount: 2, totalCount: 3),
            "Uploaded 2 of 3 photos. 1 photo failed. Try again."
        )
    }
}
