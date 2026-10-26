//
// HomeV2MetricEditorial.swift
// LogYourBody
//
import SwiftUI

/// One tappable source. The chip is the only provenance on the canvas.
/// The longer explanation stays in the sheet.
struct HomeV2ProvenanceDetail: Equatable, Identifiable {
    let chip: String
    let title: String
    let body: String

    var id: String { "\(chip)|\(title)|\(body)" }
}

struct HomeV2MetricContext: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
}

/// Chart geometry shared by Progress and the home timeline.
/// Lines stay linear, stop at gaps, and never extend below zero.
enum HomeV2ChartIntegrity {
    static let smoothing = "linear"

    struct Sample: Equatable, Identifiable {
        let date: Date
        let value: Double
        enum Kind: String { case daily, sevenDayAverage }
        var kind: Kind = .daily
        /// Distinguishes two readings that share a day and a value.
        var occurrence = 0
        /// Keep the reading time even though marks use calendar-day positions.
        var recordedAt: Date?

        var id: String { "\(date.timeIntervalSinceReferenceDate)-\(value)-\(occurrence)-\(kind.rawValue)" }
    }

    struct Plot: Equatable {
        /// Contiguous calendar runs. A run of one is a point, not a line.
        let runs: [[Sample]]
        let marks: [Sample]
        let yDomain: ClosedRange<Double>
        let anchorsToZero: Bool
        let xAxisDates: [Date]
        let smoothing: String
        let droppedNegative: Int
        let droppedMissing: Int
        let droppedCarried: Int
        let droppedNonFinite: Int

        /// Prepared once, in date order, with one selectable value per day.
        let selectionSamples: [Sample]

        func nearest(to date: Date) -> Sample? {
            var lower = 0
            var upper = selectionSamples.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if selectionSamples[middle].date < date {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            if lower == 0 { return selectionSamples.first }
            if lower == selectionSamples.count { return selectionSamples.last }
            let before = selectionSamples[lower - 1]
            let after = selectionSamples[lower]
            return date.timeIntervalSince(before.date) <= after.date.timeIntervalSince(date) ? before : after
        }

        var yTicks: [Double] {
            let lower = anchorsToZero ? 0 : yDomain.lowerBound
            let upper = yDomain.upperBound
            guard upper > lower else { return [lower] }
            return [lower, lower + (upper - lower) / 2, upper]
        }
    }

    struct FilterResult {
        let samples: [Sample]
        let droppedNegative: Int
        let droppedMissing: Int
        let droppedCarried: Int
        let droppedNonFinite: Int
    }

    struct Request: Equatable {
        var daily: [MetricChartDataPoint]
        var trend: [MetricChartDataPoint]
        var range: TimeRange
        var now: Date
        var calendar: Calendar
        var showsDots: Bool
        var usesSevenDayAverage: Bool
        var anchorsToZero: Bool

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.range == rhs.range && lhs.now == rhs.now && lhs.calendar == rhs.calendar
                && lhs.showsDots == rhs.showsDots && lhs.usesSevenDayAverage == rhs.usesSevenDayAverage
                && lhs.anchorsToZero == rhs.anchorsToZero
                && samePoints(lhs.daily, rhs.daily) && samePoints(lhs.trend, rhs.trend)
        }

        private static func samePoints(_ lhs: [MetricChartDataPoint], _ rhs: [MetricChartDataPoint]) -> Bool {
            guard lhs.count == rhs.count else { return false }
            // Swift arrays share storage until a write. Most playhead updates reuse
            // exactly that storage; equal, freshly loaded histories still compare by value.
            return lhs.withUnsafeBufferPointer { left in
                rhs.withUnsafeBufferPointer { right in
                    if left.baseAddress == right.baseAddress { return true }
                    return left.elementsEqual(right) {
                        $0.date == $1.date && $0.value.bitPattern == $1.value.bitPattern && $0.presence == $1.presence
                    }
                }
            }
        }
    }

    struct Preparation {
        let visibleDaily: [MetricChartDataPoint]
        let hasEnoughData: Bool
        let plot: Plot
    }

    /// View-owned, never shared across metrics or accounts. Selection is not an input.
    final class PreparationCache {
        private var request: Request?
        private var preparation: Preparation?
        private(set) var preparationCount = 0

        func value(for request: Request) -> Preparation {
            if self.request == request, let preparation { return preparation }
            let preparation = HomeV2ChartIntegrity.prepare(request, prefersLatestReading: true)
            self.request = request
            self.preparation = preparation
            preparationCount += 1
            return preparation
        }
    }

