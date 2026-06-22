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


final class LogWeightFormValidatorTests: XCTestCase {
    func testRejectsOutOfRangeWeightValues() {
        let zeroPounds = LogWeightFormValidator.validate(weight: "0", bodyFat: "", unit: "lbs")
        XCTAssertFalse(zeroPounds.isValid)
        XCTAssertEqual(zeroPounds.weightError, "Enter a weight between 70 and 660 lbs")
        XCTAssertNil(zeroPounds.weightValue)

        let extremePounds = LogWeightFormValidator.validate(weight: "999", bodyFat: "", unit: "lbs")
        XCTAssertFalse(extremePounds.isValid)
        XCTAssertEqual(extremePounds.weightError, "Enter a weight between 70 and 660 lbs")
        XCTAssertNil(extremePounds.weightValue)
    }

    func testRejectsOutOfRangeBodyFatValues() {
        let tooLow = LogWeightFormValidator.validate(weight: "", bodyFat: "1", unit: "lbs")
        XCTAssertFalse(tooLow.isValid)
        XCTAssertEqual(tooLow.bodyFatError, "Body fat must be between 3-60%")
        XCTAssertNil(tooLow.bodyFatValue)

        let tooHigh = LogWeightFormValidator.validate(weight: "", bodyFat: "60.1", unit: "lbs")
        XCTAssertFalse(tooHigh.isValid)
        XCTAssertEqual(tooHigh.bodyFatError, "Body fat must be between 3-60%")
        XCTAssertNil(tooHigh.bodyFatValue)
    }

    func testAllowsValidWeightAndBodyFat() {
        let validation = LogWeightFormValidator.validate(weight: "175", bodyFat: "18", unit: "lbs")

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.weightValue, 175)
        XCTAssertEqual(validation.bodyFatValue, 18)
        XCTAssertNil(validation.weightError)
        XCTAssertNil(validation.bodyFatError)
        XCTAssertNil(validation.formError)
    }

    func testRequiresAtLeastOneMeasurement() {
        let validation = LogWeightFormValidator.validate(weight: " ", bodyFat: "", unit: "lbs")

        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.formError, "Please enter at least one measurement")
    }

    func testRoutesFieldAndSubmitValidationThroughValidationService() throws {
        let expectedWeight = try ValidationService.shared.validateWeight("175.04", unit: "lbs")
        let expectedBodyFat = try ValidationService.shared.validateBodyFat("18.04")

        let validation = LogWeightFormValidator.validate(weight: "175.04", bodyFat: "18.04", unit: "lbs")

        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.weightValue, expectedWeight)
        XCTAssertEqual(validation.bodyFatValue, expectedBodyFat)
        XCTAssertNil(validation.weightError)
        XCTAssertNil(validation.bodyFatError)

        let expectedKgError = validationErrorDescription {
            _ = try ValidationService.shared.validateWeight("300.1", unit: "kg")
        }
        let expectedBodyFatError = validationErrorDescription {
            _ = try ValidationService.shared.validateBodyFat("60.1")
        }

        XCTAssertEqual(
            LogWeightFormValidator.fieldError(for: "300.1", field: .weight, unit: "kg"),
            expectedKgError
        )
        XCTAssertEqual(
            LogWeightFormValidator.fieldError(for: "60.1", field: .bodyFat, unit: "kg"),
            expectedBodyFatError
        )
    }

    private func validationErrorDescription(_ expression: () throws -> Void) -> String? {
        do {
            try expression()
            XCTFail("Expected validation to fail")
            return nil
        } catch let error as ValidationError {
            return error.errorDescription
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}
