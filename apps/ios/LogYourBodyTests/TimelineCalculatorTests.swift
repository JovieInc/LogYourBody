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
    private func makeMetric(id: String, daysAgo: Double, weight: Double? = 80) -> BodyMetrics {
        let date = Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)
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
        XCTAssertTrue(TimelineCalculator.calculateTimelinePoints(from: []).isEmpty)
    }

    func testSingleRecentMetricMapsToDailyImportanceNearNewestPosition() {
        let points = TimelineCalculator.calculateTimelinePoints(from: [makeMetric(id: "m1", daysAgo: 3)])

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.id, "m1")
        XCTAssertEqual(points.first?.index, 0)
        XCTAssertEqual(points.first?.importance, .daily)
        XCTAssertEqual(points.first?.position ?? 0, 0.93, accuracy: 0.02)
    }

    func testImportanceTiersFollowAgeOfEntry() {
        let metrics = [
            makeMetric(id: "daily", daysAgo: 2),
            makeMetric(id: "weekly", daysAgo: 15),
            makeMetric(id: "monthly", daysAgo: 100),
            makeMetric(id: "yearly", daysAgo: 500)
        ]

        let points = TimelineCalculator.calculateTimelinePoints(from: metrics)
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
        let metrics = [
            makeMetric(id: "oldest", daysAgo: 500),
            makeMetric(id: "month", daysAgo: 100),
            makeMetric(id: "week", daysAgo: 15),
            makeMetric(id: "day", daysAgo: 2)
        ]

        let points = TimelineCalculator.calculateTimelinePoints(from: metrics)

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
        let metrics = [
            makeMetric(id: "daily", daysAgo: 2),
            makeMetric(id: "monthly", daysAgo: 100),
            makeMetric(id: "yearly", daysAgo: 500)
        ]

        let points = TimelineCalculator.calculateTimelinePoints(from: metrics)
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
