//
// ExportCSVBuilder.swift
// LogYourBody
//

import Foundation

/// Pure CSV generation for the data-export flow, extracted from `ExportDataView`
/// with no behavior change. The default date formatter and FFMI resolution match
/// the historical export output exactly.
enum ExportCSVBuilder {
    static let bodyMetricsHeader = "Date,Weight,Weight Unit,Body Fat %,FFMI,Muscle Mass,Bone Mass,Notes,Photo URL"
    static let dailyLogsHeader = "Date,Weight,Weight Unit,Steps,Notes"

    /// Row-date formatter matching the historical export format (locale short date).
    static func makeRowDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }

    /// Builds the body-metrics CSV: header plus one row per metric, oldest first.
    /// - Parameters:
    ///   - metrics: Metrics to export, in any order.
    ///   - heightInches: User height used for FFMI estimation; `nil` yields 0 in the FFMI column.
    ///   - dateFormatter: Row-date formatter (defaults to the historical locale short-date style).
    ///   - ffmiValue: FFMI override for a metric date; defaults to `MetricsInterpolationService`.
    static func makeBodyMetricsCSV(
        metrics: [BodyMetrics],
        heightInches: Double?,
        dateFormatter: DateFormatter = makeRowDateFormatter(),
        ffmiValue: ((Date, [BodyMetrics]) -> Double?)? = nil
    ) -> String {
        var csv = bodyMetricsHeader + "\n"

        let sortedMetrics = metrics.sorted { $0.date < $1.date }

        for metric in sortedMetrics {
            let date = dateFormatter.string(from: metric.date)
            let weight = metric.weight ?? 0
            let weightUnit = metric.weightUnit ?? "lbs"
            let bodyFat = metric.bodyFatPercentage ?? 0
            let ffmi: Double
            if let ffmiValue {
                ffmi = ffmiValue(metric.date, sortedMetrics) ?? 0
            } else if let heightInches,
                      let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                          for: metric.date,
                          metrics: sortedMetrics,
                          heightInches: heightInches
                      ) {
                ffmi = ffmiResult.value
            } else {
                ffmi = 0
            }
            let muscleMass = metric.muscleMass ?? 0
            let boneMass = metric.boneMass ?? 0
            let notes = metric.notes ?? ""
            let photoURL = metric.photoUrl ?? ""

            csv += "\(date),\(weight),\(weightUnit),\(bodyFat),\(ffmi),\(muscleMass),\(boneMass),\"\(notes)\",\(photoURL)\n"
        }

        return csv
    }

    /// Builds the daily-logs CSV: header plus one row per log, oldest first.
    static func makeDailyLogsCSV(
        logs: [DailyLog],
        dateFormatter: DateFormatter = makeRowDateFormatter()
    ) -> String {
        var csv = dailyLogsHeader + "\n"

        for log in logs.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: log.date)
            let weight = log.weight ?? 0
            let weightUnit = log.weightUnit ?? ""
            let steps = log.stepCount ?? 0
            let notes = log.notes ?? ""

            csv += "\(date),\(weight),\(weightUnit),\(steps),\"\(notes)\"\n"
        }

        return csv
    }
}
