import XCTest
@testable import LogYourBody

final class ProfileSettingsPolicyTests: XCTestCase {
    // MARK: - joinedDisplayName

    func testJoinedDisplayNameCombinesFirstAndLast() {
        XCTAssertEqual(
            ProfileSettingsPolicy.joinedDisplayName(first: "John", last: "Doe"),
            "John Doe"
        )
    }

    func testJoinedDisplayNameDropsEmptySide() {
        XCTAssertEqual(ProfileSettingsPolicy.joinedDisplayName(first: "John", last: ""), "John")
        XCTAssertEqual(ProfileSettingsPolicy.joinedDisplayName(first: "", last: "Doe"), "Doe")
    }

    func testJoinedDisplayNameTrimsWhitespaceAndDropsBlankParts() {
        XCTAssertEqual(
            ProfileSettingsPolicy.joinedDisplayName(first: "  John  ", last: "   "),
            "John"
        )
        XCTAssertEqual(ProfileSettingsPolicy.joinedDisplayName(first: "   ", last: "  "), "")
    }

    func testJoinedDisplayNamePreservesInternalSpaces() {
        XCTAssertEqual(
            ProfileSettingsPolicy.joinedDisplayName(first: "Mary Jane", last: "Watson"),
            "Mary Jane Watson"
        )
    }

    // MARK: - displayNameBase

    func testDisplayNameBasePrefersStoredName() {
        XCTAssertEqual(
            ProfileSettingsPolicy.displayNameBase(name: "John Doe", email: "john@example.com"),
            "John Doe"
        )
    }

    func testDisplayNameBaseFallsBackToEmailLocalPart() {
        XCTAssertEqual(
            ProfileSettingsPolicy.displayNameBase(name: "", email: "jane.doe+tag@example.com"),
            "jane.doe+tag"
        )
    }

    func testDisplayNameBaseHandlesEmailWithoutAtSign() {
        XCTAssertEqual(ProfileSettingsPolicy.displayNameBase(name: "", email: "localpart"), "localpart")
        XCTAssertEqual(ProfileSettingsPolicy.displayNameBase(name: "", email: ""), "")
    }

    // MARK: - splitDisplayName

    func testSplitDisplayNameSplitsOnFirstWord() {
        let parts = ProfileSettingsPolicy.splitDisplayName("Mary Jane Watson")
        XCTAssertEqual(parts.first, "Mary")
        XCTAssertEqual(parts.last, "Jane Watson")
    }

    func testSplitDisplayNameHandlesSingleWordAndEmpty() {
        XCTAssertEqual(ProfileSettingsPolicy.splitDisplayName("John").first, "John")
        XCTAssertEqual(ProfileSettingsPolicy.splitDisplayName("John").last, "")

        let empty = ProfileSettingsPolicy.splitDisplayName("")
        XCTAssertEqual(empty.first, "")
        XCTAssertEqual(empty.last, "")
    }

    func testSplitDisplayNameCollapsesRepeatedSpaces() {
        let parts = ProfileSettingsPolicy.splitDisplayName("  John   Doe  ")
        XCTAssertEqual(parts.first, "John")
        XCTAssertEqual(parts.last, "Doe")
    }

    // MARK: - formattedHeight

    func testFormattedHeightMetric() {
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 170, useMetric: true), "170 cm")
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 100, useMetric: true), "100 cm")
    }

    func testFormattedHeightImperialTruncatesToWholeInches() {
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 170, useMetric: false), "5'6\"")
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 183, useMetric: false), "6'0\"")
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 152, useMetric: false), "4'11\"")
    }

    // MARK: - formattedAge

    private func makeFixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to build date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    func testFormattedAgeCountsWholeYears() {
        let calendar = makeFixedCalendar()
        let now = makeDate(2_026, 7, 20, calendar: calendar)
        let dob = makeDate(2_000, 7, 20, calendar: calendar)
        XCTAssertEqual(
            ProfileSettingsPolicy.formattedAge(dateOfBirth: dob, now: now, calendar: calendar),
            "26 years"
        )
    }

    func testFormattedAgeDoesNotRoundUpBeforeBirthday() {
        let calendar = makeFixedCalendar()
        let now = makeDate(2_026, 7, 20, calendar: calendar)
        let dob = makeDate(2_000, 7, 21, calendar: calendar)
        XCTAssertEqual(
            ProfileSettingsPolicy.formattedAge(dateOfBirth: dob, now: now, calendar: calendar),
            "25 years"
        )
    }

    func testFormattedAgeShowsNotSetForZeroOrFutureDates() {
        let calendar = makeFixedCalendar()
        let now = makeDate(2_026, 7, 20, calendar: calendar)
        XCTAssertEqual(
            ProfileSettingsPolicy.formattedAge(dateOfBirth: now, now: now, calendar: calendar),
            "Not set"
        )
        let future = makeDate(2_027, 7, 20, calendar: calendar)
        XCTAssertEqual(
            ProfileSettingsPolicy.formattedAge(dateOfBirth: future, now: now, calendar: calendar),
            "Not set"
        )
    }

    // MARK: - Imperial picker conversions

    func testImperialHeightComponents() {
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 170).feet, 5)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 170).inches, 6)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 183).feet, 6)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 183).inches, 0)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 213).feet, 6)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 213).inches, 11)
    }

    func testHeightCmFromImperialComponents() {
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 5, inches: 6), 167)
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 6, inches: 0), 182)
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 4, inches: 11), 149)
    }
}
