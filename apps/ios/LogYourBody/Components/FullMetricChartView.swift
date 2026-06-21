import SwiftUI
import Charts

// MARK: - Chart Mode & Quick Stats

enum ChartMode: CaseIterable {
    case trend
    case raw

    var label: String {
        switch self {
        case .trend: return "Smoothed"
        case .raw: return "Raw"
        }
    }
}

// MARK: - Time Range & Data Points

enum TimeRange: String, CaseIterable {
    case week1 = "1W"
    case month1 = "1M"
    case month3 = "3M"
    case month6 = "6M"
    case year1 = "1Y"
    case all = "All"

    /// Approximate length of the range in days for filtering.
    /// `.all` returns nil to indicate the full available history should be shown.
    var days: Int? {
        switch self {
        case .week1:
            return 7
        case .month1:
            return 30
        case .month3:
            return 90
        case .month6:
            return 180
        case .year1:
            return 365
        case .all:
            return nil
        }
    }
}

struct MetricChartDataPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    let presence: MetricPresence

    var id: String {
        "\(date.timeIntervalSince1970)-\(value)-\(presence.rawValue)"
    }

    var isEstimated: Bool {
        presence != .present
    }

    init(
        date: Date,
        value: Double,
        presence: MetricPresence = .present
    ) {
        self.date = date
        self.value = value
        self.presence = presence
    }

    init(
        date: Date,
        value: Double,
        isEstimated: Bool
    ) {
        self.init(
            date: date,
            value: value,
            presence: isEstimated ? .interpolated : .present
        )
    }
}

// MARK: - Chart Series Preprocessing

struct ChartSeriesPreprocessor {
    let referenceDate: Date
    private let calendar = Calendar.current

    func seriesByRange(from points: [MetricChartDataPoint]) -> [TimeRange: [MetricChartDataPoint]] {
        guard !points.isEmpty else { return [:] }

        let sorted = points.sorted { $0.date < $1.date }
        var result: [TimeRange: [MetricChartDataPoint]] = [:]

        for range in TimeRange.allCases {
            let filtered = filter(sorted, for: range)
            result[range] = downsampleIfNeeded(filtered, limit: maxPointCount(for: range))
        }

        return result
    }

    private func filter(_ points: [MetricChartDataPoint], for range: TimeRange) -> [MetricChartDataPoint] {
        guard let days = range.days else {
            return points
        }

        let cutoff = calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return points.filter { $0.date >= cutoff }
    }

    private func maxPointCount(for range: TimeRange) -> Int {
        switch range {
        case .week1:
            return 140
        case .month1:
            return 180
        case .month3:
            return 210
        case .month6:
            return 240
        case .year1:
            return 260
        case .all:
            return 320
        }
    }

    private func downsampleIfNeeded(_ points: [MetricChartDataPoint], limit: Int) -> [MetricChartDataPoint] {
        guard points.count > limit, limit >= 3 else { return points }
        return largestTriangleThreeBuckets(points: points, threshold: limit)
    }

    private func largestTriangleThreeBuckets(points: [MetricChartDataPoint], threshold: Int) -> [MetricChartDataPoint] {
        guard threshold < points.count else { return points }

        let dataCount = points.count
        let bucketSize = Double(dataCount - 2) / Double(threshold - 2)

        var sampled: [MetricChartDataPoint] = [points[0]]
        var aIndex = 0

        for bucket in 0..<(threshold - 2) {
            let rangeStart = Int(floor(Double(bucket) * bucketSize)) + 1
            var rangeEnd = Int(floor(Double(bucket + 1) * bucketSize)) + 1
            rangeEnd = min(rangeEnd, dataCount - 1)

            let avgRangeStart = Int(floor(Double(bucket + 1) * bucketSize)) + 1
            var avgRangeEnd = Int(floor(Double(bucket + 2) * bucketSize)) + 1
            avgRangeEnd = min(avgRangeEnd, dataCount)

            let average = averagedPoint(points, start: avgRangeStart, end: avgRangeEnd)

            if rangeStart >= rangeEnd {
                continue
            }

            let ax = timeValue(points[aIndex])
            let ay = points[aIndex].value

            var maxArea: Double = -1
            var selectedIndex = rangeStart

            for index in rangeStart..<rangeEnd {
                let bx = timeValue(points[index])
                let by = points[index].value
                let cx = average.x
                let cy = average.y

                let area = abs((ax * (by - cy) + bx * (cy - ay) + cx * (ay - by)) * 0.5)

                if area > maxArea {
                    maxArea = area
                    selectedIndex = index
                }
            }

            sampled.append(points[selectedIndex])
            aIndex = selectedIndex
        }

        sampled.append(points.last!)
        return sampled
    }

