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


final class ValidationServiceTests: XCTestCase {
    func testWeightBoundariesAreInclusiveForPoundsAndKilograms() throws {
        let service = ValidationService.shared

        XCTAssertEqual(try service.validateWeight("70", unit: "lbs"), 70)
        XCTAssertEqual(try service.validateWeight("660", unit: "lbs"), 660)
        XCTAssertEqual(try service.validateWeight("32", unit: "kg"), 32)
        XCTAssertEqual(try service.validateWeight("300", unit: "kg"), 300)

        assertValidationError(
            try service.validateWeight("69.9", unit: "lbs"),
            expectedMessage: "Enter a weight between 70 and 660 lbs"
        )
        assertValidationError(
            try service.validateWeight("660.1", unit: "lbs"),
            expectedMessage: "Enter a weight between 70 and 660 lbs"
        )
        assertValidationError(
            try service.validateWeight("31.9", unit: "kg"),
            expectedMessage: "Enter a weight between 32 and 300 kg"
        )
        assertValidationError(
            try service.validateWeight("300.1", unit: "kg"),
            expectedMessage: "Enter a weight between 32 and 300 kg"
        )
    }

    func testBodyFatBoundariesAreInclusive() throws {
        let service = ValidationService.shared

        XCTAssertEqual(try service.validateBodyFat("3"), 3)
        XCTAssertEqual(try service.validateBodyFat("60"), 60)

        assertValidationError(
            try service.validateBodyFat("2.9"),
            expectedMessage: "Body fat must be between 3-60%"
        )
        assertValidationError(
            try service.validateBodyFat("60.1"),
            expectedMessage: "Body fat must be between 3-60%"
        )
    }

    func testDecimalCommaIsAValidWeightBodyFatAndHeight() throws {
        let service = ValidationService.shared

        XCTAssertEqual(try service.validateWeight("80,5", unit: "kg"), 80.5, accuracy: 0.001)
        XCTAssertEqual(try service.validateWeight("150,5", unit: "lbs"), 150.5, accuracy: 0.001)
        XCTAssertEqual(try service.validateBodyFat("18,5"), 18.5, accuracy: 0.001)
        XCTAssertEqual(try service.validateHeight("178,5", unit: "cm"), 178.5, accuracy: 0.001)

        let logged = LogWeightFormValidator.validate(weight: "80,5", bodyFat: "18,5", unit: "kg")
        XCTAssertEqual(logged.weightValue ?? -1, 80.5, accuracy: 0.001)
        XCTAssertEqual(logged.bodyFatValue ?? -1, 18.5, accuracy: 0.001)
        XCTAssertNil(logged.weightError)
        XCTAssertNil(logged.bodyFatError)
        XCTAssertTrue(logged.isValid)
        XCTAssertTrue(PaidWeightLoggerMVPPolicy.canSaveWeight(weightText: "80,5", unit: "kg", isSaving: false))
    }

    func testRejectsBadNumericStrings() {
        let service = ValidationService.shared

        assertValidationError(
            try service.validateWeight("abc", unit: "lbs"),
            expectedMessage: "Please enter a valid number"
        )
        assertValidationError(
            try service.validateWeight("1..2", unit: "kg"),
            expectedMessage: "Please enter a valid number"
        )
        assertValidationError(
            try service.validateBodyFat("not a percentage"),
            expectedMessage: "Please enter a valid percentage"
        )
        assertValidationError(
            try service.validateBodyFat("5..0"),
            expectedMessage: "Please enter a valid percentage"
        )
    }

    private func assertValidationError<T>(
        _ expression: @autoclosure () throws -> T,
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual((error as? ValidationError)?.errorDescription, expectedMessage, file: file, line: line)
        }
    }
}
