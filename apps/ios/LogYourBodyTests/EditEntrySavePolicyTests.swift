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
    @MainActor
    func testPrefilledBodyFatKeepsEverySupportedMethod() {
        for method in BodyFatEntryMethod.allCases {
            let sheet = AddEntrySheet(
                isPresented: .constant(true), initialTab: 1,
                initialBodyFat: 18, initialBodyFatMethod: method.rawValue
            )
            XCTAssertEqual(sheet.bodyFat, "18.0")
            XCTAssertEqual(sheet.bodyFatMethod, method.rawValue)
            XCTAssertFalse(BodyFatEntryMethod.needsPreservedOption(sheet.bodyFatMethod))
        }
    }

    @MainActor
    func testPrefilledBodyFatPreservesMissingAndUnsupportedMethodsWithoutGuessing() {
        let methods: [String?] = [nil, "", "healthkit", "apple_health", "future_method", "not dexa"]
        for method in methods {
            let sheet = AddEntrySheet(
                isPresented: .constant(true), initialTab: 1,
                initialBodyFat: 18, initialBodyFatMethod: method
            )
            XCTAssertEqual(sheet.bodyFatMethod, method, "Opaque provenance must remain byte-for-byte unchanged")
            XCTAssertTrue(BodyFatEntryMethod.needsPreservedOption(sheet.bodyFatMethod))
            XCTAssertEqual(BodyFatEntryMethod.selectionTitle(sheet.bodyFatMethod), "Method not specified")
        }
    }

    @MainActor
    func testPrefilledBodyFatRetainsTypedAndKnownLegacyMethodBytes() {
        let methods = [
            ("manual", "Entered by you"), ("typed", "Entered by you"), ("DEXA", "DEXA"),
            (" dexa (BodySpec) ", "DEXA"), ("inbody", "InBody"),
            ("bioelectrical", "Bioelectrical"), ("calipers", "Calipers")
        ]
        for (method, title) in methods {
            let sheet = AddEntrySheet(
                isPresented: .constant(true), initialTab: 1,
                initialBodyFat: 18, initialBodyFatMethod: method
            )
            XCTAssertEqual(sheet.bodyFatMethod, method)
            XCTAssertEqual(BodyFatEntryMethod.selectionTitle(sheet.bodyFatMethod), title)
            XCTAssertTrue(BodyFatEntryMethod.needsPreservedOption(sheet.bodyFatMethod))
        }
    }

    @MainActor
    func testBlankBodyFatEntryKeepsTheExistingVisualEstimateDefault() {
        let sheet = AddEntrySheet(
            isPresented: .constant(true), initialTab: 1,
            initialBodyFat: nil, initialBodyFatMethod: "dexa"
        )
        XCTAssertEqual(sheet.bodyFat, "")
        XCTAssertEqual(sheet.bodyFatMethod, BodyFatEntryMethod.visualEstimate.rawValue)
        XCTAssertEqual(BodyFatEntryMethod.selectionTitle(sheet.bodyFatMethod), "Visual Estimate")
    }
}