    private func averagedPoint(_ points: [MetricChartDataPoint], start: Int, end: Int) -> (x: Double, y: Double) {
        guard !points.isEmpty else { return (0, 0) }

        let safeStart = min(max(start, 0), points.count - 1)
        let safeEndExclusive = max(min(end, points.count), safeStart + 1)

        if safeStart >= safeEndExclusive {
            let point = points[safeStart]
            return (timeValue(point), point.value)
        }

        var sumX: Double = 0
        var sumY: Double = 0
        let count = safeEndExclusive - safeStart

        for index in safeStart..<safeEndExclusive {
            let point = points[index]
            sumX += timeValue(point)
            sumY += point.value
        }

        return (sumX / Double(count), sumY / Double(count))
    }

    private func timeValue(_ point: MetricChartDataPoint) -> Double {
        point.date.timeIntervalSince1970
    }
}

// MARK: - Metric Entries Support

enum MetricEntrySourceType: Equatable {
    case manual
    case healthKit
    case integration(id: String?)
}

struct MetricHistoryEntry: Identifiable, Sendable {
    let id: String
    let date: Date
    let primaryValue: Double
    let secondaryValue: Double?
    let source: MetricEntrySourceType
}

struct MetricEntriesConfiguration {
    let metricType: DashboardViewLiquid.MetricType
    let unitLabel: String
    let secondaryUnitLabel: String?
    let primaryFormatter: NumberFormatter
    let secondaryFormatter: NumberFormatter?
}

struct MetricEntriesPayload {
    let config: MetricEntriesConfiguration
    let entries: [MetricHistoryEntry]
}

struct MetricDetailRelatedMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let caption: String
    let systemImageName: String
}

func makeMetricFormatter(minFractionDigits: Int = 0, maxFractionDigits: Int = 1) -> NumberFormatter {
    MetricFormatterCache.formatter(minFractionDigits: minFractionDigits, maxFractionDigits: maxFractionDigits)
}

private struct HistorySection: Identifiable, Sendable {
    let id: String
    let title: String
    let showsHeader: Bool
    let entries: [MetricHistoryEntry]
}

private struct ChartPresenceLegendItem: Identifiable {
    let presence: MetricPresence
    let label: String
    let total: Int

    var id: String {
        presence.rawValue
    }
}

// MARK: - Full Metric Chart View

struct FullMetricChartView: View {
    let title: String
    let icon: String
    let iconColor: Color
    let currentValue: String
    let unit: String
    let currentDate: String
    let chartData: [MetricChartDataPoint]
    let onAdd: (() -> Void)?
    let metricEntries: MetricEntriesPayload?
    let relatedMetrics: [MetricDetailRelatedMetric]

    let goalValue: Double?

    @Binding var selectedTimeRange: TimeRange
    @Binding var selectedTimelineDate: Date?
    @State private var cachedSeries: [TimeRange: [MetricChartDataPoint]] = [:]
    @State private var isLoadingData = false
    @State private var lastFingerprint: String = ""
    @State private var chartMode: ChartMode = .trend
    @State private var activePoint: MetricChartDataPoint?
    @State private var isScrubbing = false
    @State private var activeHistorySectionIndex: Int?
    @State private var isHistoryScrubbing = false

    @State private var localHistorySections: [HistorySection]?
    @State private var historyEntryPendingDeletion: MetricHistoryEntry?
    @State private var showingHistoryDeleteConfirmation = false

    @ScaledMetric(relativeTo: .largeTitle) private var headlineValueFontSize: CGFloat = 56

    private let chartHeight: CGFloat = 320

