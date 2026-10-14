//
// HomeV2TrendChart.swift
// LogYourBody
//
import Charts
import SwiftUI

/// What the metric-first Home chart shows for a range, and when it is honest
/// to draw a trend at all (Pencil H1: "Your trend appears after 7 days").
enum HomeV2TrendPolicy {
    static let visibleRanges: [TimeRange] = [.month1, .month3, .month6, .year1, .all]
    static let minimumDistinctDays = 7
    static let sevenDayAverageLabel = "7-day average"
    static let notEnoughData = "Your trend appears after 7 days"

    static func points(
        _ points: [MetricChartDataPoint],
        in range: TimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MetricChartDataPoint] {
        guard let days = range.days,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else {
            return points
        }
        return points.filter { $0.date >= cutoff }
    }

    static func hasEnoughData(_ points: [MetricChartDataPoint], calendar: Calendar = .current) -> Bool {
        Set(points.map { calendar.startOfDay(for: $0.date) }).count >= minimumDistinctDays
    }

    static func startLabel(for points: [MetricChartDataPoint], formatter: DateFormatter) -> String {
        guard let first = points.min(by: { $0.date < $1.date }) else { return " " }
        return formatter.string(from: first.date)
    }
}

/// Edge-to-edge trend for the metric-first Home: daily dots, the 7-day average
/// as a straight-segment line (no smoothing that invents peaks), faint grid,
/// text range tabs. Geometry is identical with and without enough data.
struct HomeV2TrendChart: View {
    enum Axis {
        /// Start date on the left, "7-day average" on the right (Home).
        case trend
        /// Full dates under the plot (Progress and the timeline).
        case months
    }

    let daily: [MetricChartDataPoint]
    let trend: [MetricChartDataPoint]
    let accent: Color
    @Binding var range: TimeRange
    var showsRangeTabs = true
    var showsDots = true
    var chartHeight: CGFloat = HomeV2Tokens.chartHeight
    var axis: Axis = .trend
    var metricTitle = "Weight"
    var usesSevenDayAverage = true
    var anchorsToZero = false
    var requiresMinimumDays = true
    var plotIdentifier = "home_v2_trend_chart"
    /// Progress can scrub a day. The home pager keeps the drag for changing days.
    var allowsSelection = true
    var formatValue: (Double) -> String = { String(format: "%.1f", $0) }
    var now = Date()

    @State private var selectedX: Date?

    private static let startFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private var visibleDaily: [MetricChartDataPoint] { HomeV2TrendPolicy.points(daily, in: range, now: now) }
    private var visibleTrend: [MetricChartDataPoint] { HomeV2TrendPolicy.points(trend, in: range, now: now) }
    private var hasEnoughData: Bool { HomeV2TrendPolicy.hasEnoughData(HomeV2MetricEditorial.observedPoints(visibleDaily)) }

    private var plotted: HomeV2ChartIntegrity.Plot {
        HomeV2ChartIntegrity.plot(
            points: usesSevenDayAverage ? visibleTrend : visibleDaily,
            dotPoints: showsDots ? visibleDaily : [],
            anchorsToZero: anchorsToZero,
            keepsCarriedValues: usesSevenDayAverage
        )
    }

    private var showsPlot: Bool {
        if requiresMinimumDays { return hasEnoughData && !plotted.marks.isEmpty }
        return !plotted.marks.isEmpty
    }

    private var selectedSample: HomeV2ChartIntegrity.Sample? {
        guard let selectedX else { return nil }
        return HomeV2ChartIntegrity.nearest(to: selectedX, in: plotted.selectionSamples)
    }

    private var selectedTooltip: String? {
        guard let selectedSample else { return nil }
        return HomeV2ChartIntegrity.tooltip(
            date: selectedSample.date,
            valueText: formatValue(selectedSample.value),
            locale: .current,
            kind: selectedSample.kind
        )
    }

    var accessibilitySummary: String {
        guard showsPlot else {
            return "\(metricTitle) history. \(HomeV2TrendPolicy.notEnoughData)"
        }
        return usesSevenDayAverage
            ? "\(metricTitle) trend, \(HomeV2TrendPolicy.sevenDayAverageLabel)"
            : "\(metricTitle) history"
    }

