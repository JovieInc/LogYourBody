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

struct QuickStat: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
    let detail: String?
    let color: Color
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
    let id = UUID()
    let date: Date
    let value: Double
    var isEstimated: Bool = false
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

struct MetricHistoryEntry: Identifiable {
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

func makeMetricFormatter(minFractionDigits: Int = 0, maxFractionDigits: Int = 1) -> NumberFormatter {
    MetricFormatterCache.formatter(minFractionDigits: minFractionDigits, maxFractionDigits: maxFractionDigits)
}

// MARK: - Full Metric Chart View

struct FullMetricChartView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let icon: String
    let iconColor: Color
    let currentValue: String
    let unit: String
    let currentDate: String
    let chartData: [MetricChartDataPoint]
    let onAdd: () -> Void
    let metricEntries: MetricEntriesPayload?

    @Binding var selectedTimeRange: TimeRange
    @State private var cachedSeries: [TimeRange: [MetricChartDataPoint]] = [:]
    @State private var isLoadingData = false
    @State private var lastFingerprint: String = ""
    @State private var chartMode: ChartMode = .trend
    @State private var activePoint: MetricChartDataPoint?
    @State private var isScrubbing = false

    private let chartHeight: CGFloat = 260

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.metricCanvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        navigationBar
                        headlineBlock
                        quickStatsRow
                        timeRangeSelector
                        chartCard
                        historyBlock
                        addEntryButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                    .padding(.top, 12)
                }
            }
        }
        .task(id: chartDataFingerprint) {
            await preprocessChartDataIfNeeded()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            activePoint = nil
            HapticManager.shared.selection()
        }
        .onChange(of: chartMode) { _, _ in
            activePoint = nil
            HapticManager.shared.selection()
        }
    }

    // MARK: - Layout Sections

    private var navigationBar: some View {
        HStack {
            Button {
                HapticManager.shared.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.metricSurface.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button {
                HapticManager.shared.selection()
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.metricAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.metricSurface.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .tracking(1)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headlineValueText)
                    .font(.system(size: 62, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))
                }
            }

            Text(headlineDateText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
        }
    }

    private var quickStatsRow: some View {
        Group {
            if !quickStats.isEmpty {
                HStack(spacing: 12) {
                    ForEach(quickStats) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stat.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .tracking(0.3)
                            Text(stat.value)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(stat.color)
                            if let detail = stat.detail {
                                Text(detail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.45))
                            }
                        }
                        .padding(.vertical, 6)
                        if stat.id != quickStats.last?.id {
                            Text("·")
                                .foregroundColor(Color.white.opacity(0.35))
                        }
                    }
                }
            }
        }
    }

    private var timeRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button {
                        selectedTimeRange = range
                    } label: {
                        Text(range.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedTimeRange == range ? .black : .white.opacity(0.8))
                            .frame(width: 68, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedTimeRange == range ? Color.metricAccent : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(0.15), lineWidth: selectedTimeRange == range ? 0 : 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeader
            if isLoadingData {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: chartHeight)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.metricCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
        )
    }

    private var chartHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trend")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text(chartSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            Spacer()
            chartModeToggle
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
                        .foregroundColor(chartMode == mode ? .black : Color.white.opacity(0.8))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(chartMode == mode ? Color.metricAccent : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: chartMode == mode ? 0 : 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chartView: some View {
        Chart {
            let series = activeSeries
            ForEach(series) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: chartMode == .trend ? 3 : 2, lineCap: .round))
                .foregroundStyle(Color.metricChartLine)

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
                } else {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .symbolSize(16)
                    .foregroundStyle(Color.metricChartLine)
                }
            }

            if let focus = activePoint {
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
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.6))
                    .font(.system(size: 11, weight: .medium))
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.6))
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let plotFrame = proxy.plotAreaFrame
                                let frame = geo[plotFrame]
                                let origin = frame.origin
                                let width = frame.size.width
                                let locationX = value.location.x - origin.x
                                guard locationX >= 0, locationX <= width else { return }
                                if let date: Date = proxy.value(atX: locationX) {
                                    if !isScrubbing {
                                        isScrubbing = true
                                        HapticManager.shared.selection()
                                    }
                                    activePoint = nearestPoint(to: date)
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
            Text("History")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            if let payload = metricEntries, !payload.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(payload.entries.enumerated()), id: \.element.id) { index, entry in
                        historyRow(for: entry, config: payload.config)
                        if index < payload.entries.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.08))
                        }
                    }
                }
                .background(Color.metricSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Text("No entries yet. Add your first log to see history here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.6))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.metricSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func historyRow(for entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(.dateTime.month().day().year()))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(sourceLabel(for: entry.source))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.45))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(primaryHistoryValue(entry, config: config))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if let secondary = secondaryHistoryValue(entry, config: config) {
                    Text(secondary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                }
            }
        }
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

    private var addEntryButton: some View {
        Button {
            HapticManager.shared.selection()
            onAdd()
        } label: {
            Label("Add Entry", systemImage: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.metricAccent.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Data

    private var displayedSeries: [MetricChartDataPoint] {
        cachedSeries[selectedTimeRange] ?? chartData
    }

    private var smoothedSeries: [MetricChartDataPoint] {
        movingAverage(for: displayedSeries, windowSize: 7)
    }

    private var activeSeries: [MetricChartDataPoint] {
        chartMode == .trend ? smoothedSeries : displayedSeries
    }

    private var minSeriesValue: Double? {
        activeSeries.map(\.value).min()
    }

    private var chartSubtitle: String {
        "\(selectedTimeRange.rawValue) · \(chartMode.label)"
    }

    private var quickStats: [QuickStat] {
        guard let stats = computeSeriesStats(for: displayedSeries) else { return [] }

        var items: [QuickStat] = []

        let averageText = "\(selectedTimeRange.rawValue) avg \(formatStatValue(stats.average))"
        items.append(QuickStat(label: "Average", value: averageText, detail: nil, color: .white))

        let deltaValue = stats.delta
        let deltaText = formatDeltaValue(deltaValue)
        let deltaDetail = "since start"
        items.append(QuickStat(label: "Δ", value: deltaText, detail: deltaDetail, color: deltaColor(for: deltaValue)))

        if let rangeText = rangeText(for: displayedSeries) {
            items.append(QuickStat(label: "Range", value: rangeText, detail: nil, color: Color.white))
        }

        return items
    }

    private var headlineValueText: String {
        if let point = activePoint {
            return formatHeadlineValue(point.value)
        }
        return currentValue
    }

    private var headlineDateText: String {
        if let point = activePoint {
            return point.date.formatted(.dateTime.month().day().year())
        }
        return currentDate
    }

    private var chartDataFingerprint: String {
        guard let first = chartData.first, let last = chartData.last else {
            return "empty-\(chartData.count)"
        }
        return "\(chartData.count)-\(first.date.timeIntervalSince1970)-\(last.date.timeIntervalSince1970)-\(first.value)-\(last.value)"
    }

    // MARK: - Helpers

    private func formatHeadlineValue(_ value: Double) -> String {
        if unit == "%" {
            return String(format: "%.1f", value)
        }
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

    private func formatStatValue(_ value: Double) -> String {
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
            let isEstimated = window.contains(where: { $0.isEstimated })

            smoothed.append(
                MetricChartDataPoint(
                    date: series[index].date,
                    value: average,
                    isEstimated: isEstimated
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

    private func formatDeltaValue(_ delta: Double) -> String {
        formatDelta(delta: delta, unit: unit)
    }

    private func deltaColor(for delta: Double) -> Color {
        let threshold: Double = 0.0001
        guard abs(delta) > threshold else {
            return Color.white
        }
        return delta > 0 ? .green : .red
    }

    private func rangeText(
        for series: [MetricChartDataPoint]
    ) -> String? {
        guard
            let minValue = series.map(\.value).min(),
            let maxValue = series.map(\.value).max(),
            minValue != maxValue
        else {
            return nil
        }

        let minText = formatStatValue(minValue)
        let maxText = formatStatValue(maxValue)
        return "\(minText) – \(maxText)"
    }

    private func nearestPoint(to date: Date) -> MetricChartDataPoint? {
        activeSeries.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
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
        defer { isLoadingData = false }

        let referenceDate = chartData.last?.date ?? Date()
        let preprocessor = ChartSeriesPreprocessor(referenceDate: referenceDate)
        let newSeries = preprocessor.seriesByRange(from: chartData)

        cachedSeries = newSeries
        lastFingerprint = fingerprint
    }
}
