//
// TimelineCalculatorTests.swift
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


final class TimelineCalculatorTests: XCTestCase {
    private func makeMetric(
        id: String,
        daysAgo: Int,
        weight: Double? = 80,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BodyMetrics {
        makeMetric(
            id: id,
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            weight: weight
        )
    }

    private func makeMetric(id: String, date: Date, weight: Double? = 80) -> BodyMetrics {
        return BodyMetrics(
            id: id,
            userId: "user-1",
            date: date,
            localDate: "2024-01-01",
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func timelinePoints(
        from metrics: [BodyMetrics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimelineDataPoint] {
        TimelineCalculator.calculateTimelinePoints(from: metrics, now: now, calendar: calendar)
    }

    private func makePoint(index: Int, position: Double) -> TimelineDataPoint {
        TimelineDataPoint(
            id: "point-\(index)",
            index: index,
            date: Date(timeIntervalSince1970: Double(index) * 86_400),
            position: position,
            displayLabel: "label-\(index)",
            importance: .daily
        )
    }

    func testEmptyInputProducesNoPoints() {
        XCTAssertTrue(timelinePoints(from: []).isEmpty)
    }

    func testSingleRecentMetricMapsToDailyImportanceNearNewestPosition() {
        let now = Date()
        let calendar = Calendar.current
        let points = timelinePoints(
            from: [makeMetric(id: "m1", daysAgo: 3, now: now, calendar: calendar)],
            now: now,
            calendar: calendar
        )
        let expected = 0.3 + ((1.0 - (3.0 / 30.0)) * 0.7)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.id, "m1")
        XCTAssertEqual(points.first?.index, 0)
        XCTAssertEqual(points.first?.importance, .daily)
        XCTAssertEqual(points.first?.position ?? 0, expected)
        XCTAssertEqual(expected, 0.93, accuracy: 0.000001)
    }

    func testPacificFallbackHourKeepsCalendarDayTimelinePosition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // 2026-11-01 10:54:55Z, the merge-group failure instant: 02:54 PST after the fallback.
        let now = Date(timeIntervalSince1970: 1_793_530_495)
        // pacific fallback hour keeps calendar-day timeline position
        let metricDate = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let timeline = timelinePoints(
            from: [makeMetric(id: "fallback-hour", date: metricDate)],
            now: now,
            calendar: calendar
        )
        let days = try XCTUnwrap(calendar.dateComponents([.day], from: metricDate, to: now).day)
        let expected = 0.3 + ((1.0 - (Double(days) / 30.0)) * 0.7)

        XCTAssertEqual(days, 2)
        XCTAssertEqual(timeline.first?.importance, .daily)
        XCTAssertEqual(timeline.first?.position ?? -1, expected)
        XCTAssertGreaterThan(abs((timeline.first?.position ?? 0) - 0.93), 0.02)
    }

    func testImportanceTiersFollowAgeOfEntry() {
        let now = Date()
        let calendar = Calendar.current
        let metrics = [
            makeMetric(id: "daily", daysAgo: 2, now: now, calendar: calendar),
            makeMetric(id: "weekly", daysAgo: 15, now: now, calendar: calendar),
            makeMetric(id: "monthly", daysAgo: 100, now: now, calendar: calendar),
            makeMetric(id: "yearly", daysAgo: 500, now: now, calendar: calendar)
        ]

        let points = timelinePoints(from: metrics, now: now, calendar: calendar)
        var importanceById: [String: TimelineDataPoint.TimelineImportance] = [:]
        for point in points {
            importanceById[point.id] = point.importance
        }

        XCTAssertEqual(importanceById["daily"], .daily)
        XCTAssertEqual(importanceById["weekly"], .weekly)
        XCTAssertEqual(importanceById["monthly"], .monthly)
        XCTAssertEqual(importanceById["yearly"], .yearly)
    }

    func testPositionsIncreaseWithRecencyAndStayWithinUnitRange() {
        let now = Date()
        let calendar = Calendar.current
        let metrics = [
            makeMetric(id: "oldest", daysAgo: 500, now: now, calendar: calendar),
            makeMetric(id: "month", daysAgo: 100, now: now, calendar: calendar),
            makeMetric(id: "week", daysAgo: 15, now: now, calendar: calendar),
            makeMetric(id: "day", daysAgo: 2, now: now, calendar: calendar)
        ]

        let points = timelinePoints(from: metrics, now: now, calendar: calendar)

        XCTAssertEqual(points.map(\.id), ["oldest", "month", "week", "day"])
        for point in points {
            XCTAssertGreaterThanOrEqual(point.position, 0)
            XCTAssertLessThanOrEqual(point.position, 1)
        }
        for (previous, next) in zip(points, points.dropFirst()) {
            XCTAssertLessThan(previous.position, next.position)
        }
        XCTAssertGreaterThan(points.last?.position ?? 0, 0.9)
        XCTAssertLessThanOrEqual(points.first?.position ?? 1, 0.1)
    }

    func testDisplayLabelsReflectImportanceGranularity() {
        let now = Date()
        let calendar = Calendar.current
        let metrics = [
            makeMetric(id: "daily", daysAgo: 2, now: now, calendar: calendar),
            makeMetric(id: "monthly", daysAgo: 100, now: now, calendar: calendar),
            makeMetric(id: "yearly", daysAgo: 500, now: now, calendar: calendar)
        ]

        let points = timelinePoints(from: metrics, now: now, calendar: calendar)
        let yearlyPoint = points.first { $0.id == "yearly" }
        let monthlyPoint = points.first { $0.id == "monthly" }
        let dailyPoint = points.first { $0.id == "daily" }

        let yearlyYear = Calendar.current.component(.year, from: metrics[2].date)
        let monthlyYear = Calendar.current.component(.year, from: metrics[1].date)
        XCTAssertEqual(yearlyPoint?.displayLabel, String(yearlyYear))
        XCTAssertTrue(monthlyPoint?.displayLabel.contains(String(monthlyYear)) == true)
        XCTAssertNotEqual(dailyPoint?.displayLabel, yearlyPoint?.displayLabel)
    }

    func testFindNearestPointReturnsClosestByPosition() {
        let points = [makePoint(index: 0, position: 0.1), makePoint(index: 1, position: 0.5), makePoint(index: 2, position: 0.9)]

        XCTAssertEqual(TimelineCalculator.findNearestPoint(to: 0.95, in: points)?.index, 2)
        XCTAssertEqual(TimelineCalculator.findNearestPoint(to: 0.4, in: points)?.index, 1)
        XCTAssertEqual(TimelineCalculator.findNearestPoint(to: 0.0, in: points)?.index, 0)
        XCTAssertNil(TimelineCalculator.findNearestPoint(to: 0.5, in: []))
    }

    func testPositionAndIndexLookupBridgeBothDirections() {
        let points = [makePoint(index: 0, position: 0.1), makePoint(index: 1, position: 0.5), makePoint(index: 2, position: 0.9)]

        XCTAssertEqual(TimelineCalculator.position(for: 1, in: points), 0.5)
        XCTAssertNil(TimelineCalculator.position(for: 99, in: points))
        XCTAssertEqual(TimelineCalculator.index(for: 0.85, in: points), 2)
        XCTAssertNil(TimelineCalculator.index(for: 0.5, in: []))
    }
}
