//
// HomeV2ProgressView.swift
// LogYourBody
//
import SwiftUI

/// The four metrics of the one Progress workspace (Pencil R1/R2).
enum HomeV2ProgressMetric: String, CaseIterable, Identifiable {
    case bodyFat
    case ffmi
    case weight
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

    /// The summary shows a range extreme, not a recommendation or goal.
    var prefersHigh: Bool { self == .steps }

    /// Steps count from zero. Body metrics stay padded so a small change stays visible.
    var anchorsChartToZero: Bool { self == .steps }
}

/// What Progress needs for one metric. Values are already in display units.
struct HomeV2ProgressSeries {
    let daily: [MetricChartDataPoint]
    let trend: [MetricChartDataPoint]
    let unit: String
    let deltaUnit: String
    let target: Double?
    let provenance: HomeV2ProvenanceDetail?
    let insightTitle: String?
    let insightBody: String?
    var shareEntries: [MetricHistoryEntry] = []
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
    static let sparseRequirement =
        "A trend needs data on \(HomeV2TrendPolicy.minimumDistinctDays) days in this range."
    static let earlierDataHint = "Choose a wider range to check earlier entries."
    static let bodyFatInsightTitle = "Body fat is an estimate"
    static let bodyFatInsightBody =
        "Scale and photo estimates drift day to day. The trend line matters more than any single reading."
    static let ffmiInsightTitle = "FFMI is derived"
    static let ffmiInsightBody = "Computed from weight, body fat and height, so it moves with the body-fat estimate."
    static let ffmiSource = "Estimated from weight, body fat and height"
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

    /// Latest day against the range average, so the hero number has a comparison.
    static func stepsComparison(latest: Double?, average: Double?, range: TimeRange) -> String {
        guard let latest, latest.isFinite, let average, average.isFinite,
              let averageText = FormatterCache.formattedSteps(average),
              let deltaText = FormatterCache.formattedSteps(abs(latest - average)) else {
            return noTrendYet
        }
        let delta = (latest - average).rounded()
        if abs(delta) < 1 {
            return "At the \(averageText) daily average \(rangeLabel(range))"
        }
        let direction = delta > 0 ? "above" : "below"
        return "\(deltaText) \(direction) the \(averageText) daily average \(rangeLabel(range))"
    }

    static func dataDaysSentence(days: Int) -> String {
        guard days > 0 else { return "No data in this range" }
        return "\(days) day\(days == 1 ? "" : "s") of data in this range"
    }
}

enum HomeV2ProgressPolicy {
    struct Stats: Equatable {
        let latest: Double?
        let start: Double?
        let startDate: Date?
        let extreme: Double?
        let extremeDate: Date?
        let delta: Double?
        let average: Double?
        let distinctDays: Int
    }

    static func stats(points: [MetricChartDataPoint], prefersHigh: Bool, calendar: Calendar = .current) -> Stats {
        let sorted = points.sorted { $0.date < $1.date }
        let values = sorted.map(\.value)
        let extreme = prefersHigh ? values.max() : values.min()
        let extremePoint = extreme.flatMap { target in
            sorted.filter { $0.value == target }.min { $0.date < $1.date }
        }
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let delta: Double? = (values.count > 1) ? (values.last ?? 0) - (values.first ?? 0) : nil
        return Stats(
            latest: values.last,
            start: values.first,
            startDate: sorted.first?.date,
            extreme: extreme,
            extremeDate: extremePoint?.date,
            delta: delta,
            average: average,
            distinctDays: Set(sorted.map { calendar.startOfDay(for: $0.date) }).count
        )
    }

    static func supportedWeightPoints(
        _ points: [MetricChartDataPoint],
        system: MeasurementSystem
    ) -> [MetricChartDataPoint] {
        points.filter { point in
            let kilograms = system == .imperial ? point.value.lbsToKg : point.value
            return HomeV2WeightQuality.isWithinSupportedLoggingRange(kilograms)
        }
    }
}