    var accessibilityValueText: String {
        let ticks = plotted.yTicks
        let low = HomeV2ChartIntegrity.tickLabel(ticks.first ?? 0, integers: anchorsToZero)
        let high = HomeV2ChartIntegrity.tickLabel(ticks.last ?? 0, integers: anchorsToZero)
        var parts = ["Scale from \(low) to \(high)"]
        if anchorsToZero { parts.append("starting at zero") }
        if let selectedTooltip { parts.append(selectedTooltip) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPlot {
                if allowsSelection {
                    tooltipRow
                }
                chart
                    .frame(height: chartHeight)
                if axis == .months {
                    if usesSevenDayAverage {
                        Text(HomeV2TrendPolicy.sevenDayAverageLabel)
                            .font(.caption)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .padding(.horizontal, HomeV2Tokens.Space.inset)
                            .padding(.top, HomeV2Tokens.Space.tight)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                placeholder
                    .frame(height: chartHeight)
            }
            if axis == .trend {
                axisRow
            }
            if showsRangeTabs {
                HomeV2RangePicker(range: $range)
            }
        }
        .onChange(of: range) { _, _ in selectedX = nil }
    }

    private var tooltipRow: some View {
        Text(selectedTooltip ?? " ")
            .font(.caption)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget / 2, alignment: .leading)
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .accessibilityIdentifier("home_v2_chart_tooltip")
            .accessibilityHidden(selectedTooltip == nil)
    }

    private var chart: some View {
        plottedChart
            .animation(nil, value: range)
    }

    @ViewBuilder
    private var plottedChart: some View {
        if allowsSelection {
            plotMarks.chartXSelection(value: $selectedX)
        } else {
            plotMarks
        }
    }

    private var plotMarks: some View {
        Chart {
            lineMarks
            pointMarks
            selectionMarks
        }
        .chartYScale(domain: plotted.yDomain)
        .chartXAxis {
            AxisMarks(values: plotted.xAxisDates) { value in
                AxisGridLine().foregroundStyle(HomeV2Tokens.Colors.border)
                if axis == .months, let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(HomeV2ChartIntegrity.axisLabel(date: date, range: range, locale: .current))
                            .font(.caption)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: plotted.yTicks) { _ in
                AxisGridLine().foregroundStyle(HomeV2Tokens.Colors.border)
                if anchorsToZero {
                    AxisValueLabel(format: .number.precision(.fractionLength(0)))
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .font(.caption)
                } else {
                    AxisValueLabel(format: .number.precision(.fractionLength(1)))
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .font(.caption)
                }
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.horizontal, HomeV2Tokens.Space.tight)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(allowsSelection ? "Drag across the chart to read a day" : "")
        .accessibilityHidden(!allowsSelection)
        .accessibilityIdentifier(plotIdentifier)
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(Array(plotted.runs.enumerated()), id: \.offset) { index, run in
            if run.count > 1 {
                ForEach(run) { sample in
                    LineMark(
                        x: .value("Day", sample.date),
                        y: .value("Value", sample.value),
                        series: .value("Run", index)
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(accent)
                }
            }
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(plotted.marks) { sample in
            PointMark(x: .value("Day", sample.date), y: .value("Value", sample.value))
                .symbolSize(sample.id == plotted.marks.last?.id ? 56 : 18)
                .foregroundStyle(accent.opacity(sample.id == plotted.marks.last?.id ? 1 : 0.45))
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let selectedSample {
            RuleMark(x: .value("Selected", selectedSample.date))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
            PointMark(
                x: .value("Selected", selectedSample.date),
                y: .value("Selected", selectedSample.value)
            )
            .symbolSize(80)
            .foregroundStyle(accent)
        }
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let ordered = plotted.selectionSamples
        guard !ordered.isEmpty else { return }
        let current = selectedSample.flatMap { sample in ordered.firstIndex { $0.id == sample.id } }
        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(ordered.count - 1, (current ?? -1) + 1)
        case .decrement:
            nextIndex = max(0, (current ?? 0) - 1)
        @unknown default:
            return
        }
        selectedX = ordered[nextIndex].date
    }

    private var placeholder: some View {
        Text(HomeV2TrendPolicy.notEnoughData)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityIdentifier(plotIdentifier)
    }

    private var axisRow: some View {
        HStack {
            Text(showsPlot ? HomeV2TrendPolicy.startLabel(for: visibleDaily, formatter: Self.startFormatter) : " ")
            Spacer(minLength: HomeV2Tokens.Space.tight)
            Text(showsPlot && usesSevenDayAverage ? HomeV2TrendPolicy.sevenDayAverageLabel : " ")
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.top, HomeV2Tokens.Space.tight)
    }
}

/// Shared range controls. Sparse Progress can scroll them at large text sizes.
struct HomeV2RangePicker: View {
    @Binding var range: TimeRange
    var scrollsHorizontally = false

    var body: some View {
        Group {
            if scrollsHorizontally {
                ScrollView(.horizontal, showsIndicators: false) {
                    choices
                }
            } else {
                choices
            }
        }
        .accessibilityIdentifier("home_v2_range_selector")
    }

    private var choices: some View {
        HStack(spacing: HomeV2Tokens.Space.inset) {
            ForEach(HomeV2TrendPolicy.visibleRanges, id: \.self) { candidate in
                let isSelected = candidate == range
                Button {
                    range = candidate
                } label: {
                    Text(candidate.rawValue)
                        .scaledSystemFont(
                            size: HomeV2Tokens.TypeSize.secondary,
                            weight: isSelected ? .semibold : .medium,
                            relativeTo: .subheadline
                        )
                        .foregroundStyle(isSelected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.quiet)
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.rawValue) range")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("home_v2_range_\(candidate.rawValue)")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.top, HomeV2Tokens.Space.tight)
    }
}
