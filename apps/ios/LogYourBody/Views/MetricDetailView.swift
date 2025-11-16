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
    @AppStorage(Constants.preferredTimeFormatKey) private var timeFormatPreference = TimeFormatPreference.defaultValue

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
                }
            }
            .refreshable {
                await refreshData()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await loadChartData()
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

    // MARK: - Data Loading

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

    private func refreshData() async {
        // Clear cache and reload data
        MetricChartDataHelper.clearCache()
        await loadChartData()

        // Small delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
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
        let preference = TimeFormatPreference(rawValue: timeFormatPreference) ?? .twelveHour
        return preference.formattedString(for: date, includeDate: true)
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
                print("Add tapped")
            }
        )
    }
}
