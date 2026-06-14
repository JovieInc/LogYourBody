import SwiftUI

// MARK: - GLP-1 Metric Card

extension DashboardViewLiquid {
    @ViewBuilder
    var glp1MetricCard: some View {
        let sortedLogs = glp1DoseLogs.sorted { $0.takenAt < $1.takenAt }

        if let latestLog = sortedLogs.last,
           let latestDose = latestLog.doseAmount {
            let unit = latestLog.doseUnit ?? "mg"
            let dataPoints: [MetricSummaryCard.DataPoint] = Array(sortedLogs.suffix(7))
                .enumerated()
                .compactMap { index, log in
                    guard let value = log.doseAmount else { return nil }
                    return MetricSummaryCard.DataPoint(index: index, value: value)
                }

            Button {
                selectedMetricType = .glp1
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "syringe",
                    accentColor: Color.metricAccent,
                    state: .data(
                        MetricSummaryCard.Content(
                            title: "GLP-1 Dose",
                            value: String(format: "%.1f", latestDose),
                            unit: unit,
                            timestamp: formatCardDateOnly(latestLog.takenAt),
                            dataPoints: dataPoints,
                            chartAccessibilityLabel: "GLP-1 dose history",
                            chartAccessibilityValue: "Latest dose \(String(format: "%.1f", latestDose)) \(unit)",
                            trend: nil,
                            footnote: nil
                        )
                    ),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        } else {
            EmptyView()
        }
    }
}
