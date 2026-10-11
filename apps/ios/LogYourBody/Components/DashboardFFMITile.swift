import SwiftUI

struct DashboardFFMITile: View {
    @Environment(\.theme) private var theme

    let currentMetric: BodyMetrics?
    let bodyMetrics: [BodyMetrics]
    let heightInches: Double?
    let ffmiGoal: Double
    let animatedFFMI: Double

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DSMetricLabel(
                    text: "FFMI",
                    size: .system(size: 15),
                    weight: .semibold,
                    color: theme.colors.text.opacity(0.85)
                )

                if let metric = currentMetric,
                   let ffmiData = ffmiData(for: metric) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        DSMetricValue(
                            value: String(format: "%.1f", animatedFFMI),
                            unit: nil,
                            size: Font.jovieDisplay,
                            color: theme.colors.text
                        )
                        .tracking(-0.3)
                        .monospacedDigit()

                        if ffmiData.isInterpolated || ffmiData.isLastKnown {
                            DSInterpolationIcon(
                                confidenceLevel: ffmiData.confidenceLevel,
                                isLastKnown: ffmiData.isLastKnown
                            )
                        }
                    }
                    DSMetricLabel(
                        text: "of \(String(format: "%.0f", ffmiGoal))",
                        size: .system(size: 12),
                        weight: .medium,
                        color: theme.colors.text.opacity(0.70)
                    )
                } else {
                    DSMetricValue(
                        value: "—",
                        unit: nil,
                        size: Font.jovieDisplay,
                        color: theme.colors.text.opacity(0.30)
                    )
                    .tracking(-0.3)
                }
            }

            Spacer()

            if let metric = currentMetric,
               let ffmiData = ffmiData(for: metric) {
                ffmiProgressBar(current: ffmiData.value, goal: ffmiGoal)
            }
        }
        .padding(12)
        .dashboardContentSurface(cornerRadius: theme.radius.card, border: theme.colors.border)
    }

    private func ffmiData(for metric: BodyMetrics) -> InterpolatedMetric? {
        guard let heightInches else { return nil }
        return MetricsInterpolationService.shared.estimateFFMI(
            for: metric.date,
            metrics: bodyMetrics,
            heightInches: heightInches
        )
    }

    private func ffmiProgressBar(current: Double, goal: Double) -> some View {
        // Human FFMI range: 10 (very low) to 30 (elite bodybuilder)
        let minFFMI: Double = 10
        let maxFFMI: Double = 30

        return Gauge(value: max(minFFMI, min(current, maxFFMI)), in: minFFMI...maxFFMI) {
            Text("FFMI progress")
        } currentValueLabel: {
            Text(String(format: "%.1f", current))
        } minimumValueLabel: {
            Text("")
        } maximumValueLabel: {
            Text(String(format: "Target %.1f", goal))
        }
        .gaugeStyle(.accessoryLinearCapacity)
        .tint(Color.metricAccentFFMI)
        .labelsHidden()
        .frame(width: 88, height: 8)
        .accessibilityLabel("FFMI \(String(format: "%.1f", current)), target \(String(format: "%.1f", goal))")
    }
}
