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


final class EditEntrySavePolicyTests: XCTestCase {
    func testEditEntryCanRetryAfterPreviousErrorWhenCurrentValueIsValid() {
        XCTAssertTrue(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: nil,
            value: "20"
        ))
    }

    func testEditEntrySaveIsBlockedForCurrentValidationErrorSavingOrBlankValue() {
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: "Enter percentage between 3 and 60",
            value: "99"
        ))
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: true,
            validationMessage: nil,
            value: "20"
        ))
        XCTAssertFalse(EditEntrySavePolicy.canAttemptSave(
            isSaving: false,
            validationMessage: nil,
            value: "   "
        ))
    }

    func testAddEntrySheetPresentationMatchesExistingSaveAndDismissRules() {
        XCTAssertEqual(
            NativeSheetPresentationPolicy.detents(for: .addEntry),
            [.medium, .large]
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.dragIndicator(for: .addEntry),
            .visible
        )
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomGrabber(.addEntry))
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomDimOverlay(.addEntry))
        XCTAssertTrue(NativeSheetPresentationPolicy.usesNativeNavigationChrome(.addEntry))

        XCTAssertEqual(
            NativeSheetPresentationPolicy.canDismissAddEntry(isSaving: false, isProcessing: false),
            PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: false)
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.canDismissAddEntry(isSaving: true, isProcessing: false),
            PhotoUploadBatchPolicy.canDismiss(isSaving: true, isProcessing: false)
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.canDismissAddEntry(isSaving: false, isProcessing: true),
            PhotoUploadBatchPolicy.canDismiss(isSaving: false, isProcessing: true)
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.canDismissAfterPhotoUpload(successfulCount: 3, totalCount: 3),
            PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 3, totalCount: 3)
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.canDismissAfterPhotoUpload(successfulCount: 2, totalCount: 3),
            PhotoUploadBatchPolicy.shouldDismissAfterUpload(successfulCount: 2, totalCount: 3)
        )
    }

    func testAddMedicationAndBugReportUseNativeSheetChrome() {
        XCTAssertEqual(
            NativeSheetPresentationPolicy.detents(for: .addMedication),
            [.medium, .large]
        )
        XCTAssertEqual(
            NativeSheetPresentationPolicy.detents(for: .bugReportPrompt),
            [.medium]
        )
        XCTAssertTrue(NativeSheetPresentationPolicy.detents(for: .bugReportForm).isEmpty)
        XCTAssertTrue(NativeSheetPresentationPolicy.usesNativeNavigationChrome(.bugReportForm))
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomGrabber(.bugReportPrompt))
    }
}
