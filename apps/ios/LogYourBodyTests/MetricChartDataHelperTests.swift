//
// MetricChartDataHelperTests.swift
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


final class MetricChartDataHelperTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
        MetricChartDataHelper.clearCache()
    }

    override func tearDown() async throws {
        MetricChartDataHelper.clearCache()
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    private func makeMetric(
        id: String,
        userId: String,
        daysAgo: Int,
        weight: Double? = nil,
        waistCm: Double? = nil
    ) -> BodyMetrics {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            localDate: nil,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: waistCm,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func testEmptyStoreProducesNoChartData() async throws {
        let userId = "chart-empty-\(UUID().uuidString)"

        let points = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .weight, useMetric: true)

        XCTAssertTrue(points.isEmpty)
    }

    func testWeightChartConvertsKilogramsToPoundsForImperial() async throws {
        let userId = "chart-weight-\(UUID().uuidString)"
        let metric = makeMetric(id: "m1", userId: userId, daysAgo: 1, weight: 100)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: true)

        let imperial = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .weight, useMetric: false)
        let metricSystem = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .weight, useMetric: true)

        XCTAssertEqual(imperial.count, 1)
        XCTAssertEqual(imperial.first?.value ?? 0, 220.462, accuracy: 0.001)
        XCTAssertEqual(metricSystem.first?.value ?? 0, 100, accuracy: 0.001)
        XCTAssertFalse(imperial.first?.isEstimated ?? true)
    }

    func testWeightChartSkipsMetricsWithoutWeight() async throws {
        let userId = "chart-skip-\(UUID().uuidString)"
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            makeMetric(id: "with", userId: userId, daysAgo: 1, weight: 80),
            userId: userId,
            markAsSynced: true
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            makeMetric(id: "without", userId: userId, daysAgo: 2),
            userId: userId,
            markAsSynced: true
        )

        let points = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .weight, useMetric: true)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value ?? 0, 80, accuracy: 0.001)
    }

    func testChartDataHonoursDayWindow() async throws {
        let userId = "chart-window-\(UUID().uuidString)"
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            makeMetric(id: "recent", userId: userId, daysAgo: 1, weight: 100),
            userId: userId,
            markAsSynced: true
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            makeMetric(id: "old", userId: userId, daysAgo: 10, weight: 90),
            userId: userId,
            markAsSynced: true
        )

        let week = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .weight, useMetric: false)
        let allTime = MetricChartDataHelper.generateChartData(for: userId, days: nil, metricType: .weight, useMetric: false)

        XCTAssertEqual(week.count, 1)
        XCTAssertEqual(week.first?.value ?? 0, 220.462, accuracy: 0.001)
        XCTAssertEqual(allTime.count, 2)
        XCTAssertEqual(allTime.last?.value ?? 0, 198.4158, accuracy: 0.001)
    }

    func testWaistChartConvertsCentimetersToInchesForImperial() async throws {
        let userId = "chart-waist-\(UUID().uuidString)"
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            makeMetric(id: "waist", userId: userId, daysAgo: 1, waistCm: 80),
            userId: userId,
            markAsSynced: true
        )

        let metricSystem = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .waist, useMetric: true)
        let imperial = MetricChartDataHelper.generateChartData(for: userId, days: 7, metricType: .waist, useMetric: false)

        XCTAssertEqual(metricSystem.first?.value ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(imperial.first?.value ?? 0, 31.4961, accuracy: 0.001)
    }

    func testStepsChartMapsSeededDaysAndSkipsZeroStepDays() async throws {
        let userId = "chart-steps-\(UUID().uuidString)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today) ?? today

        for (date, steps) in [(today, 8_000), (twoDaysAgo, 6_000), (fiveDaysAgo, 0)] {
            let daily = DailyMetrics(
                id: "daily-\(localDateString(for: date))",
                userId: userId,
                date: date,
                steps: steps,
                notes: nil,
                createdAt: date,
                updatedAt: date
            )
            try await CoreDataManager.shared.saveDailyMetricsAndWait(daily, userId: userId)
        }

        let points = MetricChartDataHelper.generateStepsChartData(for: userId)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first { $0.index == 6 }?.value ?? 0, 8_000)
        XCTAssertEqual(points.first { $0.index == 4 }?.value ?? 0, 6_000)
    }

    func testLongRangeChartDataDownsamplesToTargetCount() async throws {
        let userId = "chart-downsample-\(UUID().uuidString)"

        for day in 1...170 {
            try await CoreDataManager.shared.saveBodyMetricsAndWait(
                makeMetric(id: "bulk-\(day)", userId: userId, daysAgo: day, weight: 80),
                userId: userId,
                markAsSynced: true
            )
        }

        let points = MetricChartDataHelper.generateChartData(for: userId, days: 365, metricType: .weight, useMetric: true)

        XCTAssertEqual(points.count, 150)
    }
}
