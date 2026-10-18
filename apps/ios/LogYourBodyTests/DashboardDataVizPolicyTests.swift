//
// DashboardTimelineAndPolicyTests.swift
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


final class DashboardDataVizPolicyTests: XCTestCase {
    func testMetricSummaryFootnoteKeepsOneGoalStatWhenGoalExists() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "181.4 lb average",
                goalText: "Target 180.0 lb"
            ),
            "Target 180.0 lb"
        )
    }

    func testMetricSummaryFootnoteFallsBackToOneAverageStat() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "18.2 average",
                goalText: nil
            ),
            "18.2 average"
        )
    }

    func testMetricSummaryFootnoteOmitsEmptyStats() {
        XCTAssertNil(
            metricSummaryFootnote(
                averageText: "",
                goalText: ""
            )
        )
    }
}

extension DashboardDataVizPolicyTests {
    func testLatestStepsKeepsRecordedZeroTodayInsteadOfOlderPositiveDay() {
        let today = stepRecord(daysAgo: 0, steps: 0)
        let yesterday = stepRecord(daysAgo: 1, steps: 5_432)
        let result = stepSnapshot([today, yesterday], fallback: today)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.date, today.date)
    }

    func testLatestStepsFallsBackToRecordedDayWhenTodayIsMissing() {
        let today = stepRecord(daysAgo: 0, steps: nil)
        let yesterday = stepRecord(daysAgo: 1, steps: 5_432)
        for records in [[today, yesterday], [yesterday]] {
            let result = stepSnapshot(records, fallback: today)
            XCTAssertEqual(result.value, 5_432)
            XCTAssertEqual(result.date, yesterday.date)
        }
    }

    func testLatestStepsKeepsOrdinaryPositiveToday() {
        let today = stepRecord(daysAgo: 0, steps: 1_234)
        let yesterday = stepRecord(daysAgo: 1, steps: 5_432)
        let result = stepSnapshot([today, yesterday], fallback: yesterday)
        XCTAssertEqual(result.value, 1_234)
        XCTAssertEqual(result.date, today.date)
    }

    func testLatestStepsDoesNotInventZeroOrDateWithoutHistory() {
        let result = stepSnapshot([])
        XCTAssertNil(result.value)
        XCTAssertNil(result.date)
        let missingRecord = stepSnapshot([stepRecord(daysAgo: 0, steps: nil)])
        XCTAssertNil(missingRecord.value)
        XCTAssertNil(missingRecord.date)
    }

    func testLatestStepsRetainsEarlierRecordedZeroAndRejectsNegativeCount() {
        let invalidToday = stepRecord(daysAgo: 0, steps: -1)
        let yesterday = stepRecord(daysAgo: 1, steps: 0)
        let older = stepRecord(daysAgo: 2, steps: 5_432)
        let result = stepSnapshot([invalidToday, yesterday, older])
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(result.date, yesterday.date)
    }

    func testLatestStepsPreservesThirtyDayWindowAndExplicitFallback() {
        let lastIncluded = stepRecord(daysAgo: 29, steps: 0)
        let firstExcluded = stepRecord(daysAgo: 30, steps: 5_432)
        let included = stepSnapshot([lastIncluded, firstExcluded])
        XCTAssertEqual(included.value, 0)
        XCTAssertEqual(included.date, lastIncluded.date)
        let excluded = stepSnapshot([firstExcluded])
        XCTAssertNil(excluded.value)
        XCTAssertNil(excluded.date)
        let fallback = stepSnapshot([], fallback: firstExcluded)
        XCTAssertEqual(fallback.value, 5_432)
        XCTAssertEqual(fallback.date, firstExcluded.date)
    }

    private var stepCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var stepNow: Date {
        Date(timeIntervalSince1970: 1_792_022_400)
    }

    private func stepRecord(daysAgo: Int, steps: Int?) -> DailyMetrics {
        let date = stepCalendar.date(byAdding: .day, value: -daysAgo, to: stepNow)!
        return DailyMetrics(
            id: "record-\(daysAgo)", userId: "synthetic-stats-owner", date: date, steps: steps,
            notes: nil, createdAt: date, updatedAt: date
        )
    }

    private func stepSnapshot(
        _ records: [DailyMetrics],
        fallback: DailyMetrics? = nil
    ) -> (value: Int?, date: Date?) {
        let lookup = Dictionary(uniqueKeysWithValues: records.map {
            (stepCalendar.startOfDay(for: $0.date), $0)
        })
        return DashboardStepsSnapshotPolicy.latest(
            in: lookup, fallback: fallback, now: stepNow, calendar: stepCalendar
        )
    }
}
