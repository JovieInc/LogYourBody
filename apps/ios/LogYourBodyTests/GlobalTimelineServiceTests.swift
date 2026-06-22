//
// GlobalTimelineServiceTests.swift
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

final class GlobalTimelineServiceTests: XCTestCase {
    private var calendar: Calendar!
    private var service: GlobalTimelineService!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        service = GlobalTimelineService(calendar: calendar)
    }

    func testBuildsWeekMonthYearBucketsWithDirectMetricsPhotosStepsAndFFMI() throws {
        let januaryPhoto = "https://example.com/january.jpg"
        let februaryPhoto = "https://example.com/february.jpg"
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 2),
                weight: 80,
                bodyFatPercentage: 20,
                photoUrl: januaryPhoto
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 7),
                weight: 82,
                bodyFatPercentage: 18
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 2, day: 5),
                weight: 78,
                bodyFatPercentage: 17,
                photoUrl: februaryPhoto
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 1, day: 3), steps: 5_000),
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 1, day: 4), steps: 7_000),
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 6), steps: 10_000)
        ]

        let monthlyBuckets = service.makeBuckets(
            for: .month,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )
        let yearlyBuckets = service.makeBuckets(
            for: .year,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let january = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M01" })
        XCTAssertEqual(january.metrics.weight.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.weight.value), 81, accuracy: 0.001)
        XCTAssertEqual(january.metrics.bodyFat.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.bodyFat.value), 19, accuracy: 0.001)
        XCTAssertEqual(january.metrics.ffmi.presence, .present)
        XCTAssertNotNil(january.metrics.ffmi.value)
        XCTAssertEqual(january.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(january.metrics.steps.value), 12_000, accuracy: 0.001)
        XCTAssertEqual(january.metrics.canonicalPhotoId, januaryPhoto)
        XCTAssertEqual(january.metrics.photoCount, 1)

        let february = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M02" })
        XCTAssertEqual(february.metrics.weight.presence, .present)
        XCTAssertEqual(february.metrics.canonicalPhotoId, februaryPhoto)
        XCTAssertEqual(try XCTUnwrap(february.metrics.steps.value), 10_000, accuracy: 0.001)

        let year = try XCTUnwrap(yearlyBuckets.first { $0.id == "2026" })
        XCTAssertEqual(year.metrics.weight.presence, .present)
        XCTAssertEqual(try XCTUnwrap(year.metrics.weight.value), 80, accuracy: 0.001)
        XCTAssertEqual(year.metrics.bodyFat.presence, .present)
        XCTAssertEqual(try XCTUnwrap(year.metrics.bodyFat.value), 18, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(year.metrics.steps.value), 22_000, accuracy: 0.001)
        XCTAssertEqual(year.metrics.photoCount, 2)
    }

    func testSparseBucketsSurfaceInterpolatedAndLastKnownWithoutMeasuredPresence() throws {
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 1),
                weight: 80,
                bodyFatPercentage: 20
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 15),
                weight: 82,
                bodyFatPercentage: 18
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 10), steps: 3_000)
        ]

        let weeklyBuckets = service.makeBuckets(
            for: .week,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let interpolatedWeek = try XCTUnwrap(weeklyBuckets.first { $0.id == "2026-W02" })
        XCTAssertEqual(interpolatedWeek.metrics.weight.presence, .interpolated)
        XCTAssertEqual(interpolatedWeek.metrics.weight.confidence, .medium)
        XCTAssertEqual(try XCTUnwrap(interpolatedWeek.metrics.weight.value), 81, accuracy: 0.2)
        XCTAssertEqual(interpolatedWeek.metrics.bodyFat.presence, .interpolated)
        XCTAssertEqual(interpolatedWeek.metrics.bodyFat.confidence, .medium)
        XCTAssertEqual(interpolatedWeek.metrics.ffmi.presence, .interpolated)

        let lastKnownWeek = try XCTUnwrap(weeklyBuckets.first { $0.id == "2026-W07" })
        XCTAssertEqual(lastKnownWeek.metrics.weight.presence, .lastKnown)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.weight.value), 82, accuracy: 0.001)
        XCTAssertEqual(lastKnownWeek.metrics.bodyFat.presence, .lastKnown)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.bodyFat.value), 18, accuracy: 0.001)
        XCTAssertEqual(lastKnownWeek.metrics.ffmi.presence, .lastKnown)
        XCTAssertEqual(lastKnownWeek.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(lastKnownWeek.metrics.steps.value), 3_000, accuracy: 0.001)
    }

    func testMissingValuesStayMissingWhenInterpolationGapIsTooWide() throws {
        let metrics = [
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 1, day: 1),
                weight: 80,
                bodyFatPercentage: 20
            ),
            makeTimelineMetric(
                date: makeDate(year: 2_026, month: 3, day: 15),
                weight: 85,
                bodyFatPercentage: 18
            )
        ]
        let dailyMetrics = [
            makeTimelineDailyMetric(date: makeDate(year: 2_026, month: 2, day: 15), steps: 9_000)
        ]

        let monthlyBuckets = service.makeBuckets(
            for: .month,
            metrics: metrics,
            dailyMetrics: dailyMetrics,
            heightInches: 70
        )

        let february = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M02" })
        XCTAssertEqual(february.metrics.weight.presence, .missing)
        XCTAssertNil(february.metrics.weight.value)
        XCTAssertEqual(february.metrics.bodyFat.presence, .missing)
        XCTAssertNil(february.metrics.bodyFat.value)
        XCTAssertEqual(february.metrics.ffmi.presence, .missing)
        XCTAssertEqual(february.metrics.steps.presence, .present)
        XCTAssertEqual(try XCTUnwrap(february.metrics.steps.value), 9_000, accuracy: 0.001)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makeTimelineMetric(
        date: Date,
        weight: Double? = nil,
        bodyFatPercentage: Double? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "timeline-user",
            date: date,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatPercentage == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeTimelineDailyMetric(date: Date, steps: Int) -> DailyMetrics {
        DailyMetrics(
            id: UUID().uuidString,
            userId: "timeline-user",
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}
