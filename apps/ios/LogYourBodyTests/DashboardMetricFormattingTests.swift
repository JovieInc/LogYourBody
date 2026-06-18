//
// DashboardMetricFormattingTests.swift
// LogYourBodyTests
//
// Coverage for the pure dashboard hero-metric logic in
// Helpers/DashboardMetricFormatting.swift: range-stats (the engine behind the
// hero 30-day deltas), delta/footnote formatting, trend classification, and the
// metric footnote precedence rule.
//
import XCTest
@testable import LogYourBody

final class DashboardMetricFormattingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - computeRangeStats (drives heroWeightDelta30d / heroBodyFatDelta30d / heroFFMIDelta30d)

    func testComputeRangeStatsReturnsNilForEmpty() {
        XCTAssertNil(computeRangeStats(metrics: []) { $0.weight })
    }

    func testComputeRangeStatsReturnsNilWhenProviderYieldsNothing() {
        let metrics = [makeMetric(id: "a", date: base, weight: nil, bodyFat: nil)]
        XCTAssertNil(computeRangeStats(metrics: metrics) { $0.weight })
    }

    func testComputeRangeStatsSinglePointHasZeroDelta() throws {
        let metrics = [makeMetric(id: "a", date: base, weight: 180, bodyFat: nil)]
        let stats = try XCTUnwrap(computeRangeStats(metrics: metrics) { $0.weight })
        XCTAssertEqual(stats.startValue, 180)
        XCTAssertEqual(stats.endValue, 180)
        XCTAssertEqual(stats.delta, 0)
        XCTAssertEqual(stats.average, 180)
        XCTAssertEqual(stats.percentageChange, 0)
    }

    func testComputeRangeStatsSortsByDateBeforeComputingDelta() throws {
        // Provide newest-first to prove the function sorts ascending before delta.
        let metrics = [
            makeMetric(id: "new", date: base.addingTimeInterval(86_400 * 10), weight: 175, bodyFat: nil),
            makeMetric(id: "old", date: base, weight: 185, bodyFat: nil),
            makeMetric(id: "mid", date: base.addingTimeInterval(86_400 * 5), weight: 180, bodyFat: nil)
        ]
        let stats = try XCTUnwrap(computeRangeStats(metrics: metrics) { $0.weight })
        XCTAssertEqual(stats.startValue, 185) // oldest
        XCTAssertEqual(stats.endValue, 175)   // newest
        XCTAssertEqual(stats.delta, -10)
        XCTAssertEqual(stats.average, 180, accuracy: 0.0001)
        XCTAssertEqual(stats.percentageChange, (-10.0 / 185.0) * 100, accuracy: 0.0001)
    }

    func testComputeRangeStatsGuardsAgainstZeroFirstValue() throws {
        let metrics = [
            makeMetric(id: "old", date: base, weight: 0, bodyFat: nil),
            makeMetric(id: "new", date: base.addingTimeInterval(86_400), weight: 5, bodyFat: nil)
        ]
        let stats = try XCTUnwrap(computeRangeStats(metrics: metrics) { $0.weight })
        XCTAssertEqual(stats.delta, 5)
        XCTAssertEqual(stats.percentageChange, 0) // avoids divide-by-zero blowup
    }

    // MARK: - formatDelta

    func testFormatDeltaSignAndUnit() {
        XCTAssertEqual(formatDelta(delta: 2.0, unit: "lbs"), "+2 lbs")
        XCTAssertEqual(formatDelta(delta: -1.5, unit: "lbs"), "\u{2013}1.5 lbs") // en dash
        XCTAssertEqual(formatDelta(delta: 2.3, unit: "%"), "+2.3%")
        XCTAssertEqual(formatDelta(delta: -4.0, unit: ""), "\u{2013}4")
    }

    // MARK: - makeTrend

    func testMakeTrendFlatWithinEpsilon() throws {
        let trend = try XCTUnwrap(makeTrend(delta: 0.0005, unit: "lbs", range: .month1))
        XCTAssertEqual(directionLabel(trend.direction), "flat")
        XCTAssertEqual(trend.valueText, "No change")
        XCTAssertEqual(trend.caption, "1M")
    }

    func testMakeTrendUpAndDown() throws {
        let up = try XCTUnwrap(makeTrend(delta: 1.5, unit: "lbs", range: .week1))
        XCTAssertEqual(directionLabel(up.direction), "up")
        XCTAssertEqual(up.valueText, "1.5 lbs")
        XCTAssertEqual(up.caption, "7d")

        let down = try XCTUnwrap(makeTrend(delta: -2.0, unit: "%", range: .year1))
        XCTAssertEqual(directionLabel(down.direction), "down")
        XCTAssertEqual(down.valueText, "2%")
        XCTAssertEqual(down.caption, "1Y")
    }

    private func directionLabel(_ direction: MetricSummaryCard.Trend.Direction) -> String {
        switch direction {
        case .up: return "up"
        case .down: return "down"
        case .flat: return "flat"
        }
    }

    func testMakeTrendEmptyUnitOmitsSuffix() throws {
        let trend = try XCTUnwrap(makeTrend(delta: 3.0, unit: "", range: .all))
        XCTAssertEqual(trend.valueText, "3")
        XCTAssertEqual(trend.caption, "All")
    }

    // MARK: - formatAverageFootnote

    func testFormatAverageFootnote() {
        XCTAssertEqual(formatAverageFootnote(value: 180.5, unit: "lbs"), "180.5 lbs average")
        XCTAssertEqual(formatAverageFootnote(value: 18.0, unit: "%"), "18 % average")
        XCTAssertEqual(formatAverageFootnote(value: 22.0, unit: ""), "22 average")
    }

    // MARK: - metricSummaryFootnote precedence

    func testMetricSummaryFootnotePrefersGoalText() {
        XCTAssertEqual(metricSummaryFootnote(averageText: "180 avg", goalText: "Goal: 175"), "Goal: 175")
        XCTAssertEqual(metricSummaryFootnote(averageText: "180 avg", goalText: nil), "180 avg")
        XCTAssertEqual(metricSummaryFootnote(averageText: "180 avg", goalText: ""), "180 avg")
        XCTAssertNil(metricSummaryFootnote(averageText: nil, goalText: nil))
        XCTAssertNil(metricSummaryFootnote(averageText: "", goalText: ""))
    }

    // MARK: - TimeRange.shortRelativeLabel

    func testShortRelativeLabelsCoverAllRanges() {
        XCTAssertEqual(TimeRange.week1.shortRelativeLabel, "7d")
        XCTAssertEqual(TimeRange.month1.shortRelativeLabel, "1M")
        XCTAssertEqual(TimeRange.month3.shortRelativeLabel, "3M")
        XCTAssertEqual(TimeRange.month6.shortRelativeLabel, "6M")
        XCTAssertEqual(TimeRange.year1.shortRelativeLabel, "1Y")
        XCTAssertEqual(TimeRange.all.shortRelativeLabel, "All")
    }

    // MARK: - Fixture

    private func makeMetric(id: String, date: Date, weight: Double?, bodyFat: Double?) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "dashboard-metric-format-user",
            date: date,
            localDate: nil,
            weight: weight,
            weightUnit: "lbs",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }
}