/// Progress (Pencil R1/R2/R3): one metric workspace. The selected metric and
/// its chart stay dominant; the longer reading sits behind View insight.
struct HomeV2ProgressView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var metric: HomeV2ProgressMetric
    @Binding var range: TimeRange
    let series: (HomeV2ProgressMetric) -> HomeV2ProgressSeries
    let formatValue: (HomeV2ProgressMetric, Double) -> String
    let onLogWeight: () -> Void
    var now = Date()
    var isShareContextVisible = true

    @State private var showsInsight = false
    @State private var showsMetricShare = false
    @State private var focusedSample: HomeV2ChartIntegrity.Sample?
    @State private var showsProvenance = false

    private static let contextDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    var body: some View {
        let truthEnabled = MetricStatsTruthPolicy.isEnabled()
        let current = series(metric)
        let visible = HomeV2MetricEditorial.observedPoints(
            HomeV2TrendPolicy.points(current.daily, in: range, now: now)
        )
        let hasEnoughData = HomeV2TrendPolicy.hasEnoughData(visible)
        let selected = shareSelection(for: metric, data: current)
        let activeFocus = selected.flatMap { $0.isFocused ? $0.point : nil }
        let observation = truthEnabled ? MetricObservationSummary(
            points: current.daily, range: range, selectedDate: activeFocus?.date, now: now) : nil
        let presented = HomeV2MetricEditorial.canvas(
            HomeV2MetricCanvasRequest(
                metric: metric,
                points: visible,
                unit: current.unit,
                deltaUnit: current.deltaUnit,
                range: range,
                provenance: truthEnabled ? nil : current.provenance,
                target: current.target,
                hasEnoughData: hasEnoughData,
                formatValue: { formatValue(metric, $0) },
                dateText: { Self.contextDateFormatter.string(from: $0) },
                observationSummary: observation
            )
        )

        VStack(spacing: 0) {
            switcher

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeV2MetricHero(
                        value: activeFocus.map { formatValue(metric, $0.value) } ?? presented.value,
                        unit: presented.unit,
                        comparison: observation?.changeText(unit: metric == .steps ? "steps" : current.unit) ?? activeFocus.map {
                            $0.date.formatted(date: .abbreviated, time: .omitted)
                        } ?? presented.comparison,
                        provenance: activeFocus == nil ? presented.provenance : nil,
                        onProvenancePresentationChange: { showsProvenance = $0 }
                    )
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.vertical, HomeV2Tokens.Space.margin)

                    if let observation {
                        let snapshot = truthSnapshot(for: metric, data: current, summary: observation)
                        Text([snapshot?.observation, snapshot?.evidence, snapshot?.provenanceLabel,
                              snapshot.map { "\($0.range) · Daily observations; gaps unfilled" },
                              snapshot?.trend].compactMap { $0 }.joined(separator: "\n"))
                            .font(.footnote)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, HomeV2Tokens.Space.inset)
                            .accessibilityIdentifier("home_v2_progress_observation_context")
                    }

                    if contextualSharePayload != nil, !showsProvenance {
                        Button { showsMetricShare = true } label: {
                            Label("Share \(metric.title)", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .padding(.horizontal, HomeV2Tokens.Space.inset)
                        .accessibilityIdentifier("home_v2_progress_share")
                    }

                    if hasEnoughData {
                        HomeV2TrendChart(
                            daily: current.daily,
                            trend: truthEnabled || current.trend.isEmpty ? current.daily : current.trend,
                            accent: metric.accent,
                            range: $range,
                            showsDots: !truthEnabled && !current.trend.isEmpty,
                            chartHeight: HomeV2Tokens.progressChartHeight,
                            axis: .months,
                            metricTitle: metric.title,
                            usesSevenDayAverage: !truthEnabled && !current.trend.isEmpty,
                            anchorsToZero: metric.anchorsChartToZero,
                            formatValue: { formatValue(metric, $0) },
                            onSelection: { focusedSample = $0 },
                            now: now
                        )
                        .id(metric)
                        .onDisappear { focusedSample = nil }
                        .padding(.top, HomeV2Tokens.Space.tight)
                        if let title = current.insightTitle, let body = current.insightBody {
                            insightRow(title: title, body: body)
                        }
                        statsRow(presented.context)
                    } else {
                        let earlier = visible.isEmpty && !current.daily.isEmpty
                        sparseHistory(hasEarlierData: earlier)
                    }
                }
            }
            .accessibilityIdentifier("home_v2_progress_scroll")

            if !hasEnoughData, metric == .weight {
                HomeV2Dock(title: HomeV2Copy.logWeight, identifier: "home_v2_progress_log_weight", action: onLogWeight)
            }
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .onChange(of: metric) { _, _ in
            showsInsight = false
            focusedSample = nil
        }
        .onChange(of: range) { _, _ in focusedSample = nil }
        .modifier(ContextualMetricShareModifier(
            payload: contextualSharePayload, isVisible: isShareContextVisible && !showsProvenance,
            directRequest: $showsMetricShare
        ))
    }

    private func shareSelection(
        for candidate: HomeV2ProgressMetric, data: HomeV2ProgressSeries
    ) -> ContextualMetricProgressPolicy.Selection? {
        if MetricStatsTruthPolicy.isEnabled() {
            return ContextualMetricProgressPolicy.presentationSelection(
                points: HomeV2TrendPolicy.points(data.daily, in: range, now: now), averages: [],
                focus: candidate == metric && focusedSample?.kind == .daily ? focusedSample : nil,
                usesCalendarDayDomain: true)
        }
        return ContextualMetricProgressPolicy.presentationSelection(
            points: HomeV2TrendPolicy.points(data.daily, in: range, now: now),
            averages: HomeV2TrendPolicy.points(data.trend, in: range, now: now),
            focus: candidate == metric ? focusedSample : nil
        )
    }

    private var contextualSharePayload: BodyScoreSharePayload? {
        let snapshots = HomeV2ProgressMetric.allCases.compactMap { candidate -> ContextualMetricSnapshot? in
            let data = series(candidate)
            let points = HomeV2TrendPolicy.points(data.daily, in: range, now: now)
            let stats = HomeV2ProgressPolicy.stats(
                points: HomeV2MetricEditorial.observedPoints(points), prefersHigh: candidate.prefersHigh)
            guard let selected = shareSelection(for: candidate, data: data),
                  let kind = ContextualMetricKind(rawValue: candidate.rawValue) else { return nil }
            if MetricStatsTruthPolicy.isEnabled() {
                let summary = MetricObservationSummary(points: data.daily, range: range,
                                                       selectedDate: selected.point.date, now: now)
                return truthSnapshot(for: candidate, data: data, summary: summary)
            }
            let trend = candidate == .steps
                ? HomeV2ProgressCopy.stepsComparison(latest: selected.point.value, average: stats.average, range: range)
                : HomeV2ProgressCopy.deltaSentence(delta: stats.delta, unit: data.deltaUnit, range: range)
            return ContextualMetricSnapshot(
                kind: kind, value: formatValue(candidate, selected.point.value), unit: candidate == .steps ? "steps" : data.unit,
                observation: selected.point.date.formatted(
                    date: .abbreviated, time: candidate == .steps ? .omitted : .shortened),
                range: range.accessibilityLabel,
                trend: HomeV2TrendPolicy.hasEnoughData(points) ? trend : nil,
                provenance: selected.source(entries: data.shareEntries),
                evidence: ContextualMetricEvidencePolicy.label(
                    for: kind, isEstimated: selected.point.isEstimated || selected.isSmoothed,
                    isSmoothed: kind == .weight && selected.isSmoothed)
            )
        }
        guard let kind = ContextualMetricKind(rawValue: metric.rawValue) else { return nil }
        return .contextual(snapshots, selected: kind)
    }

    private func truthSnapshot(for candidate: HomeV2ProgressMetric, data: HomeV2ProgressSeries,
                               summary: MetricObservationSummary) -> ContextualMetricSnapshot? {
        guard let kind = ContextualMetricKind(rawValue: candidate.rawValue) else { return nil }
        let source = kind == .ffmi ? "Derived from smoothed weight, body fat and height"
            : ContextualMetricSourcePolicy.source(for: summary.point, entries: data.shareEntries, fallback: nil)
        return .observationSummary(summary, kind: kind, unit: kind == .steps ? "steps" : data.unit,
                                   provenance: source ?? "Source unavailable or mixed")
    }

    private var switcher: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    metricButtons
                }
            } else {
                HStack(spacing: 0) {
                    metricButtons
                }
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(minHeight: HomeV2Tokens.rowHeight)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
    }

    private var metricButtons: some View {
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? HomeV2Tokens.Space.tight : 0)
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

    private func insightRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsInsight.toggle() }
            } label: {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                        Text(title)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        Text(showsInsight ? HomeV2ProgressCopy.hideInsight : HomeV2ProgressCopy.viewInsight)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    }
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .rotationEffect(.degrees(showsInsight ? 90 : 0))
                }
                .padding(.horizontal, HomeV2Tokens.Space.inset)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_progress_insight")

            if showsInsight {
                Text(body)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.inset)
                    .padding(.bottom, HomeV2Tokens.Space.compact)
                    .accessibilityIdentifier("home_v2_progress_insight_body")
            }
        }
    }

    private func statsRow(_ context: [HomeV2MetricContext]) -> some View {
        let cells = ForEach(context) { item in
            statCell(label: item.label, value: item.value)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { cells }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(context.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { divider }
                        statCell(label: item.label, value: item.value)
                    }
                }
            }
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

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.lead, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.vertical, HomeV2Tokens.Space.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sparseHistory(hasEarlierData: Bool) -> some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
            HomeV2RangePicker(range: $range, scrollsHorizontally: true)

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2ProgressCopy.sparseRequirement)
                if hasEarlierData {
                    Text(HomeV2ProgressCopy.earlierDataHint)
                }
            }
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .padding(.vertical, HomeV2Tokens.Space.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { HomeV2Hairline() }
            .overlay(alignment: .bottom) { HomeV2Hairline() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(metric.title) history. \(HomeV2ProgressCopy.sparseRequirement)" +
                    (hasEarlierData ? " \(HomeV2ProgressCopy.earlierDataHint)" : "")
            )
            .accessibilityIdentifier("home_v2_trend_chart")
        }
    }
}
