//
// MetricDetailView.swift
// LogYourBody
//
// Full-screen metric detail view with period selector and enhanced chart
// Matches Apple Health's metric detail screen design
//

import SwiftUI
import Charts
import Foundation

// MARK: - Metric Detail View

struct MetricDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // Metric information
    let metricType: DashboardViewLiquid.DashboardMetricKind
    let userId: String
    let useMetricUnits: Bool

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
    @State private var entrySections: [EntrySection] = []
    @State private var isLoadingEntries: Bool = false
    @State private var editingEntry: MetricEntry?
    @State private var entryPendingDeletion: MetricEntry?
    @State private var showingDeleteConfirmation: Bool = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            List {
                Section {
                    navigationBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    PeriodSelector(selectedPeriod: $selectedPeriod)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .onChange(of: selectedPeriod) { _ in
                            Task {
                                await loadChartData()
                            }
                        }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    currentValueDisplay
                        .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    chartView
                        .frame(height: 360)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if hasStatistics {
                    Section {
                        statisticsView
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if supportsEntryManagement {
                    entriesSectionContent
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await refreshData()
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(
                entry: entry,
                metricType: metricType,
                useMetricUnits: useMetricUnits,
                onComplete: {
                    await refreshAfterEntryMutation()
                }
            )
        }
        .alert("Delete Entry?", isPresented: $showingDeleteConfirmation, presenting: entryPendingDeletion) { entry in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteEntry(entry)
                }
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { _ in
            Text("This will remove the entry and update your charts.")
        }
        .onAppear {
            Task {
                await loadChartData()
                if supportsEntryManagement {
                    await loadEntries()
                } else {
                    entrySections = []
                }
            }
        }
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
            } else if !chartData.isEmpty {
                Text("Chart placeholder - tap Add to record more data")
                    .foregroundColor(.white.opacity(0.6))
            } else {
                // Empty state
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
            }
        }
    }

    // MARK: - Entry Management Views

    @ViewBuilder
    private var entriesSectionContent: some View {
        if isLoadingEntries {
            Section {
                entryLoadingView
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else if entrySections.isEmpty {
            Section {
                entriesEmptyState
                    .padding(.vertical, 32)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } else {
            ForEach(entrySections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        MetricEntryRow(
                            entry: entry,
                            metricType: metricType,
                            measurementSystem: measurementSystem
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard entry.isEditable else { return }
                            editingEntry = entry
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.isEditable {
                                Button(role: .destructive) {
                                    entryPendingDeletion = entry
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack {
                        Text(section.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Text(section.entries.count == 1 ? "1 entry" : "\(section.entries.count) entries")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
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

    private var entryLoadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading entries…")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var entriesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))

            Text("No entries yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Add your first entry to start building a history.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
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

    private var supportsEntryManagement: Bool {
        switch metricType {
        case .weight, .bodyFat:
            return true
        default:
            return false
        }
    }

    private var hasStatistics: Bool {
        !chartData.isEmpty && !isLoadingData
    }

    // MARK: - Data Loading

    @MainActor
    private func loadChartData() async {
        isLoadingData = true

        chartData = MetricChartDataHelper.generateChartData(
            for: userId,
            days: selectedPeriod.days,
            metricType: metricType,
            useMetric: useMetricUnits
        )
        isLoadingData = false
    }

    @MainActor
    private func refreshData() async {
        MetricChartDataHelper.clearCache(for: userId)
        await loadChartData()
        if supportsEntryManagement {
            await loadEntries()
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
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
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

    private func handleChartDrag(at location: CGPoint) {
        guard !chartData.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            isScrubbing = true
        }

        // Calculate which data point is nearest to the drag location
        // Assuming chart width of screen width - 40px padding
        let chartWidth = UIScreen.main.bounds.width - 40
        let pointSpacing = chartWidth / CGFloat(max(chartData.count - 1, 1))
        let index = Int(round(location.x / pointSpacing))
        let clampedIndex = min(max(index, 0), chartData.count - 1)

        // Update selected data point
        if clampedIndex < chartData.count {
            let point = chartData[clampedIndex]
            selectedDataPoint = DetailChartDataPoint(
                index: point.index,
                value: point.value
            )

            // Haptic feedback on snap to new point
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
        if let selected = selectedDataPoint,
           let point = chartData.first(where: { $0.index == selected.index }) {
            // Calculate the date for this point
            let daysAgo = chartData.count - 1 - chartData.firstIndex(where: { $0.index == point.index })!
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            return formatTimestamp(date)
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

    // MARK: - Entry Helpers

    @MainActor
    private func loadEntries() async {
        guard supportsEntryManagement else {
            entrySections = []
            return
        }

        isLoadingEntries = true
        defer { isLoadingEntries = false }

        let cachedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let bodyMetrics = cachedMetrics
            .compactMap { $0.toBodyMetrics() }
            .filter { metric in
                switch metricType {
                case .weight:
                    return metric.weight != nil
                case .bodyFat:
                    return metric.bodyFatPercentage != nil
                default:
                    return false
                }
            }
            .sorted { $0.date > $1.date }

        let entries = bodyMetrics.compactMap(makeEntry(from:))
        entrySections = buildSections(from: entries)
    }

    @MainActor
    private func refreshAfterEntryMutation() async {
        await loadEntries()
        await loadChartData()
    }

    @MainActor
    private func deleteEntry(_ entry: MetricEntry) async {
        defer {
            entryPendingDeletion = nil
            showingDeleteConfirmation = false
        }

        let success = await CoreDataManager.shared.markBodyMetricDeleted(id: entry.id)
        if success {
            await refreshAfterEntryMutation()
        }
    }

    private func makeEntry(from metric: BodyMetrics) -> MetricEntry? {
        let primaryValue: Double?
        let unit: String
        var secondaryValue: Double?
        var secondaryUnit: String?

        switch metricType {
        case .weight:
            guard let weightKg = metric.weight else { return nil }
            primaryValue = convertWeightForDisplay(weightKg)
            unit = measurementSystem.weightUnit
            if let bodyFat = metric.bodyFatPercentage {
                secondaryValue = bodyFat
                secondaryUnit = "%"
            }
        case .bodyFat:
            guard let bodyFat = metric.bodyFatPercentage else { return nil }
            primaryValue = bodyFat
            unit = "%"
            if let weightKg = metric.weight {
                secondaryValue = convertWeightForDisplay(weightKg)
                secondaryUnit = measurementSystem.weightUnit
            }
        default:
            return nil
        }

        guard let value = primaryValue else { return nil }

        return MetricEntry(
            id: metric.id,
            date: metric.date,
            primaryValue: value,
            primaryUnit: unit,
            secondaryValue: secondaryValue,
            secondaryUnit: secondaryUnit,
            notes: metric.notes,
            source: sourceType(for: metric.dataSource),
            isEditable: isEditableSource(metric.dataSource)
        )
    }

    private func buildSections(from entries: [MetricEntry]) -> [EntrySection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: entries) { entry -> DateComponents in
            Calendar.current.dateComponents([.year, .month], from: entry.date)
        }

        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            let lhsDate = Calendar.current.date(from: lhs) ?? Date.distantPast
            let rhsDate = Calendar.current.date(from: rhs) ?? Date.distantPast
            return lhsDate > rhsDate
        }

        return sortedKeys.compactMap { components in
            guard let date = Calendar.current.date(from: components),
                  let entries = grouped[components] else { return nil }

            let title = formatter.string(from: date)
            let sortedEntries = entries.sorted { $0.date > $1.date }
            return EntrySection(id: UUID().uuidString, title: title, entries: sortedEntries)
        }
    }

    private func convertWeightForDisplay(_ weightKg: Double) -> Double {
        switch measurementSystem {
        case .metric:
            return weightKg
        case .imperial:
            return weightKg * 2.20462
        }
    }

    private func sourceType(for dataSource: String?) -> EntrySource {
        let normalized = dataSource?.lowercased() ?? ""
        if normalized.contains("health") {
            return .healthKit
        } else if normalized.isEmpty || normalized == "manual" {
            return .manual
        } else {
            return .integration(name: dataSource)
        }
    }

    private func isEditableSource(_ dataSource: String?) -> Bool {
        guard let source = dataSource else { return true }
        return source.lowercased().contains("manual") || source.lowercased().isEmpty
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
}

// MARK: - Entry Row & Models

private struct MetricEntryRow: View {
    let entry: MetricEntry
    let metricType: DashboardViewLiquid.DashboardMetricKind
    let measurementSystem: MeasurementSystem

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    var body: some View {
        HStack(spacing: 16) {
            sourceBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(primaryValueText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    if let secondary = secondaryValueText {
                        Text(secondary)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                HStack(spacing: 6) {
                    Text(dateFormatter.string(from: entry.date))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    if let notes = entry.notes, !notes.isEmpty {
                        Circle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 3, height: 3)

                        Text(notes)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Spacer()

            if entry.isEditable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 8)
    }

    private var primaryValueText: String {
        switch metricType {
        case .weight:
            return String(format: "%.1f %@", entry.primaryValue, entry.primaryUnit)
        case .bodyFat:
            return String(format: "%.1f%@", entry.primaryValue, entry.primaryUnit)
        default:
            return "--"
        }
    }

    private var secondaryValueText: String? {
        guard let value = entry.secondaryValue,
              let unit = entry.secondaryUnit else { return nil }

        if unit == "%" {
            return String(format: "%.1f%@", value, unit)
        }

        return String(format: "%.1f %@", value, unit)
    }

    private var sourceBadge: some View {
        let configuration = entry.source.configuration

        return ZStack {
            Circle()
                .fill(configuration.background)
                .frame(width: 36, height: 36)
            Image(systemName: configuration.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(configuration.iconColor)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct EntrySection: Identifiable {
    let id: String
    let title: String
    let entries: [MetricEntry]
}

struct MetricEntry: Identifiable, Equatable {
    let id: String
    let date: Date
    let primaryValue: Double
    let primaryUnit: String
    let secondaryValue: Double?
    let secondaryUnit: String?
    let notes: String?
    let source: EntrySource
    let isEditable: Bool
}

enum EntrySource: Equatable {
    case manual
    case healthKit
    case integration(name: String?)

    struct Configuration {
        let icon: String
        let iconColor: Color
        let background: Color
    }

    var configuration: Configuration {
        switch self {
        case .manual:
            return Configuration(icon: "pencil", iconColor: .white, background: Color.white.opacity(0.15))
        case .healthKit:
            return Configuration(icon: "heart.fill", iconColor: .red, background: Color.red.opacity(0.2))
        case .integration:
            return Configuration(icon: "bolt.horizontal", iconColor: .blue, background: Color.blue.opacity(0.2))
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        MetricDetailView(
            metricType: .weight,
            userId: "preview-user",
            useMetricUnits: false,
            currentValue: "165.2",
            unit: "lbs",
            timestamp: Date(),
            onAdd: {
        // print("Add tapped")
            }
        )
    }
}
