//
// Glp1DoseCardData.swift
// LogYourBody
//
import Foundation

/// Pure data preparation for the dashboard GLP-1 dose card.
///
/// Extracted from `DashboardViewLiquid.glp1MetricCard` so the sort / last-7 /
/// mapping logic can be unit tested without rendering a SwiftUI view.
struct Glp1DoseCardData {
    let latestDose: Double
    let unit: String
    let latestTakenAt: Date
    let dataPoints: [MetricSummaryCard.DataPoint]

    /// Builds card data from raw dose logs, or `nil` when there is no logged dose
    /// to headline. Mirrors the card's original behaviour exactly: logs are sorted
    /// ascending by `takenAt`; the newest log must itself carry a dose or the card
    /// is hidden; the last 7 logs form the sparkline, where rest-day entries (no
    /// dose) are dropped but still consume their enumeration index.
    static func make(from logs: [Glp1DoseLog]) -> Glp1DoseCardData? {
        let sortedLogs = logs.sorted { $0.takenAt < $1.takenAt }

        guard let latestLog = sortedLogs.last,
              let latestDose = latestLog.doseAmount else {
            return nil
        }

        let dataPoints: [MetricSummaryCard.DataPoint] = Array(sortedLogs.suffix(7))
            .enumerated()
            .compactMap { index, log in
                guard let value = log.doseAmount else { return nil }
                return MetricSummaryCard.DataPoint(index: index, value: value)
            }

        return Glp1DoseCardData(
            latestDose: latestDose,
            unit: latestLog.doseUnit ?? "mg",
            latestTakenAt: latestLog.takenAt,
            dataPoints: dataPoints
        )
    }
}
