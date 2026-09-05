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

    func testVisualBodyFatEstimateStaysEstimatedInTimelineAndDerivedFFMI() throws {
        let date = makeDate(year: 2_026, month: 4, day: 8)
        let metric = makeTimelineMetric(
            date: date,
            weight: 80,
            bodyFatPercentage: 19,
            bodyFatMethod: "visual_estimate"
        )

        let monthlyBuckets = service.makeBuckets(
            for: .month,
            metrics: [metric],
            dailyMetrics: [],
            heightInches: 70
        )

        let april = try XCTUnwrap(monthlyBuckets.first { $0.id == "2026-M04" })
        XCTAssertEqual(april.metrics.bodyFat.presence, .estimated)
        XCTAssertEqual(april.metrics.ffmi.presence, .estimated)
    }

    func testTimelineFFMIMatchesHomeAndBodyScoreAcrossHeights() throws {
        let date = Calendar.current.startOfDay(for: makeDate(year: 2_026, month: 4, day: 8))
        let metric = makeTimelineMetric(date: date, weight: 77.3, bodyFatPercentage: 12.1)

        for heightCm in [165.0, 180.0, 193.0] {
            let heightInches = heightCm / 2.54
            let buckets = service.makeBuckets(
                for: .month, metrics: [metric], dailyMetrics: [], heightInches: heightInches
            )
            let timelineFFMI = try XCTUnwrap(buckets.first?.metrics.ffmi.value)
            let homeFFMI = try XCTUnwrap(MetricsInterpolationService.shared.estimateFFMI(
                for: date, metrics: [metric], heightInches: heightInches
            )).value
            let input = BodyScoreInput(
                sex: .male,
                height: HeightValue(value: heightCm, unit: .centimeters),
                weight: WeightValue(value: 77.3, unit: .kilograms),
                bodyFat: BodyFatValue(percentage: 12.1, source: .manualValue)
            )
            let score = try BodyScoreCalculator().calculateScore(context: .init(input: input))

            XCTAssertEqual(timelineFFMI, homeFFMI, accuracy: 0.001, "Height: \(heightCm)")
            XCTAssertEqual(timelineFFMI, score.ffmi, accuracy: 0.001, "Height: \(heightCm)")
        }
    }

    @MainActor
    func testUnchangedTimelineContentDoesNotRebuildBucketsDuringScrub() throws {
        var builds = 0
        let store = GlobalTimelineStore(service: service) { scale, metrics, daily, height in
            builds += 1
            return self.service.makeBuckets(for: scale, metrics: metrics, dailyMetrics: daily, heightInches: height)
        }
        let date = makeDate(year: 2_026, month: 4, day: 8)
        let metrics = [makeTimelineMetric(date: date, weight: 80, bodyFatPercentage: 20)]
        store.updateMetrics(metrics, heightInches: 70)
        let bucket = try XCTUnwrap(store.weeklyBuckets.first)
        builds = 0

        for tick in 0..<100 {
            store.updateCursor(GlobalTimelineCursor(
                date: date.addingTimeInterval(Double(tick)), scale: .week, bucketId: bucket.id
            ))
            store.updateMetrics(metrics, heightInches: 70)
        }

        XCTAssertEqual(builds, 0, "Selection and identical content must reuse the existing buckets")
        XCTAssertEqual(store.cursor?.date, date.addingTimeInterval(99))

        store.updateCursor(GlobalTimelineCursor(date: date, scale: .week, bucketId: "removed"))
        store.updateMetrics(metrics, heightInches: 70)
        XCTAssertEqual(builds, 0)
        XCTAssertEqual(store.cursor?.bucketId, bucket.id)
    }

    @MainActor
    func testRepeatedThousandMeasurementRefreshStaysWithinScrubBudget() {
        let store = GlobalTimelineStore(service: service)
        let start = makeDate(year: 2_026, month: 1, day: 1)
        let metrics = (0..<1_000).map { index in
            makeTimelineMetric(date: start.addingTimeInterval(Double(index) * 86_400), weight: 80)
        }
        store.updateMetrics(metrics, heightInches: 70)
        let clockStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 {
            store.updateMetrics(metrics, heightInches: 70)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - clockStart
        let timing = XCTAttachment(string: "100 refreshes of 1,000 measurements: \(elapsed) seconds")
        timing.name = "Timeline cache timing"
        timing.lifetime = .keepAlways
        add(timing)
        XCTAssertLessThan(elapsed, 1, "Repeated content refreshes must average less than 10 ms")
    }

    @MainActor
    func testStoreInvalidatesCorrectedMeasurementAndHeightWithoutTimestampChange() throws {
        let store = GlobalTimelineStore(service: service)
        let date = makeDate(year: 2_026, month: 4, day: 8)
        let original = makeTimelineMetric(id: "same", date: date, weight: 80, bodyFatPercentage: 20)
        let corrected = makeTimelineMetric(
            id: "same", date: date, weight: 82, bodyFatPercentage: 18,
            bodyFatMethod: "visual_estimate", photoUrl: "https://example.com/corrected.jpg"
        )
        store.updateMetrics([original], heightInches: 70)
        let initialFFMI = try XCTUnwrap(store.monthlyBuckets.first?.metrics.ffmi.value)
        store.updateMetrics([corrected], heightInches: 70)
        let snapshot = try XCTUnwrap(store.monthlyBuckets.first?.metrics)
        XCTAssertEqual(snapshot.weight.value, 82)
        XCTAssertEqual(snapshot.bodyFat.value, 18)
        XCTAssertEqual(snapshot.bodyFat.presence, .estimated)
        XCTAssertEqual(snapshot.canonicalPhotoId, corrected.photoUrl)
        XCTAssertNotEqual(snapshot.ffmi.value, initialFFMI)

        store.updateMetrics([corrected], heightInches: 76)
        XCTAssertNotEqual(store.monthlyBuckets.first?.metrics.ffmi.value, snapshot.ffmi.value)
        store.updateMetrics([corrected], heightInches: nil)
        XCTAssertNil(store.monthlyBuckets.first?.metrics.ffmi.value)
    }

    @MainActor
    func testStoreInvalidatesWhenInterpolationTimeZoneChanges() {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        var builds = 0
        let store = GlobalTimelineStore(service: service) { scale, metrics, daily, height in
            builds += 1
            return self.service.makeBuckets(for: scale, metrics: metrics, dailyMetrics: daily, heightInches: height)
        }
        let metric = makeTimelineMetric(date: makeDate(year: 2_026, month: 4, day: 8), weight: 80)
        store.updateMetrics([metric])
        builds = 0
        NSTimeZone.default = TimeZone(secondsFromGMT: 18_000)!
        store.updateMetrics([metric])
        XCTAssertEqual(builds, 3)
    }

    @MainActor
    func testStoreInvalidatesStepEditsDatesAndEmptyHistory() throws {
        let store = GlobalTimelineStore(service: service)
        let april = makeDate(year: 2_026, month: 4, day: 8)
        let may = makeDate(year: 2_026, month: 5, day: 8)
        store.updateMetrics([], dailyMetrics: [makeTimelineDailyMetric(id: "same", date: april, steps: 100)])
        XCTAssertEqual(store.monthlyBuckets.first?.metrics.steps.value, 100)
        store.updateMetrics([], dailyMetrics: [makeTimelineDailyMetric(id: "same", date: april, steps: 200)])
        XCTAssertEqual(store.monthlyBuckets.first?.metrics.steps.value, 200)
        store.updateMetrics([], dailyMetrics: [makeTimelineDailyMetric(id: "same", date: may, steps: 200)])
        XCTAssertEqual(store.monthlyBuckets.map(\.id), ["2026-M05"])
        XCTAssertEqual(store.cursor?.bucketId, store.weeklyBuckets.last?.id)

        store.updateMetrics([])
        XCTAssertTrue(store.weeklyBuckets.isEmpty)
        XCTAssertTrue(store.monthlyBuckets.isEmpty)
        XCTAssertTrue(store.yearlyBuckets.isEmpty)
        XCTAssertNil(store.cursor)
    }

    func testBucketSweepAssignsBoundariesOnceAcrossEveryScale() throws {
        let date = makeDate(year: 2_026, month: 4, day: 8)
        let cases: [(GlobalTimelineScale, Calendar.Component)] = [(.week, .weekOfYear), (.month, .month), (.year, .year)]
        for (scale, component) in cases {
            let interval = try XCTUnwrap(calendar.dateInterval(of: component, for: date))
            let dates = [interval.start.addingTimeInterval(-1), interval.start,
                         interval.end.addingTimeInterval(-1), interval.end]
            let metrics = dates.enumerated().map { index, date in
                makeTimelineMetric(date: date, weight: Double((index + 1) * 10), photoUrl: "photo-\(index)")
            }
            let daily = dates.enumerated().map { index, date in
                makeTimelineDailyMetric(date: date, steps: (index + 1) * 10)
            }
            let ignoredDate = interval.start.addingTimeInterval(-86_400 * 400)
            let buckets = service.makeBuckets(
                for: scale,
                metrics: [makeTimelineMetric(date: ignoredDate)] + metrics.reversed(),
                dailyMetrics: [makeTimelineDailyMetric(date: ignoredDate, steps: 0)] + daily.reversed()
            )
            let middle = try XCTUnwrap(buckets.first { $0.startDate == interval.start })
            XCTAssertEqual(middle.metrics.weight.value, 25)
            XCTAssertEqual(middle.metrics.steps.value, 50)
            XCTAssertEqual(middle.metrics.photoCount, 2)
            XCTAssertEqual(buckets.reduce(0) { $0 + $1.metrics.photoCount }, 4)
            XCTAssertEqual(buckets.last?.metrics.weight.value, 40)
            XCTAssertEqual(buckets.last?.metrics.steps.value, 40)
        }
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
        id: String = UUID().uuidString,
        date: Date,
        weight: Double? = nil,
        bodyFatPercentage: Double? = nil,
        bodyFatMethod: String? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "timeline-user",
            date: date,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod ?? (bodyFatPercentage == nil ? nil : "manual"),
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

    private func makeTimelineDailyMetric(
        id: String = UUID().uuidString, date: Date, steps: Int
    ) -> DailyMetrics {
        DailyMetrics(
            id: id,
            userId: "timeline-user",
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}
