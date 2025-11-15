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
                Button {
                    selectedMetric = .steps
                } label: {
                    MetricSummaryCard(
                        icon: "figure.walk",
                        accentColor: .orange,
                        state: .data(MetricSummaryCard.Content(
                            title: "Steps",
                            value: formatSteps(steps),
                            unit: "steps",
                            timestamp: formatTimestamp(),
                            dataPoints: MetricChartDataHelper.generateStepsChartData(for: userId).map {
                                MetricSummaryCard.DataPoint(index: $0.index, value: $0.value)
                            },
                            chartAccessibilityLabel: "Steps trend for the past week",
                            chartAccessibilityValue: "Latest value \(formatSteps(steps)) steps",
                            trend: nil,
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                MetricSummaryCard(
                    icon: "figure.walk",
                    accentColor: .orange,
                    state: .empty(message: "No steps data", action: nil)
                )
            }
        }
    }

    private var weightCard: some View {
        Group {
            if let weight = weight {
                let displayWeight = useMetricUnits ? weight : weight * 2.20462
                let unit = useMetricUnits ? "kg" : "lbs"

                Button {
                    selectedMetric = .weight
                } label: {
                    MetricSummaryCard(
                        icon: "figure.stand",
                        accentColor: .purple,
                        state: .data(MetricSummaryCard.Content(
                            title: "Weight",
                            value: formatWeight(displayWeight, useMetric: useMetricUnits),
                            unit: unit,
                            timestamp: formatTimestamp(),
                            dataPoints: MetricChartDataHelper.generateWeightChartData(for: userId, useMetric: useMetricUnits).map {
                                MetricSummaryCard.DataPoint(index: $0.index, value: $0.value)
                            },
                            chartAccessibilityLabel: "Weight trend for the past week",
                            chartAccessibilityValue: "Latest value \(formatWeight(displayWeight, useMetric: useMetricUnits)) \(unit)",
                            trend: nil,
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                MetricSummaryCard(
                    icon: "figure.stand",
                    accentColor: .purple,
                    state: .empty(message: "No weight data", action: nil)
                )
            }
        }
    }

    private var bodyFatCard: some View {
        Group {
            if let bodyFat = bodyFat {
                Button {
                    selectedMetric = .bodyFat
                } label: {
                    MetricSummaryCard(
                        icon: "percent",
                        accentColor: .purple,
                        state: .data(MetricSummaryCard.Content(
                            title: "Body Fat Percentage",
                            value: String(format: "%.1f", bodyFat),
                            unit: "%",
                            timestamp: formatTimestamp(),
                            dataPoints: MetricChartDataHelper.generateBodyFatChartData(for: userId).map {
                                MetricSummaryCard.DataPoint(index: $0.index, value: $0.value)
                            },
                            chartAccessibilityLabel: "Body fat percentage trend for the past week",
                            chartAccessibilityValue: "Latest value \(String(format: "%.1f", bodyFat))%",
                            trend: nil,
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                MetricSummaryCard(
                    icon: "percent",
                    accentColor: .purple,
                    state: .empty(message: "No body fat data", action: nil)
                )
            }
        }
    }

    private var ffmiCard: some View {
        Group {
            if let ffmi = ffmi {
                Button {
                    selectedMetric = .ffmi
                } label: {
                    MetricSummaryCard(
                        icon: "figure.arms.open",
                        accentColor: .purple,
                        state: .data(MetricSummaryCard.Content(
                            title: "Fat Free Mass Index",
                            value: String(format: "%.1f", ffmi),
                            unit: "",
                            timestamp: formatTimestamp(),
                            dataPoints: MetricChartDataHelper.generateFFMIChartData(for: userId).map {
                                MetricSummaryCard.DataPoint(index: $0.index, value: $0.value)
                            },
                            chartAccessibilityLabel: "FFMI trend for the past week",
                            chartAccessibilityValue: "Latest value \(String(format: "%.1f", ffmi))",
                            trend: nil,
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                MetricSummaryCard(
                    icon: "figure.arms.open",
                    accentColor: .purple,
                    state: .empty(message: "No FFMI data", action: nil)
                )
            }
        }
    }

    private var waistCard: some View {
        Group {
            if let waist = waist {
                let displayWaist = useMetricUnits ? waist : waist / 2.54
                let unit = useMetricUnits ? "cm" : "in"

                Button {
                    selectedMetric = .waist
                } label: {
                    MetricSummaryCard(
                        icon: "ruler",
                        accentColor: .blue,
                        state: .data(MetricSummaryCard.Content(
                            title: "Waist",
                            value: formatWaist(displayWaist, useMetric: useMetricUnits),
                            unit: unit,
                            timestamp: formatTimestamp(),
                            dataPoints: MetricChartDataHelper.generateWaistChartData(for: userId, useMetric: useMetricUnits).map {
                                MetricSummaryCard.DataPoint(index: $0.index, value: $0.value)
                            },
                            chartAccessibilityLabel: "Waist measurement trend for the past week",
                            chartAccessibilityValue: "Latest value \(formatWaist(displayWaist, useMetric: useMetricUnits)) \(unit)",
                            trend: nil,
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                MetricSummaryCard(
                    icon: "ruler",
                    accentColor: .blue,
                    state: .empty(message: "No waist data", action: nil)
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
