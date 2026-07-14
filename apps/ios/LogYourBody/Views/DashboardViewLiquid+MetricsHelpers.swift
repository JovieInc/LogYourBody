import SwiftUI
import Foundation

extension DashboardViewLiquid {
    // MARK: - Animation Helpers

    /// Update animated metric values with 180ms ease-out animation
    func updateAnimatedValues(for index: Int) {
        let metrics = viewModel.bodyMetrics
        guard index >= 0 && index < metrics.count else { return }
        let metric = metrics[index]

        let interval = PerfSignpost.begin("scrub_update_animated_values")
        defer { PerfSignpost.end(interval) }

        withAnimation(.easeOut(duration: 0.18)) {
            // Weight
            let weightResult: InterpolatedMetric?
            if let weight = metric.weight {
                weightResult = InterpolatedMetric(
                    value: weight,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                )
            } else {
                weightResult = MetricsInterpolationService.shared.estimateWeight(
                    for: metric.date,
                    metrics: viewModel.bodyMetrics
                )
            }

            if let weightResult {
                let system = currentMeasurementSystem
                animatedWeight = convertWeight(weightResult.value, to: system) ?? weightResult.value
            }

            // Body Fat
            let bodyFatResult: InterpolatedMetric?
            if let bodyFatPercentage = metric.bodyFatPercentage {
                bodyFatResult = InterpolatedMetric(
                    value: bodyFatPercentage,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                )
            } else {
                bodyFatResult = MetricsInterpolationService.shared.estimateBodyFat(
                    for: metric.date,
                    metrics: viewModel.bodyMetrics
                )
            }

            if let bodyFatResult {
                animatedBodyFat = bodyFatResult.value
            }

            // FFMI
            let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
            )

            if let heightInches,
               let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                   for: metric.date,
                   metrics: viewModel.bodyMetrics,
                   heightInches: heightInches
               ) {
                animatedFFMI = ffmiResult.value
            }
        }
    }

    // MARK: - Metrics View Helpers

    func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "–" }
        return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    func formatWeightValue(_ weight: Double?) -> String {
        guard let weight = weight else { return "–" }
        let system = currentMeasurementSystem
        let converted = convertWeight(weight, to: system) ?? weight
        // Display with a single decimal place for consistency across views
        return String(format: "%.1f", converted)
    }

    func formatBodyFatValue(_ bodyFat: Double?) -> String {
        guard let bodyFat = bodyFat else {
            // Try to get estimated value
            if let metric = currentMetric,
               let estimated = MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics) {
                return String(format: "%.1f", estimated.value)
            }
            return "–"
        }
        return String(format: "%.1f", bodyFat)
    }

    func formatFFMIValue(_ metric: BodyMetrics) -> String {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        if let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
            for: metric.date,
            metrics: bodyMetrics,
            heightInches: heightInches
        ) {
            // Apple Health-style: no decimals for FFMI headline value
            return String(format: "%.0f", ffmiResult.value)
        }
        return "–"
    }

    /// Headline formatter for the weight metric card using trend-weight when enabled.
    func formatTrendWeightHeadline(_ metric: BodyMetrics, usesTrend: Bool) -> String {
        let system = currentMeasurementSystem

        if usesTrend,
           let trendResult = MetricsInterpolationService.shared.estimateTrendWeight(
               for: metric.date,
               metrics: bodyMetrics
           ) {
            let converted = convertWeight(trendResult.value, to: system) ?? trendResult.value
            return String(format: "%.1f", converted)
        }

        if let rawWeight = metric.weight {
            let converted = convertWeight(rawWeight, to: system) ?? rawWeight
            return String(format: "%.1f", converted)
        }

        if let trendFallback = MetricsInterpolationService.shared.estimateTrendWeight(
            for: metric.date,
            metrics: bodyMetrics
        ) {
            let converted = convertWeight(trendFallback.value, to: system) ?? trendFallback.value
            return String(format: "%.1f", converted)
        }

        return "–"
    }

    // MARK: - Metric Entries Helpers

    func metricEntriesPayload(for metricType: MetricType) -> MetricEntriesPayload? {
        switch metricType {
        case .weight:
            return weightEntriesPayload()
        case .bodyFat:
            return bodyFatEntriesPayload()
        case .ffmi:
            return ffmiEntriesPayload()
        case .steps:
            return stepsEntriesPayload()
        case .glp1:
            return glp1EntriesPayload()
        case .bodyScore:
            return bodyScoreEntriesPayload()
        }
    }

    func stepsEntriesPayload() -> MetricEntriesPayload? {
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 0)

        let entries = recentDailyMetrics
            .sorted { $0.date < $1.date }
            .compactMap { metric -> MetricHistoryEntry? in
                guard let steps = metric.steps, steps > 0 else { return nil }
                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: Double(steps),
                    secondaryValue: nil,
                    source: .healthKit
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .steps,
            unitLabel: "steps",
            secondaryUnitLabel: nil,
            primaryFormatter: primaryFormatter,
            secondaryFormatter: nil
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    func weightEntriesPayload() -> MetricEntriesPayload? {
        let system = currentMeasurementSystem
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        let secondaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                guard let rawWeight = metric.weight else { return nil }
                let convertedWeight = convertWeight(rawWeight, to: system) ?? rawWeight
                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: convertedWeight,
                    secondaryValue: metric.bodyFatPercentage,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .weight,
            unitLabel: system.weightUnit,
            secondaryUnitLabel: "%",
            primaryFormatter: primaryFormatter,
            secondaryFormatter: secondaryFormatter
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    func bodyFatEntriesPayload() -> MetricEntriesPayload? {
        let system = currentMeasurementSystem
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 1)
        let secondaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)

        let interpolationContext = MetricsInterpolationService.shared
            .makeBodyFatInterpolationContext(for: bodyMetrics)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                let primaryValue = metric.bodyFatPercentage
                    ?? interpolationContext?.estimate(for: metric.date)?.value
                guard let bodyFatValue = primaryValue else { return nil }

                let secondaryValue: Double?
                if let weight = metric.weight {
                    secondaryValue = convertWeight(weight, to: system) ?? weight
                } else {
                    secondaryValue = nil
                }

                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: bodyFatValue,
                    secondaryValue: secondaryValue,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .bodyFat,
            unitLabel: "%",
            secondaryUnitLabel: system.weightUnit,
            primaryFormatter: primaryFormatter,
            secondaryFormatter: secondaryFormatter
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    func ffmiEntriesPayload() -> MetricEntriesPayload? {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return nil }

        guard let interpolationContext = MetricsInterpolationService.shared
            .makeFFMIInterpolationContext(for: bodyMetrics, heightInches: heightInches) else {
            return nil
        }

        let formatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 1)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                guard let ffmiResult = interpolationContext.estimate(for: metric.date) else {
                    return nil
                }

                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: ffmiResult.value,
                    secondaryValue: nil,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .ffmi,
            unitLabel: "",
            secondaryUnitLabel: nil,
            primaryFormatter: formatter,
            secondaryFormatter: nil
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    func glp1EntriesPayload() -> MetricEntriesPayload? {
        guard !glp1DoseLogs.isEmpty else { return nil }

        let logs = glp1DoseLogs.sorted { $0.takenAt < $1.takenAt }
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 1)

        let entries: [MetricHistoryEntry] = logs.compactMap { log in
            guard let dose = log.doseAmount else { return nil }
            return MetricHistoryEntry(
                id: log.id,
                date: log.takenAt,
                primaryValue: dose,
                secondaryValue: nil,
                source: .manual
            )
        }

        guard !entries.isEmpty else { return nil }

        let unitLabel = logs.first?.doseUnit ?? "mg"

        let config = MetricEntriesConfiguration(
            metricType: .glp1,
            unitLabel: unitLabel,
            secondaryUnitLabel: nil,
            primaryFormatter: primaryFormatter,
            secondaryFormatter: nil
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    func metricEntrySourceType(from dataSource: String?) -> MetricEntrySourceType {
        let normalized = dataSource?.lowercased() ?? ""

        if normalized.contains("healthkit") || normalized.contains("health") {
            return .healthKit
        }

        if normalized.isEmpty || normalized == "manual" {
            return .manual
        }

        return .integration(id: dataSource)
    }

    func formatTime(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        return FormatterCache.shortTimeFormatter.string(from: date)
    }

    func formatDate(_ date: Date) -> String {
        return FormatterCache.mediumDateFormatter.string(from: date)
    }

    func formatCardDateOnly(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)

        if day == today {
            return "Today"
        }

        if let days = calendar.dateComponents([.day], from: day, to: today).day, days == 1 {
            return "Yesterday"
        }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        if sameYear {
            return FormatterCache.monthDayFormatter.string(from: date)
        } else {
            return FormatterCache.monthYearFormatter.string(from: date)
        }
    }

    func formatCardDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)

        if day == today {
            return "Today"
        }

        if let days = calendar.dateComponents([.day], from: day, to: today).day, days == 1 {
            return "Yesterday"
        }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        if sameYear {
            return FormatterCache.monthDayFormatter.string(from: date)
        } else {
            return FormatterCache.monthYearFormatter.string(from: date)
        }
    }

    func generateStepsChartData() -> [MetricDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = dailyMetricsLookup()

        guard !lookup.isEmpty else { return [] }

        var chartData: [MetricDataPoint] = []

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let stepsValue = lookup[date]?.steps
            chartData.append(
                MetricDataPoint(index: 6 - offset, value: Double(max(stepsValue ?? 0, 0)))
            )
        }

        return chartData
    }

    func latestStepsSnapshot() -> (value: Int?, date: Date?) {
        // Prefer Core Data so we can fall back to the most recent day with data
        guard authManager.currentUser?.id != nil else {
            return (dailyMetrics?.steps, dailyMetrics?.date)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = dailyMetricsLookup()

        // Look back up to 30 days for the latest non-zero steps entry
        for offset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let entry = lookup[date], let steps = entry.steps, steps > 0 {
                return (steps, entry.date)
            }
        }

        if let metrics = dailyMetrics {
            return (metrics.steps, metrics.date)
        }

        return (nil, nil)
    }

    func dailyMetricsLookup() -> [Date: DailyMetrics] {
        if !dailyMetricsLookupCache.isEmpty || recentDailyMetrics.isEmpty {
            return dailyMetricsLookupCache
        }

        return makeDailyMetricsLookup()
    }

    func rebuildDailyMetricsLookupCache() {
        dailyMetricsLookupCache = makeDailyMetricsLookup()
    }

    private func makeDailyMetricsLookup() -> [Date: DailyMetrics] {
        var lookup = [Date: DailyMetrics](minimumCapacity: recentDailyMetrics.count)
        let calendar = Calendar.current

        for metric in recentDailyMetrics {
            let key = calendar.startOfDay(for: metric.date)
            if let existing = lookup[key] {
                if metric.updatedAt > existing.updatedAt {
                    lookup[key] = metric
                }
            } else {
                lookup[key] = metric
            }
        }

        return lookup
    }

    func generateWeightChartData() -> [MetricDataPoint] {
        let system = currentMeasurementSystem

        let allPoints: [Double] = sortedBodyMetricsAscending.compactMap { metric in
            guard let weight = metric.weight else { return nil }
            return convertWeight(weight, to: system) ?? weight
        }

        let tail = Array(allPoints.suffix(7))
        return tail.enumerated().map { index, value in
            MetricDataPoint(index: index, value: value)
        }
    }

    func generateBodyFatChartData() -> [MetricDataPoint] {
        let interpolationContext = MetricsInterpolationService.shared
            .makeBodyFatInterpolationContext(for: bodyMetrics)

        let allPoints: [Double] = sortedBodyMetricsAscending.compactMap { metric in
            if let bf = metric.bodyFatPercentage {
                return bf
            }
            if let estimated = interpolationContext?.estimate(for: metric.date) {
                return estimated.value
            }
            return nil
        }

        let tail = Array(allPoints.suffix(7))
        return tail.enumerated().map { index, value in
            MetricDataPoint(index: index, value: value)
        }
    }

    func generateFFMIChartData() -> [MetricDataPoint] {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return [] }

        guard let interpolationContext = MetricsInterpolationService.shared
            .makeFFMIInterpolationContext(for: bodyMetrics, heightInches: heightInches) else {
            return []
        }

        let allPoints: [Double] = sortedBodyMetricsAscending.compactMap { metric in
            guard let ffmiResult = interpolationContext.estimate(for: metric.date) else {
                return nil
            }
            return ffmiResult.value
        }

        let tail = Array(allPoints.suffix(7))
        return tail.enumerated().map { index, value in
            MetricDataPoint(index: index, value: value)
        }
    }

    func filteredMetrics(for range: TimeRange) -> [BodyMetrics] {
        guard let days = range.days else {
            return sortedBodyMetricsAscending
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sortedBodyMetricsAscending.filter { $0.date >= cutoffDate }
    }

    func cachedMetricEntries(for type: MetricType) -> MetricEntriesPayload? {
        if let cached = metricEntriesCache[type] {
            return cached
        }
        return metricEntriesPayload(for: type)
    }

    func cachedChartData(
        for type: MetricType,
        generator: () -> [MetricChartDataPoint]
    ) -> [MetricChartDataPoint] {
        if let cached = fullChartCache[type] {
            return cached
        }
        return generator()
    }

    func weightRangeStats() -> MetricRangeStats? {
        let system = currentMeasurementSystem
        return computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            guard let weight = metric.weight else { return nil }
            return convertWeight(weight, to: system) ?? weight
        }
    }

    func bodyFatRangeStats() -> MetricRangeStats? {
        let interpolationContext = MetricsInterpolationService.shared
            .makeBodyFatInterpolationContext(for: bodyMetrics)

        return computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            if let value = metric.bodyFatPercentage {
                return value
            }
            return interpolationContext?.estimate(for: metric.date)?.value
        }
    }

    func ffmiRangeStats() -> MetricRangeStats? {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return nil }

        guard let interpolationContext = MetricsInterpolationService.shared
            .makeFFMIInterpolationContext(for: bodyMetrics, heightInches: heightInches) else {
            return nil
        }

        return computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            interpolationContext.estimate(for: metric.date)?.value
        }
    }
}
