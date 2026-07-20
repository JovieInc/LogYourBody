//
// TimelineBucketCalculatorTests.swift
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


final class TimelineBucketCalculatorTests: XCTestCase {
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func makeMetric(id: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user-1",
            date: date,
            localDate: "2024-01-01",
            weight: 80,
            weightUnit: "kg",
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

    // MARK: - Zoom level calculation

    func testZoomLevelBoundariesAcrossDataRanges() {
        let start = makeDate(year: 2_024, month: 1, day: 15)

        let twoMonths = Calendar.current.date(byAdding: .month, value: 2, to: start) ?? start
        let threeMonths = Calendar.current.date(byAdding: .month, value: 3, to: start) ?? start
        let elevenMonths = Calendar.current.date(byAdding: .month, value: 11, to: start) ?? start
        let twelveMonths = Calendar.current.date(byAdding: .month, value: 12, to: start) ?? start
        let sixtyMonths = Calendar.current.date(byAdding: .month, value: 60, to: start) ?? start

        XCTAssertEqual(TimelineZoomLevel.calculate(from: start, to: twoMonths), .week)
        XCTAssertEqual(TimelineZoomLevel.calculate(from: start, to: threeMonths), .month)
        XCTAssertEqual(TimelineZoomLevel.calculate(from: start, to: elevenMonths), .month)
        XCTAssertEqual(TimelineZoomLevel.calculate(from: start, to: twelveMonths), .year)
        XCTAssertEqual(TimelineZoomLevel.calculate(from: start, to: sixtyMonths), .all)
    }

    func testZoomLevelBucketSizingAndMetricTickVisibility() {
        XCTAssertEqual(TimelineZoomLevel.week.daysPerBucket, 2)
        XCTAssertEqual(TimelineZoomLevel.month.daysPerBucket, 7)
        XCTAssertEqual(TimelineZoomLevel.year.daysPerBucket, 30)
        XCTAssertEqual(TimelineZoomLevel.all.daysPerBucket, 90)

        XCTAssertTrue(TimelineZoomLevel.week.showMetricTicks)
        XCTAssertTrue(TimelineZoomLevel.month.showMetricTicks)
        XCTAssertFalse(TimelineZoomLevel.year.showMetricTicks)
        XCTAssertFalse(TimelineZoomLevel.all.showMetricTicks)
    }

    // MARK: - Bucket creation

    func testCreateBucketsReturnsEmptyForEmptyRange() {
        let start = makeDate(year: 2_024, month: 3, day: 1)

        XCTAssertTrue(TimelineBucketCalculator.createBuckets(from: start, to: start, zoomLevel: .week).isEmpty)
    }

    func testCreateBucketsBuildsContiguousBucketsCoveringRange() {
        let start = makeDate(year: 2_024, month: 3, day: 1)
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start

        let buckets = TimelineBucketCalculator.createBuckets(from: start, to: end, zoomLevel: .week)

        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.first?.startDate, start)
        for (previous, next) in zip(buckets, buckets.dropFirst()) {
            XCTAssertEqual(previous.endDate, next.startDate)
        }
    }

    func testCreateBucketsRoundsUpPartialTrailingBucket() {
        let start = makeDate(year: 2_024, month: 3, day: 1)
        let end = Calendar.current.date(byAdding: .day, value: 15, to: start) ?? start

        let buckets = TimelineBucketCalculator.createBuckets(from: start, to: end, zoomLevel: .week)

        XCTAssertEqual(buckets.count, 8)
    }

    func testBucketIdentifiesByStartTimestamp() {
        let start = makeDate(year: 2_024, month: 3, day: 1)

        let bucket = TimelineBucket(startDate: start, days: 7)

        XCTAssertEqual(bucket.id, "\(Int(start.timeIntervalSince1970))")
    }

    // MARK: - Bucket membership

    func testBucketContainsIsStartInclusiveEndExclusive() {
        let start = makeDate(year: 2_024, month: 3, day: 1)
        let bucket = TimelineBucket(startDate: start, days: 2)
        let middle = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        XCTAssertTrue(bucket.contains(start))
        XCTAssertTrue(bucket.contains(middle))
        XCTAssertFalse(bucket.contains(bucket.endDate))
    }

    func testDistributeToBucketsPlacesMetricsInMatchingBuckets() {
        let start = makeDate(year: 2_024, month: 3, day: 1)
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start) ?? start
        var buckets = TimelineBucketCalculator.createBuckets(from: start, to: end, zoomLevel: .week)
        let dayTwo = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let dayThree = Calendar.current.date(byAdding: .day, value: 3, to: start) ?? start
        let metrics = [makeMetric(id: "early", date: dayTwo), makeMetric(id: "late", date: dayThree)]

        TimelineBucketCalculator.distributeToBuckets(metrics: metrics, buckets: &buckets)

        XCTAssertEqual(buckets[0].candidates.map(\.id), ["early"])
        XCTAssertEqual(buckets[1].candidates.map(\.id), ["late"])
    }

    func testDistributeToBucketsDropsMetricsOutsideAllBuckets() {
        let start = makeDate(year: 2_024, month: 3, day: 1)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
        var buckets = TimelineBucketCalculator.createBuckets(from: start, to: end, zoomLevel: .week)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        let after = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
        let metrics = [makeMetric(id: "before", date: before), makeMetric(id: "after", date: after)]

        TimelineBucketCalculator.distributeToBuckets(metrics: metrics, buckets: &buckets)

        XCTAssertTrue(buckets.allSatisfy { $0.candidates.isEmpty })
    }
}
