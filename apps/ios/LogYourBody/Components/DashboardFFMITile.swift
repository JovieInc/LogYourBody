import SwiftUI

struct DashboardFFMITile: View {
    let currentMetric: BodyMetrics?
    let bodyMetrics: [BodyMetrics]
    let heightInches: Double?
    let ffmiGoal: Double
    let animatedFFMI: Double

    var body: some View {
        CompactGlassCard {
            HStack(spacing: 12) {
                // Left: Value and goal
                VStack(alignment: .leading, spacing: 4) {
                    Text("FFMI")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.85))

                    if let metric = currentMetric,
                       let ffmiData = ffmiData(for: metric) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", animatedFFMI))
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.3)
                                .foregroundColor(Color.liquidTextPrimary)
                                .monospacedDigit()

                            if ffmiData.isInterpolated || ffmiData.isLastKnown {
                                DSInterpolationIcon(
                                    confidenceLevel: ffmiData.confidenceLevel,
                                    isLastKnown: ffmiData.isLastKnown
                                )
                            }
                        }
                        Text("of \(String(format: "%.0f", ffmiGoal))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.70))
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.3)
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                    }
                }

                Spacer()

                // Right: Progress bar
                if let metric = currentMetric,
                   let ffmiData = ffmiData(for: metric) {
                    ffmiProgressBar(current: ffmiData.value, goal: ffmiGoal)
                }
            }
        }
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
