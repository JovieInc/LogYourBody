import XCTest
@testable import LogYourBody

final class ProfileSettingsPolicyTests: XCTestCase {
    func testBirthdayAgeChangesOnTheLocalBirthdayAcrossTimeZones() throws {
        let birthday = try XCTUnwrap(ProfileBirthDatePolicy.date(year: 2_008))
        for zone in ["America/Los_Angeles", "Pacific/Honolulu", "Europe/London", "Asia/Tokyo", "Pacific/Kiritimati"] {
            let calendar = try birthDateCalendar(zone)
            let before = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2_026, month: 12, day: 31, hour: 23, minute: 59)))
            let onBirthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_027, month: 1, day: 1)))
            XCTAssertEqual(ProfileBirthDatePolicy.age(from: birthday, now: before, localCalendar: calendar), 18, zone)
            XCTAssertEqual(ProfileBirthDatePolicy.age(from: birthday, now: onBirthday, localCalendar: calendar), 19, zone)
            XCTAssertEqual(
                ProfileSettingsPolicy.formattedAge(dateOfBirth: birthday, now: before, calendar: calendar),
                "18 years", zone
            )
        }
    }

    func testBirthdayValidationDoesNotAdmitAnUnderageUserBeforeTheirLocalBirthday() throws {
        let birthday = try XCTUnwrap(ProfileBirthDatePolicy.date(year: 2_010))
        let calendar = try birthDateCalendar("America/Los_Angeles")
        let before = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2_025, month: 12, day: 31, hour: 18)))
        let onBirthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 1, day: 1)))
        XCTAssertFalse(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(
            birthday, now: before, calendar: calendar))
        XCTAssertTrue(ProfileDetailsValidationPolicy.isDateOfBirthWithinValidRange(
            birthday, now: onBirthday, calendar: calendar))
    }

    func testBirthdayPresentationAndBirthYearPreserveTheAPIJanFirstDate() throws {
        let birthday = try XCTUnwrap(ISO8601DateFormatter().date(from: "1990-01-01T00:00:00Z"))
        XCTAssertEqual(ProfileBirthDatePolicy.year(from: birthday), 1_990)
        XCTAssertEqual(
            ProfileBirthDatePolicy.formatted(birthday, locale: Locale(identifier: "en_US")),
            "Jan 1, 1990"
        )
        XCTAssertEqual(
            ProfileBirthDatePolicy.formatted(birthday, style: .long, locale: Locale(identifier: "en_US")),
            "January 1, 1990"
        )
    }

    func testBirthdayPickerCalendarRoundTripsThroughTheActualProfilePayload() throws {
        let pickerCalendar = ProfileBirthDatePolicy.calendar
        for components in [
            DateComponents(year: 1_990, month: 1, day: 1),
            DateComponents(year: 2_000, month: 2, day: 29),
            DateComponents(year: 2_004, month: 12, day: 31)
        ] {
            let selected = try XCTUnwrap(pickerCalendar.date(from: components))
            let payload = try ProductAPIClient.firstPartyProfilePatchBody(["dateOfBirth": selected])
            let day = try XCTUnwrap(payload["dateOfBirth"] as? String)
            let expected = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
            XCTAssertEqual(day, expected)
            let decoded = try XCTUnwrap(AuthManager.parseProductProfileDate(day))
            let decodedComponents = pickerCalendar.dateComponents([.year, .month, .day], from: decoded)
            XCTAssertEqual(decodedComponents.year, components.year)
            XCTAssertEqual(decodedComponents.month, components.month)
            XCTAssertEqual(decodedComponents.day, components.day)
        }
    }

    func testBirthdayTodayBoundaryUsesTheLocalDayOnEitherSideOfTheDateLine() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-01T03:00:00Z"))
        for (zone, expected) in [("America/Los_Angeles", "Dec 31, 2025"), ("Asia/Tokyo", "Jan 1, 2026")] {
            let today = ProfileBirthDatePolicy.today(now: now, localCalendar: try birthDateCalendar(zone))
            XCTAssertEqual(ProfileBirthDatePolicy.formatted(today, locale: Locale(identifier: "en_US")), expected)
        }
    }

    func testBirthdayAgeUsesGregorianYearsWithANonGregorianUserCalendar() throws {
        let birthday = try XCTUnwrap(ProfileBirthDatePolicy.date(year: 2_000))
        let gregorian = try birthDateCalendar("Asia/Bangkok")
        let now = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2_026, month: 1, day: 1)))
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = gregorian.timeZone
        XCTAssertEqual(ProfileBirthDatePolicy.age(from: birthday, now: now, localCalendar: buddhist), 26)
    }

    func testBirthdayAgeRetainsLeapDayAndIgnoresLegacyTimestampTimeOfDay() throws {
        let birthday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-02-29T18:20:00Z"))
        let calendar = try birthDateCalendar("America/Los_Angeles")
        for (year, month, day, expected) in [(2_024, 2, 28, 23), (2_024, 2, 29, 24), (2_025, 3, 1, 25)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
            XCTAssertEqual(ProfileBirthDatePolicy.age(from: birthday, now: now, localCalendar: calendar), expected)
        }
    }

    private func birthDateCalendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

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

    func testFormattedHeightImperialRoundsToNearestInch() {
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 170, useMetric: false), "5'7\"")
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 183, useMetric: false), "6'0\"")
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 152, useMetric: false), "5'0\"")
    }

    func testStoredHeightRejectsInvalidAndUnrepresentableValuesWithoutInventingAHeight() {
        for height in [Double.nan, .infinity, -.infinity, 0, -170, 0.1, 1e20, Double(Int.max)] {
            XCTAssertNil(ProfileSettingsPolicy.roundedStoredHeight(height))
            XCTAssertNil(ProfileSettingsPolicy.storedHeightText(height, useMetric: true))
            XCTAssertNil(ProfileSettingsPolicy.storedHeightText(height, useMetric: false))
        }
        XCTAssertNil(ProfileSettingsPolicy.roundedStoredHeight(nil))
    }

    func testStoredHeightPreservesDisplayRoundingAndImperialSpacing() {
        XCTAssertEqual(ProfileSettingsPolicy.storedHeightText(170.4, useMetric: true), "170 cm")
        XCTAssertEqual(ProfileSettingsPolicy.storedHeightText(182.8, useMetric: true), "183 cm")
        XCTAssertEqual(ProfileSettingsPolicy.storedHeightText(182.8, useMetric: false), "6'0\"")
        XCTAssertEqual(ProfileSettingsPolicy.storedHeightText(170, useMetric: false), "5'7\"")
        XCTAssertEqual(ProfileSettingsPolicy.storedHeightText(170, useMetric: false, spaces: true), "5' 7\"")
    }

    func testHeightEditorSeedPreservesValidStoredHeights() {
        for height in [Double.nan, .infinity, -.infinity, -1, 0, 1e20, Double(Int.max)] {
            XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(height), 170)
        }
        XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(nil), 170)
        XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(100), 100)
        XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(182.8), 183)
        XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(250), 250)
        for height in [50, 91, 99, 251, 259, 272, 275] {
            XCTAssertEqual(ProfileSettingsPolicy.heightEditorSeed(Double(height)), height)
        }
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
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 170).inches, 7)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 183).feet, 6)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 183).inches, 0)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 213).feet, 7)
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 213).inches, 0)
    }

    func testHeightCmFromImperialComponents() {
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 5, inches: 6), 168)
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 6, inches: 0), 183)
        XCTAssertEqual(ProfileSettingsPolicy.heightCm(feet: 4, inches: 11), 150)
    }

    func testImperialHeightWheelRoundTripsAndMatchesNearestInch() {
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 170, useMetric: false), "5'7\"")
        XCTAssertEqual(ProfileSettingsPolicy.imperialHeightComponents(heightCm: 170).inches, 7)
        XCTAssertEqual(ProfileSettingsPolicy.formattedHeight(heightCm: 213, useMetric: false), "7'0\"")

        let sixFeet = ProfileSettingsPolicy.heightCm(feet: 6, inches: 0)
        let shown = ProfileSettingsPolicy.imperialHeightComponents(heightCm: sixFeet)
        XCTAssertEqual(shown.feet, 6)
        XCTAssertEqual(shown.inches, 0)

        for feet in 3...8 {
            for inches in 0...11 {
                let centimeters = ProfileSettingsPolicy.heightCm(feet: feet, inches: inches)
                let components = ProfileSettingsPolicy.imperialHeightComponents(heightCm: centimeters)
                XCTAssertEqual(
                    components.feet,
                    feet,
                    "\(feet) ft \(inches) in stored \(centimeters) cm and came back as \(components.feet) ft \(components.inches) in"
                )
                XCTAssertEqual(
                    components.inches,
                    inches,
                    "\(feet) ft \(inches) in stored \(centimeters) cm and came back as \(components.feet) ft \(components.inches) in"
                )
                XCTAssertEqual(
                    ProfileSettingsPolicy.formattedHeight(heightCm: centimeters, useMetric: false),
                    "\(feet)'\(inches)\""
                )
            }
        }
    }
}
