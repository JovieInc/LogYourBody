//
// DashboardView+Views.swift
// LogYourBody
//
import Foundation
import SwiftUI

extension DashboardView {
    @ViewBuilder
    var metricCardSection: some View {
        if let metric = currentMetric {
            VStack(spacing: 12) {
                // Photo mode (avatar mode removed)
                // Display mode toggle removed - using metric cards instead

                // Photo or Avatar
                visualView(for: metric)

                // Timeline navigation - moved directly under photo
                if bodyMetrics.count > 1 {
                    Group {
                        ProgressTimelineView(
                            bodyMetrics: bodyMetrics,
                            selectedIndex: $selectedIndex,
                            mode: $timelineMode
                        )
                        .frame(height: 80)
                        .padding(.top, 8)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Weight")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        if let weight = metric.weight {
                            Text(formatWeight(weight))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    // Weight trend indicator (if you have previous data)
                    if bodyMetrics.count > 1, let prevWeight = bodyMetrics[1].weight, let currWeight = metric.weight {
                        let change = currWeight - prevWeight
                        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                        let convertedChange = convertWeight(abs(change), to: system) ?? abs(change)
                        let unit = system.weightUnit

                        VStack(alignment: .trailing, spacing: 4) {
                            Image(systemName: change < 0 ? "arrow.down.circle.fill" : change > 0 ? "arrow.up.circle.fill" : "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(change < 0 ? .green : change > 0 ? .red : .gray)

                            Text(String(format: "%.1f %@", convertedChange, unit))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                HStack {
                    Text(metric.date ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    if let bodyFat = metric.bodyFatPercentage {
                        Text("\(bodyFat, specifier: "%.1f")% body fat")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )
            .padding(.horizontal)
        }
    }
}
