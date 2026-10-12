import SwiftUI

struct DashboardPrimaryMetricCard<BodyFatProgress: View>: View {
    @Environment(\.theme) private var theme

    let animatedBodyFat: Double
    let bodyFatResult: InterpolatedMetric?
    let bodyFatProgress: BodyFatProgress

    var body: some View {
        VStack(spacing: 12) {
            DSMetricLabel(
                text: "Body Fat %",
                size: .system(size: 15),
                weight: .semibold,
                color: theme.colors.text.opacity(0.85)
            )

            if let bodyFatResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        DSMetricValue(
                            value: String(format: "%.1f", animatedBodyFat),
                            unit: nil,
                            size: Font.jovieDisplay,
                            color: theme.colors.text
                        )
                        .tracking(-0.3)
                        .monospacedDigit()

                        if bodyFatResult.isInterpolated || bodyFatResult.isLastKnown {
                            DSInterpolationIcon(
                                confidenceLevel: bodyFatResult.confidenceLevel,
                                isLastKnown: bodyFatResult.isLastKnown
                            )
                        }
                    }

                    DSMetricLabel(
                        text: "%",
                        size: .system(size: 13),
                        weight: .medium,
                        color: theme.colors.text.opacity(0.70)
                    )

                    bodyFatProgress
                }
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
        .padding(20)
        .dashboardContentSurface(cornerRadius: 24, border: theme.colors.border)
    }
}
