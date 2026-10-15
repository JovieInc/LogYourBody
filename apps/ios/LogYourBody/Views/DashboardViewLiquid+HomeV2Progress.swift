//
// DashboardViewLiquid+HomeV2Progress.swift
// LogYourBody
//
import SwiftUI

extension DashboardViewLiquid {
    /// Progress (Pencil R1–R3) takes the Stats page's place while the gate is on.
    var homeV2ProgressView: some View {
        HomeV2ProgressView(
            metric: $homeV2ProgressMetric,
            range: $selectedRange,
            series: { homeV2ProgressSeries(for: $0) },
            formatValue: { homeV2ProgressValueText($0, $1) },
            onLogWeight: { presentHomeV2LogSheet() },
            isShareContextVisible: isMetricShareContextVisible && !isMetricDetailActive && !isStatsDestinationActive
        )
        .id(authManager.captureAccountSession())
    }

    func openHomeV2Progress(metric: HomeV2ProgressMetric = .bodyFat) {
        homeV2ProgressMetric = metric
        if !HomeV2TrendPolicy.visibleRanges.contains(selectedRange) {
            selectedRange = .month3
        }
        selectedPhotoTimelineRootPage = .analytics
        isHomeChatExpanded = false
        HapticManager.shared.selection()
    }

    /// Series come from the prewarmed whole-history caches (display units).
    func homeV2ProgressSeries(for metric: HomeV2ProgressMetric) -> HomeV2ProgressSeries {
        guard let ownership = authManager.captureAccountSession(), dashboardMetricsBelong(to: ownership) else {
            return HomeV2ProgressSeries(
                daily: [], trend: [], unit: "", deltaUnit: "", target: nil,
                provenance: nil, insightTitle: nil, insightBody: nil)
        }
        let system = currentMeasurementSystem
        switch metric {
        case .weight:
            // ponytail: PhaseInsightPolicy sorts the metrics on every read; cache it if Progress ever feels slow.
            let insight = PhaseInsightPolicy.insight(for: homeV2InsightMetrics)
            let title = homeV2PhaseSentence.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 } ?? insight.title
            let daily = HomeV2ProgressPolicy.supportedWeightPoints(
                fullChartCache[.weight] ?? [],
                system: system
            )
            let trend = HomeV2ProgressPolicy.supportedWeightPoints(
                fullTrendChartCache[.weight] ?? [],
                system: system
            )
            return HomeV2ProgressSeries(
                daily: daily,
                trend: trend,
                unit: homeV2DisplayUnit,
                deltaUnit: homeV2DisplayUnit,
                target: weightGoal.map { convertWeight($0, to: system) ?? $0 },
                provenance: HomeV2MetricEditorial.progressProvenance(metric: .weight, bodyFatSource: nil),
                insightTitle: title,
                insightBody: [insight.message, insight.detail].compactMap { $0 }.joined(separator: " "),
                shareEntries: cachedMetricEntries(for: .weight)?.entries ?? []
            )
        case .bodyFat:
            let latestSource = bodyMetrics
                .filter { $0.bodyFatPercentage != nil }
                .max { $0.date < $1.date }
                .map { HomeV2Provenance.label(for: $0) }
            return HomeV2ProgressSeries(
                daily: fullChartCache[.bodyFat] ?? [],
                trend: [],
                unit: "%",
                deltaUnit: "points",
                target: bodyFatGoal,
                provenance: HomeV2MetricEditorial.progressProvenance(metric: .bodyFat, bodyFatSource: latestSource),
                insightTitle: nil,
                insightBody: nil,
                shareEntries: cachedMetricEntries(for: .bodyFat)?.entries ?? []
            )
        case .ffmi:
            return HomeV2ProgressSeries(
                daily: fullChartCache[.ffmi] ?? [],
                trend: [],
                unit: "",
                deltaUnit: "",
                target: ffmiGoal,
                provenance: HomeV2MetricEditorial.progressProvenance(metric: .ffmi, bodyFatSource: nil),
                insightTitle: nil,
                insightBody: nil
            )
        case .steps:
            return HomeV2ProgressSeries(
                daily: fullChartCache[.steps] ?? [],
                trend: [],
                unit: HomeV2MetricEditorial.stepsDisplayUnit,
                deltaUnit: "",
                target: Double(stepGoal),
                provenance: HomeV2MetricEditorial.progressProvenance(metric: .steps, bodyFatSource: nil),
                insightTitle: nil,
                insightBody: nil,
                shareEntries: cachedMetricEntries(for: .steps)?.entries ?? []
            )
        }
    }

    func homeV2ProgressValueText(_ metric: HomeV2ProgressMetric, _ value: Double) -> String {
        switch metric {
        case .steps:
            return FormatterCache.formattedSteps(value) ?? "—"
        case .weight, .bodyFat, .ffmi:
            return String(format: "%.1f", value)
        }
    }
}
