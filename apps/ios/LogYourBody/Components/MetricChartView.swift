//
// MetricChartView.swift
// LogYourBody
//
// A reusable chart component for displaying metric trends (BF%, Weight, FFMI)
// with timeline scrubbing support. Styled to match shadcn/ui aesthetic.
//

import SwiftUI
import Charts

struct MetricChartView: View {
    let bodyMetrics: [BodyMetrics]
    let displayMode: DashboardDisplayMode
    @Binding var selectedDate: Date?

    @State private var chartData: [DashboardChartDataPoint] = []
    @State private var trendPercentage: Double = 0.0
    @State private var trendDirection: TrendDirection = .neutral
    @State private var isLoadingData: Bool = false

    private let interpolationService = MetricsInterpolationService.shared

    var body: some View {
        VStack(spacing: 16) {
            // Current Value Header
            currentValueHeader

            // Chart
            chartView
                .frame(height: 280)
                .padding(.horizontal, 16)

            // Trend Indicator
            trendIndicator
                .padding(.horizontal, 16)
        }
        .onAppear {
            loadChartData()
            calculateTrend()
        }
        .onChange(of: bodyMetrics) { _, _ in
            loadChartData()
            calculateTrend()
        }
        .onChange(of: displayMode) { _, _ in
            loadChartData()
            calculateTrend()
        }
    }

    // MARK: - Header

    private var currentValueHeader: some View {
        VStack(spacing: 4) {
            if let currentValue = getCurrentValue() {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatValue(currentValue))
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.appText)

                    Text(getUnit())
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            } else {
                Text("No data")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }

