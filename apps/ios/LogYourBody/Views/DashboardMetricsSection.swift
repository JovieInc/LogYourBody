import SwiftUI

// MARK: - Metrics Section Wrapper

struct DashboardMetricsSection: View {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    @Environment(\.theme) private var theme

    @Binding var metricsOrder: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    let onReorder: () -> Void
    var truthSummaries: [ContextualMetricKind: MetricObservationSummary] = [:]
    var truthSnapshots: [ContextualMetricSnapshot] = []
    var truthSyncText = ""

    @State private var dropTargetMetric: MetricIdentifier?

    @Binding var selectedRange: TimeRange
    @Binding var selectedMetricType: DashboardViewLiquid.MetricType
    @Binding var isMetricDetailActive: Bool

    let currentMetric: BodyMetrics?
    let bodyMetrics: [BodyMetrics]
    let dailyMetrics: DailyMetrics?
    let weightUnit: String
    let stepsGoalText: String?
    let weightGoalText: String?
    let bodyFatGoalText: String?
    let ffmiGoalText: String?

    let generateStepsChartData: () -> [MetricDataPoint]
    let generateWeightChartData: () -> [MetricDataPoint]
    let generateBodyFatChartData: () -> [MetricDataPoint]
    let generateFFMIChartData: () -> [MetricDataPoint]

    let weightRangeStats: () -> MetricRangeStats?
    let bodyFatRangeStats: () -> MetricRangeStats?
    let ffmiRangeStats: () -> MetricRangeStats?

    let formatSteps: (Int?) -> String
    let formatWeightValue: (Double?) -> String
    let formatBodyFatValue: (Double?) -> String
    let formatFFMIValue: (BodyMetrics) -> String

    let makeTrend: (Double, String, TimeRange) -> MetricSummaryCard.Trend?
    let formatAverageFootnote: (Double, String) -> String
    let formatCardDateOnly: (Date?) -> String?
    let formatCardDate: (Date) -> String
    let latestStepsSnapshot: () -> (value: Int?, date: Date?)

    @Binding var weightUsesTrend: Bool
    let formatTrendWeightHeadline: (BodyMetrics, Bool) -> String

    var body: some View {
        DashboardMetricsList(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            dropTargetMetric: $dropTargetMetric,
            onReorder: onReorder,
            cardContent: { metric in
                metricCardView(for: metric)
            }
        )
        .accessibilityIdentifier("photo_timeline_stats_metric_stack")
    }

    @ViewBuilder
    private func metricCardView(for metric: MetricIdentifier) -> some View {
        if let snapshot = truthSnapshots.first(where: { $0.kind.rawValue == metric.rawValue }),
           let summary = truthSummaries[snapshot.kind] {
            truthMetricCard(snapshot, summary: summary)
        } else {
            switch metric {
            case .steps:
                stepsMetricCard()

            case .weight:
                weightMetricCard()

            case .bodyFat:
                bodyFatMetricCard()

            case .ffmi:
                ffmiMetricCard()
            }
        }
    }

    private func truthMetricCard(_ snapshot: ContextualMetricSnapshot, summary: MetricObservationSummary) -> some View {
        Button {
            switch snapshot.kind {
            case .steps: selectedMetricType = .steps
            case .weight: selectedMetricType = .weight
            case .bodyFat: selectedMetricType = .bodyFat
            case .ffmi: selectedMetricType = .ffmi
            case .bodyScore: selectedMetricType = .bodyScore
            }
            isMetricDetailActive = true
        } label: {
            MetricSummaryCard(
                icon: truthIcon(for: snapshot.kind),
                accentColor: truthAccent(for: snapshot.kind),
                state: .data(MetricSummaryCard.Content(
                    title: snapshot.kind.title, value: snapshot.value, unit: snapshot.unit,
                    timestamp: nil,
                    dataPoints: summary.points.enumerated().map {
                        MetricSummaryCard.DataPoint(index: $0.offset, value: $0.element.value, date: $0.element.date)
                    },
                    chartAccessibilityLabel: "\(snapshot.kind.title) · \(summary.periodLabel) · Observations only; gaps unfilled",
                    chartAccessibilityValue: snapshot.trend,
                    trend: nil,
                    footnote: [snapshot.observation, snapshot.evidence, snapshot.provenanceLabel, snapshot.trend,
                               truthGoal(for: snapshot.kind), truthSyncText]
                        .compactMap { $0 }.joined(separator: "\n"),
                    chartPeriod: "\(summary.periodLabel) · Observations; gaps unfilled",
                    chartInterval: summary.displayInterval
                )), isButtonContext: true
            )
        }
        .buttonStyle(MetricCardButtonStyle())
        .accessibilityIdentifier("photo_timeline_stats_metric_card_\(snapshot.kind == .bodyFat ? "body_fat" : snapshot.kind.rawValue)")
    }

