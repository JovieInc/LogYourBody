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
        let range = maxFFMI - minFFMI

        // Calculate positions (0.0 to 1.0)
        let currentPosition = max(0, min(1, (current - minFFMI) / range))
        let goalPosition = max(0, min(1, (goal - minFFMI) / range))

        return VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                // Progress fill (from min to current value)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#6EE7F0"))
                    .frame(width: max(0, currentPosition * 60), height: 4)  // 60pt total width

                // Goal indicator tick
                Rectangle()
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 2, height: 8)
                    .offset(x: goalPosition * 60 - 1)  // Center the tick on goal position
            }
            .frame(width: 60, height: 8)  // Container for the bar
        }
    }
}
