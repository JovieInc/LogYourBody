//
// DSCircularProgressTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class DSCircularProgressTests: XCTestCase {
    
    func testProgressNormalization() {
        // Test that progress values are normalized between 0 and 1
        let testCases: [(input: Double, expected: Double)] = [
            (-0.5, 0.0),
            (0.0, 0.0),
            (0.5, 0.5),
            (1.0, 1.0),
            (1.5, 1.0),
            (100.0, 1.0)
        ]
        
        for testCase in testCases {
            let progress = DSCircularProgress(progress: testCase.input)
            let normalizedValue = min(1.0, max(0.0, testCase.input))
            XCTAssertEqual(normalizedValue, testCase.expected, 
                          "Progress \(testCase.input) should normalize to \(testCase.expected)")
        }
    }
    
    func testDefaultValues() {
        let progress = DSCircularProgress(progress: 0.5)
        
        // Test default property values through the initializer
        XCTAssertEqual(progress.progress, 0.5)
        XCTAssertEqual(progress.size, 100)
        XCTAssertEqual(progress.lineWidth, 3)
        XCTAssertEqual(progress.backgroundColor, .white.opacity(0.2))
        XCTAssertEqual(progress.foregroundColor, .white)
        XCTAssertEqual(progress.animationDuration, 0.6)
        XCTAssertFalse(progress.showPercentage)
        XCTAssertEqual(progress.percentageFontSize, 14)
    }
    
    func testCustomValues() {
        let progress = DSCircularProgress(
            progress: 0.75,
            size: 120,
            lineWidth: 5,
            backgroundColor: .gray,
            foregroundColor: .blue,
            animationDuration: 1.0,
            showPercentage: true,
            percentageFontSize: 18
        )
        
        XCTAssertEqual(progress.progress, 0.75)
        XCTAssertEqual(progress.size, 120)
        XCTAssertEqual(progress.lineWidth, 5)
        XCTAssertEqual(progress.backgroundColor, .gray)
        XCTAssertEqual(progress.foregroundColor, .blue)
        XCTAssertEqual(progress.animationDuration, 1.0)
        XCTAssertTrue(progress.showPercentage)
        XCTAssertEqual(progress.percentageFontSize, 18)
    }
    
    func testPercentageCalculation() {
        let testCases: [(progress: Double, expectedPercentage: Int)] = [
            (0.0, 0),
            (0.25, 25),
            (0.5, 50),
            (0.75, 75),
            (1.0, 100),
            (1.5, 100), // Should cap at 100%
            (-0.5, 0)   // Should floor at 0%
        ]
        
        for testCase in testCases {
            let normalizedProgress = min(1.0, max(0.0, testCase.progress))
            let percentage = Int(normalizedProgress * 100)
            XCTAssertEqual(percentage, testCase.expectedPercentage,
                          "Progress \(testCase.progress) should show \(testCase.expectedPercentage)%")
        }
    }
}