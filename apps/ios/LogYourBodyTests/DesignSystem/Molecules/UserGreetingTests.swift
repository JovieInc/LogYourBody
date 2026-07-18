//
// UserGreetingTests.swift
// LogYourBodyTests
//
import XCTest
import SwiftUI
@testable import LogYourBody

final class UserGreetingTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(atHour hour: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: 2_026, month: 1, day: 1, hour: hour))!
    }

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
            XCTAssertEqual(UserGreeting.firstName(from: testCase.fullName), testCase.expectedFirstName)
        }
    }

    func testGreetingTimeBasedLogic() {
        let testCases: [(hour: Int, expected: String)] = [
            (0, "Good morning"),
            (11, "Good morning"),
            (12, "Good afternoon"),
            (16, "Good afternoon"),
            (17, "Good evening"),
            (23, "Good evening")
        ]

        for testCase in testCases {
            XCTAssertEqual(
                UserGreeting.greeting(
                    at: date(atHour: testCase.hour),
                    showEmoji: false,
                    customGreeting: nil,
                    calendar: utcCalendar
                ),
                testCase.expected
            )
        }
    }

    func testEmojiGreeting() {
        let testCases: [(hour: Int, expected: String)] = [
            (0, "Good morning ☀️"),
            (12, "Good afternoon 🌤"),
            (17, "Good evening 🌅"),
            (21, "Good evening 🌙")
        ]

        for testCase in testCases {
            XCTAssertEqual(
                UserGreeting.greeting(
                    at: date(atHour: testCase.hour),
                    showEmoji: true,
                    customGreeting: nil,
                    calendar: utcCalendar
                ),
                testCase.expected
            )
        }
    }

    func testCompactMode() {
        let regularGreeting = UserGreeting(fullName: "John Doe", compactMode: false)
        let compactGreeting = UserGreeting(fullName: "John Doe", compactMode: true)

        XCTAssertFalse(regularGreeting.compactMode)
        XCTAssertTrue(compactGreeting.compactMode)
    }

    func testCustomGreeting() {
        XCTAssertEqual(
            UserGreeting.greeting(
                at: date(atHour: 9),
                showEmoji: true,
                customGreeting: "Welcome back",
                calendar: utcCalendar
            ),
            "Welcome back"
        )
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

        XCTAssertEqual(UserGreeting.firstName(from: multiSpace.fullName), "John")
        XCTAssertEqual(UserGreeting.firstName(from: specialChars.fullName), "John-Doe")
        XCTAssertEqual(UserGreeting.firstName(from: longName.fullName), "John")
        XCTAssertEqual(UserGreeting.firstName(from: unicode.fullName), "José")
    }
}
