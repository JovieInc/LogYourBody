//
// MetricSummaryCard.swift
// LogYourBody
//
// Health-app-style metric summary card with inline chart
// Follows Apple Health design pattern
//

import SwiftUI
import Charts

// MARK: - MetricSummaryCard Organism

/// A card displaying a metric summary with inline trend chart, inspired by Apple Health
struct MetricSummaryCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    let timestamp: String?
    let chartData: [MetricDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon + Label + Time
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.appText)

                Spacer()

                if let time = timestamp {
                    Text(time)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appTextSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Value + Chart Row
            HStack(alignment: .bottom, spacing: 16) {
                // Large Value Display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.appText)

                    Text(unit)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                // Inline Chart
                if !chartData.isEmpty {
                    Chart {
                        ForEach(chartData) { point in
                            LineMark(
                                x: .value("Index", point.index),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(iconColor.gradient)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 120, height: 50)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.appCard)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Supporting Types

struct MetricDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Steps card
        MetricSummaryCard(
            icon: "flame.fill",
            iconColor: .orange,
            label: "Steps",
            value: "3,334",
            unit: "steps",
            timestamp: "6:15 PM",
            chartData: [
                MetricDataPoint(index: 0, value: 2000),
                MetricDataPoint(index: 1, value: 3500),
                MetricDataPoint(index: 2, value: 2800),
                MetricDataPoint(index: 3, value: 4200),
                MetricDataPoint(index: 4, value: 3100),
                MetricDataPoint(index: 5, value: 3900),
                MetricDataPoint(index: 6, value: 3334)
            ]
        )

        // Weight card
        MetricSummaryCard(
            icon: "figure.stand",
            iconColor: .purple,
            label: "Weight",
            value: "160",
            unit: "lbs",
            timestamp: "8:48 AM",
            chartData: [
                MetricDataPoint(index: 0, value: 165),
                MetricDataPoint(index: 1, value: 164),
                MetricDataPoint(index: 2, value: 163),
                MetricDataPoint(index: 3, value: 162),
                MetricDataPoint(index: 4, value: 161),
                MetricDataPoint(index: 5, value: 160)
            ]
        )

        // Body Fat card
        MetricSummaryCard(
            icon: "percent",
            iconColor: .purple,
            label: "Body Fat Percentage",
            value: "10.2",
            unit: "%",
            timestamp: "8:48 AM",
            chartData: [
                MetricDataPoint(index: 0, value: 12.5),
                MetricDataPoint(index: 1, value: 12.0),
                MetricDataPoint(index: 2, value: 11.5),
                MetricDataPoint(index: 3, value: 11.0),
                MetricDataPoint(index: 4, value: 10.5),
                MetricDataPoint(index: 5, value: 10.2)
            ]
        )

        // FFMI card
        MetricSummaryCard(
            icon: "figure.arms.open",
            iconColor: .purple,
            label: "Fat Free Mass Index",
            value: "21.4",
            unit: "",
            timestamp: "8:48 AM",
            chartData: [
                MetricDataPoint(index: 0, value: 20.0),
                MetricDataPoint(index: 1, value: 20.3),
                MetricDataPoint(index: 2, value: 20.7),
                MetricDataPoint(index: 3, value: 21.0),
                MetricDataPoint(index: 4, value: 21.2),
                MetricDataPoint(index: 5, value: 21.4)
            ]
        )
    }
    .padding(20)
    .background(Color.appBackground)
}
