//
// CoreMetricsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - CoreMetricsRow Organism

/// Displays the two primary metrics (Body Fat % and Weight) with interactive tap gestures
struct CoreMetricsRow: View {
    let bodyFatPercentage: Double?
    let weight: Double?
    let bodyFatTrend: Double?
    let weightTrend: Double?
    let weightUnit: String
    let isEstimated: Bool

    @Binding var displayMode: DashboardDisplayMode

    var body: some View {
        HStack(spacing: 16) {
            // Body Fat Card - Tappable
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayMode = .bodyFatChart
                }
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } label: {
                if let bf = bodyFatPercentage {
                    DSMetricCard(
                        value: String(format: "%.1f", bf),
                        unit: "%",
                        label: isEstimated ? "Est. Body Fat" : "Body Fat",
                        trend: bodyFatTrend,
                        trendType: .negative
                    )
                    .scaleEffect(displayMode == .bodyFatChart ? 1.05 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(displayMode == .bodyFatChart ? Color.liquidAccent : Color.clear, lineWidth: 2)
                    )
                } else {
                    DSEmptyMetricCard(
                        label: "Body Fat",
                        unit: "%"
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Weight Card - Tappable
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayMode = .weightChart
                }
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } label: {
                if let w = weight {
                    DSMetricCard(
                        value: formatWeight(w),
                        unit: weightUnit,
                        label: "Weight",
                        trend: weightTrend,
                        trendType: .neutral
                    )
                    .scaleEffect(displayMode == .weightChart ? 1.05 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(displayMode == .weightChart ? Color.liquidAccent : Color.clear, lineWidth: 2)
                    )
                } else {
                    DSEmptyMetricCard(
                        label: "Weight",
                        unit: weightUnit
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
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
            isEstimated: false,
            displayMode: .constant(.photo)
        )

        // With estimated body fat - Chart mode active
        CoreMetricsRow(
            bodyFatPercentage: 24.2,
            weight: 75.2,
            bodyFatTrend: nil,
            weightTrend: 0.5,
            weightUnit: "kg",
            isEstimated: true,
            displayMode: .constant(.bodyFatChart)
        )

        // Empty state
        CoreMetricsRow(
            bodyFatPercentage: nil,
            weight: nil,
            bodyFatTrend: nil,
            weightTrend: nil,
            weightUnit: "lbs",
            isEstimated: false,
            displayMode: .constant(.photo)
        )
    }
    .background(Color.appBackground)
}
