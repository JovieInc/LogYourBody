//
// DashboardTimelineAndPolicyTests.swift
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


final class PreferenceGoalValidatorTests: XCTestCase {
    func testAcceptsValidGoalValuesAtBoundaries() {
        XCTAssertEqual(
            PreferenceGoalValidator.validate("1", for: .weight),
            PreferenceGoalValidationResult(value: 1, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("3", for: .bodyFat),
            PreferenceGoalValidationResult(value: 3, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("60", for: .bodyFat),
            PreferenceGoalValidationResult(value: 60, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("10", for: .ffmi),
            PreferenceGoalValidationResult(value: 10, errorMessage: nil)
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("30", for: .ffmi),
            PreferenceGoalValidationResult(value: 30, errorMessage: nil)
        )
    }

    func testRejectsInvalidGoalValuesWithSpecificMessages() {
        XCTAssertEqual(
            PreferenceGoalValidator.validate(" ", for: .weight).errorMessage,
            "Enter a value."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("abc", for: .weight).errorMessage,
            "Enter a valid number."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("0", for: .weight).errorMessage,
            "Weight goal must be greater than 0."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("2.9", for: .bodyFat).errorMessage,
            "Body fat goal must be between 3-60%."
        )
        XCTAssertEqual(
            PreferenceGoalValidator.validate("30.1", for: .ffmi).errorMessage,
            "FFMI goal must be between 10-30."
        )
    }
}
