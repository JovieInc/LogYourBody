//
//  TimelineCalculator.swift
//  LogYourBody
//
//  Smart timeline calculation with time-weighted positioning
//

import Foundation

/// Represents a data point on the timeline with weighted position
struct TimelineDataPoint: Identifiable {
    let id: String
    let index: Int                  // Index in original bodyMetrics array
    let date: Date                  // Actual date of this entry
    let position: Double            // Weighted position (0.0 = oldest, 1.0 = newest)
    let displayLabel: String        // Human-readable label for this point
    let importance: TimelineImportance

    enum TimelineImportance {
        case daily      // Individual day (last 7 days)
        case weekly     // Week checkpoint (8-30 days)
        case monthly    // Month checkpoint (1-12 months)
        case yearly     // Year checkpoint (>1 year)
    }
}

/// Calculates smart time-weighted positions for timeline entries
class TimelineCalculator {

    /// Calculate weighted timeline positions for body metrics
    /// - Parameter metrics: Array of BodyMetrics sorted by date (newest first)
    /// - Returns: Array of TimelineDataPoint with weighted positions
    static func calculateTimelinePoints(from metrics: [BodyMetrics]) -> [TimelineDataPoint] {
        guard !metrics.isEmpty else { return [] }

        // Sort metrics oldest to newest for easier calculation
        let sortedMetrics = metrics.sorted { $0.date < $1.date }
        guard let oldestDate = sortedMetrics.first?.date,
              let newestDate = sortedMetrics.last?.date else {
            return []
        }

        let now = Date()
        var timelinePoints: [TimelineDataPoint] = []
        let calendar = Calendar.current

        // Calculate time intervals from now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now

        // Process each metric and assign importance level
        for (index, metric) in sortedMetrics.enumerated() {
            let importance: TimelineDataPoint.TimelineImportance

            if metric.date >= sevenDaysAgo {
                // Last 7 days: show every day
                importance = .daily
            } else if metric.date >= thirtyDaysAgo {
                // 8-30 days: show weekly checkpoints
                importance = .weekly
            } else if metric.date >= oneYearAgo {
                // 1-12 months: show monthly checkpoints
                importance = .monthly
            } else {
                // >1 year: show yearly checkpoints
                importance = .yearly
            }

            timelinePoints.append(TimelineDataPoint(
                id: metric.id,
                index: index,
                date: metric.date,
                position: 0.0, // Will be calculated next
                displayLabel: formatLabel(for: metric.date, importance: importance),
                importance: importance
            ))
        }

        // Calculate weighted positions
        timelinePoints = calculateWeightedPositions(points: timelinePoints, newestDate: newestDate)

        return timelinePoints
    }

    /// Calculate weighted positions where recent dates get more timeline space
    /// 70% of timeline = last 30 days, 20% = last year, 10% = everything older
    private static func calculateWeightedPositions(points: [TimelineDataPoint], newestDate: Date) -> [TimelineDataPoint] {
        let calendar = Calendar.current
        let now = Date()

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now

        return points.map { point in
            let position: Double

            if point.date >= thirtyDaysAgo {
                // Last 30 days: 0.3 to 1.0 (70% of timeline)
                let daysAgo = calendar.dateComponents([.day], from: point.date, to: now).day ?? 0
                let normalizedPosition = 1.0 - (Double(daysAgo) / 30.0) // 1.0 = today, 0.0 = 30 days ago
                position = 0.3 + (normalizedPosition * 0.7)
            } else if point.date >= oneYearAgo {
                // 30 days to 1 year: 0.1 to 0.3 (20% of timeline)
                let daysAgo = calendar.dateComponents([.day], from: point.date, to: now).day ?? 0
                let daysSinceThirty = Double(daysAgo - 30)
                let normalizedPosition = 1.0 - (daysSinceThirty / 335.0) // 335 days = 1 year - 30 days
                position = 0.1 + (normalizedPosition * 0.2)
            } else {
                // Older than 1 year: 0.0 to 0.1 (10% of timeline)
                guard let oldestPoint = points.first else {
                    position = 0.0
                    return point
                }

                let totalOldTime = oneYearAgo.timeIntervalSince(oldestPoint.date)
                guard totalOldTime > 0 else {
                    position = 0.0
                    return point
                }

                let timeFromOldest = point.date.timeIntervalSince(oldestPoint.date)
                let normalizedPosition = timeFromOldest / totalOldTime
                position = normalizedPosition * 0.1
            }

            return TimelineDataPoint(
                id: point.id,
                index: point.index,
                date: point.date,
                position: max(0.0, min(1.0, position)), // Clamp to 0.0-1.0
                displayLabel: point.displayLabel,
                importance: point.importance
            )
        }
    }

    /// Format display label based on importance level
    private static func formatLabel(for date: Date, importance: TimelineDataPoint.TimelineImportance) -> String {
        let formatter = DateFormatter()

        switch importance {
        case .daily:
            formatter.dateFormat = "MMM d"  // "Jan 15"
        case .weekly:
            formatter.dateFormat = "MMM d"  // "Jan 15"
        case .monthly:
            formatter.dateFormat = "MMM yyyy"  // "Jan 2024"
        case .yearly:
            formatter.dateFormat = "yyyy"  // "2024"
        }

        return formatter.string(from: date)
    }

    /// Find nearest data point to a given position (0.0-1.0)
    static func findNearestPoint(to position: Double, in points: [TimelineDataPoint]) -> TimelineDataPoint? {
        guard !points.isEmpty else { return nil }

        return points.min { point1, point2 in
            abs(point1.position - position) < abs(point2.position - position)
        }
    }

    /// Get position for a specific index
    static func position(for index: Int, in points: [TimelineDataPoint]) -> Double? {
        points.first { $0.index == index }?.position
    }

    /// Get index for a specific position
    static func index(for position: Double, in points: [TimelineDataPoint]) -> Int? {
        findNearestPoint(to: position, in: points)?.index
    }
}
