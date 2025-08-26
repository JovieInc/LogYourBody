//
// CoreMetricsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - CoreMetricsRow Organism

/// Displays the two primary metrics (Body Fat % and Weight)
struct CoreMetricsRow: View {
    let bodyFatPercentage: Double?
    let weight: Double?
    let bodyFatTrend: Double?
    let weightTrend: Double?
    let weightUnit: String
    let isEstimated: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Body Fat Card
            if let bf = bodyFatPercentage {
                DSMetricCard(
                    value: String(format: "%.1f", bf),
                    unit: "%",
                    label: isEstimated ? "Est. Body Fat" : "Body Fat",
                    trend: bodyFatTrend,
                    trendType: .negative
                )
            } else {
                DSEmptyMetricCard(
                    label: "Body Fat",
                    unit: "%"
                )
            }
            
            // Weight Card
            if let w = weight {
                DSMetricCard(
                    value: formatWeight(w),
                    unit: weightUnit,
                    label: "Weight",
                    trend: weightTrend,
                    trendType: .neutral
                )
            } else {
                DSEmptyMetricCard(
                    label: "Weight",
                    unit: weightUnit
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weightUnit == "lbs" {
            return String(format: "%.1f", weight)
        } else {
            return String(format: "%.2f", weight)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // With all data
        CoreMetricsRow(
            bodyFatPercentage: 22.5,
            weight: 165.5,
            bodyFatTrend: -0.8,
            weightTrend: -2.3,
            weightUnit: "lbs",
            isEstimated: false
        )
        
        // With estimated body fat
        CoreMetricsRow(
            bodyFatPercentage: 24.2,
            weight: 75.2,
            bodyFatTrend: nil,
            weightTrend: 0.5,
            weightUnit: "kg",
            isEstimated: true
        )
        
        // Empty state
        CoreMetricsRow(
            bodyFatPercentage: nil,
            weight: nil,
            bodyFatTrend: nil,
            weightTrend: nil,
            weightUnit: "lbs",
            isEstimated: false
        )
    }
    .background(Color.appBackground)
}