    private func truthIcon(for kind: ContextualMetricKind) -> String {
        switch kind {
        case .steps: return "flame.fill"
        case .weight: return "figure.stand"
        case .bodyFat: return "percent"
        case .ffmi: return "figure.arms.open"
        case .bodyScore: return "star.fill"
        }
    }

    private func truthAccent(for kind: ContextualMetricKind) -> Color {
        switch kind {
        case .steps: return theme.colors.accentOrange
        case .weight: return theme.colors.accentViolet
        case .bodyFat: return theme.colors.accentPink
        case .ffmi: return theme.colors.accentTeal
        case .bodyScore: return theme.colors.primary
        }
    }

    private func truthGoal(for kind: ContextualMetricKind) -> String? {
        switch kind {
        case .steps: return stepsGoalText
        case .weight: return weightGoalText
        case .bodyFat: return bodyFatGoalText
        case .ffmi: return ffmiGoalText
        case .bodyScore: return nil
        }
    }

    // MARK: - Metric Card Builders

    @ViewBuilder
    private func stepsMetricCard() -> some View {
        Button {
            selectedMetricType = .steps
            isMetricDetailActive = true
        } label: {
            let latestSteps = latestStepsSnapshot()

            MetricSummaryCard(
                icon: "flame.fill",
                accentColor: theme.colors.accentOrange,
                state: .data(MetricSummaryCard.Content(
                    title: "Steps",
                    value: formatSteps(latestSteps.value),
                    unit: "steps",
                    timestamp: formatCardDateOnly(latestSteps.date),
                    dataPoints: generateStepsChartData().map { point in
                        MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                    },
                    chartAccessibilityLabel: "Steps trend for the past week",
                    chartAccessibilityValue: "Latest value \(formatSteps(latestSteps.value)) steps",
                    trend: nil,
                    footnote: stepsGoalText
                )),
                isButtonContext: true
            )
        }
        .buttonStyle(MetricCardButtonStyle())
        .accessibilityIdentifier("photo_timeline_stats_metric_card_steps")
    }

    @ViewBuilder
    private func weightMetricCard() -> some View {
        if let currentMetric {
            let stats = weightRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, weightUnit) }
            Button {
                selectedMetricType = .weight
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "figure.stand",
                    accentColor: theme.colors.accentViolet,
                    state: .data(MetricSummaryCard.Content(
                        title: "Weight",
                        value: formatTrendWeightHeadline(currentMetric, weightUsesTrend),
                        unit: weightUnit,
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateWeightChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "Weight trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatTrendWeightHeadline(currentMetric, weightUsesTrend)) \(weightUnit)",
                        trend: stats.flatMap { makeTrend($0.delta, weightUnit, selectedRange) },
                        footnote: metricSummaryFootnote(averageText: averageText, goalText: weightGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
            .accessibilityIdentifier("photo_timeline_stats_metric_card_weight")
        }
    }

    @ViewBuilder
    private func bodyFatMetricCard() -> some View {
        if let currentMetric {
            let stats = bodyFatRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, "%") }
            Button {
                selectedMetricType = .bodyFat
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "percent",
                    accentColor: theme.colors.accentPink,
                    state: .data(MetricSummaryCard.Content(
                        title: "Body Fat",
                        value: formatBodyFatValue(currentMetric.bodyFatPercentage),
                        unit: "%",
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateBodyFatChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "Body fat percentage trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatBodyFatValue(currentMetric.bodyFatPercentage))%",
                        trend: stats.flatMap { makeTrend($0.delta, "%", selectedRange) },
                        footnote: metricSummaryFootnote(averageText: averageText, goalText: bodyFatGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
            .accessibilityIdentifier("photo_timeline_stats_metric_card_body_fat")
        }
    }

    @ViewBuilder
    private func ffmiMetricCard() -> some View {
        if let currentMetric {
            let stats = ffmiRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, "") }
            Button {
                selectedMetricType = .ffmi
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "figure.arms.open",
                    accentColor: theme.colors.accentTeal,
                    state: .data(MetricSummaryCard.Content(
                        title: "FFMI",
                        value: formatFFMIValue(currentMetric),
                        unit: "",
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateFFMIChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "FFMI trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatFFMIValue(currentMetric))",
                        trend: stats.flatMap { makeTrend($0.delta, "", selectedRange) },
                        footnote: metricSummaryFootnote(averageText: averageText, goalText: ffmiGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
            .accessibilityIdentifier("photo_timeline_stats_metric_card_ffmi")
        }
    }
}
