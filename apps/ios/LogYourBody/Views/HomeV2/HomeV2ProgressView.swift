//
// HomeV2ProgressView.swift
// LogYourBody
//
import SwiftUI

/// The four metrics of the one Progress workspace (Pencil R1/R2).
enum HomeV2ProgressMetric: String, CaseIterable, Identifiable {
    case weight
    case bodyFat
    case ffmi
    case steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .bodyFat: return "Body fat"
        case .ffmi: return "FFMI"
        case .steps: return "Steps"
        }
    }

    var identifier: String {
        switch self {
        case .weight: return "weight"
        case .bodyFat: return "body_fat"
        case .ffmi: return "ffmi"
        case .steps: return "steps"
        }
    }

    var accent: Color {
        switch self {
        case .weight: return HomeV2Tokens.Metric.weight
        case .bodyFat: return HomeV2Tokens.Metric.bodyFat
        case .ffmi: return HomeV2Tokens.Metric.ffmi
        case .steps: return HomeV2Tokens.Metric.steps
        }
    }

    /// Steps count up; everything else reads best as its low.
    var prefersHigh: Bool { self == .steps }
}

/// What Progress needs for one metric. Values are already in display units.
struct HomeV2ProgressSeries {
    let daily: [MetricChartDataPoint]
    let trend: [MetricChartDataPoint]
    let unit: String
    let deltaUnit: String
    let target: Double?
    let sourceLine: String?
    let insightTitle: String
    let insightBody: String
}

enum HomeV2ProgressCopy {
    static let title = "Progress"
    static let viewInsight = "View insight"
    static let hideInsight = "Hide insight"
    static let start = "Start"
    static let low = "Low"
    static let high = "High"
    static let target = "Target"
    static let notSet = "Not set"
    static let keepLogging = "Keep logging"
    static let keepLoggingBody =
        "After 7 days you’ll see pace, and whether this looks like a cut, maintenance or a gain."
    static let bodyFatInsightTitle = "Body fat is an estimate"
    static let bodyFatInsightBody =
        "Scale and photo estimates drift day to day. The trend line matters more than any single reading."
    static let ffmiInsightTitle = "FFMI is derived"
    static let ffmiInsightBody = "Computed from weight, body fat and height, so it moves with the body-fat estimate."
    static let ffmiSource = "Estimated from weight, body fat and height"
    static let stepsInsightTitle = "Steps come from Apple Health"
    static let stepsInsightBody = "Daily totals as your iPhone or watch recorded them. Nothing is written back."
    static let stepsSource = "Apple Health"
    static let noTrendYet = "Your trend appears after 7 days"

    static func estimatedBy(_ source: String) -> String {
        source == HomeV2ContextCopy.typed ? "Estimated, typed by you" : "Estimated by your \(source)"
    }

    static func rangeLabel(_ range: TimeRange) -> String {
        switch range {
        case .week1: return "in 7 days"
        case .month1: return "in 30 days"
        case .month3: return "in 3 months"
        case .month6: return "in 6 months"
        case .year1: return "in a year"
        case .all: return "overall"
        }
    }

    /// "Down 4.1 lb in 3 months", "Down 0.9 points in 3 months", "No change in 30 days".
    static func deltaSentence(delta: Double?, unit: String, range: TimeRange) -> String {
        guard let delta else { return noTrendYet }
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change \(rangeLabel(range))" }
        let direction = delta < 0 ? "Down" : "Up"
        let value = String(format: "%.1f", magnitude)
        let unitText = unit.isEmpty ? "" : " \(unit)"
        return "\(direction) \(value)\(unitText) \(rangeLabel(range))"
    }

    static func stepsAverageSentence(average: Int?, range: TimeRange) -> String {
        guard let average, let text = FormatterCache.stepsFormatter.string(from: NSNumber(value: average)) else {
            return noTrendYet
        }
        return "Averaging \(text) a day \(rangeLabel(range))"
    }

    /// R3: "3 days logged. Your trend appears after 7."
    static func loggedDaysSentence(days: Int) -> String {
        "\(days) day\(days == 1 ? "" : "s") logged. Your trend appears after \(HomeV2TrendPolicy.minimumDistinctDays)."
    }
}

enum HomeV2ProgressPolicy {
    struct Stats: Equatable {
        let latest: Double?
        let start: Double?
        let extreme: Double?
        let delta: Double?
        let average: Double?
        let distinctDays: Int
    }

    static func stats(points: [MetricChartDataPoint], prefersHigh: Bool, calendar: Calendar = .current) -> Stats {
        let sorted = points.sorted { $0.date < $1.date }
        let values = sorted.map(\.value)
        let extreme = prefersHigh ? values.max() : values.min()
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let delta: Double? = (values.count > 1) ? (values.last ?? 0) - (values.first ?? 0) : nil
        return Stats(
            latest: values.last,
            start: values.first,
            extreme: extreme,
            delta: delta,
            average: average,
            distinctDays: Set(sorted.map { calendar.startOfDay(for: $0.date) }).count
        )
    }
}

/// Progress (Pencil R1/R2/R3): one metric workspace. The selected metric and
/// its chart stay dominant; the longer reading sits behind View insight.
struct HomeV2ProgressView: View {
    @Binding var metric: HomeV2ProgressMetric
    @Binding var range: TimeRange
    let series: (HomeV2ProgressMetric) -> HomeV2ProgressSeries
    let formatValue: (HomeV2ProgressMetric, Double) -> String
    let onLogWeight: () -> Void
    var now = Date()

    @State private var showsInsight = false

