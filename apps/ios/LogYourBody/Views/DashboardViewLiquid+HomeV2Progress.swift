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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeV2DisclosureLink(title: "Entries", identifier: "home_v2_metric_entries") {
                if homeV2ProgressMetric == .steps {
                    selectedMetricType = .steps
                    isMetricDetailActive = true
                } else {
                    isHomeV2EntriesPresented = true
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .background(HomeV2Tokens.Colors.shell)
        }
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
            return HomeV2ProgressSeries(
                daily: HomeV2ProgressPolicy.supportedWeightPoints(fullChartCache[.weight] ?? [], system: system),
                trend: HomeV2ProgressPolicy.supportedWeightPoints(fullTrendChartCache[.weight] ?? [], system: system),
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
                .map { HomeV2Provenance.label(for: $0, field: .bodyFat) }
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
    /// Raw observations remain raw; no inferred measurement becomes an entry.
    @ViewBuilder
    var homeV2SelectedMetricEntries: some View {
        let snapshot = homeV2Timeline
        if let ownership = authManager.captureAccountSession(), hasCurrentDashboardPublication,
           snapshot.isOwned(by: ownership) {
            HomeV2EntriesView(
                sections: homeV2MetricEntrySections(snapshot: snapshot),
                onSelect: { captured in
                    guard authManager.ownsAccountSession(ownership), homeV2Timeline.isOwned(by: ownership),
                          homeV2Timeline.metrics == snapshot.metrics,
                          HomeV2EntriesPolicy.admittedMetric(
                              captured, metrics: snapshot.metrics, ownership: ownership,
                              currentOwnership: authManager.captureAccountSession()
                          ) != nil,
                          let metric = HomeV2EntriesPolicy.admittedMetric(
                              captured, metrics: bodyMetrics, ownership: ownership,
                              currentOwnership: authManager.captureAccountSession()
                          ), homeV2Timeline.metric(for: .init(metric)) == metric else { return }
                    selectHomeV2TimelineEntry(.init(metric))
                    guard homeV2TimelineSelection == HomeV2TimelinePolicy.Selection(metric) else { return }
                    openHomeV2Context(on: metric.date)
                },
                onBack: { isHomeV2EntriesPresented = false }
            )
        }
    }

    func homeV2MetricEntrySections(snapshot: HomeV2TimelinePolicy.Snapshot) -> [HomeV2EntriesSection] {
        let calendar = Calendar.current
        let rows: [HomeV2EntriesRow] = snapshot.metrics.compactMap { metric in
            let text: String
            let source: String
            switch homeV2ProgressMetric {
            case .weight:
                guard let raw = metric.weight, raw.isFinite else { return nil }
                let value = UnitConversion.displayWeight(raw, useMetric: currentMeasurementSystem == .metric)
                text = HomeV2Provenance.weightText(displayValue: value, metric: metric, unit: homeV2DisplayUnit)
                source = HomeV2Provenance.weightSubline(for: metric)
            case .bodyFat:
                guard let reading = HomeV2EditorialPolicy.bodyFat(in: metric) else { return nil }
                text = String(format: "%.1f%%", reading.percentage)
                source = reading.caption
            case .ffmi:
                guard let value = homeV2FFMIValue(metric), value.isFinite else { return nil }
                text = String(format: "%.1f", value)
                source = "Derived from recorded weight, body fat and profile height"
            case .steps:
                return nil // Daily-metric entries use their existing detail renderer.
            }
            return HomeV2EntriesRow(
                id: metric.id, date: metric.date,
                dayText: metric.date.formatted(date: .abbreviated, time: .shortened),
                source: source,
                valueText: text,
                photoURL: PhotoTimelineHUDPolicy.hasUsablePhoto(metric) ? metric.photoUrl : nil,
                metric: metric
            )
        }
        let groups = Dictionary(grouping: rows) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return groups.keys.sorted(by: >).map { month in
            HomeV2EntriesSection(
                id: String(month.timeIntervalSince1970), title: month.formatted(.dateTime.month(.wide).year()),
                delta: nil, rows: (groups[month] ?? []).sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
            )
        }
    }
}
