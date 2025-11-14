//
// AllMetricsRow.swift
// LogYourBody
//
// Unified metrics display using Apple Health-style cards
// Supports all core metrics: Steps, Weight, Body Fat, FFMI, Waist
//

import SwiftUI

// MARK: - AllMetricsRow Organism

/// Displays all metrics in a vertical list with Apple Health-style cards
struct AllMetricsRow: View {
    // User and metrics data
    let userId: String
    let steps: Int?
    let weight: Double?
    let bodyFat: Double?
    let ffmi: Double?
    let waist: Double?

    // User preferences
    let useMetricUnits: Bool
    let lastUpdateTime: Date?

    // Optional: Support for drag-to-reorder
    @Binding var metricsOrder: [String]

    // Placeholder for navigation
    @State private var selectedMetric: DashboardMetric?

    var body: some View {
        VStack(spacing: 16) {
            ForEach(metricsOrder, id: \.self) { metricKey in
                metricCard(for: metricKey)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Metric Card Builder

    @ViewBuilder
    private func metricCard(for metricKey: String) -> some View {
        switch metricKey {
        case "steps":
            stepsCard
        case "weight":
            weightCard
        case "bodyFat":
            bodyFatCard
        case "ffmi":
            ffmiCard
        case "waist":
            waistCard
        default:
            EmptyView()
        }
    }

    // MARK: - Individual Metric Cards

    private var stepsCard: some View {
        Group {
            if let steps = steps {
                DSMetricCard(
                    value: formatSteps(steps),
                    unit: "steps",
                    label: "Steps",
                    icon: "figure.walk",
                    iconColor: .orange,
                    timestamp: formatTimestamp(),
                    chartData: MetricChartDataHelper.generateStepsChartData(for: userId),
                    showChevron: true,
                    isInteractive: true,
                    onTap: {
                        selectedMetric = .steps
                    }
                )
            } else {
                DSEmptyMetricCard(label: "Steps", unit: "steps")
            }
        }
    }

    private var weightCard: some View {
        Group {
            if let weight = weight {
                let displayWeight = useMetricUnits ? weight : weight * 2.20462
                let unit = useMetricUnits ? "kg" : "lbs"

                DSMetricCard(
                    value: formatWeight(displayWeight, useMetric: useMetricUnits),
                    unit: unit,
                    label: "Weight",
                    icon: "figure.stand",
                    iconColor: .purple,
                    timestamp: formatTimestamp(),
                    chartData: MetricChartDataHelper.generateWeightChartData(for: userId, useMetric: useMetricUnits),
                    showChevron: true,
                    isInteractive: true,
                    onTap: {
                        selectedMetric = .weight
                    }
                )
            } else {
                DSEmptyMetricCard(
                    label: "Weight",
                    unit: useMetricUnits ? "kg" : "lbs"
                )
            }
        }
    }

    private var bodyFatCard: some View {
        Group {
            if let bodyFat = bodyFat {
                DSMetricCard(
                    value: String(format: "%.1f", bodyFat),
                    unit: "%",
                    label: "Body Fat Percentage",
                    icon: "percent",
                    iconColor: .purple,
                    timestamp: formatTimestamp(),
                    chartData: MetricChartDataHelper.generateBodyFatChartData(for: userId),
                    showChevron: true,
                    isInteractive: true,
                    onTap: {
                        selectedMetric = .bodyFat
                    }
                )
            } else {
                DSEmptyMetricCard(label: "Body Fat", unit: "%")
            }
        }
    }

    private var ffmiCard: some View {
        Group {
            if let ffmi = ffmi {
                DSMetricCard(
                    value: String(format: "%.1f", ffmi),
                    unit: "",
                    label: "Fat Free Mass Index",
                    icon: "figure.arms.open",
                    iconColor: .purple,
                    timestamp: formatTimestamp(),
                    chartData: MetricChartDataHelper.generateFFMIChartData(for: userId),
                    showChevron: true,
                    isInteractive: true,
                    onTap: {
                        selectedMetric = .ffmi
                    }
                )
            } else {
                DSEmptyMetricCard(label: "FFMI", unit: "")
            }
        }
    }

    private var waistCard: some View {
        Group {
            if let waist = waist {
                let displayWaist = useMetricUnits ? waist : waist / 2.54
                let unit = useMetricUnits ? "cm" : "in"

                DSMetricCard(
                    value: formatWaist(displayWaist, useMetric: useMetricUnits),
                    unit: unit,
                    label: "Waist",
                    icon: "ruler",
                    iconColor: .blue,
                    timestamp: formatTimestamp(),
                    chartData: MetricChartDataHelper.generateWaistChartData(for: userId, useMetric: useMetricUnits),
                    showChevron: true,
                    isInteractive: true,
                    onTap: {
                        selectedMetric = .waist
                    }
                )
            } else {
                DSEmptyMetricCard(
                    label: "Waist",
                    unit: useMetricUnits ? "cm" : "in"
                )
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private func formatWeight(_ weight: Double, useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.1f", weight)
        } else {
            return String(format: "%.1f", weight)
        }
    }

    private func formatWaist(_ waist: Double, useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.1f", waist)
        } else {
            return String(format: "%.1f", waist)
        }
    }

    private func formatTimestamp() -> String? {
        guard let lastUpdate = lastUpdateTime else { return nil }

        let calendar = Calendar.current
        if calendar.isDateInToday(lastUpdate) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: lastUpdate)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: lastUpdate)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AllMetricsRow(
            userId: "preview-user",
            steps: 8432,
            weight: 75.0,  // kg
            bodyFat: 18.2,
            ffmi: 21.4,
            waist: 85.0,  // cm
            useMetricUnits: false,
            lastUpdateTime: Date(),
            metricsOrder: .constant(["steps", "weight", "bodyFat", "ffmi", "waist"])
        )
    }
    .background(Color.appBackground)
}
