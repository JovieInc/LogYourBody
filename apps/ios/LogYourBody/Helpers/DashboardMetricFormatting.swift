import SwiftUI
import Charts

enum MetricStatsTruthPolicy {
    static let gateKey = "metric_stats_truth_v1"

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains("-lybUITestMetricStatsTruth"),
           arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
           UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil,
           environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") == true {
            return true
        }
        #endif
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }

    static func synchronizationText(status: String, lastCloudSync: Date?, healthAccessStatus: String) -> String {
        let synced = lastCloudSync.map {
            "Last cloud sync \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "Cloud sync not yet recorded"
        return ["\(status) · \(synced)", healthAccessStatus.isEmpty ? nil : "Apple Health: \(healthAccessStatus)"]
            .compactMap { $0 }.joined(separator: "\n")
    }
}

struct CircleSymbol: ChartSymbolShape {
    var perceptualUnitRect: CGRect { CGRect(x: -0.5, y: -0.5, width: 1, height: 1) }

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

/// Paid HUD must show the logged scale weight on a day that has one.
/// Trend/EMA is a fallback only when that day has no measured weight.
enum TimelineWeightHeadlinePolicy {
    static func kilograms(
        measuredWeight: Double?,
        trendWeight: Double?,
        prefersTrend: Bool
    ) -> Double? {
        if let measuredWeight {
            return measuredWeight
        }
        if prefersTrend {
            return trendWeight
        }
        return trendWeight
    }
}

struct MetricRangeStats {
    let startValue: Double
    let endValue: Double
    let delta: Double
    let average: Double
    let percentageChange: Double
    var startDate: Date?
    var endDate: Date?
    var sampleCount = 0
}

func computeRangeStats(
    metrics: [BodyMetrics],
    valueProvider: (BodyMetrics) -> Double?
) -> MetricRangeStats? {
    let points = metrics.compactMap { metric -> MetricChartDataPoint? in
        guard let value = valueProvider(metric), value.isFinite else { return nil }
        return MetricChartDataPoint(date: metric.date, value: value)
    }
    return computeRangeStats(points: points, requiresComparison: false, includesInferredValues: true)
}

/// LYB-47 / JOV-3331: one endpoint delta and arithmetic observation mean.
/// No carried values, missing samples, synthetic days or time weighting.
func computeRangeStats(
    points: [MetricChartDataPoint], requiresComparison: Bool = true, includesInferredValues: Bool = false
) -> MetricRangeStats? {
    let eligible = includesInferredValues ? points.filter { $0.value.isFinite } : HomeV2MetricEditorial.observedPoints(points)
    let dataPoints = eligible.sorted {
        $0.date == $1.date ? $0.value < $1.value : $0.date < $1.date
    }
    guard let first = dataPoints.first, let last = dataPoints.last else { return nil }
    if requiresComparison && first.date == last.date { return nil }

    let total = dataPoints.reduce(0) { partialResult, point in
        partialResult + point.value
    }

    let average = total / Double(dataPoints.count)
    let delta = last.value - first.value
    let percentageChange: Double

    if abs(first.value) < .leastNormalMagnitude {
        percentageChange = 0
    } else {
        percentageChange = (delta / first.value) * 100
    }

    return MetricRangeStats(
        startValue: first.value,
        endValue: last.value,
        delta: delta,
        average: average,
        percentageChange: percentageChange,
        startDate: first.date, endDate: last.date, sampleCount: dataPoints.count
    )
}

typealias MetricSeriesStats = MetricRangeStats

/// Chart cards keep the historical two-point rule. One timestamp cannot show change.
func computeSeriesStats(
    for series: [MetricChartDataPoint]
) -> MetricSeriesStats? {
    guard series.count >= 2 else { return nil }
    return computeRangeStats(points: series, requiresComparison: false, includesInferredValues: true)
}

/// Presentation uses the unthinned observation series; plotting never changes the calculation.
struct MetricObservationSummary {
    let point: MetricChartDataPoint?
    let points: [MetricChartDataPoint]
    let stats: MetricRangeStats?
    let range: TimeRange
    let now: Date
    let calendar: Calendar

    init(points: [MetricChartDataPoint], range: TimeRange, selectedDate: Date? = nil,
         now: Date = Date(), calendar: Calendar = .current) {
        let history = HomeV2MetricEditorial.observedPoints(points).filter { $0.date <= now }
        self.point = history.filter { $0.date <= (selectedDate ?? now) }.max { $0.date < $1.date }
        self.points = Self.window(history, range: range, now: now, calendar: calendar)
        self.stats = computeRangeStats(points: self.points)
        self.range = range
        self.now = now
        self.calendar = calendar
    }

    static func window(_ points: [MetricChartDataPoint], range: TimeRange, now: Date,
                       calendar: Calendar = .current) -> [MetricChartDataPoint] {
        let cutoff = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        return points.filter { point in
            guard point.date <= now else { return false }
            return cutoff.map { point.date >= $0 } ?? true
        }
            .sorted { $0.date < $1.date }
    }

