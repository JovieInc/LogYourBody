//
// MetricStatsSeriesStoreTests.swift
// LogYourBodyTests
//

import XCTest
@testable import LogYourBody

final class MetricStatsSeriesStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testSummariesBuildOnceForTheSameFingerprintAndSkipASelectedDateChange() {
        let store = MetricStatsSeriesStore()
        let earlier = now.addingTimeInterval(-86_400)
        var misses = 0
        let input = makeInput(
            chart: chart(weight: (80, 81), bodyFat: 20, steps: 1_000),
            trend: trend(weight: (70, 71), bodyFat: 99),
            fingerprint: 42,
            ready: true,
            selectedDate: earlier,
            onMiss: { misses += 1 }
        )

        let first = store.summaries(input)
        let second = store.summaries(input)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(misses, 0)
        XCTAssertEqual(first[.weight]?.point?.value, 70)
        XCTAssertEqual(second[.weight]?.point?.date, first[.weight]?.point?.date)
        XCTAssertEqual(first[.steps]?.point?.value, 1_000)
        XCTAssertEqual(first[.bodyFat]?.point?.value, 20, "Body fat stays on the daily cache")

        var selectedNow = input
        selectedNow.selectedDate = now
        let third = store.summaries(selectedNow)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(third[.weight]?.point?.value, 71)
        XCTAssertEqual(store.cardPoints(for: .weight, selectedNow).last?.value, 71)
        XCTAssertEqual(store.rangeStats(for: .weight, selectedNow)?.startValue, 70)
        XCTAssertEqual(store.buildCount, 1)
    }

    func testCacheMissSchedulesPrewarmAndRendersTheLastSnapshot() {
        let store = MetricStatsSeriesStore()
        let earlier = now.addingTimeInterval(-86_400)
        var misses = 0
        let warm = makeInput(
            chart: chart(weight: (80, 81), bodyFat: 20, steps: 1_000),
            trend: trend(weight: (70, 71), bodyFat: 99),
            fingerprint: 7,
            ready: true,
            selectedDate: now,
            onMiss: { misses += 1 }
        )
        XCTAssertEqual(store.summaries(warm)[.weight]?.point?.value, 71)
        XCTAssertEqual(store.buildCount, 1)

        var gap = warm
        gap.chart = [:]
        gap.trend = [:]
        gap.ready = false
        gap.fingerprint = 8
        gap.selectedDate = earlier
        let during = store.summaries(gap)
        XCTAssertEqual(misses, 1)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(during[.weight]?.point?.value, 70)
        XCTAssertEqual(store.summaries(gap)[.weight]?.point?.value, 70)
        XCTAssertEqual(misses, 1)

        var stillReady = gap
        stillReady.ready = true
        XCTAssertEqual(store.summaries(stillReady)[.weight]?.point?.value, 70)
        XCTAssertEqual(misses, 1)
        XCTAssertEqual(store.buildCount, 1)

        store.invalidate()
        var cleared = gap
        cleared.ready = true
        XCTAssertTrue(store.summaries(cleared).isEmpty)
        XCTAssertEqual(misses, 1)
        XCTAssertEqual(store.buildCount, 1)

        var rebuilt = warm
        rebuilt.fingerprint = 9
        XCTAssertEqual(store.summaries(rebuilt)[.weight]?.point?.value, 71)
        XCTAssertEqual(store.buildCount, 2)
    }

    func testPublishAdoptsOnceAndSummariesDoNotRebuild() {
        let store = MetricStatsSeriesStore()
        let chart = chart(weight: (80, 81), bodyFat: 20, steps: 1_000)
        let trend = trend(weight: (70, 71), bodyFat: 99)
        let fingerprint = MetricStatsSeriesStore.contentFingerprint(chart: chart, trend: trend)
        store.publish(MetricStatsSeriesStore.BuiltCharts(
            chart: chart, trend: trend, entries: nil, fingerprint: fingerprint
        ))
        XCTAssertEqual(store.buildCount, 1)

        var misses = 0
        let input = makeInput(
            chart: chart, trend: trend, fingerprint: fingerprint, ready: true,
            selectedDate: now, onMiss: { misses += 1 }
        )
        XCTAssertEqual(store.summaries(input)[.weight]?.point?.value, 71)
        XCTAssertEqual(store.summaries(input)[.weight]?.point?.value, 71)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(misses, 0)

        store.publish(MetricStatsSeriesStore.BuiltCharts(
            chart: [:], trend: [:], entries: nil, fingerprint: 0
        ))
        XCTAssertTrue(store.summaries(makeInput(
            chart: [:], trend: [:], fingerprint: 0, ready: true,
            selectedDate: now, onMiss: { misses += 1 }
        )).isEmpty)
        XCTAssertEqual(store.buildCount, 1)
        XCTAssertEqual(misses, 0)
    }

    func testContentFingerprintTracksSeriesContentsOnly() {
        let chart = chart(weight: (80, 81), bodyFat: 20, steps: 1_000)
        let trend = trend(weight: (70, 71), bodyFat: 99)
        let first = MetricStatsSeriesStore.contentFingerprint(chart: chart, trend: trend)
        XCTAssertEqual(MetricStatsSeriesStore.contentFingerprint(chart: chart, trend: trend), first)

        var changed = chart
        changed[.weight, default: []].append(MetricChartDataPoint(date: now.addingTimeInterval(10), value: 90))
        XCTAssertNotEqual(MetricStatsSeriesStore.contentFingerprint(chart: changed, trend: trend), first)
    }

    func testStatsSeriesSignpostIsRegistered() {
        XCTAssertTrue(PerfSignpost.registeredNames.contains("stats_series"))
    }

    private func makeInput(
        chart: MetricStatsSeriesStore.ChartCache,
        trend: MetricStatsSeriesStore.ChartCache,
        fingerprint: Int,
        ready: Bool,
        selectedDate: Date?,
        onMiss: @escaping () -> Void
    ) -> MetricStatsSeriesStore.Input {
        MetricStatsSeriesStore.Input(
            chart: chart,
            trend: trend,
            fingerprint: fingerprint,
            ready: ready,
            weightUsesTrend: true,
            range: .all,
            selectedDate: selectedDate,
            now: now,
            calendar: .current,
            onCacheMiss: onMiss
        )
    }

    private func chart(weight: (Double, Double), bodyFat: Double, steps: Double) -> MetricStatsSeriesStore.ChartCache {
        let earlier = now.addingTimeInterval(-86_400)
        return [
            .weight: [point(earlier, weight.0), point(now, weight.1)],
            .bodyFat: [point(now, bodyFat)],
            .steps: [point(now, steps)],
            .ffmi: [point(now, 21)]
        ]
    }

    private func trend(weight: (Double, Double), bodyFat: Double) -> MetricStatsSeriesStore.ChartCache {
        let earlier = now.addingTimeInterval(-86_400)
        return [
            .weight: [point(earlier, weight.0), point(now, weight.1)],
            .bodyFat: [point(now, bodyFat)]
        ]
    }

    private func point(_ date: Date, _ value: Double) -> MetricChartDataPoint {
        MetricChartDataPoint(date: date, value: value)
    }
}
