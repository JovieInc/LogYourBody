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