    var displayInterval: ClosedRange<Date> {
        let start = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            ?? points.first?.date ?? now.addingTimeInterval(-1)
        return min(start, now.addingTimeInterval(-1))...now
    }

    var periodLabel: String {
        range.days.map { "Past \($0) days" } ?? "All recorded history"
    }

    var comparisonLabel: String {
        guard let stats, let start = stats.startDate, let end = stats.endDate else {
            return points.isEmpty ? "No observations in displayed period" : "Need 2 observations at different times"
        }
        return "First → last · \(dateText(start)) – \(dateText(end))"
    }

    var observationLabel: String {
        guard let point else { return "No observation" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: point.date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let age = days > 0 ? " · \(days) day\(days == 1 ? "" : "s") ago" : ""
        let outside = points.contains { $0.id == point.id } ? "" : " · Outside displayed period"
        return "Observed \(dateText(point.date))\(age)\(outside)"
    }

    func changeText(unit: String, includesDates: Bool = true) -> String {
        guard let stats else { return comparisonLabel }
        let comparison = includesDates ? comparisonLabel : "First → last observation"
        return "\(Self.deltaText(stats.delta, unit: unit)) · \(comparison)"
    }

    var averageLabel: String? {
        stats.map { "Mean of \($0.sampleCount) observations" }
    }

    static func deltaText(_ delta: Double, unit: String) -> String {
        guard delta.isFinite else { return "Change unavailable" }
        let rounded = (delta * 10).rounded() / 10
        guard rounded != 0 else { return "Unchanged at displayed precision" }
        return formatDelta(delta: rounded, unit: unit == "%" ? "percentage points" : unit)
    }

    func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: date)) \(calendar.timeZone.abbreviation(for: date) ?? calendar.timeZone.identifier)"
    }
}

func makeTrend(delta: Double, unit: String, range: TimeRange) -> MetricSummaryCard.Trend? {
    let caption = range.shortRelativeLabel

    guard abs(delta) > 0.001 else {
        return MetricSummaryCard.Trend(direction: .flat, valueText: "No change", caption: caption)
    }

    let direction: MetricSummaryCard.Trend.Direction = delta > 0 ? .up : .down

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = unit == "%" ? 1 : 1
    formatter.minimumFractionDigits = 0

    let magnitude = abs(delta)
    let formattedMagnitude = formatter.string(from: NSNumber(value: magnitude))
        ?? String(format: "%.1f", magnitude)

    let valueText: String
    if unit.isEmpty {
        valueText = formattedMagnitude
    } else if unit == "%" {
        valueText = "\(formattedMagnitude)\(unit)"
    } else {
        valueText = "\(formattedMagnitude) \(unit)"
    }

    return MetricSummaryCard.Trend(direction: direction, valueText: valueText, caption: caption)
}

func formatDelta(delta: Double, unit: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = unit == "%" ? 1 : 1
    formatter.minimumFractionDigits = 0

    let value = formatter.string(from: NSNumber(value: abs(delta))) ?? String(format: "%.1f", abs(delta))
    let prefix = delta > 0 ? "+" : "–"
    if unit.isEmpty {
        return "\(prefix)\(value)"
    }
    return "\(prefix)\(value)\(unit == "%" ? unit : " \(unit)")"
}

func formatAverageFootnote(value: Double, unit: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = unit == "%" ? 1 : 1
    formatter.minimumFractionDigits = 0

    let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    if unit.isEmpty {
        return "\(formatted) average"
    }
    return "\(formatted) \(unit) average"
}

func metricSummaryFootnote(averageText: String?, goalText: String?) -> String? {
    if let goalText, !goalText.isEmpty {
        return goalText
    }

    if let averageText, !averageText.isEmpty {
        return averageText
    }

    return nil
}

extension TimeRange {
    var shortRelativeLabel: String {
        switch self {
        case .week1:
            return "7d"
        case .month1:
            return "1M"
        case .month3:
            return "3M"
        case .month6:
            return "6M"
        case .year1:
            return "1Y"
        case .all:
            return "All"
        }
    }
}

enum FormatterCache {
    static let stepsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func formattedSteps(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        return stepsFormatter.string(from: NSNumber(value: value.rounded()))
    }

    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

struct MetricFormatterKey: Hashable {
    let minFractionDigits: Int
    let maxFractionDigits: Int
}

enum MetricFormatterCache {
    private static var cache: [MetricFormatterKey: NumberFormatter] = [:]
    private static let lock = NSLock()

    static func formatter(minFractionDigits: Int, maxFractionDigits: Int) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }

        let key = MetricFormatterKey(minFractionDigits: minFractionDigits, maxFractionDigits: maxFractionDigits)
        if let formatter = cache[key] {
            return formatter
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minFractionDigits
        formatter.maximumFractionDigits = maxFractionDigits
        cache[key] = formatter
        return formatter
    }
}

struct MetricDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}
