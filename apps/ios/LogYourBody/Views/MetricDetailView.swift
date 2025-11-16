//
// MetricDetailView.swift
// LogYourBody
//
// Full-screen metric detail view with period selector and enhanced chart
// Matches Apple Health's metric detail screen design
//

import SwiftUI
import Charts

// MARK: - Metric Detail View

struct MetricDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // Metric information
    let metricType: DashboardViewLiquid.DashboardMetricKind
    let userId: String
    let useMetricUnits: Bool
    let userHeightCm: Double?

    // Current values
    let currentValue: String
    let unit: String
    let timestamp: Date?

    // Callbacks
    let onAdd: () -> Void

    @State private var selectedPeriod: TimePeriod = .week
    @State private var chartData: [SparklineDataPoint] = []
    @State private var selectedDataPoint: DetailChartDataPoint?
    @State private var isScrubbing: Bool = false
    @State private var lastHapticIndex: Int? = nil
    @State private var isLoadingData: Bool = false
    @State private var entrySections: [MetricEntrySection] = []
    @State private var editingEntry: MetricEntry?
    @State private var editableWeightText: String = ""
    @State private var editableBodyFatText: String = ""
    @State private var isPerformingEntryAction = false
    @State private var showDeleteConfirmation = false
    @State private var editingErrorMessage: String?

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Navigation bar
                    navigationBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    // Period selector
                    PeriodSelector(selectedPeriod: $selectedPeriod)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .onChange(of: selectedPeriod) { _ in
                            Task {
                                await loadChartData()
                            }
                        }

                    // Current value display
                    currentValueDisplay
                        .padding(.bottom, 24)

                    // Chart
                    chartView
                        .frame(height: 360)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)

                    // Statistics
                    statisticsView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)

                    if canEditEntries {
                        entryList
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .refreshable {
                await refreshData()
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $editingEntry) { entry in
            MetricEntryEditSheet(
                entry: entry,
                metricName: metricTitle,
                weightText: $editableWeightText,
                bodyFatText: $editableBodyFatText,
                measurementSystem: measurementSystem,
                showsWeightField: entry.supportsWeight,
                showsBodyFatField: entry.supportsBodyFat,
                isSaving: isPerformingEntryAction,
                showsIntegrationBanner: entry.source == .integration,
                errorMessage: editingErrorMessage,
                onSave: { saveEditingEntry() },
                onDelete: { showDeleteConfirmation = true },
                onClose: {
                    editingErrorMessage = nil
                    editingEntry = nil
                }
            )
            .presentationDetents([.fraction(0.7), .large])
            .presentationBackground(.black)
        }
        .alert("Delete Entry?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteEditingEntry()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            Task {
                await loadChartData()
                await loadEntries()
            }
        }
    }

    private func startEditing(_ entry: MetricEntry) {
        editingEntry = entry
        editingErrorMessage = nil

        if entry.supportsWeight, let weight = entry.weightKg {
            editableWeightText = formatWeightInput(weight)
        } else {
            editableWeightText = ""
        }

        if entry.supportsBodyFat, let bodyFat = entry.bodyFatPercentage {
            editableBodyFatText = formatBodyFatInput(bodyFat)
        } else {
            editableBodyFatText = ""
        }
    }

    private func primaryValue(for entry: MetricEntry) -> (value: String, unit: String) {
        switch metricType {
        case .weight:
            guard let weight = entry.weightKg else { return ("––", measurementSystem.weightUnit) }
            return (formatWeight(weight), measurementSystem.weightUnit)
        case .bodyFat:
            guard let bodyFat = entry.bodyFatPercentage else { return ("––", "%") }
            return (formatBodyFatValue(bodyFat), "%")
        case .ffmi:
            guard let ffmiValue = entry.ffmi else { return ("––", "FFMI") }
            return (String(format: "%.1f", ffmiValue), "FFMI")
        default:
            return ("––", "")
        }
    }

    private func secondaryValue(for entry: MetricEntry) -> String? {
        switch metricType {
        case .weight:
            if let bodyFat = entry.bodyFatPercentage {
                return "Body Fat \(formatBodyFatDisplay(bodyFat))"
            }
            return nil
        case .bodyFat:
            if let weight = entry.weightKg {
                return "Weight \(formatWeight(weight)) \(measurementSystem.weightUnit)"
            }
            return nil
        case .ffmi:
            var components: [String] = []
            if let weight = entry.weightKg {
                components.append("Weight \(formatWeight(weight)) \(measurementSystem.weightUnit)")
            }
            if let bodyFat = entry.bodyFatPercentage {
                components.append("Body Fat \(formatBodyFatDisplay(bodyFat))")
            }
            return components.isEmpty ? nil : components.joined(separator: " • ")
        default:
            return nil
        }
    }

    private func formatEntryDate(_ date: Date) -> String {
        MetricDetailFormatters.entryDate.string(from: date)
    }

    private func formatWeight(_ weightKg: Double) -> String {
        let displayWeight = measurementSystem == .imperial ? weightKg * 2.20462 : weightKg
        return String(format: "%.1f", displayWeight)
    }

    private func formatWeightInput(_ weightKg: Double) -> String {
        formatWeight(weightKg)
    }

    private func formatBodyFatValue(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func formatBodyFatDisplay(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func formatBodyFatInput(_ value: Double) -> String {
        formatBodyFatValue(value)
    }

    private func parseDecimal(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: metricIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(metricColor)

                Text(metricTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
        }
    }

    // MARK: - Current Value Display

    private var currentValueDisplay: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayedValue)
                    .font(.system(size: 68, weight: .bold))
                    .foregroundColor(.white)
                    .animation(.easeOut(duration: 0.2), value: selectedDataPoint?.index)

                Text(unit)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            HStack(spacing: 6) {
                Text(displayedTimestamp)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))

                if isSelectedPointEstimated {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8))

                        Text("Estimated")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedDataPoint?.index)
        }
    }

    // MARK: - Chart View

    private var chartView: some View {
        Group {
            if isLoadingData {
                loadingView
            } else {
                if chartData.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))

                        Text("No Data")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))

                        Text("Add entries to see your progress")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        Chart {
                            ForEach(chartData) { point in
                                LineMark(
                                    x: .value("Index", point.index),
                                    y: .value("Value", point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(metricColor.gradient)

                                AreaMark(
                                    x: .value("Index", point.index),
                                    yStart: .value("Value", 0),
                                    yEnd: .value("Value", point.value)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(metricColor.opacity(0.2).gradient)
                            }

                            if let selected = selectedDataPoint {
                                RuleMark(x: .value("Index", selected.index))
                                    .foregroundStyle(Color.white.opacity(0.35))

                                PointMark(
                                    x: .value("Index", selected.index),
                                    y: .value("Value", selected.value)
                                )
                                .symbolSize(80)
                                .foregroundStyle(Color.white)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartPlotStyle { plot in
                            plot
                                .background(Color.white.opacity(0.03))
                                .cornerRadius(20)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let clampedX = min(max(0, value.location.x), geometry.size.width)
                                    handleChartDrag(at: clampedX, chartWidth: geometry.size.width)
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isScrubbing = false
                                        selectedDataPoint = nil
                                        lastHapticIndex = nil
                                    }
                                }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Statistics View

    private var statisticsView: some View {
        Group {
            if !isLoadingData && !chartData.isEmpty {
                HStack(spacing: 16) {
                    MetricStatCard(
                        label: "Average",
                        value: formatStatValue(calculateAverage()),
                        unit: unit
                    )

                    MetricStatCard(
                        label: "Min",
                        value: formatStatValue(calculateMin()),
                        unit: unit
                    )

                    MetricStatCard(
                        label: "Max",
                        value: formatStatValue(calculateMax()),
                        unit: unit
                    )

                    MetricStatCard(
                        label: "Change",
                        value: formatChange(calculateChange()),
                        unit: unit,
                        isChange: true
                    )
                }
            }
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Entries")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            if entrySections.isEmpty {
                VStack(spacing: 8) {
                    Text("No entries yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Text("Log a new measurement to get started.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
            } else {
                VStack(spacing: 20) {
                    ForEach(entrySections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

                            VStack(spacing: 12) {
                                ForEach(section.entries) { entry in
                                    entryRow(for: entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(for entry: MetricEntry) -> some View {
        Button {
            startEditing(entry)
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    let primary = primaryValue(for: entry)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(primary.value)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)

                        if !primary.unit.isEmpty {
                            Text(primary.unit)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    if let secondary = secondaryValue(for: entry) {
                        Text(secondary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(formatEntryDate(entry.date))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 6) {
                        Image(systemName: entry.source.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(entry.source.tint)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.08), in: Circle())

                        Text(entry.source.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(entry.source.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(entry.source.background, in: Capsule())
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(metricColor)

            Text("Loading data...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Properties

    private var metricTitle: String {
        switch metricType {
        case .steps: return "Steps"
        case .weight: return "Weight"
        case .bodyFat: return "Body Fat"
        case .ffmi: return "FFMI"
        case .waist: return "Waist"
        }
    }

    private var metricIcon: String {
        switch metricType {
        case .steps: return "figure.walk"
        case .weight: return "figure.stand"
        case .bodyFat: return "percent"
        case .ffmi: return "figure.arms.open"
        case .waist: return "ruler"
        }
    }

    private var metricColor: Color {
        switch metricType {
        case .steps: return .orange
        case .weight: return .purple
        case .bodyFat: return .purple
        case .ffmi: return .purple
        case .waist: return .blue
        }
    }

    private var measurementSystem: MeasurementSystem {
        useMetricUnits ? .metric : .imperial
    }

    private var canEditEntries: Bool {
        switch metricType {
        case .weight, .bodyFat, .ffmi:
            return true
        default:
            return false
        }
    }

    // MARK: - Data Loading

    private func loadChartData() async {
        isLoadingData = true

        chartData = MetricChartDataHelper.generateChartData(
            for: userId,
            days: selectedPeriod.days,
            metricType: metricType,
            useMetric: useMetricUnits,
            userHeightCm: userHeightCm
        )

        isLoadingData = false
    }

    private func refreshData() async {
        // Clear cache and reload data
        MetricChartDataHelper.clearCache()
        await loadChartData()
        await loadEntries()

        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
    }

    private func loadEntries() async {
        guard canEditEntries else {
            await MainActor.run { entrySections = [] }
            return
        }

        let cached = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let metrics = cached.compactMap { $0.toBodyMetrics() }.sorted { $0.date > $1.date }
        let entries = metrics.compactMap { entry(from: $0) }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }

        let sections = grouped.keys.sorted(by: >).map { month -> MetricEntrySection in
            let monthEntries = grouped[month]?.sorted { $0.date > $1.date } ?? []
            return MetricEntrySection(month: month, entries: monthEntries)
        }

        await MainActor.run {
            entrySections = sections
        }
    }

    // MARK: - Entry Builders

    private func entry(from metric: BodyMetrics) -> MetricEntry? {
        let source = entrySource(for: metric)

        switch metricType {
        case .weight:
            guard let weight = metric.weight else { return nil }
            return MetricEntry(
                metric: metric,
                metricKind: metricType,
                weightKg: weight,
                bodyFatPercentage: metric.bodyFatPercentage,
                ffmi: nil,
                source: source,
                supportsWeight: true,
                supportsBodyFat: metric.bodyFatPercentage != nil
            )
        case .bodyFat:
            guard let bodyFat = metric.bodyFatPercentage else { return nil }
            return MetricEntry(
                metric: metric,
                metricKind: metricType,
                weightKg: metric.weight,
                bodyFatPercentage: bodyFat,
                ffmi: nil,
                source: source,
                supportsWeight: false,
                supportsBodyFat: true
            )
        case .ffmi:
            guard
                let height = userHeightCm,
                let weight = metric.weight,
                let bodyFat = metric.bodyFatPercentage
            else {
                return nil
            }

            let ffmiValue = MetricChartDataHelper.calculateFFMI(
                weightKg: weight,
                bodyFatPercentage: bodyFat,
                heightCm: height
            )

            return MetricEntry(
                metric: metric,
                metricKind: metricType,
                weightKg: weight,
                bodyFatPercentage: bodyFat,
                ffmi: ffmiValue,
                source: source,
                supportsWeight: true,
                supportsBodyFat: true
            )
        default:
            return nil
        }
    }

    private func entrySource(for metric: BodyMetrics) -> MetricEntrySource {
        guard let dataSource = metric.dataSource?.lowercased() else { return .manual }
        if dataSource == "manual" {
            return .manual
        }
        return .integration
    }

    // MARK: - Entry Editing

    private func saveEditingEntry() {
        Task {
            await persistEditingEntry()
        }
    }

    @MainActor
    private func persistEditingEntry() async {
        guard let entry = editingEntry else { return }

        editingErrorMessage = nil

        let trimmedWeight = editableWeightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBodyFat = editableBodyFatText.trimmingCharacters(in: .whitespacesAndNewlines)

        var updatedWeightKg: Double? = entry.metric.weight
        if entry.supportsWeight {
            guard !trimmedWeight.isEmpty, let weightValue = parseDecimal(from: trimmedWeight) else {
                setEditingError("Enter a valid weight")
                return
            }
            guard weightValue > 0 else {
                setEditingError("Weight must be greater than 0")
                return
            }
            updatedWeightKg = measurementSystem == .imperial ? weightValue * 0.453592 : weightValue
        }

        var updatedBodyFat: Double? = entry.metric.bodyFatPercentage
        if entry.supportsBodyFat {
            guard !trimmedBodyFat.isEmpty, let bodyFatValue = parseDecimal(from: trimmedBodyFat) else {
                setEditingError("Enter a valid body fat percentage")
                return
            }
            guard bodyFatValue >= 0, bodyFatValue <= 100 else {
                setEditingError("Body fat must be between 0 and 100")
                return
            }
            updatedBodyFat = bodyFatValue
        }

        guard updatedWeightKg != nil || updatedBodyFat != nil else {
            setEditingError("Enter at least one value")
            return
        }

        isPerformingEntryAction = true

        let base = entry.metric
        let newDataSource = entry.source == .integration ? "Manual Override" : (base.dataSource ?? "Manual")
        let updatedMetric = BodyMetrics(
            id: base.id,
            userId: base.userId,
            date: base.date,
            weight: entry.supportsWeight ? updatedWeightKg : base.weight,
            weightUnit: entry.supportsWeight ? (updatedWeightKg != nil ? "kg" : nil) : base.weightUnit,
            bodyFatPercentage: entry.supportsBodyFat ? updatedBodyFat : base.bodyFatPercentage,
            bodyFatMethod: entry.supportsBodyFat ? (updatedBodyFat != nil ? "Manual" : nil) : base.bodyFatMethod,
            muscleMass: base.muscleMass,
            boneMass: base.boneMass,
            notes: base.notes,
            photoUrl: base.photoUrl,
            dataSource: newDataSource,
            createdAt: base.createdAt,
            updatedAt: Date()
        )

        CoreDataManager.shared.saveBodyMetrics(updatedMetric, userId: base.userId, markAsSynced: false)
        RealtimeSyncManager.shared.syncIfNeeded()

        editingEntry = nil
        editableWeightText = ""
        editableBodyFatText = ""
        isPerformingEntryAction = false

        MetricChartDataHelper.clearCache()
        await loadChartData()
        await loadEntries()
    }

    private func deleteEditingEntry() {
        Task {
            await performDeleteEditingEntry()
        }
    }

    @MainActor
    private func performDeleteEditingEntry() async {
        guard let entry = editingEntry else { return }
        showDeleteConfirmation = false
        editingErrorMessage = nil
        isPerformingEntryAction = true

        CoreDataManager.shared.markBodyMetricAsDeleted(id: entry.metric.id)
        RealtimeSyncManager.shared.syncIfNeeded()

        editingEntry = nil
        editableWeightText = ""
        editableBodyFatText = ""
        isPerformingEntryAction = false

        MetricChartDataHelper.clearCache()
        await loadChartData()
        await loadEntries()
    }

    @MainActor
    private func setEditingError(_ message: String) {
        editingErrorMessage = message
        UINotificationFeedbackGenerator(style: .error).notificationOccurred(.error)
    }

    // MARK: - Statistics Calculations

    private func calculateAverage() -> Double? {
        guard !chartData.isEmpty else { return nil }
        let sum = chartData.reduce(0.0) { $0 + $1.value }
        return sum / Double(chartData.count)
    }

    private func calculateMin() -> Double? {
        chartData.map { $0.value }.min()
    }

    private func calculateMax() -> Double? {
        chartData.map { $0.value }.max()
    }

    private func calculateChange() -> Double? {
        guard chartData.count >= 2 else { return nil }
        let first = chartData.first!.value
        let last = chartData.last!.value
        return last - first
    }

    // MARK: - Formatting Helpers

    private func formatTimestamp(_ date: Date) -> String {
        MetricDetailFormatters.timestamp.string(from: date)
    }

    private func formatStatValue(_ value: Double?) -> String {
        guard let value = value else { return "––" }

        switch metricType {
        case .steps:
            return String(format: "%.0f", value)
        case .weight:
            return String(format: "%.1f", value)
        case .bodyFat:
            return String(format: "%.1f", value)
        case .ffmi:
            return String(format: "%.1f", value)
        case .waist:
            return String(format: "%.1f", value)
        }
    }

    private func formatChange(_ value: Double?) -> String {
        guard let value = value else { return "––" }

        let prefix = value >= 0 ? "+" : ""

        switch metricType {
        case .steps:
            return "\(prefix)\(String(format: "%.0f", value))"
        case .weight, .bodyFat, .ffmi, .waist:
            return "\(prefix)\(String(format: "%.1f", value))"
        }
    }

    // MARK: - Interactive Scrubbing

    private func handleChartDrag(at locationX: CGFloat, chartWidth: CGFloat) {
        guard !chartData.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            isScrubbing = true
        }

        let pointSpacing = chartWidth / CGFloat(max(chartData.count - 1, 1))
        let index = Int(round(locationX / pointSpacing))
        let clampedIndex = min(max(index, 0), chartData.count - 1)

        if clampedIndex < chartData.count {
            let point = chartData[clampedIndex]
            selectedDataPoint = DetailChartDataPoint(
                index: point.index,
                value: point.value,
                date: point.date
            )

            if lastHapticIndex != clampedIndex {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastHapticIndex = clampedIndex
            }
        }
    }

    // MARK: - Display Values

    private var displayedValue: String {
        if let selected = selectedDataPoint {
            return formatStatValue(selected.value)
        }
        return currentValue
    }

    private var displayedTimestamp: String {
        if let selected = selectedDataPoint {
            if let date = selected.date ?? chartData.first(where: { $0.index == selected.index })?.date {
                return formatTimestamp(date)
            }
        }
        return timestamp.map { formatTimestamp($0) } ?? ""
    }

    private var isSelectedPointEstimated: Bool {
        guard let selected = selectedDataPoint,
              let point = chartData.first(where: { $0.index == selected.index }) else {
            return false
        }
        return point.isEstimated
    }
}

// MARK: - Stat Card Component

private struct MetricStatCard: View {
    let label: String
    let value: String
    let unit: String
    var isChange: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(isChange ? changeColor : .white)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private var changeColor: Color {
        if value.hasPrefix("+") {
            return .green
        } else if value.hasPrefix("-") {
            return .red
        } else {
            return .white
        }
    }
}

// MARK: - Supporting Types

struct DetailChartDataPoint: Equatable {
    let index: Int
    let value: Double
    let date: Date?
}

struct MetricEntrySection: Identifiable {
    let month: Date
    let entries: [MetricEntry]

    var id: Date { month }

    var title: String {
        MetricDetailFormatters.month.string(from: month)
    }
}

struct MetricEntry: Identifiable, Equatable {
    let metric: BodyMetrics
    let metricKind: DashboardViewLiquid.DashboardMetricKind
    let weightKg: Double?
    let bodyFatPercentage: Double?
    let ffmi: Double?
    let source: MetricEntrySource
    let supportsWeight: Bool
    let supportsBodyFat: Bool

    var id: String { metric.id }
    var date: Date { metric.date }
}

enum MetricEntrySource {
    case manual
    case integration

    var iconName: String {
        switch self {
        case .manual: return "pencil"
        case .integration: return "arrow.triangle.2.circlepath"
        }
    }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .integration: return "Integration"
        }
    }

    var tint: Color {
        switch self {
        case .manual: return .white
        case .integration: return Color.cyan
        }
    }

    var background: Color {
        switch self {
        case .manual: return Color.white.opacity(0.08)
        case .integration: return Color.cyan.opacity(0.15)
        }
    }
}

private struct MetricEntryEditSheet: View {
    let entry: MetricEntry
    let metricName: String
    @Binding var weightText: String
    @Binding var bodyFatText: String
    let measurementSystem: MeasurementSystem
    let showsWeightField: Bool
    let showsBodyFatField: Bool
    let isSaving: Bool
    let showsIntegrationBanner: Bool
    let errorMessage: String?
    let onSave: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if showsIntegrationBanner {
                    IntegrationOverrideBanner()
                }

                if showsWeightField {
                    inputField(
                        title: "Weight (\(measurementSystem.weightUnit))",
                        text: $weightText,
                        placeholder: "Enter weight"
                    )
                }

                if showsBodyFatField {
                    inputField(
                        title: "Body Fat (%)",
                        text: $bodyFatText,
                        placeholder: "Enter body fat"
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: onSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Changes")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.6 : 1)
            }
            .padding(.vertical, 30)
        }
        .padding(.horizontal, 20)
        .background(Color.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(MetricDetailFormatters.entryDate.string(from: entry.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Text(metricName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 38, height: 38)
                    .background(Color.red.opacity(0.15), in: Circle())
            }
            .disabled(isSaving)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
        }
    }

    private func inputField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundColor(.white)
        }
    }
}

private struct IntegrationOverrideBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.orange)

            Text("Data for this day was populated from your Health integration. Manually entering data here will override the synced data.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum MetricDetailFormatters {
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()

    static let entryDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        formatter.locale = .current
        formatter.timeZone = .current
        return formatter
    }()
}

// MARK: - Preview

#Preview {
    NavigationView {
        MetricDetailView(
            metricType: .weight,
            userId: "preview-user",
            useMetricUnits: false,
            userHeightCm: 180,
            currentValue: "165.2",
            unit: "lbs",
            timestamp: Date(),
            onAdd: {
                print("Add tapped")
            }
        )
    }
}