    static func prepare(_ request: Request, prefersLatestReading: Bool) -> Preparation {
        let daily = HomeV2TrendPolicy.points(
            request.daily, in: request.range, now: request.now, calendar: request.calendar
        )
        let trend = HomeV2TrendPolicy.points(
            request.trend, in: request.range, now: request.now, calendar: request.calendar
        )
        return Preparation(
            visibleDaily: daily,
            hasEnoughData: HomeV2TrendPolicy.hasEnoughData(
                HomeV2MetricEditorial.observedPoints(daily), calendar: request.calendar
            ),
            plot: plot(
                points: request.usesSevenDayAverage ? trend : daily,
                dotPoints: request.showsDots ? daily : [],
                anchorsToZero: request.anchorsToZero,
                keepsCarriedValues: request.usesSevenDayAverage,
                calendar: request.calendar,
                prefersLatestReading: prefersLatestReading
            )
        )
    }

    static func plot(
        points: [MetricChartDataPoint],
        dotPoints: [MetricChartDataPoint] = [],
        anchorsToZero: Bool,
        keepsCarriedValues: Bool,
        calendar: Calendar = .current,
        prefersLatestReading: Bool = true
    ) -> Plot {
        let line = filter(points, keepsCarriedValues: keepsCarriedValues, calendar: calendar,
                          kind: keepsCarriedValues ? .sevenDayAverage : .daily)
        let dots = filter(dotPoints, keepsCarriedValues: false, calendar: calendar)
        let runs = contiguousRuns(line.samples, calendar: calendar)
        var seen = Set(line.samples.map(\.id))
        var marks = line.samples
        for sample in dots.samples where seen.insert(sample.id).inserted {
            marks.append(sample)
        }
        marks.sort { $0.date == $1.date ? $0.value < $1.value : $0.date < $1.date }
        let domainValues = marks.map(\.value)
        return Plot(
            runs: runs,
            marks: marks,
            yDomain: yDomain(values: domainValues, anchorsToZero: anchorsToZero),
            anchorsToZero: anchorsToZero,
            xAxisDates: axisDates(in: marks),
            smoothing: smoothing,
            droppedNegative: line.droppedNegative + dots.droppedNegative,
            droppedMissing: line.droppedMissing + dots.droppedMissing,
            droppedCarried: line.droppedCarried + dots.droppedCarried,
            droppedNonFinite: line.droppedNonFinite + dots.droppedNonFinite,
            selectionSamples: selectionSamples(in: marks, prefersLatestReading: prefersLatestReading)
        )
    }

