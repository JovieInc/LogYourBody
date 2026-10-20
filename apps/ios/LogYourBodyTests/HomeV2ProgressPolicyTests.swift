//
// HomeV2ProgressPolicyTests.swift
// LogYourBodyTests
//
import SwiftUI
import XCTest
@testable import LogYourBody

final class HomeV2ProgressPolicyTests: XCTestCase {
    private func point(daysAgo: Int, value: Double) -> MetricChartDataPoint {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return MetricChartDataPoint(date: date, value: value, presence: .present)
    }

    func testDeltaSentencesReadAsSentences() {
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: -4.1, unit: "lb", range: .month3), "Down 4.1 lb in 3 months")
        XCTAssertEqual(
            HomeV2ProgressCopy.deltaSentence(delta: 0.9, unit: "points", range: .month1),
            "Up 0.9 points in 30 days"
        )
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: -0.3, unit: "", range: .year1), "Down 0.3 in a year")
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: 0.01, unit: "lb", range: .all), "No change overall")
        XCTAssertEqual(
            HomeV2ProgressCopy.deltaSentence(delta: nil, unit: "lb", range: .month6),
            "Your trend appears after 7 days"
        )
        XCTAssertEqual(HomeV2ProgressCopy.estimatedBy("Withings"), "Estimated by your Withings")
        XCTAssertEqual(HomeV2ProgressCopy.estimatedBy("Typed"), "Estimated, typed by you")
        XCTAssertTrue(HomeV2ProgressCopy.stepsAverageSentence(average: 8_412, range: .month3).hasPrefix("Averaging "))
    }

    func testStatsTakeStartLowAndChangeFromTheVisiblePoints() {
        let points = [point(daysAgo: 0, value: 173.4), point(daysAgo: 10, value: 172.9), point(daysAgo: 40, value: 186.2)]
        let stats = HomeV2ProgressPolicy.stats(points: points, prefersHigh: false)
        XCTAssertEqual(stats.latest ?? 0, 173.4, accuracy: 0.001)
        XCTAssertEqual(stats.start ?? 0, 186.2, accuracy: 0.001)
        XCTAssertEqual(stats.extreme ?? 0, 172.9, accuracy: 0.001)
        XCTAssertEqual(stats.delta ?? 0, -12.8, accuracy: 0.001)
        XCTAssertEqual(stats.distinctDays, 3)

        let steps = HomeV2ProgressPolicy.stats(
            points: [point(daysAgo: 0, value: 9_842), point(daysAgo: 1, value: 4_000)],
            prefersHigh: true
        )
        XCTAssertEqual(steps.extreme ?? 0, 9_842, accuracy: 0.001)
        XCTAssertEqual(steps.average ?? 0, 6_921, accuracy: 0.001)

        let empty = HomeV2ProgressPolicy.stats(points: [], prefersHigh: false)
        XCTAssertNil(empty.latest)
        XCTAssertNil(empty.delta)
        XCTAssertEqual(empty.distinctDays, 0)
    }

    func testEveryMetricHasAnAccentAndATitle() {
        for metric in HomeV2ProgressMetric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.identifier.isEmpty)
        }
        XCTAssertTrue(HomeV2ProgressMetric.steps.prefersHigh)
        XCTAssertFalse(HomeV2ProgressMetric.weight.prefersHigh)
    }

    func testSparseClassificationUsesDistinctDaysInTheSelectedRange() {
        for days in 0...7 {
            let visible = (0..<days).flatMap { offset in
                [point(daysAgo: offset, value: 180), point(daysAgo: offset, value: 181)]
            }
            let all = visible + [point(daysAgo: 60, value: 190)]
            let selected = HomeV2TrendPolicy.points(all, in: .month1)
            let stats = HomeV2ProgressPolicy.stats(points: selected, prefersHigh: false)
            XCTAssertEqual(stats.distinctDays, days, "Multiple entries on one day do not advance the trend threshold")
            XCTAssertEqual(HomeV2TrendPolicy.hasEnoughData(selected), days >= HomeV2TrendPolicy.minimumDistinctDays)
        }
    }

    @MainActor
    func testRawProgressChartsIdentifyTheirMetricWithoutClaimingAnAverage() {
        let points = (0..<7).map { point(daysAgo: $0, value: 20) }
        for metric in HomeV2ProgressMetric.allCases {
            let chart = HomeV2TrendChart(
                daily: points,
                trend: points,
                accent: metric.accent,
                range: .constant(.all),
                axis: .months,
                metricTitle: metric.title,
                usesSevenDayAverage: false
            )
            XCTAssertEqual(chart.accessibilitySummary, "\(metric.title) history")
        }
    }

    @MainActor
    func testAveragedWeightChartDescribesItsActualSeries() {
        let points = (0..<7).map { point(daysAgo: $0, value: 170) }
        let chart = HomeV2TrendChart(
            daily: points,
            trend: points,
            accent: HomeV2ProgressMetric.weight.accent,
            range: .constant(.all)
        )
        XCTAssertEqual(chart.accessibilitySummary, "Weight trend, 7-day average")
    }

    @MainActor
    func testSparseProgressChartKeepsMetricIdentityInItsAccessibilitySummary() {
        let chart = HomeV2TrendChart(
            daily: [point(daysAgo: 0, value: 8_000)],
            trend: [],
            accent: HomeV2ProgressMetric.steps.accent,
            range: .constant(.month1),
            axis: .months,
            metricTitle: HomeV2ProgressMetric.steps.title,
            usesSevenDayAverage: false
        )
        XCTAssertEqual(chart.accessibilitySummary, "Steps history. Your trend appears after 7 days")
    }
}
