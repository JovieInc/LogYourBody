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
                    MetricSummaryCard(
                        icon: "percent",
                        accentColor: Color.metricAccentBodyFat,
                        state: .data(MetricSummaryCard.Content(
                            title: isEstimated ? "Est. Body Fat" : "Body Fat",
                            value: String(format: "%.1f", bf),
                            unit: "%",
                            timestamp: nil,
                            dataPoints: [],
                            chartAccessibilityLabel: nil,
                            chartAccessibilityValue: nil,
                            trend: bodyFatTrend.map { trend in
                                MetricSummaryCard.Trend(
                                    direction: trend < 0 ? .down : (trend > 0 ? .up : .flat),
                                    valueText: String(format: "%.1f", abs(trend))
                                )
                            },
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                    .scaleEffect(displayMode == .bodyFatChart ? 1.05 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(displayMode == .bodyFatChart ? Color.liquidAccent : Color.clear, lineWidth: 2)
                    )
                } else {
                    MetricSummaryCard(
                        icon: "percent",
                        accentColor: Color.metricAccentBodyFat,
                        state: .empty(message: "No body fat data", action: nil)
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
                    MetricSummaryCard(
                        icon: "figure.stand",
                        accentColor: Color.metricAccentWeight,
                        state: .data(MetricSummaryCard.Content(
                            title: "Weight",
                            value: formatWeight(w),
                            unit: weightUnit,
                            timestamp: nil,
                            dataPoints: [],
                            chartAccessibilityLabel: nil,
                            chartAccessibilityValue: nil,
                            trend: weightTrend.map { trend in
                                MetricSummaryCard.Trend(
                                    direction: trend < 0 ? .down : (trend > 0 ? .up : .flat),
                                    valueText: String(format: "%.1f", abs(trend))
                                )
                            },
                            footnote: nil
                        )),
                        isButtonContext: true
                    )
                    .scaleEffect(displayMode == .weightChart ? 1.05 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(displayMode == .weightChart ? Color.liquidAccent : Color.clear, lineWidth: 2)
                    )
                } else {
                    MetricSummaryCard(
                        icon: "figure.stand",
                        accentColor: Color.metricAccentWeight,
                        state: .empty(message: "No weight data", action: nil)
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
