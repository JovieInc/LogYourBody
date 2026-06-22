import SwiftUI
import Charts

extension FullMetricChartView {
var historyBlock: some View {
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

func historyRow(for entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> some View {
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

func primaryHistoryValue(_ entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> String {
        let formatter = config.primaryFormatter
        let value = formatter.string(from: NSNumber(value: entry.primaryValue)) ?? formattedValue(entry.primaryValue)
        if config.unitLabel.isEmpty {
            return value
        }
        return "\(value) \(config.unitLabel)"
    }

func secondaryHistoryValue(_ entry: MetricHistoryEntry, config: MetricEntriesConfiguration) -> String? {
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

func sourceLabel(for source: MetricEntrySourceType) -> String {
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
    func historySourceIcon(for source: MetricEntrySourceType) -> some View {
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

func historyScrubber(proxy: ScrollViewProxy) -> some View {
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

    var displayedSeries: [MetricChartDataPoint] {
        if let cached = cachedSeries[selectedTimeRange], !cached.isEmpty {
            return cached
        }

        if chartData.count > 120 {
            return Array(chartData.suffix(120))
        }

        return chartData
    }

var smoothedSeries: [MetricChartDataPoint] {
        movingAverage(for: displayedSeries, windowSize: 7)
    }

var activeSeries: [MetricChartDataPoint] {
        chartMode == .trend ? smoothedSeries : displayedSeries
    }

var visiblePresenceLegendItems: [ChartPresenceLegendItem] {
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

var chartPresenceCounts: [MetricPresence: Int] {
        chartData.reduce(into: [:]) { counts, point in
            counts[point.presence, default: 0] += 1
        }
    }

var shouldShowPresenceLegend: Bool {
        visiblePresenceLegendItems.contains { item in
            item.presence != .present
        }
    }

var minSeriesValue: Double? {
        activeSeries.map(\.value).min()
    }

var headlineValueText: String {
        if let point = selectedFocusPoint {
            return formatHeadlineValue(point.value)
        }
        return currentValue
    }

var headlineDateText: String {
        if let point = selectedFocusPoint {
            return point.date.formatted(.dateTime.month().day().year())
        }
        return currentDate
    }

var selectedFocusPoint: MetricChartDataPoint? {
        if let activePoint {
            return activePoint
        }

        guard let selectedTimelineDate else { return nil }
        return nearestPoint(to: selectedTimelineDate)
    }

var chartDataFingerprint: String {
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

    func formatHeadlineValue(_ value: Double) -> String {
        if isStepsMetric {
            let steps = Int(value.rounded())
            return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }

        if unit == "%" {
            return String(format: "%.1f", value)
        }
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

func formatStatValue(_ value: Double) -> String {
        if isStepsMetric {
            let steps = Int(value.rounded())
            return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }

        if unit == "%" {
            return String(format: "%.1f%%", value)
        }
        return String(format: value < 10 ? "%.2f" : "%.1f", value)
    }

func formattedValue(_ value: Double) -> String {
        formatStatValue(value)
    }

func movingAverage(
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

func computeSeriesStats(
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

func combinedPresence(for presences: [MetricPresence]) -> MetricPresence {
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

func presenceLabel(for presence: MetricPresence) -> String {
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

func chartPointColor(for presence: MetricPresence) -> Color {
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

func chartPointSymbolSize(for presence: MetricPresence) -> CGFloat {
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

func chartPointOpacity(for presence: MetricPresence) -> Double {
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

func pointCountLabel(for count: Int) -> String {
        count == 1 ? "point" : "points"
    }

func formatDeltaValue(_ delta: Double) -> String {
        formatDelta(delta: delta, unit: unit)
    }

func deltaColor(for delta: Double) -> Color {
        let threshold: Double = 0.0001
        guard abs(delta) > threshold else {
            return Color.metricTextPrimary
        }
        return delta > 0 ? Color.metricDeltaPositive : Color.metricDeltaNegative
    }

@MainActor
    func deleteHistoryEntry(_ entry: MetricHistoryEntry) async {
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

func nearestPoint(to date: Date) -> MetricChartDataPoint? {
        activeSeries.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

var isStepsMetric: Bool {
        unit.lowercased() == "steps"
    }

var xAxisTickCount: Int {
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
    func preprocessChartDataIfNeeded() async {
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
    func preprocessHistorySectionsIfNeeded() async {
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
