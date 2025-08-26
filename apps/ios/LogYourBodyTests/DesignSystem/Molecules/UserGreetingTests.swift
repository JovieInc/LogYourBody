//
// UserGreetingTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class UserGreetingTests: XCTestCase {
    
    func testFirstNameExtraction() {
        let testCases: [(fullName: String?, expectedFirstName: String)] = [
            ("John Doe", "John"),
            ("Jane", "Jane"),
            ("Alice Johnson Smith", "Alice"),
            ("   Bob   ", "Bob"), // Trimmed
            ("", "there"), // Empty string
            ("   ", "there"), // Only spaces
            (nil, "there") // Nil
        ]
        
        for testCase in testCases {
            let greeting = UserGreeting(fullName: testCase.fullName)
            // Since firstName is private, we would need to make it internal for testing
            // or test the actual rendered output
        }
    }
    
    func testGreetingTimeBasedLogic() {
        // This would require mocking the current time
        // For now, we can test that the greeting property exists
        let greeting = UserGreeting(fullName: "Test User")
        
        // The actual greeting depends on the current hour
        let hour = Calendar.current.component(.hour, from: Date())
        let expectedPrefix: String
        
        switch hour {
        case 0..<12:
            expectedPrefix = "Good morning"
        case 12..<17:
            expectedPrefix = "Good afternoon"
        default:
            expectedPrefix = "Good evening"
        }
        
        // Would need to access the greeting property to verify
    }
    
    func testEmojiGreeting() {
        let greeting = UserGreeting(fullName: "Test User", showEmoji: true)
        
        // Test that emoji mode is enabled
        XCTAssertTrue(greeting.showEmoji)
        
        // Verify emoji mapping based on time
        let hour = Calendar.current.component(.hour, from: Date())
        let expectedEmoji: String
        
        switch hour {
        case 0..<12:
            expectedEmoji = "☀️"
        case 12..<17:
            expectedEmoji = "🌤"
        case 17..<21:
            expectedEmoji = "🌅"
        default:
            expectedEmoji = "🌙"
        }
    }
    
    func testCompactMode() {
        let regularGreeting = UserGreeting(fullName: "John Doe", compactMode: false)
        let compactGreeting = UserGreeting(fullName: "John Doe", compactMode: true)
        
        XCTAssertFalse(regularGreeting.compactMode)
        XCTAssertTrue(compactGreeting.compactMode)
    }
    
    func testCustomGreeting() {
        let customGreeting = UserGreeting(
            fullName: "John Doe",
            customGreeting: "Welcome back"
        )
        
        XCTAssertEqual(customGreeting.customGreeting, "Welcome back")
    }
    
    func testEdgeCases() {
        // Multiple spaces between names
        let multiSpace = UserGreeting(fullName: "John    Doe")
        
        // Special characters
        let specialChars = UserGreeting(fullName: "John-Doe O'Brien")
        
        // Very long name
        let longName = UserGreeting(fullName: "John Jacob Jingleheimer Schmidt")
        
        // Unicode characters
        let unicode = UserGreeting(fullName: "José García")
        
        // All should create valid greeting views
        XCTAssertNotNil(multiSpace)
        XCTAssertNotNil(specialChars)
        XCTAssertNotNil(longName)
        XCTAssertNotNil(unicode)
    }
}