import SwiftUI

struct DashboardPrimaryMetricCard<BodyFatProgress: View>: View {
    let animatedBodyFat: Double
    let bodyFatResult: InterpolatedMetric?
    let bodyFatProgress: BodyFatProgress

    var body: some View {
        LiquidGlassCard(cornerRadius: 24, padding: 20) {
            VStack(spacing: 12) {
                Text("Body Fat %")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.85))

                if let bodyFatResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", animatedBodyFat))
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.3)
                                .foregroundColor(Color.liquidTextPrimary)
                                .monospacedDigit()

                            if bodyFatResult.isInterpolated || bodyFatResult.isLastKnown {
                                DSInterpolationIcon(
                                    confidenceLevel: bodyFatResult.confidenceLevel,
                                    isLastKnown: bodyFatResult.isLastKnown
                                )
                            }
                        }

                        Text("%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

                        bodyFatProgress
                    }
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.3)
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                }
            }
        }
    }
}
