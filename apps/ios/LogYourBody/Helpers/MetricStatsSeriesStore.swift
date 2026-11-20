//
// MetricStatsSeriesStore.swift
// LogYourBody
//
// Stats cards and legacy metric sparklines read the prewarmed chart caches.
// The series is adopted once per content fingerprint. Selecting a date or
// scrubbing reuses that series. A cache miss asks for the existing prewarm
// and keeps the last adopted series.

import Foundation

final class MetricStatsSeriesStore {
    private(set) var buildCount = 0
    private(set) var publishedFingerprint = 0
    private(set) var isReady = false
    private(set) var isRefreshInFlight = false

    typealias ChartCache = [DashboardViewLiquid.MetricType: [MetricChartDataPoint]]

    struct Input {
        var chart: ChartCache
        var trend: ChartCache
        var fingerprint: Int
        var ready: Bool
        var weightUsesTrend: Bool
        var range: TimeRange
        var selectedDate: Date?
        var now: Date
        var calendar: Calendar
        var onCacheMiss: () -> Void
    }

    struct BuiltCharts {
        var chart: ChartCache
        var trend: ChartCache
        var entries: MetricEntriesPayload?
        var fingerprint: Int
    }

    private var adoptedFingerprint: Int?
    private var chart: ChartCache = [:]
    private var trend: ChartCache = [:]
    private var hasSeries = false
    private var reportedMiss = false
    private var refreshGeneration = UUID()

    func invalidate() {
        adoptedFingerprint = nil
        chart = [:]
        trend = [:]
        hasSeries = false
        reportedMiss = false
    }

    /// Warmed empty: nothing to draw, and another prewarm would not help.
    func publishEmpty() {
        invalidate()
        publishedFingerprint = 0
        isReady = true
    }

    /// Caches were cleared while a rebuild is in flight. Keep the last series.
    func markRefreshing() {
        isReady = false
    }

    /// The detached prewarm finished. Copy the series now so a body evaluation
    /// that still sees empty view caches renders this snapshot.
    func publish(_ built: BuiltCharts) {
        if built.chart.isEmpty && built.trend.isEmpty {
            publishEmpty()
            return
        }
        publishedFingerprint = built.fingerprint
        isReady = true
        reportedMiss = false
        storeSeries(built.chart, built.trend, fingerprint: built.fingerprint)
    }

    func beginRefresh() -> UUID {
        let generation = UUID()
        refreshGeneration = generation
        isRefreshInFlight = true
        return generation
    }

    func endRefresh(_ generation: UUID) {
        guard refreshGeneration == generation else { return }
        isRefreshInFlight = false
    }

    func cancelRefresh() {
        refreshGeneration = UUID()
        isRefreshInFlight = false
    }

    func summaries(_ input: Input) -> [ContextualMetricKind: MetricObservationSummary] {
        guard adopt(input) else { return [:] }
        let weight = weightSeries(usesTrend: input.weightUsesTrend)
        return [
            .steps: MetricObservationSummary(
                points: chart[.steps] ?? [], range: input.range, now: input.now, calendar: input.calendar),
            .weight: MetricObservationSummary(
                points: weight, range: input.range, selectedDate: input.selectedDate,
                now: input.now, calendar: input.calendar),
            .bodyFat: MetricObservationSummary(
                points: chart[.bodyFat] ?? [], range: input.range, selectedDate: input.selectedDate,
                now: input.now, calendar: input.calendar),
            .ffmi: MetricObservationSummary(
                points: chart[.ffmi] ?? [], range: input.range, selectedDate: input.selectedDate,
                now: input.now, calendar: input.calendar)
        ]
    }

    func cardPoints(
        for kind: DashboardViewLiquid.MetricIdentifier, _ input: Input
    ) -> [MetricDataPoint] {
        guard adopt(input) else { return [] }
        switch kind {
        case .steps:
            let steps = chart[.steps] ?? []
            guard !steps.isEmpty else { return [] }
            return Self.stepsSparkline(steps, now: input.now, calendar: input.calendar)
        case .weight:
            return Self.sparkline(weightSeries(usesTrend: input.weightUsesTrend))
        case .bodyFat:
            return Self.sparkline(chart[.bodyFat] ?? [])
        case .ffmi:
            return Self.sparkline(chart[.ffmi] ?? [])
        }
    }

