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

    var accessibilityLabel: String {
        switch self {
        case .week1:
            return "1 week"
        case .month1:
            return "1 month"
        case .month3:
            return "3 months"
        case .month6:
            return "6 months"
        case .year1:
            return "1 year"
        case .all:
            return "All time"
        }
    }
}

enum MetricChartLayoutPolicy {
    static func xAxisTickCount(
        for range: TimeRange,
        isAccessibilitySize: Bool
    ) -> Int {
        guard !isAccessibilitySize else { return 3 }

        switch range {
        case .week1, .month1, .month3, .month6:
            return 4
        case .year1, .all:
            return 3
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
    let calendar = Calendar.current

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

    func filter(_ points: [MetricChartDataPoint], for range: TimeRange) -> [MetricChartDataPoint] {
        guard let days = range.days else {
            return points
        }

        let cutoff = calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return points.filter { $0.date >= cutoff }
    }

    func maxPointCount(for range: TimeRange) -> Int {
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

    func downsampleIfNeeded(_ points: [MetricChartDataPoint], limit: Int) -> [MetricChartDataPoint] {
        guard points.count > limit, limit >= 3 else { return points }
        return largestTriangleThreeBuckets(points: points, threshold: limit)
    }

    func largestTriangleThreeBuckets(points: [MetricChartDataPoint], threshold: Int) -> [MetricChartDataPoint] {
        guard threshold < points.count,
              let firstPoint = points.first,
              let lastPoint = points.last else {
            return points
        }

        let dataCount = points.count
        let bucketSize = Double(dataCount - 2) / Double(threshold - 2)

        var sampled: [MetricChartDataPoint] = [firstPoint]
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

        sampled.append(lastPoint)
        return sampled
    }

    func averagedPoint(_ points: [MetricChartDataPoint], start: Int, end: Int) -> (x: Double, y: Double) {
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

    func timeValue(_ point: MetricChartDataPoint) -> Double {
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

struct HistorySection: Identifiable, Sendable {
    let id: String
    let title: String
    let showsHeader: Bool
    let entries: [MetricHistoryEntry]
}

struct ChartPresenceLegendItem: Identifiable {
    let presence: MetricPresence
    let label: String
    let total: Int

    var id: String {
        presence.rawValue
    }
}

// MARK: - Full Metric Chart View

struct FullMetricChartView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

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
    @State var cachedSeries: [TimeRange: [MetricChartDataPoint]] = [:]
    @State var isLoadingData = false
    @State var lastFingerprint: String = ""
    @State var chartMode: ChartMode = .trend
    @State var activePoint: MetricChartDataPoint?
    @State var isScrubbing = false
    @State var activeHistorySectionIndex: Int?
    @State var isHistoryScrubbing = false

    @State var localHistorySections: [HistorySection]?
    @State var historyEntryPendingDeletion: MetricHistoryEntry?
    @State var showingHistoryDeleteConfirmation = false

    @ScaledMetric(relativeTo: .largeTitle) var headlineValueFontSize: CGFloat = 56

    var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 360 : 320
    }

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
}

func makeHistorySections(from entries: [MetricHistoryEntry]) -> [HistorySection] {
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
