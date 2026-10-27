import SwiftUI

// MARK: - GLP-1 Metric Card

extension DashboardViewLiquid {
    @ViewBuilder
    var glp1MetricCard: some View {
        if let cardData = Glp1DoseCardData.make(from: glp1DoseLogs) {
            Group {
                let detailAction = MetricSummaryCard.CardAction(title: "Show details") {
                    selectedMetricType = .glp1
                    isMetricDetailActive = true
                }
                MetricSummaryCard(
                    icon: "syringe",
                    accentColor: theme.colors.primary,
                    state: .data(
                        MetricSummaryCard.Content(
                            title: "GLP-1 Dose",
                            value: String(format: "%.1f", cardData.latestDose),
                            unit: cardData.unit,
                            timestamp: formatCardDateOnly(cardData.latestTakenAt),
                            dataPoints: cardData.dataPoints,
                            chartAccessibilityLabel: "GLP-1 dose history",
                            chartAccessibilityValue: "Latest dose \(String(format: "%.1f", cardData.latestDose)) \(cardData.unit)",
                            trend: nil,
                            footnote: nil
                        )
                    ),
                    detailAction: detailAction
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        } else {
            EmptyView()
        }
    }
}
