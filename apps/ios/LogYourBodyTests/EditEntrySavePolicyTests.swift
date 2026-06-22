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
}
