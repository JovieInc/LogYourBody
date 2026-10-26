//
// DashboardMetricFormattingTests.swift
// LogYourBodyTests
//
// Coverage for the pure dashboard hero-metric logic in
// Helpers/DashboardMetricFormatting.swift: range-stats (the engine behind the
// hero 30-day deltas), delta/footnote formatting, trend classification, and the
// metric footnote precedence rule.
//
import SwiftUI
import XCTest
@testable import LogYourBody

final class DashboardMetricFormattingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testStatsTruthRequiresExplicitGateOrAuthenticatedUITest() {
        XCTAssertFalse(MetricStatsTruthPolicy.isEnabled { _ in false })
        XCTAssertTrue(MetricStatsTruthPolicy.isEnabled { key in key == "metric_stats_truth_v1" })
        XCTAssertFalse(MetricStatsTruthPolicy.isEnabled(
            arguments: ["-lybUITestMetricStatsTruth", "-lybUITestPhotoTimelineHUDFixture"],
            environment: [:], isGateEnabled: { _ in false }))
    }

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

    func testTimelineHeadlineUsesMeasuredWeightEvenWhenTrendIsPreferred() {
        XCTAssertEqual(
            TimelineWeightHeadlinePolicy.kilograms(
                measuredWeight: 82.736, // 182.4 lb stored as kg
                trendWeight: 83.5,
                prefersTrend: true
            ),
            82.736
        )
    }

    func testTimelineHeadlineFallsBackToTrendWhenDayHasNoMeasuredWeight() {
        XCTAssertEqual(
            TimelineWeightHeadlinePolicy.kilograms(
                measuredWeight: nil,
                trendWeight: 83.5,
                prefersTrend: true
            ),
            83.5
        )
    }

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

    // MARK: - JOV-6090 trend-chip contract

    func testMakeTrendFlatKeepsNoChangeWithRangeCaption() throws {
        // The flat trend renders "No change · 1M" as one coherent line; the
        // card must never wrap the valueText itself at standard text size.
        let trend = try XCTUnwrap(makeTrend(delta: 0, unit: "%", range: .month1))
        XCTAssertEqual(directionLabel(trend.direction), "flat")
        XCTAssertEqual(trend.valueText, "No change")
        XCTAssertEqual(trend.caption, "1M")
        XCTAssertFalse(trend.valueText.contains("\n"))
        XCTAssertFalse(trend.valueText.contains("·"))
    }

    func testFFMIUnitlessTrendOmitsUnitSuffix() throws {
        // Stats FFMI card ships unit "" (title already carries "FFMI"), so its
        // trend value must be a bare formatted number with no duplicated unit.
        let trend = try XCTUnwrap(makeTrend(delta: 0.4, unit: "", range: .month3))
        XCTAssertEqual(directionLabel(trend.direction), "up")
        XCTAssertEqual(trend.valueText, "0.4")
        XCTAssertEqual(trend.caption, "3M")
        XCTAssertFalse(trend.valueText.lowercased().contains("ffmi"))
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

    // MARK: - MetricFormatterCache

    func testMetricFormatterCacheReusesConfiguredFormatterForTheSameKey() {
        let formatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 3)
        let reused = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 3)
        let different = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 2)

        XCTAssertTrue(formatter === reused)
        XCTAssertFalse(formatter === different)
        XCTAssertEqual(formatter.numberStyle, .decimal)
        XCTAssertEqual(formatter.minimumFractionDigits, 1)
        XCTAssertEqual(formatter.maximumFractionDigits, 3)
    }

    func testMetricFormatterCacheSerializesConcurrentInsertionsAndReads() {
        let resultsLock = NSLock()
        var formattersByKey: [MetricFormatterKey: Set<ObjectIdentifier>] = [:]
        var invalidConfigurations = 0

        DispatchQueue.concurrentPerform(iterations: 2_048) { iteration in
            let minimum = 5 + iteration % 8
            let key = MetricFormatterKey(minFractionDigits: minimum, maxFractionDigits: minimum + 1)
            let formatter = MetricFormatterCache.formatter(
                minFractionDigits: key.minFractionDigits,
                maxFractionDigits: key.maxFractionDigits
            )
            let configured = formatter.numberStyle == .decimal &&
                formatter.minimumFractionDigits == key.minFractionDigits &&
                formatter.maximumFractionDigits == key.maxFractionDigits

            resultsLock.lock()
            formattersByKey[key, default: []].insert(ObjectIdentifier(formatter))
            if !configured { invalidConfigurations += 1 }
            resultsLock.unlock()
        }

        XCTAssertEqual(invalidConfigurations, 0)
        XCTAssertEqual(formattersByKey.count, 8)
        for (key, formatters) in formattersByKey {
            XCTAssertEqual(formatters.count, 1, "Concurrent callers must share one formatter for \(key)")
        }
    }

    // MARK: - Fixture

    // LYB-47 extends the existing truth calculator fixtures; dates are deliberately unequal.
    @MainActor
    func testObservationSummaryUsesEndpointsAndObservationMeanAcrossUnequalDates() throws {
        let points = [truthPoint(0, 80), truthPoint(-29, 90), truthPoint(-2, 70)]
        let summary = MetricObservationSummary(points: points, range: .month1, now: base)
        let stats = try XCTUnwrap(summary.stats)
        XCTAssertEqual(stats.startValue, 90)
        XCTAssertEqual(stats.endValue, 80)
        XCTAssertEqual(stats.delta, -10)
        XCTAssertEqual(stats.average, 80)
        XCTAssertEqual(stats.sampleCount, 3)
        XCTAssertEqual(stats.startDate, points[1].date)
        XCTAssertEqual(stats.endDate, base)
        XCTAssertEqual(summary.periodLabel, "Past 30 days")
        XCTAssertTrue(summary.comparisonLabel.hasPrefix("First → last"))
        let chart = FullMetricChartView(
            title: "Weight", icon: "figure.stand", iconColor: .blue,
            currentValue: "80.0", unit: "kg", currentDate: "Observation date",
            chartData: points, onAdd: nil, metricEntries: nil, goalValue: nil,
            selectedTimeRange: .constant(.month1), statsTruthEnabled: true, referenceDate: base,
            synchronizationText: "Cloud sync: Yesterday")
        XCTAssertEqual(chart.computeSeriesStats(for: points)?.delta, stats.delta)
        XCTAssertEqual(chart.computeSeriesStats(for: points)?.average, stats.average)
        XCTAssertEqual(chart.synchronizationText, "Cloud sync: Yesterday")
    }

    func testMissingSingleTimestampAndOldOnlyNeverBecomeNoChange() {
        for points in [[], [truthPoint(0, 80)], [truthPoint(0, 80), truthPoint(0, 81)], [truthPoint(-90, 80)]] {
            let summary = MetricObservationSummary(points: points, range: .month1, now: base)
            XCTAssertNil(summary.stats)
            XCTAssertFalse(summary.changeText(unit: "kg").contains("Unchanged"))
            XCTAssertFalse(summary.changeText(unit: "kg").contains("No change"))
        }
        let old = MetricObservationSummary(points: [truthPoint(-90, 80)], range: .month1, now: base)
        XCTAssertEqual(old.point?.value, 80)
        XCTAssertTrue(old.points.isEmpty)
        XCTAssertTrue(old.observationLabel.contains("90 days ago"))
        XCTAssertTrue(old.observationLabel.contains("Outside displayed period"))
        XCTAssertEqual(old.changeText(unit: "kg"), "No observations in displayed period")
    }

    func testObservationSummaryExcludesCarryMissingFutureAndNonfiniteWithoutInventingZero() {
        let points = [truthPoint(-5, 100), truthPoint(-1, 200), truthPoint(-2, 0, presence: .missing),
                      truthPoint(-3, 300, presence: .lastKnown), truthPoint(-4, 400, presence: .interpolated),
                      truthPoint(1, 999), truthPoint(-1, .nan), truthPoint(-1, .infinity)]
        let summary = MetricObservationSummary(points: points, range: .week1, now: base)
        XCTAssertEqual(summary.points.map(\.value), [100, 200])
        XCTAssertEqual(summary.stats?.average, 150)
        XCTAssertEqual(summary.stats?.delta, 100)
        let zero = MetricObservationSummary(points: [truthPoint(-1, 10), truthPoint(0, 0)], range: .week1, now: base)
        XCTAssertEqual(zero.point?.value, 0, "A recorded zero is an observation")
        XCTAssertEqual(zero.stats?.delta, -10)
    }

    func testStepsProviderRetainsRecordedZeroAndOmitsMissingAndInvalidDays() {
        let daily = [nil, -1, 0, 500].enumerated().map { index, value in
            DailyMetrics(id: "day-\(index)", userId: "fixture", date: base.addingTimeInterval(Double(index) * 86_400),
                         steps: value, notes: nil, createdAt: base, updatedAt: base.addingTimeInterval(999_999))
        }
        let points = buildFullScreenStepsChartData(from: daily)
        XCTAssertEqual(points.map(\.value), [0, 500])
        XCTAssertEqual(points.map(\.date), [daily[2].date, daily[3].date])
        XCTAssertFalse(points.contains { $0.date == daily[0].updatedAt }, "Sync/update time is not the observation date")
    }

    func testSelectedObservationCannotBorrowLaterSnapshot() {
        let early = truthPoint(-8, 82)
        let summary = MetricObservationSummary(points: [early, truthPoint(0, 78)], range: .month1,
                                               selectedDate: early.date, now: base)
        XCTAssertEqual(summary.point?.date, early.date)
        XCTAssertEqual(summary.point?.value, 82)
        let before = MetricObservationSummary(points: [early], range: .month1,
                                              selectedDate: early.date.addingTimeInterval(-1), now: base)
        XCTAssertNil(before.point)
    }

    func testPermissionErrorAndSyncTimeRemainSeparateFromLegitimateOldMeasurement() {
        let old = MetricObservationSummary(points: [truthPoint(-90, 80)], range: .month1, now: base)
        let observed = old.observationLabel
        for (status, access) in [("Sync failed", "Permission denied"), ("Offline", "Access limited"), ("Synced", "")] {
            let synchronization = MetricStatsTruthPolicy.synchronizationText(
                status: status, lastCloudSync: base, healthAccessStatus: access)
            XCTAssertTrue(synchronization.contains(status))
            XCTAssertTrue(synchronization.contains("Last cloud sync"))
            if !access.isEmpty { XCTAssertTrue(synchronization.contains("Apple Health: \(access)")) }
            XCTAssertEqual(old.point?.value, 80)
            XCTAssertEqual(old.observationLabel, observed)
            XCTAssertFalse(old.observationLabel.contains("Sync"))
        }
        let unknown = MetricStatsTruthPolicy.synchronizationText(status: "Idle", lastCloudSync: nil, healthAccessStatus: "")
        XCTAssertTrue(unknown.contains("Cloud sync not yet recorded"))
        XCTAssertFalse(unknown.lowercased().contains("denied"), "Missing reads never establish denial")
    }

    func testDisplayUnitConversionPrecedesSingleRoundingAndDeltaUsesPercentagePoints() throws {
        let metric = [truthPoint(-1, 80), truthPoint(0, 80.02)]
        let imperial = metric.map { MetricChartDataPoint(date: $0.date, value: $0.value * 2.20462) }
        let kg = MetricObservationSummary(points: metric, range: .month1, now: base)
        let lbs = MetricObservationSummary(points: imperial, range: .month1, now: base)
        XCTAssertEqual(try XCTUnwrap(lbs.stats).delta, try XCTUnwrap(kg.stats).delta * 2.20462, accuracy: 0.00001)
        XCTAssertEqual(MetricObservationSummary.deltaText(0.049, unit: "kg"), "Unchanged at displayed precision")
        XCTAssertEqual(MetricObservationSummary.deltaText(-0.049, unit: "kg"), "Unchanged at displayed precision")
        XCTAssertEqual(MetricObservationSummary.deltaText(0.05, unit: "%"), "+0.1 percentage points")
        XCTAssertEqual(MetricObservationSummary.deltaText(-0.05, unit: "%"), "–0.1 percentage points")
    }

    func testCalendarWindowUsesLocalDayArithmeticThroughDSTAndExcludesFutureForAll() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for components in [DateComponents(year: 2_026, month: 3, day: 9, hour: 12),
                           DateComponents(year: 2_026, month: 11, day: 2, hour: 12)] {
            let now = try XCTUnwrap(calendar.date(from: components))
            let edge = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: now))
            let points = [MetricChartDataPoint(date: edge.addingTimeInterval(-1), value: 1),
                          MetricChartDataPoint(date: edge, value: 2), MetricChartDataPoint(date: now, value: 3),
                          MetricChartDataPoint(date: now.addingTimeInterval(1), value: 4)]
            let summary = MetricObservationSummary(points: points, range: .week1, now: now, calendar: calendar)
            XCTAssertEqual(summary.points.map(\.value), [2, 3])
            XCTAssertEqual(summary.displayInterval.lowerBound, edge)
            XCTAssertEqual(summary.stats?.delta, 1)
            XCTAssertNotEqual(now.timeIntervalSince(edge), 7 * 86_400)
            XCTAssertTrue(summary.dateText(now).contains(calendar.timeZone.abbreviation(for: now)!))
            XCTAssertEqual(MetricObservationSummary.window(points, range: .all, now: now).map(\.value), [1, 2, 3])
        }
    }

    private func truthPoint(_ days: Int, _ value: Double, presence: MetricPresence = .present) -> MetricChartDataPoint {
        MetricChartDataPoint(date: base.addingTimeInterval(Double(days) * 86_400), value: value, presence: presence)
    }

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
