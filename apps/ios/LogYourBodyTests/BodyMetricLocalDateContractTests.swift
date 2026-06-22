//
// BodyMetricContractTests.swift
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


final class BodyMetricLocalDateContractTests: XCTestCase {
    func testLocalDateCapturesDeviceCalendarDayNearMidnight() throws {
        let losAngeles = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let newYork = try makeCalendar(timeZoneIdentifier: "America/New_York")

        let losAngelesLateNight = try makeDate(
            year: 2_026,
            month: 6,
            day: 9,
            hour: 23,
            minute: 58,
            calendar: losAngeles
        )
        let newYorkLateNight = try makeDate(
            year: 2_026,
            month: 6,
            day: 9,
            hour: 23,
            minute: 58,
            calendar: newYork
        )

        XCTAssertEqual(BodyMetricLocalDate.key(for: losAngelesLateNight, calendar: losAngeles), "2026-06-09")
        XCTAssertEqual(BodyMetricLocalDate.key(for: newYorkLateNight, calendar: newYork), "2026-06-09")
        XCTAssertEqual(BodyMetricLocalDate.key(for: losAngelesLateNight, calendar: newYork), "2026-06-10")
    }

    func testLocalDateCaptures2358AcrossUtcOffsetRange() throws {
        for offsetHours in -12...14 {
            let calendar = try makeCalendar(secondsFromGMT: offsetHours * 3_600)
            let lateNight = try makeDate(
                year: 2_026,
                month: 6,
                day: 9,
                hour: 23,
                minute: 58,
                calendar: calendar
            )
            let label = offsetHours >= 0 ? "UTC+\(offsetHours)" : "UTC\(offsetHours)"

            XCTAssertEqual(
                BodyMetricLocalDate.key(for: lateNight, calendar: calendar),
                "2026-06-09",
                "\(label) should keep the user's 23:58 local calendar day"
            )

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lateNight)
            XCTAssertEqual(components.year, 2_026, label)
            XCTAssertEqual(components.month, 6, label)
            XCTAssertEqual(components.day, 9, label)
            XCTAssertEqual(components.hour, 23, label)
            XCTAssertEqual(components.minute, 58, label)
        }
    }

    func testStartOfDayUsesStoredLocalDateAfterTimezoneChange() throws {
        let tokyo = try makeCalendar(timeZoneIdentifier: "Asia/Tokyo")
        let startOfDay = try XCTUnwrap(BodyMetricLocalDate.startOfDay(for: "2026-06-09", calendar: tokyo))
        let components = tokyo.dateComponents([.year, .month, .day], from: startOfDay)

        XCTAssertEqual(components.year, 2_026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 9)
    }

    func testBodyMetricsRoundTripsLocalDateToSupabaseKey() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let loggedAt = try makeDate(year: 2_026, month: 6, day: 9, hour: 23, minute: 58, calendar: calendar)
        let metric = makeMetric(date: loggedAt, localDate: "2026-06-09")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metric)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["local_date"] as? String, "2026-06-09")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BodyMetrics.self, from: data)

        XCTAssertEqual(decoded.localDate, "2026-06-09")
    }

    func testBodyMetricsFallbackNormalizesInvalidLocalDate() throws {
        let calendar = try makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let loggedAt = try makeDate(year: 2_026, month: 6, day: 9, hour: 23, minute: 58, calendar: calendar)
        let metric = makeMetric(date: loggedAt, localDate: "not-a-date")

        XCTAssertEqual(metric.localDate, BodyMetricLocalDate.key(for: loggedAt))
    }

    func testVisibilityConflictResolutionCollapsesSameStoredLocalDay() throws {
        let userId = "local-date-user"
        let older = makeMetric(
            id: "older",
            userId: userId,
            date: try makeDate(
                year: 2_026,
                month: 6,
                day: 9,
                hour: 23,
                minute: 58,
                calendar: makeCalendar(timeZoneIdentifier: "America/Los_Angeles")
            ),
            localDate: "2026-06-09",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeMetric(
            id: "newer",
            userId: userId,
            date: try makeDate(
                year: 2_026,
                month: 6,
                day: 10,
                hour: 1,
                minute: 15,
                calendar: makeCalendar(timeZoneIdentifier: "America/New_York")
            ),
            localDate: "2026-06-09",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let visible = EntryVisibilityManager.shared.resolvedVisibleMetrics([older, newer], userId: userId)

        XCTAssertEqual(visible.map(\.id), ["newer"])
    }

    private func makeMetric(
        id: String = UUID().uuidString,
        userId: String = "user",
        date: Date,
        localDate: String?,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            localDate: localDate,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }

    private func makeCalendar(timeZoneIdentifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneIdentifier))
        return calendar
    }

    private func makeCalendar(secondsFromGMT: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: secondsFromGMT))
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