    init(
        title: String,
        icon: String,
        iconColor: Color,
        currentValue: String,
        unit: String,
        currentDate: String,
        chartData: [MetricChartDataPoint],
        onAdd: (() -> Void)?,
        metricEntries: MetricEntriesPayload?,
        relatedMetrics: [MetricDetailRelatedMetric] = [],
        goalValue: Double?,
        selectedTimeRange: Binding<TimeRange>,
        selectedTimelineDate: Binding<Date?> = .constant(nil)
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.currentValue = currentValue
        self.unit = unit
        self.currentDate = currentDate
        self.chartData = chartData
        self.onAdd = onAdd
        self.metricEntries = metricEntries
        self.relatedMetrics = relatedMetrics
        self.goalValue = goalValue
        _selectedTimeRange = selectedTimeRange
        _selectedTimelineDate = selectedTimelineDate
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.metricCanvas.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headlineBlock
                        chartCard
                        relatedMetricsRow
                        historyBlock
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .padding(.top, 12)
                }
                .overlay(alignment: .trailing) {
                    historyScrubber(proxy: proxy)
                }
            }
        }
        .accessibilityIdentifier("metric_detail_screen")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            if let onAdd {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.metricAccent)
                    }
                    .accessibilityLabel("Add Entry")
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .task(id: chartDataFingerprint) {
            await preprocessChartDataIfNeeded()
        }
        .task(id: metricEntries?.entries.count ?? 0) {
            await preprocessHistorySectionsIfNeeded()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            activePoint = nil
            HapticManager.shared.selection()
        }
        .onChange(of: chartMode) { _, _ in
            activePoint = nil
            HapticManager.shared.selection()
        }
        .alert(
            "Delete Entry?",
            isPresented: $showingHistoryDeleteConfirmation,
            presenting: historyEntryPendingDeletion
        ) { entry in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteHistoryEntry(entry)
                }
            }
            Button("Cancel", role: .cancel) {
                historyEntryPendingDeletion = nil
            }
        } message: { _ in
            Text("This will remove the entry and update your history.")
        }
    }

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(0.16))
                    )

                Text("Latest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.metricTextSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headlineValueText)
                        .font(.system(size: headlineValueFontSize, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .layoutPriority(2)
                        .accessibilityIdentifier("metric_detail_headline")

                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.metricTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Text(activePoint == nil ? "Updated \(headlineDateText)" : headlineDateText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(1)
            }

            if let stats = computeSeriesStats(for: displayedSeries) {
                HStack(spacing: 10) {
                    statsCell(
                        title: "Average",
                        value: formatStatValue(stats.average),
                        caption: selectedTimeRange.rawValue
                    )

                    statsCell(
                        title: "Change",
                        value: formatDeltaValueCompact(stats.delta),
                        caption: selectedTimeRange.rawValue,
                        valueColor: deltaColor(for: stats.delta),
                        alignRight: true
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metric_detail_headline_block")
    }

    @ViewBuilder
    private func statsCell(
        title: String,
        value: String,
        caption: String,
        valueColor: Color = .white,
        alignRight: Bool = false
    ) -> some View {
        VStack(
            alignment: alignRight ? .trailing : .leading,
            spacing: 2
        ) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.metricTextSecondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(valueColor)
                .multilineTextAlignment(alignRight ? .trailing : .leading)

            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.metricTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: alignRight ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func formatDeltaValueCompact(_ delta: Double) -> String {
        let formatter: NumberFormatter

        if unit == "%" {
            formatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        } else if isStepsMetric {
            formatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 0)
        } else {
            formatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        }

        let absoluteValue = abs(delta)
        let formatted = formatter.string(from: NSNumber(value: absoluteValue))
            ?? String(format: unit == "%" ? "%.1f" : "%.1f", absoluteValue)

        let prefix = delta > 0 ? "+" : "–"
        return "\(prefix)\(formatted)"
    }

    private var historySections: [HistorySection] {
        guard let payload = metricEntries, !payload.entries.isEmpty else { return [] }
        return makeHistorySections(from: payload.entries)
    }

    private var displayedHistorySections: [HistorySection] {
        if let cached = localHistorySections {
            return cached
        }
        return historySections
    }

    private var timeRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button {
                            selectedTimeRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(
                                    selectedTimeRange == range ? Color.black : Color.metricTextPrimary
                                )
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 44, minHeight: 36)
                                .background(
                                    Capsule()
                                        .fill(selectedTimeRange == range ? Color.white : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            }
            .padding(.vertical, 6)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeader
            if isLoadingData {
                chartSkeleton
            } else if activeSeries.isEmpty {
                Text("No data available for this range.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: chartHeight, alignment: .center)
            } else {
                chartView
                    .frame(height: chartHeight)
            }
        }
        .accessibilityIdentifier("metric_detail_chart")
    }

    @ViewBuilder
    private var relatedMetricsRow: some View {
        if !relatedMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Related")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(relatedMetrics) { metric in
                        relatedMetricTile(metric)
                    }
                }
            }
            .accessibilityIdentifier("metric_detail_related_metrics")
        }
    }

    private func relatedMetricTile(_ metric: MetricDetailRelatedMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(relatedMetricAccent(for: metric.id))

                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.metricTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(metric.value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(metric.caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.metricTextTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.value), \(metric.caption)")
        .accessibilityIdentifier("metric_detail_related_metric_\(metric.id)")
    }

    private func relatedMetricAccent(for id: String) -> Color {
        switch id {
        case "steps":
            return Color.metricAccentSteps
        case "weight":
            return Color.metricAccentWeight
        case "body_fat":
            return Color.metricAccentBodyFat
        case "ffmi":
            return Color.metricAccentFFMI
        case "body_score":
            return Color.metricAccent
        default:
            return Color.metricAccent
        }
    }

    private var chartSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subtitle placeholder
            SkeletonView(width: 140, height: 14, cornerRadius: 7)

            // Chart area placeholder
            SkeletonView(height: chartHeight - 40, cornerRadius: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight, alignment: .topLeading)
    }

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            timeRangeSelector
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                chartModeToggle

                Spacer()
            }

            if shouldShowPresenceLegend {
                chartPresenceLegend
            }
        }
    }

    private var chartPresenceLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visiblePresenceLegendItems) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chartPointColor(for: item.presence))
                            .frame(width: 7, height: 7)

                        Text(item.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.metricTextSecondary)

                        if item.total > 0 {
                            Text("\(item.total)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.metricTextTertiary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                    .accessibilityLabel("\(item.label), \(item.total) \(pointCountLabel(for: item.total))")
                }
            }
        }
    }

    private var chartModeToggle: some View {
        HStack(spacing: 8) {
            ForEach(ChartMode.allCases, id: \.self) { mode in
                Button {
                    chartMode = mode
                } label: {
                    Text(mode.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(
                            chartMode == mode ? Color.metricAccent : Color.metricTextSecondary
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 44, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(chartMode == mode ? Color.metricAccent.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chartView: some View {
        Chart {
            let series = activeSeries

            if isStepsMetric {
                ForEach(series) { point in
                    let isToday = Calendar.current.isDateInToday(point.date)
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value),
                        width: selectedTimeRange == .week1 ? .fixed(18) : .automatic
                    )
                    .foregroundStyle(
                        isToday
                            ? chartPointColor(for: point.presence)
                            : chartPointColor(for: point.presence).opacity(0.62)
                    )
                }
            } else {
                ForEach(series) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: chartMode == .trend ? 3 : 2, lineCap: .round))
                    .foregroundStyle(Color.metricChartLine)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .symbolSize(chartPointSymbolSize(for: point.presence))
                    .foregroundStyle(chartPointColor(for: point.presence))
                    .opacity(chartPointOpacity(for: point.presence))
                    .accessibilityLabel("\(presenceLabel(for: point.presence)) point")

                    if chartMode == .trend {
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Baseline", minSeriesValue ?? point.value),
                            yEnd: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.metricChartFillTop, Color.metricChartFillBottom]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
            }

            if let goalValue {
                RuleMark(y: .value("Goal", goalValue))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.metricAccent.opacity(0.45))
                    .annotation(position: .topTrailing, alignment: .trailing) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.metricAccent.opacity(0.7))
                                .frame(width: 6, height: 6)
                            Text("Goal")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.metricTextSecondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.35))
                        )
                    }
            }

            if let stats = computeSeriesStats(for: activeSeries) {
                RuleMark(y: .value("Average", stats.average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(Color.metricGridMajor.opacity(0.6))
            }

            if let focus = selectedFocusPoint {
                RuleMark(x: .value("Selected", focus.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.white.opacity(0.4))

                PointMark(
                    x: .value("Selected", focus.date),
                    y: .value("Selected Value", focus.value)
                )
                .symbolSize(120)
                .foregroundStyle(Color.clear)
                .annotation(position: .top) {
                    selectedPointCallout(for: focus)
                }
                .symbol(CircleSymbol())
                .foregroundStyle(Color.metricChartLine)
                .accessibilityLabel("Selected point")
            }
        }
        .chartXAxis {
            if selectedTimeRange == .week1 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.metricTextSecondary)
                        .font(.system(size: 10, weight: .medium))
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: xAxisTickCount)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Color.metricTextSecondary)
                        .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.metricTextSecondary)
                    .font(.system(size: 10, weight: .medium))
            }
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.metricGridMajor.opacity(0.4))
                AxisValueLabel()
                    .foregroundStyle(Color.metricTextSecondary)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else {
                                    return
                                }

                                let frame = geo[plotFrame]
                                let locationX = value.location.x - frame.origin.x
                                guard locationX >= 0, locationX <= frame.size.width else { return }
                                if let date: Date = proxy.value(atX: locationX) {
                                    if !isScrubbing {
                                        isScrubbing = true
                                        HapticManager.shared.selection()
                                    }
                                    if let focus = nearestPoint(to: date) {
                                        activePoint = focus
                                        selectedTimelineDate = focus.date
                                    }
                                }
                            }
                            .onEnded { _ in
                                isScrubbing = false
                                activePoint = nil
                            }
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: activeSeries.count)
    }

    private func selectedPointCallout(for point: MetricChartDataPoint) -> some View {
        VStack(spacing: 4) {
            Text(formatHeadlineValue(point.value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
            Text(point.date.formatted(.dateTime.month().day()))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.7))
            Text(presenceLabel(for: point.presence))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.black.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white)
        )
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.metricGridMinor.opacity(0.55))
                .padding(.bottom, 8)

            HStack(alignment: .center, spacing: 8) {
                Text("History")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if let onAdd {
                    Button {
                        HapticManager.shared.selection()
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.metricAccent)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Entry")
                }
            }

            if let payload = metricEntries,
               !payload.entries.isEmpty,
               !displayedHistorySections.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayedHistorySections.enumerated()), id: \
                        .element.id
                    ) { index, section in
                        VStack(alignment: .leading, spacing: 0) {
                            if section.showsHeader {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.metricTextTertiary)
                                    .padding(.top, index == 0 ? 4 : 12)
                                    .padding(.bottom, 6)
                            }

                            ForEach(section.entries) { entry in
                                historyRow(for: entry, config: payload.config)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            historyEntryPendingDeletion = entry
                                            showingHistoryDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                if entry.id != section.entries.last?.id {
                                    Divider()
                                        .background(Color.metricGridMinor.opacity(0.55))
                                }
                            }
                        }
                        .id(section.id)
                    }
                }
            } else {
                Text("No entries yet. Add your first log to see history here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.metricTextSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private func historyRow(for entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> some View {
        let primary = primaryHistoryValue(entry, config: config)
        let unitLabel = config.unitLabel

        let valueText: String
        let unitText: String?

        if unitLabel.isEmpty {
            valueText = primary
            unitText = nil
        } else {
            let suffix = " " + unitLabel
            if primary.hasSuffix(suffix) {
                valueText = String(primary.dropLast(suffix.count))
                unitText = unitLabel
            } else {
                valueText = primary
                unitText = nil
            }
        }

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    historySourceIcon(for: entry.source)

                    Text(sourceLabel(for: entry.source))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.metricTextTertiary)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                if let unitText {
                    Text(unitText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.metricTextSecondary)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private func primaryHistoryValue(_ entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> String {
        let formatter = config.primaryFormatter
        let value = formatter.string(from: NSNumber(value: entry.primaryValue)) ?? formattedValue(entry.primaryValue)
        if config.unitLabel.isEmpty {
            return value
        }
        return "\(value) \(config.unitLabel)"
    }

    private func secondaryHistoryValue(_ entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> String? {
        guard let secondaryValue = entry.secondaryValue,
              let formatter = config.secondaryFormatter,
              let formatted = formatter.string(from: NSNumber(value: secondaryValue)) else {
            return nil
        }

        if let unit = config.secondaryUnitLabel, !unit.isEmpty {
            return "\(formatted) \(unit)"
        }
        return formatted
    }

    private func sourceLabel(for source: MetricEntrySourceType) -> String {
        switch source {
        case .manual:
            return "Manual"
        case .healthKit:
            return "Apple Health"
        case .integration(let id):
            return id ?? "Connected"
        }
    }

    @ViewBuilder
    private func historySourceIcon(for source: MetricEntrySourceType) -> some View {
        switch source {
        case .healthKit:
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
        case .manual:
            Image("AppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .integration:
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricAccent)
        }
    }

    private func historyScrubber(proxy: ScrollViewProxy) -> some View {
        Group {
            if displayedHistorySections.isEmpty {
                Color.clear.frame(width: 0, height: 0)
            } else {
                GeometryReader { geometry in
                    let sectionCount = displayedHistorySections.count
                    let height = geometry.size.height
                    let thumbWidth: CGFloat = 3
                    let minThumbHeight: CGFloat = 36
                    let step = height / CGFloat(max(sectionCount, 1))
                    let clampedIndex = min(max(activeHistorySectionIndex ?? 0, 0), max(sectionCount - 1, 0))
                    let thumbHeight = max(minThumbHeight, step * 0.7)
                    let yOffset = CGFloat(clampedIndex) * step

                    ZStack(alignment: .topTrailing) {
                        // Optional hairline track for subtle context, only while scrubbing
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1, height: height)
                            .opacity(isHistoryScrubbing ? 1 : 0)

                        Capsule()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: thumbWidth, height: thumbHeight)
                            .offset(y: yOffset)
                            .opacity(isHistoryScrubbing ? 1 : 0)
                    }
                    .padding(.trailing, 4)
                    .animation(.easeInOut(duration: 0.2), value: isHistoryScrubbing)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let y = min(max(0, value.location.y), height - 1)
                                let rawIndex = Int(y / max(step, 1))
                                let index = min(max(rawIndex, 0), sectionCount - 1)

                                if activeHistorySectionIndex != index {
                                    activeHistorySectionIndex = index
                                    if !isHistoryScrubbing {
                                        isHistoryScrubbing = true
                                    }
                                    let sectionId = displayedHistorySections[index].id
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        proxy.scrollTo(sectionId, anchor: .top)
                                    }
                                    HapticManager.shared.selection()
                                }
                            }
                            .onEnded { _ in
                                isHistoryScrubbing = false
                            }
                    )
                }
                .frame(width: 20)
            }
        }
    }

    // MARK: - Computed Data

    private var displayedSeries: [MetricChartDataPoint] {
        if let cached = cachedSeries[selectedTimeRange], !cached.isEmpty {
            return cached
        }

        if chartData.count > 120 {
            return Array(chartData.suffix(120))
        }

        return chartData
    }

    private var smoothedSeries: [MetricChartDataPoint] {
        movingAverage(for: displayedSeries, windowSize: 7)
    }

    private var activeSeries: [MetricChartDataPoint] {
        chartMode == .trend ? smoothedSeries : displayedSeries
    }

    private var visiblePresenceLegendItems: [ChartPresenceLegendItem] {
        let counts = chartPresenceCounts
        return MetricPresence.allCases.compactMap { presence in
            let count = counts[presence] ?? 0
            if count == 0 && !(presence == .missing && chartData.isEmpty) {
                return nil
            }

            return ChartPresenceLegendItem(
                presence: presence,
                label: presenceLabel(for: presence),
                total: count
            )
        }
    }

    private var chartPresenceCounts: [MetricPresence: Int] {
        chartData.reduce(into: [:]) { counts, point in
            counts[point.presence, default: 0] += 1
        }
    }

    private var shouldShowPresenceLegend: Bool {
        visiblePresenceLegendItems.contains { item in
            item.presence != .present
        }
    }

    private var minSeriesValue: Double? {
        activeSeries.map(\.value).min()
    }

    private var headlineValueText: String {
        if let point = selectedFocusPoint {
            return formatHeadlineValue(point.value)
        }
        return currentValue
    }

    private var headlineDateText: String {
        if let point = selectedFocusPoint {
            return point.date.formatted(.dateTime.month().day().year())
        }
        return currentDate
    }

    private var selectedFocusPoint: MetricChartDataPoint? {
        if let activePoint {
            return activePoint
        }

        guard let selectedTimelineDate else { return nil }
        return nearestPoint(to: selectedTimelineDate)
    }

    private var chartDataFingerprint: String {
        guard let first = chartData.first, let last = chartData.last else {
            return "empty-\(chartData.count)"
        }
        return [
            "\(chartData.count)",
            "\(first.date.timeIntervalSince1970)",
            "\(last.date.timeIntervalSince1970)",
            "\(first.value)",
            "\(last.value)",
            first.presence.rawValue,
            last.presence.rawValue
        ].joined(separator: "-")
    }

    // MARK: - Helpers

    private func formatHeadlineValue(_ value: Double) -> String {
        if isStepsMetric {
            let steps = Int(value.rounded())
            return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }

        if unit == "%" {
            return String(format: "%.1f", value)
        }
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

    private func formatStatValue(_ value: Double) -> String {
        if isStepsMetric {
            let steps = Int(value.rounded())
            return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }

        if unit == "%" {
            return String(format: "%.1f%%", value)
        }
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

    private func formattedValue(_ value: Double) -> String {
        formatStatValue(value)
    }

    private func movingAverage(
        for series: [MetricChartDataPoint],
        windowSize: Int
    ) -> [MetricChartDataPoint] {
        guard windowSize > 1, series.count > 1 else { return series }

        var smoothed: [MetricChartDataPoint] = []

        for index in series.indices {
            let start = max(0, index - windowSize + 1)
            let window = series[start...index]
            let average = window.reduce(0) { $0 + $1.value } / Double(window.count)
            let presence = combinedPresence(for: window.map(\.presence))

            smoothed.append(
                MetricChartDataPoint(
                    date: series[index].date,
                    value: average,
                    presence: presence
                )
            )
        }

        return smoothed
    }

    private func computeSeriesStats(
        for series: [MetricChartDataPoint]
    ) -> MetricSeriesStats? {
        guard series.count >= 2 else { return nil }

        let values = series.map(\.value)
        guard let first = values.first, let last = values.last else { return nil }

        let total = values.reduce(0, +)
        let average = total / Double(values.count)
        let delta = last - first

        let percentageChange: Double
        if abs(first) < .leastNormalMagnitude {
            percentageChange = 0
        } else {
            percentageChange = (delta / first) * 100
        }

        return MetricSeriesStats(
            average: average,
            delta: delta,
            percentageChange: percentageChange
        )
    }

    private func combinedPresence(for presences: [MetricPresence]) -> MetricPresence {
        if presences.contains(.interpolated) {
            return .interpolated
        }

        if presences.contains(.lastKnown) {
            return .lastKnown
        }

        if presences.contains(.missing) {
            return .missing
        }

        return .present
    }

    private func presenceLabel(for presence: MetricPresence) -> String {
        switch presence {
        case .present:
            return "Measured"
        case .interpolated:
            return "Interpolated"
        case .lastKnown:
            return "Last known"
        case .missing:
            return "Missing"
        }
    }

    private func chartPointColor(for presence: MetricPresence) -> Color {
        switch presence {
        case .present:
            return Color.metricChartLine
        case .interpolated:
            return Color.metricAccentBodyFat
        case .lastKnown:
            return Color.metricAccentFFMI
        case .missing:
            return Color.metricTextTertiary
        }
    }

    private func chartPointSymbolSize(for presence: MetricPresence) -> CGFloat {
        switch presence {
        case .present:
            return 22
        case .interpolated:
            return 42
        case .lastKnown:
            return 34
        case .missing:
            return 18
        }
    }

    private func chartPointOpacity(for presence: MetricPresence) -> Double {
        switch presence {
        case .present:
            return 0.78
        case .interpolated:
            return 0.86
        case .lastKnown:
            return 0.68
        case .missing:
            return 0.38
        }
    }

    private func pointCountLabel(for count: Int) -> String {
        count == 1 ? "point" : "points"
    }

    private func formatDeltaValue(_ delta: Double) -> String {
        formatDelta(delta: delta, unit: unit)
    }

    private func deltaColor(for delta: Double) -> Color {
        let threshold: Double = 0.0001
        guard abs(delta) > threshold else {
            return Color.metricTextPrimary
        }
        return delta > 0 ? Color.metricDeltaPositive : Color.metricDeltaNegative
    }

    @MainActor
    private func deleteHistoryEntry(_ entry: MetricHistoryEntry) async {
        defer {
            historyEntryPendingDeletion = nil
            showingHistoryDeleteConfirmation = false
        }

        let success = await RealtimeSyncManager.shared.deleteBodyMetric(id: entry.id)
        guard success else { return }

        var sections = localHistorySections ?? historySections

        for (sectionIndex, section) in sections.enumerated() {
            if let rowIndex = section.entries.firstIndex(where: { $0.id == entry.id }) {
                var newEntries = section.entries
                newEntries.remove(at: rowIndex)

                if newEntries.isEmpty {
                    sections.remove(at: sectionIndex)
                } else {
                    let updatedSection = HistorySection(
                        id: section.id,
                        title: section.title,
                        showsHeader: section.showsHeader,
                        entries: newEntries
                    )
                    sections[sectionIndex] = updatedSection
                }

                break
            }
        }

        localHistorySections = sections
    }

    private func nearestPoint(to date: Date) -> MetricChartDataPoint? {
        activeSeries.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private var isStepsMetric: Bool {
        unit.lowercased() == "steps"
    }

    private var xAxisTickCount: Int {
        switch selectedTimeRange {
        case .week1:
            return 7
        case .month1:
            return 8
        case .month3:
            return 6
        case .month6:
            return 6
        case .year1, .all:
            return 6
        }
    }

    @MainActor
    private func preprocessChartDataIfNeeded() async {
        guard !chartData.isEmpty else {
            cachedSeries = [:]
            lastFingerprint = chartDataFingerprint
            return
        }

        let fingerprint = chartDataFingerprint
        if fingerprint == lastFingerprint, !cachedSeries.isEmpty {
            return
        }

        isLoadingData = true
        let data = chartData
        let referenceDate = data.last?.date ?? Date()

        let newSeries = await Task.detached(priority: .userInitiated) {
            let preprocessor = ChartSeriesPreprocessor(referenceDate: referenceDate)
            return preprocessor.seriesByRange(from: data)
        }.value

        if fingerprint == chartDataFingerprint {
            cachedSeries = newSeries
            lastFingerprint = fingerprint
        }

        isLoadingData = false
    }

    @MainActor
    private func preprocessHistorySectionsIfNeeded() async {
        guard let payload = metricEntries, !payload.entries.isEmpty else {
            localHistorySections = nil
            return
        }

        // If we already have sections matching the entry count, skip recomputation.
        if let existing = localHistorySections {
            let existingCount = existing.reduce(0) { $0 + $1.entries.count }
            if existingCount == payload.entries.count {
                return
            }
        }

        let entries = payload.entries

        let sections = await Task.detached(priority: .utility) {
            makeHistorySections(from: entries)
        }.value

        // Guard against races if the payload changed while work was in-flight.
        if metricEntries?.entries.count == entries.count {
            localHistorySections = sections
        }
    }
}

private func makeHistorySections(from entries: [MetricHistoryEntry]) -> [HistorySection] {
    let calendar = Calendar.current

    // Use newest-first ordering for a more natural ledger feel
    let sortedEntries = entries.sorted { $0.date > $1.date }

    var groups: [(key: String, date: Date, entries: [MetricHistoryEntry])] = []
    var indexByKey: [String: Int] = [:]

    for entry in sortedEntries {
        let components = calendar.dateComponents([.year, .month], from: entry.date)
        guard let year = components.year, let month = components.month else { continue }
        let key = "\(year)-\(month)"

        if let index = indexByKey[key] {
            groups[index].entries.append(entry)
        } else {
            groups.append((key: key, date: entry.date, entries: [entry]))
            indexByKey[key] = groups.count - 1
        }
    }

    guard !groups.isEmpty else { return [] }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"

    let totalGroups = groups.count
    var sections: [HistorySection] = []

    for (index, group) in groups.enumerated() {
        let title = formatter.string(from: group.date)
        let entryCount = group.entries.count

        // Avoid a wall of headers for very sparse histories.
        // Always show headers when there are only a few groups,
        // and otherwise require a minimum entry count or boundary month.
        let showsHeader: Bool
        if totalGroups <= 4 {
            showsHeader = true
        } else {
            showsHeader = entryCount >= 3 || index == 0 || index == totalGroups - 1
        }

        sections.append(
            HistorySection(
                id: group.key,
                title: title,
                showsHeader: showsHeader,
                entries: group.entries
            )
        )
    }

    return sections
}
