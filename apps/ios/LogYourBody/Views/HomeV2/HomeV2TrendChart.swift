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
    let daily: [MetricChartDataPoint]
    let trend: [MetricChartDataPoint]
    let accent: Color
    @Binding var range: TimeRange
    var now = Date()

    private static let startFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private var visibleDaily: [MetricChartDataPoint] { HomeV2TrendPolicy.points(daily, in: range, now: now) }
    private var visibleTrend: [MetricChartDataPoint] { HomeV2TrendPolicy.points(trend, in: range, now: now) }
    private var hasEnoughData: Bool { HomeV2TrendPolicy.hasEnoughData(visibleDaily) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if hasEnoughData {
                    chart
                } else {
                    placeholder
                }
            }
            .frame(height: HomeV2Tokens.chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hasEnoughData ? "Weight trend, \(HomeV2TrendPolicy.sevenDayAverageLabel)" : HomeV2TrendPolicy.notEnoughData)
            .accessibilityIdentifier("home_v2_trend_chart")

            axisRow
            rangeTabs
        }
    }

    private var chart: some View {
        Chart {
            ForEach(visibleDaily) { point in
                PointMark(x: .value("Day", point.date), y: .value("Value", point.value))
                    .symbolSize(10)
                    .foregroundStyle(accent.opacity(0.35))
            }

            ForEach(visibleTrend) { point in
                LineMark(x: .value("Day", point.date), y: .value("Trend", point.value))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(accent)
            }

            if let last = visibleTrend.last {
                PointMark(x: .value("Day", last.date), y: .value("Trend", last.value))
                    .symbolSize(60)
                    .foregroundStyle(accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(HomeV2Tokens.Colors.border)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartPlotStyle { plot in
            plot.padding(.trailing, HomeV2Tokens.Space.compact)
        }
    }

    private var placeholder: some View {
        Text(HomeV2TrendPolicy.notEnoughData)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
            .foregroundStyle(HomeV2Tokens.Colors.quiet)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var axisRow: some View {
        HStack {
            Text(hasEnoughData ? HomeV2TrendPolicy.startLabel(for: visibleDaily, formatter: Self.startFormatter) : " ")
            Spacer(minLength: HomeV2Tokens.Space.tight)
            Text(hasEnoughData ? HomeV2TrendPolicy.sevenDayAverageLabel : " ")
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
        .foregroundStyle(HomeV2Tokens.Colors.quiet)
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.top, HomeV2Tokens.Space.tight)
    }

    private var rangeTabs: some View {
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