    var body: some View {
        let current = series(metric)
        let visible = HomeV2TrendPolicy.points(current.daily, in: range, now: now)
        let stats = HomeV2ProgressPolicy.stats(points: visible, prefersHigh: metric.prefersHigh)
        let hasEnoughData = HomeV2TrendPolicy.hasEnoughData(visible)

        VStack(spacing: 0) {
            switcher

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline(current, stats: stats, hasEnoughData: hasEnoughData)

                    if hasEnoughData {
                        HomeV2TrendChart(
                            daily: current.daily,
                            trend: current.trend.isEmpty ? current.daily : current.trend,
                            accent: metric.accent,
                            range: $range,
                            showsDots: !current.trend.isEmpty,
                            chartHeight: HomeV2Tokens.progressChartHeight,
                            axis: .months,
                            now: now
                        )
                        .padding(.top, HomeV2Tokens.Space.tight)

                        insightRow(current)
                        statsRow(stats, target: current.target)
                    } else if metric == .weight {
                        keepLoggingCard
                    }
                }
            }

            if !hasEnoughData, metric == .weight {
                HomeV2Dock(title: HomeV2Copy.logWeight, identifier: "home_v2_progress_log_weight", action: onLogWeight)
            }
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .onChange(of: metric) { _, _ in showsInsight = false }
    }

    private var switcher: some View {
        HStack(spacing: 0) {
            ForEach(HomeV2ProgressMetric.allCases) { candidate in
                let isSelected = candidate == metric
                Button {
                    metric = candidate
                    HapticManager.shared.selection()
                } label: {
                    Text(candidate.title)
                        .scaledSystemFont(
                            size: HomeV2Tokens.TypeSize.title,
                            weight: isSelected ? .semibold : .medium,
                            relativeTo: .body
                        )
                        .foregroundStyle(isSelected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? HomeV2Tokens.Colors.ink : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.title) progress")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("home_v2_progress_tab_\(candidate.identifier)")
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(minHeight: HomeV2Tokens.rowHeight)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
    }

    private func headline(_ current: HomeV2ProgressSeries, stats: HomeV2ProgressPolicy.Stats, hasEnoughData: Bool) -> some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
            HStack(alignment: .lastTextBaseline, spacing: HomeV2Tokens.Space.tight) {
                Text(stats.latest.map { formatValue(metric, $0) } ?? "—")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.progressValue, weight: .bold, relativeTo: .largeTitle)
                    .kerning(-2)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("home_v2_progress_value")

                if !current.unit.isEmpty {
                    Text(current.unit)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.lead, relativeTo: .title3)
                        .foregroundStyle(HomeV2Tokens.Colors.muted)
                }
            }

            Text(deltaText(current, stats: stats, hasEnoughData: hasEnoughData))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home_v2_progress_delta")

            if let sourceLine = current.sourceLine {
                Text(sourceLine)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.vertical, HomeV2Tokens.Space.margin)
    }

    private func deltaText(_ current: HomeV2ProgressSeries, stats: HomeV2ProgressPolicy.Stats, hasEnoughData: Bool) -> String {
        guard hasEnoughData else {
            return metric == .weight
                ? HomeV2ProgressCopy.loggedDaysSentence(days: stats.distinctDays)
                : HomeV2ProgressCopy.noTrendYet
        }
        if metric == .steps {
            return HomeV2ProgressCopy.stepsAverageSentence(average: stats.average.map { Int($0.rounded()) }, range: range)
        }
        return HomeV2ProgressCopy.deltaSentence(delta: stats.delta, unit: current.deltaUnit, range: range)
    }

    private func insightRow(_ current: HomeV2ProgressSeries) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsInsight.toggle() }
            } label: {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                        Text(current.insightTitle)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        Text(showsInsight ? HomeV2ProgressCopy.hideInsight : HomeV2ProgressCopy.viewInsight)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                            .foregroundStyle(HomeV2Tokens.Colors.muted)
                    }
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeV2Tokens.Colors.quiet)
                        .rotationEffect(.degrees(showsInsight ? 90 : 0))
                }
                .padding(.horizontal, HomeV2Tokens.Space.inset)
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_progress_insight")

            if showsInsight {
                Text(current.insightBody)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.bottom, HomeV2Tokens.Space.compact)
                    .accessibilityIdentifier("home_v2_progress_insight_body")
            }
        }
    }

    private func statsRow(_ stats: HomeV2ProgressPolicy.Stats, target: Double?) -> some View {
        HStack(spacing: 0) {
            statCell(label: HomeV2ProgressCopy.start, value: stats.start)
            divider
            statCell(label: metric.prefersHigh ? HomeV2ProgressCopy.high : HomeV2ProgressCopy.low, value: stats.extreme)
            divider
            statCell(label: HomeV2ProgressCopy.target, value: target)
        }
        .frame(minHeight: 68)
        .overlay(alignment: .top) { HomeV2Hairline() }
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityIdentifier("home_v2_progress_stats")
    }

    private var divider: some View {
        Rectangle()
            .fill(HomeV2Tokens.Colors.border)
            .frame(width: HomeV2Tokens.Space.hairline)
    }

    private func statCell(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
            Text(value.map { formatValue(metric, $0) } ?? HomeV2ProgressCopy.notSet)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.lead, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var keepLoggingCard: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2ProgressCopy.keepLogging)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Text(HomeV2ProgressCopy.keepLoggingBody)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.vertical, HomeV2Tokens.Space.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { HomeV2Hairline() }
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home_v2_progress_keep_logging")
    }
}