    func rangeStats(
        for kind: DashboardViewLiquid.MetricIdentifier, _ input: Input
    ) -> MetricRangeStats? {
        guard kind != .steps, adopt(input) else { return nil }
        let series = kind == .weight
            ? weightSeries(usesTrend: input.weightUsesTrend)
            : (chart[Self.metricType(kind)] ?? [])
        let window = Self.window(series, range: input.range, now: input.now, calendar: input.calendar)
        return computeRangeStats(points: window, requiresComparison: false, includesInferredValues: true)
    }

    func chartPoints(for type: DashboardViewLiquid.MetricType, _ input: Input) -> [MetricChartDataPoint] {
        guard adopt(input) else { return [] }
        return chart[type] ?? []
    }

    func trendPoints(for type: DashboardViewLiquid.MetricType, _ input: Input) -> [MetricChartDataPoint] {
        guard adopt(input) else { return [] }
        return trend[type] ?? []
    }

    static func contentFingerprint(chart: ChartCache, trend: ChartCache) -> Int {
        var hasher = Hasher()
        let order: [DashboardViewLiquid.MetricType] = [
            .steps, .weight, .bodyFat, .ffmi, .bodyScore, .glp1
        ]
        for type in order {
            mix(chart[type], into: &hasher)
            mix(trend[type], into: &hasher)
        }
        return hasher.finalize()
    }

    private func weightSeries(usesTrend: Bool) -> [MetricChartDataPoint] {
        let raw = chart[.weight] ?? []
        let smoothed = trend[.weight] ?? []
        return usesTrend ? smoothed : raw
    }

    /// Copies the prewarmed dictionaries once per fingerprint.
    private func adopt(_ input: Input) -> Bool {
        let cachesEmpty = input.chart.isEmpty && input.trend.isEmpty
        if cachesEmpty {
            if input.ready {
                reportedMiss = false
                return hasSeries
            }
            if !reportedMiss {
                reportedMiss = true
                input.onCacheMiss()
            }
            return hasSeries
        }
        reportedMiss = false
        storeSeries(input.chart, input.trend, fingerprint: input.fingerprint)
        return true
    }

    private func storeSeries(_ chart: ChartCache, _ trend: ChartCache, fingerprint: Int) {
        if hasSeries, adoptedFingerprint == fingerprint {
            return
        }
        buildCount += 1
        adoptedFingerprint = fingerprint
        PerfSignpost.measure("stats_series") {
            self.chart = chart
            self.trend = trend
            hasSeries = true
        }
    }

    private static func metricType(
        _ kind: DashboardViewLiquid.MetricIdentifier
    ) -> DashboardViewLiquid.MetricType {
        switch kind {
        case .steps: return .steps
        case .weight: return .weight
        case .bodyFat: return .bodyFat
        case .ffmi: return .ffmi
        }
    }

    private static func sparkline(_ series: [MetricChartDataPoint], limit: Int = 7) -> [MetricDataPoint] {
        series.suffix(limit).enumerated().map { index, point in
            MetricDataPoint(index: index, value: point.value)
        }
    }

    private static func stepsSparkline(
        _ series: [MetricChartDataPoint], now: Date, calendar: Calendar
    ) -> [MetricDataPoint] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: Double] = [:]
        for point in series where point.value.isFinite {
            byDay[calendar.startOfDay(for: point.date)] = max(point.value, 0)
        }
        var points: [MetricDataPoint] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            points.append(MetricDataPoint(index: 6 - offset, value: byDay[date] ?? 0))
        }
        return points
    }

    private static func window(
        _ series: [MetricChartDataPoint], range: TimeRange, now: Date, calendar: Calendar
    ) -> [MetricChartDataPoint] {
        guard let days = range.days,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else {
            return series
        }
        return series.filter { $0.date >= cutoff }
    }

    private static func mix(_ series: [MetricChartDataPoint]?, into hasher: inout Hasher) {
        guard let series else {
            hasher.combine(-1)
            return
        }
        hasher.combine(series.count)
        for point in series {
            hasher.combine(point.date.timeIntervalSinceReferenceDate)
            hasher.combine(point.value)
            hasher.combine(point.presence.rawValue)
        }
    }
}