    private static func selectionSamples(in marks: [Sample], prefersLatestReading: Bool) -> [Sample] {
        var byDay: [Date: Sample] = [:]
        for sample in marks {
            guard let previous = byDay[sample.date] else {
                byDay[sample.date] = sample
                continue
            }
            if previous.kind != sample.kind {
                if sample.kind == .daily { byDay[sample.date] = sample }
            } else if prefersLatestReading,
                      (sample.recordedAt ?? sample.date) > (previous.recordedAt ?? previous.date) {
                byDay[sample.date] = sample
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    static func filter(
        _ points: [MetricChartDataPoint],
        keepsCarriedValues: Bool,
        calendar: Calendar,
        kind: Sample.Kind = .daily
    ) -> FilterResult {
        var droppedNegative = 0
        var droppedMissing = 0
        var droppedCarried = 0
        var droppedNonFinite = 0
        var samples: [Sample] = []
        var occurrences: [String: Int] = [:]
        for point in points.sorted(by: { $0.date < $1.date }) {
            switch point.presence {
            case .missing:
                droppedMissing += 1
                continue
            case .interpolated, .lastKnown:
                if !keepsCarriedValues {
                    droppedCarried += 1
                    continue
                }
            case .present, .estimated:
                break
            }
            guard point.value.isFinite else {
                droppedNonFinite += 1
                continue
            }
            guard point.value >= 0 else {
                droppedNegative += 1
                continue
            }
            let day = calendar.startOfDay(for: point.date)
            let key = "\(day.timeIntervalSinceReferenceDate)-\(point.value)"
            let occurrence = occurrences[key] ?? 0
            occurrences[key] = occurrence + 1
            samples.append(Sample(date: day, value: point.value, kind: kind, occurrence: occurrence,
                                  recordedAt: point.date))
        }
        return FilterResult(
            samples: samples,
            droppedNegative: droppedNegative,
            droppedMissing: droppedMissing,
            droppedCarried: droppedCarried,
            droppedNonFinite: droppedNonFinite
        )
    }

    /// A gap of more than one calendar day breaks the line. Nothing is filled in.
    static func contiguousRuns(_ samples: [Sample], calendar: Calendar) -> [[Sample]] {
        var runs: [[Sample]] = []
        var current: [Sample] = []
        for sample in samples {
            if let last = current.last {
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: last.date),
                    to: calendar.startOfDay(for: sample.date)
                ).day ?? 0
                if days > 1 {
                    runs.append(current)
                    current = [sample]
                    continue
                }
            }
            current.append(sample)
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    static func yDomain(values: [Double], anchorsToZero: Bool) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite).filter { $0 >= 0 }
        guard let minValue = finite.min(), let maxValue = finite.max() else {
            return 0...1
        }
        if anchorsToZero {
            let upper = max(maxValue * 1.08, 1)
            return 0...upper
        }
        if minValue == maxValue {
            let pad = max(abs(minValue) * 0.08, 0.5)
            let lower = max(0, minValue - pad)
            return lower...(maxValue + pad)
        }
        let pad = (maxValue - minValue) * 0.12
        let lower = max(0, minValue - pad)
        let upper = maxValue + pad
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    /// First, middle, and last plotted day. The count stays 0, 1, or 3.
    static func axisDates(in samples: [Sample]) -> [Date] {
        let sorted = samples.sorted { $0.date < $1.date }
        switch sorted.count {
        case 0:
            return []
        case 1:
            return [sorted[0].date]
        default:
            return [sorted[0].date, sorted[sorted.count / 2].date, sorted[sorted.count - 1].date]
        }
    }

    static func axisLabel(
        date: Date,
        range: TimeRange,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if let days = range.days, days <= 31 {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else if range == .all {
            formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMM")
        }
        return formatter.string(from: date)
    }

    static func axisLabels(
        dates: [Date],
        range: TimeRange,
        locale: Locale,
        calendar: Calendar = .current
    ) -> [String] {
        dates.map { axisLabel(date: $0, range: range, locale: locale, calendar: calendar) }
    }

    static func nearest(to date: Date, in samples: [Sample]) -> Sample? {
        samples.min { lhs, rhs in
            let left = abs(lhs.date.timeIntervalSince(date))
            let right = abs(rhs.date.timeIntervalSince(date))
            if left == right { return lhs.date < rhs.date }
            return left < right
        }
    }

    static func tooltip(date: Date, valueText: String, locale: Locale, calendar: Calendar = .current,
                        kind: Sample.Kind = .daily) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(formatter.string(from: date)) · \(valueText) · \(kind == .sevenDayAverage ? "7-day average" : "Daily value")"
    }

    static func tickLabel(_ value: Double, integers: Bool) -> String {
        if integers {
            return FormatterCache.formattedSteps(value) ?? "0"
        }
        return String(format: "%.1f", value)
    }
}

/// Inputs for the shared metric hero. One value keeps the call under the parameter limit.
struct HomeV2MetricCanvasRequest {
    let metric: HomeV2ProgressMetric
    let points: [MetricChartDataPoint]
    let unit: String
    let deltaUnit: String
    let range: TimeRange
    let provenance: HomeV2ProvenanceDetail?
    let target: Double?
    let hasEnoughData: Bool
    let formatValue: (Double) -> String
    let dateText: (Date) -> String
    var calendar = Calendar.current
    var observationSummary: MetricObservationSummary?
}

/// Hero copy for Steps, Weight, Body fat, FFMI, and the home timeline.
enum HomeV2MetricEditorial {
    static let stepsDisplayUnit = "steps"
    static let healthKitChip = "HealthKit"

    struct Canvas: Equatable {
        let value: String
        let unit: String
        let comparison: String
        let provenance: HomeV2ProvenanceDetail?
        let context: [HomeV2MetricContext]
        let visibleLines: [String]
    }

    /// Raw metric summaries use the same finite, observed/estimated samples as their plot.
    /// Carried values remain available only in the separately labeled weight average.
    static func observedPoints(_ points: [MetricChartDataPoint]) -> [MetricChartDataPoint] {
        points.filter { point in
            guard point.value.isFinite, point.value >= 0 else { return false }
            switch point.presence {
            case .present, .estimated: return true
            case .missing, .interpolated, .lastKnown: return false
            }
        }
    }

    static func canvas(_ request: HomeV2MetricCanvasRequest) -> Canvas {
        let stats = HomeV2ProgressPolicy.stats(
            points: observedPoints(request.points),
            prefersHigh: request.metric.prefersHigh,
            calendar: request.calendar
        )
        let comparison = request.observationSummary?.changeText(
            unit: request.metric == .steps ? "steps" : request.unit
        ) ?? comparisonText(
            metric: request.metric,
            stats: stats,
            deltaUnit: request.deltaUnit,
            range: request.range,
            hasEnoughData: request.hasEnoughData
        )
        let context = contextItems(
            stats: stats,
            prefersHigh: request.metric.prefersHigh,
            target: request.target,
            formatValue: request.formatValue,
            dateText: request.dateText
        )
        let value = (request.observationSummary?.point?.value ?? stats.latest).map(request.formatValue) ?? "—"
        let resolvedUnit = request.metric == .steps ? stepsDisplayUnit : request.unit
        var lines = [value, comparison]
        if !resolvedUnit.isEmpty { lines.append(resolvedUnit) }
        if let provenance = request.provenance { lines.append(provenance.chip) }
        lines.append(contentsOf: context.map { "\($0.label) \($0.value)" })
        return Canvas(
            value: value,
            unit: resolvedUnit,
            comparison: comparison,
            provenance: request.provenance,
            context: context,
            visibleLines: lines
        )
    }

    static func comparisonText(
        metric: HomeV2ProgressMetric,
        stats: HomeV2ProgressPolicy.Stats,
        deltaUnit: String,
        range: TimeRange,
        hasEnoughData: Bool
    ) -> String {
        guard hasEnoughData else {
            return HomeV2ProgressCopy.dataDaysSentence(days: stats.distinctDays)
        }
        if metric == .steps {
            return HomeV2ProgressCopy.stepsComparison(
                latest: stats.latest,
                average: stats.average,
                range: range
            )
        }
        return HomeV2ProgressCopy.deltaSentence(delta: stats.delta, unit: deltaUnit, range: range)
    }

    static func contextItems(
        stats: HomeV2ProgressPolicy.Stats,
        prefersHigh: Bool,
        target: Double?,
        formatValue: (Double) -> String,
        dateText: (Date) -> String
    ) -> [HomeV2MetricContext] {
        let extremeTitle = prefersHigh ? HomeV2ProgressCopy.high : HomeV2ProgressCopy.low
        let targetDetail = prefersHigh ? "Daily goal" : "Goal"
        return [
            HomeV2MetricContext(
                id: "start",
                label: dated(HomeV2ProgressCopy.start, date: stats.startDate, dateText: dateText),
                value: stats.start.map(formatValue) ?? HomeV2ProgressCopy.notSet
            ),
            HomeV2MetricContext(
                id: "extreme",
                label: dated(extremeTitle, date: stats.extremeDate, dateText: dateText),
                value: stats.extreme.map(formatValue) ?? HomeV2ProgressCopy.notSet
            ),
            HomeV2MetricContext(
                id: "target",
                label: target == nil ? HomeV2ProgressCopy.target : "\(HomeV2ProgressCopy.target) · \(targetDetail)",
                value: target.map(formatValue) ?? HomeV2ProgressCopy.notSet
            )
        ]
    }

    static func progressProvenance(
        metric: HomeV2ProgressMetric,
        bodyFatSource: String?
    ) -> HomeV2ProvenanceDetail? {
        switch metric {
        case .weight:
            return nil
        case .steps:
            return HomeV2ProvenanceDetail(
                chip: healthKitChip,
                title: "Steps",
                body: "Daily totals as your iPhone or watch recorded them in Apple Health. Nothing is written back."
            )
        case .bodyFat:
            let lead = bodyFatSource.map { HomeV2ProgressCopy.estimatedBy($0) } ?? "Source not recorded"
            return HomeV2ProvenanceDetail(
                chip: chip(for: bodyFatSource ?? "Source not recorded"),
                title: HomeV2ProgressCopy.bodyFatInsightTitle,
                body: "\(lead). \(HomeV2ProgressCopy.bodyFatInsightBody)"
            )
        case .ffmi:
            return HomeV2ProvenanceDetail(
                chip: "Estimated",
                title: HomeV2ProgressCopy.ffmiInsightTitle,
                body: "\(HomeV2ProgressCopy.ffmiSource). \(HomeV2ProgressCopy.ffmiInsightBody)"
            )
        }
    }

    static func timelineProvenance(for metric: BodyMetrics) -> HomeV2ProvenanceDetail? {
        let fat = HomeV2EditorialPolicy.bodyFat(in: metric)
        let hasWeight = metric.weight != nil
        guard hasWeight || fat != nil else { return nil }
        let weightSource = HomeV2Provenance.label(for: metric, field: .weight)
        let weightChip = chip(for: weightSource)
        let fatChip = fat.map { chip(for: $0.caption) }
        let resolved: String
        if let fatChip, hasWeight, fatChip != weightChip {
            resolved = "Sources"
        } else if hasWeight {
            resolved = weightChip
        } else {
            resolved = fatChip ?? "Source"
        }
        var lines: [String] = []
        if hasWeight { lines.append("Weight is from \(weightSource).") }
        if let fat { lines.append("Body fat: \(fat.caption).") }
        return HomeV2ProvenanceDetail(chip: resolved, title: "Source", body: lines.joined(separator: " "))
    }

    static func compositionLine(percentage: Double) -> String {
        "Body fat \(String(format: "%.1f", percentage))%"
    }

    static func chip(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        if key.isEmpty || key == "source not recorded" { return "Source" }
        let rules: [(String, String)] = [
            ("healthkit", healthKitChip),
            ("apple health", healthKitChip),
            ("dexa", "DEXA"),
            ("bodyspec", "DEXA"),
            ("visual", "Estimate"),
            ("inbody", "InBody"),
            ("caliper", "Calipers"),
            ("bioelectrical", "Scale"),
            ("smart scale", "Scale"),
            ("typed", "Typed"),
            ("entered by you", "Typed"),
            ("manual", "Typed")
        ]
        if let match = rules.first(where: { key.contains($0.0) }) { return match.1 }
        if key.hasPrefix("estimated by your ") {
            return String(trimmed.dropFirst("Estimated by your ".count))
        }
        if key.contains("estimated from weight") { return "Estimated" }
        if key.hasPrefix("from your ") {
            let rest = String(trimmed.dropFirst("From your ".count))
            let cleaned = rest.replacingOccurrences(of: " scan", with: "")
            return cleaned.isEmpty ? trimmed : cleaned
        }
        return trimmed
    }

    private static func dated(_ title: String, date: Date?, dateText: (Date) -> String) -> String {
        guard let date else { return title }
        let text = dateText(date)
        guard !text.isEmpty else { return title }
        return "\(title) · \(text)"
    }
}

/// Value, unit, comparison, and one provenance chip.
struct HomeV2MetricHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let value: String
    let unit: String
    let comparison: String
    var provenance: HomeV2ProvenanceDetail?
    var onProvenancePresentationChange: (Bool) -> Void = { _ in }
    var valueIdentifier = "home_v2_progress_value"
    var comparisonIdentifier = "home_v2_progress_delta"
    var valueSize: CGFloat = HomeV2Tokens.TypeSize.progressValue
    var showsComparison = true

    @State private var showsProvenance = false

    var body: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
            valueRow
            if showsComparison {
                Text(comparison)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(comparisonIdentifier)
            }
            if let provenance {
                HomeV2ProvenanceChip(detail: provenance) { showsProvenance = true }
            }
        }
        .sheet(isPresented: $showsProvenance) {
            if let provenance {
                HomeV2ProvenanceSheet(detail: provenance)
            }
        }
        .onChange(of: provenance) { _, _ in showsProvenance = false }
        .onChange(of: showsProvenance) { _, presented in onProvenancePresentationChange(presented) }
        .onDisappear { onProvenancePresentationChange(false) }
    }

    @ViewBuilder
    private var valueRow: some View {
        let valueText = Text(value)
            .scaledSystemFont(size: valueSize, weight: .semibold, relativeTo: .largeTitle)
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier(valueIdentifier)
        let unitText = Text(unit)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.lead, weight: .medium, relativeTo: .title3)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
        if unit.isEmpty {
            valueText
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                valueText
                unitText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: HomeV2Tokens.Space.tight) {
                valueText
                unitText
            }
        }
    }
}

struct HomeV2ProvenanceChip: View {
    let detail: HomeV2ProvenanceDetail
    let action: () -> Void

    var body: some View {
        Button(action: action, label: {
            Text(detail.chip)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .lineLimit(1)
                .padding(.horizontal, HomeV2Tokens.Space.tight)
                .padding(.vertical, 4)
                .background(HomeV2Tokens.Colors.elevated, in: Capsule())
                .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .accessibilityLabel("Source, \(detail.chip)")
        .accessibilityHint("Shows where this number comes from")
        .accessibilityIdentifier("home_v2_provenance_chip")
    }
}

struct HomeV2ProvenanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: HomeV2ProvenanceDetail

    var body: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
            Text(detail.title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .semibold, relativeTo: .title2)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Text(detail.body)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: { dismiss() }, label: {
                Text(HomeV2Copy.done)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ctaInk)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                    .background(HomeV2Tokens.Colors.ctaFill, in: Capsule())
            })
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_provenance_done")
        }
        .padding(HomeV2Tokens.Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .presentationDetents([.medium])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_provenance_detail")
    }
}
