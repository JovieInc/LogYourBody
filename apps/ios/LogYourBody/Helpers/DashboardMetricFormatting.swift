import SwiftUI
import Charts

enum DashboardMetricFormatting {
    /// Matches the dashboard's existing 30-day recency window.
    static let currentWeightWindowDays = 30

    static func readingDateLabel(
        effectiveDate: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        if calendar.isDate(effectiveDate, inSameDayAs: now) { return "Today" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.isDate(effectiveDate, equalTo: now, toGranularity: .year)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: effectiveDate)
    }

    static func currentWeight(
        in metrics: [BodyMetrics], now: Date = Date(), calendar: Calendar = .current
    ) -> BodyMetrics? {
        guard let start = calendar.date(byAdding: .day, value: -currentWeightWindowDays, to: now) else { return nil }
        return metrics.filter { metric in
            guard let weight = metric.weight, weight.isFinite, weight > 0 else { return false }
            return metric.effectiveDate >= start && metric.effectiveDate <= now
        }.max { $0.effectiveDate < $1.effectiveDate }
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
}

func computeRangeStats(
    metrics: [BodyMetrics],
    valueProvider: (BodyMetrics) -> Double?
) -> MetricRangeStats? {
    let sortedMetrics = metrics.sorted { $0.date < $1.date }
    let dataPoints: [(date: Date, value: Double)] = sortedMetrics.compactMap { metric in
        guard let value = valueProvider(metric) else { return nil }
        return (metric.date, value)
    }

    guard let first = dataPoints.first, let last = dataPoints.last, !dataPoints.isEmpty else {
        return nil
    }

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
        percentageChange: percentageChange
    )
}

struct MetricSeriesStats {
    let average: Double
    let delta: Double
    let percentageChange: Double
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
