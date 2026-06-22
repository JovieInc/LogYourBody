import SwiftUI
import Charts

extension FullMetricChartView {
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

var headlineBlock: some View {
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
    func statsCell(
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

func formatDeltaValueCompact(_ delta: Double) -> String {
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

var historySections: [HistorySection] {
        guard let payload = metricEntries, !payload.entries.isEmpty else { return [] }
        return makeHistorySections(from: payload.entries)
    }

var displayedHistorySections: [HistorySection] {
        if let cached = localHistorySections {
            return cached
        }
        return historySections
    }

var timeRangeSelector: some View {
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

var chartCard: some View {
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
    var relatedMetricsRow: some View {
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

func relatedMetricTile(_ metric: MetricDetailRelatedMetric) -> some View {
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

func relatedMetricAccent(for id: String) -> Color {
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

var chartSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subtitle placeholder
            SkeletonView(width: 140, height: 14, cornerRadius: 7)

            // Chart area placeholder
            SkeletonView(height: chartHeight - 40, cornerRadius: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight, alignment: .topLeading)
    }

var chartHeader: some View {
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

var chartPresenceLegend: some View {
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

var chartModeToggle: some View {
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

var chartView: some View {
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

func selectedPointCallout(for point: MetricChartDataPoint) -> some View {
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
}
