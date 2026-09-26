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
            onLogWeight: { presentHomeV2LogSheet() }
        )
        .task(id: bodyMetrics.count) {
            if fullChartCache[.weight] == nil {
                await prewarmMetricCaches()
            }
        }
    }

    func openHomeV2Progress(metric: HomeV2ProgressMetric = .weight) {
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
        let system = currentMeasurementSystem
        switch metric {
        case .weight:
            // ponytail: PhaseInsightPolicy sorts the metrics on every read; cache it if Progress ever feels slow.
            let insight = PhaseInsightPolicy.insight(for: bodyMetrics)
            let title = homeV2PhaseSentence.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 } ?? insight.title
            return HomeV2ProgressSeries(
                daily: fullChartCache[.weight] ?? [],
                trend: fullTrendChartCache[.weight] ?? [],
                unit: homeV2DisplayUnit,
                deltaUnit: homeV2DisplayUnit,
                target: weightGoal.map { convertWeight($0, to: system) ?? $0 },
                sourceLine: nil,
                insightTitle: title,
                insightBody: [insight.message, insight.detail].compactMap { $0 }.joined(separator: " ")
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
                sourceLine: latestSource.map { HomeV2ProgressCopy.estimatedBy($0) },
                insightTitle: HomeV2ProgressCopy.bodyFatInsightTitle,
                insightBody: HomeV2ProgressCopy.bodyFatInsightBody
            )
        case .ffmi:
            return HomeV2ProgressSeries(
                daily: fullChartCache[.ffmi] ?? [],
                trend: [],
                unit: "",
                deltaUnit: "",
                target: ffmiGoal,
                sourceLine: HomeV2ProgressCopy.ffmiSource,
                insightTitle: HomeV2ProgressCopy.ffmiInsightTitle,
                insightBody: HomeV2ProgressCopy.ffmiInsightBody
            )
        case .steps:
            return HomeV2ProgressSeries(
                daily: fullChartCache[.steps] ?? [],
                trend: [],
                unit: "",
                deltaUnit: "",
                target: Double(stepGoal),
                sourceLine: HomeV2ProgressCopy.stepsSource,
                insightTitle: HomeV2ProgressCopy.stepsInsightTitle,
                insightBody: HomeV2ProgressCopy.stepsInsightBody
            )
        }
    }

    func homeV2ProgressValueText(_ metric: HomeV2ProgressMetric, _ value: Double) -> String {
        switch metric {
        case .steps:
            return FormatterCache.stepsFormatter.string(from: NSNumber(value: Int(value.rounded()))) ?? "\(Int(value.rounded()))"
        case .weight, .bodyFat, .ffmi:
            return String(format: "%.1f", value)
        }
    }
}