            Text(displayMode.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.appTextSecondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartView: some View {
        if isLoadingData {
            // Loading state
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.liquidAccent)

                Text("Loading chart data...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.appTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if chartData.isEmpty {
            emptyStateView
        } else {
            Chart {
                    ForEach(chartData) { point in
                        // Area fill gradient (render first, below the line)
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.liquidAccent.opacity(0.3), Color.liquidAccent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        // Line
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(Color.liquidAccent.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3))

                        // Points (hidden by default to reduce clutter)
                        if selectedDate != nil {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(Color.liquidAccent)
                            .symbolSize(point.isEstimated ? 30 : 60)
                            .opacity(point.isEstimated ? 0.6 : 0.8)
                        }
                    }

                    // Vertical scrubber line
                    if let selectedDate = selectedDate,
                       let selectedPoint = findNearestPoint(to: selectedDate) {
                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                        // Highlight selected point
                        PointMark(
                            x: .value("Date", selectedPoint.date),
                            y: .value("Value", selectedPoint.value)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(120)
                        .symbol {
                            Circle()
                                .fill(Color.liquidAccent)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 3)
                                )
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { _ in
                        // Hide grid lines by default (only show during interaction)
                        AxisValueLabel()
                            .foregroundStyle(Color.appTextSecondary)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .trailing, values: .automatic(desiredCount: 6)) { value in
                        // Hide grid lines by default (only show during interaction)
                        AxisValueLabel()
                            .foregroundStyle(Color.appTextSecondary)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.clear)
                }
                .animation(.easeInOut(duration: 0.8), value: chartData.count)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.appTextSecondary.opacity(0.5))

            Text("No data yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.appText)

            Text("Start tracking your \(displayMode.title.lowercased()) to see trends")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trend Indicator

    private var trendIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: trendDirection.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(trendDirection.color)

            Text(trendDirection.description(percentage: trendPercentage))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.appTextSecondary)

            Text("this month")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Data Loading

    private func loadChartData() {
        isLoadingData = true
        defer { isLoadingData = false }

        var points: [DashboardChartDataPoint] = []

        switch displayMode {
        case .photo:
            // No chart for photo mode
            break

        case .bodyFatChart:
            for metric in bodyMetrics {
                if let bf = metric.bodyFatPercentage {
                    points.append(DashboardChartDataPoint(
                        date: metric.date,
                        value: bf,
                        isEstimated: false
                    ))
                }
            }

        case .weightChart:
            for metric in bodyMetrics {
                if let weight = metric.weight {
                    points.append(DashboardChartDataPoint(
                        date: metric.date,
                        value: weight,
                        isEstimated: false
                    ))
                }
            }

        case .ffmiChart:
            // Get height from user profile
            guard let heightInches = AuthManager.shared.currentUser?.profile?.height else {
                chartData = []
                return
            }

            for metric in bodyMetrics {
                if let ffmiResult = interpolationService.estimateFFMI(
                    for: metric.date,
                    metrics: bodyMetrics,
                    heightInches: heightInches
                ) {
                    points.append(DashboardChartDataPoint(
                        date: metric.date,
                        value: ffmiResult.value,
                        isEstimated: ffmiResult.isInterpolated
                    ))
                }
            }
        }

        // Sort by date
        chartData = points.sorted { $0.date < $1.date }
    }

    // MARK: - Helper Methods

    private func getCurrentValue() -> Double? {
        guard let selectedDate = selectedDate else {
            return chartData.last?.value
        }

        return findNearestPoint(to: selectedDate)?.value ?? chartData.last?.value
    }

    private func findNearestPoint(to date: Date) -> DashboardChartDataPoint? {
        guard !chartData.isEmpty else { return nil }

        return chartData.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func formatValue(_ value: Double) -> String {
        switch displayMode {
        case .photo:
            return ""
        case .bodyFatChart:
            return String(format: "%.1f", value)
        case .weightChart:
            return String(format: "%.1f", value)
        case .ffmiChart:
            return String(format: "%.1f", value)
        }
    }

    private func getUnit() -> String {
        switch displayMode {
        case .photo:
            return ""
        case .bodyFatChart:
            return "%"
        case .weightChart:
            // TODO: Get from user preference
            return "lbs"
        case .ffmiChart:
            return ""
        }
    }

    private func calculateTrend() {
        guard chartData.count >= 2 else {
            trendPercentage = 0.0
            trendDirection = .neutral
            return
        }

        // Get last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentData = chartData.filter { $0.date >= thirtyDaysAgo }

        guard recentData.count >= 2,
              let firstValue = recentData.first?.value,
              let lastValue = recentData.last?.value else {
            trendPercentage = 0.0
            trendDirection = .neutral
            return
        }

        let change = lastValue - firstValue
        let percentChange = (change / firstValue) * 100

        trendPercentage = abs(percentChange)

        if abs(percentChange) < 0.5 {
            trendDirection = .neutral
        } else if percentChange > 0 {
            trendDirection = .up
        } else {
            trendDirection = .down
        }
    }
}

// MARK: - Supporting Types

struct DashboardChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let isEstimated: Bool
}

enum TrendDirection {
    case up, down, neutral

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .gray
        }
    }

    func description(percentage: Double) -> String {
        switch self {
        case .up:
            return "Trending up by \(String(format: "%.1f", percentage))%"
        case .down:
            return "Trending down by \(String(format: "%.1f", percentage))%"
        case .neutral:
            return "Stable"
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleMetrics = [
        BodyMetrics(
            id: "1",
            userId: "user1",
            date: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
            weight: 180.0,
            weightUnit: "lbs",
            bodyFatPercentage: 20.0,
            bodyFatMethod: "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: Date(),
            updatedAt: Date()
        ),
        BodyMetrics(
            id: "2",
            userId: "user1",
            date: Calendar.current.date(byAdding: .day, value: -15, to: Date())!,
            weight: 178.0,
            weightUnit: "lbs",
            bodyFatPercentage: 19.5,
            bodyFatMethod: "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: Date(),
            updatedAt: Date()
        ),
        BodyMetrics(
            id: "3",
            userId: "user1",
            date: Date(),
            weight: 175.0,
            weightUnit: "lbs",
            bodyFatPercentage: 18.5,
            bodyFatMethod: "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: Date(),
            updatedAt: Date()
        )
    ]

    return MetricChartView(
        bodyMetrics: sampleMetrics,
        displayMode: .bodyFatChart,
        selectedDate: .constant(nil)
    )
    .background(Color.appBackground)
}
