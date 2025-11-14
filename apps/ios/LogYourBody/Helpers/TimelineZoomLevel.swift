//
// TimelineZoomLevel.swift
// LogYourBody
//
// Auto-zoom calculation logic for Progress Timeline inspired by iOS Photos
//

import Foundation

/// Automatic zoom level based on data range and density
enum TimelineZoomLevel {
    case week      // All photos visible, 1-3 days per bucket
    case month     // 1-3 photos per week
    case year      // 1 photo per week or month
    case all       // 1 photo per time bucket (month/quarter/year)

    /// Calculate appropriate zoom level based on data range
    static func calculate(from startDate: Date, to endDate: Date) -> TimelineZoomLevel {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: startDate, to: endDate)
        let months = components.month ?? 0

        if months < 3 {
            return .week
        } else if months < 12 {
            return .month
        } else if months < 60 {  // < 5 years
            return .year
        } else {
            return .all
        }
    }

    /// Number of days per time bucket for this zoom level
    var daysPerBucket: Int {
        switch self {
        case .week: return 2        // Every 2 days
        case .month: return 7       // Weekly
        case .year: return 30       // Monthly
        case .all: return 90        // Quarterly
        }
    }

    /// Maximum number of visible thumbnails
    var maxVisibleThumbnails: Int {
        return 20
    }

    /// Whether to show metric-only ticks at this zoom level
    var showMetricTicks: Bool {
        switch self {
        case .week, .month: return true
        case .year, .all: return false  // Too cluttered at wide zoom
        }
    }

    /// Thumbnail size for this zoom level
    var thumbnailSize: CGFloat {
        switch self {
        case .week: return 36
        case .month: return 32
        case .year: return 28
        case .all: return 24
        }
    }
}

/// Helper for creating time buckets for photo sampling
struct TimelineBucket: Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    var candidates: [BodyMetrics] = []

    /// Initialize with start date and bucket size in days
    init(startDate: Date, days: Int) {
        self.startDate = startDate
        self.endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
        self.id = "\(Int(startDate.timeIntervalSince1970))"
    }

    /// Whether this date falls within the bucket
    func contains(_ date: Date) -> Bool {
        return date >= startDate && date < endDate
    }

    /// Add a candidate to this bucket
    mutating func addCandidate(_ metric: BodyMetrics) {
        candidates.append(metric)
    }
}

/// Calculator for time buckets based on zoom level
class TimelineBucketCalculator {
    /// Create buckets for a date range using the given zoom level
    static func createBuckets(from startDate: Date, to endDate: Date, zoomLevel: TimelineZoomLevel) -> [TimelineBucket] {
        var buckets: [TimelineBucket] = []
        let calendar = Calendar.current
        let daysPerBucket = zoomLevel.daysPerBucket

        var currentDate = startDate
        while currentDate < endDate {
            let bucket = TimelineBucket(startDate: currentDate, days: daysPerBucket)
            buckets.append(bucket)

            guard let nextDate = calendar.date(byAdding: .day, value: daysPerBucket, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        return buckets
    }

    /// Distribute metrics into buckets
    static func distributeToBuckets(metrics: [BodyMetrics], buckets: inout [TimelineBucket]) {
        for metric in metrics {
            for i in 0..<buckets.count {
                if buckets[i].contains(metric.date) {
                    buckets[i].addCandidate(metric)
                    break
                }
            }
        }
    }
}
