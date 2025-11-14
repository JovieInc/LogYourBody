//
// TimelineMode.swift
// LogYourBody
//
// Timeline display mode and supporting types for Progress Timeline component
//

import Foundation
import SwiftUI

/// Display mode for the progress timeline
enum TimelineMode: String, Codable, CaseIterable {
    case photo      // Photo-first mode: emphasizes photos, shows metrics alongside
    case avatar     // Metrics-first mode: emphasizes metrics, snaps to data points

    var displayName: String {
        switch self {
        case .photo: return "Photo Mode"
        case .avatar: return "Avatar Mode"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "photo"
        case .avatar: return "figure.stand"
        }
    }
}

/// Result of searching for nearest photo/metrics around a date
struct TimelineDataResult {
    let scrubDate: Date
    let photo: PhotoResult?
    let metrics: MetricsResult?

    struct PhotoResult {
        let bodyMetrics: BodyMetrics
        let daysFromScrub: Int
    }

    struct MetricsResult {
        let bodyMetrics: BodyMetrics
        let daysFromScrub: Int
        let isInterpolated: Bool
    }

    /// Date to display in UI
    var displayDate: Date {
        // Prefer photo date if available and close
        if let photo = photo, abs(photo.daysFromScrub) <= 1 {
            return photo.bodyMetrics.date
        }
        // Otherwise prefer metrics date if available
        if let metrics = metrics {
            return metrics.bodyMetrics.date
        }
        // Fallback to scrub date
        return scrubDate
    }

    /// Whether photo and metrics dates differ significantly (>1 day)
    var hasDateMismatch: Bool {
        guard let photo = photo, let metrics = metrics else { return false }
        let daysDiff = Calendar.current.dateComponents([.day],
                                                       from: photo.bodyMetrics.date,
                                                       to: metrics.bodyMetrics.date).day ?? 0
        return abs(daysDiff) > 1
    }

    /// Formatted date label for UI
    func formattedDateLabel() -> String {
        if hasDateMismatch, let photo = photo, let metrics = metrics {
            let photoPart = formatDate(photo.bodyMetrics.date, short: true)
            let metricsPart = formatDate(metrics.bodyMetrics.date, short: true)
            let daysDiff = abs(photo.daysFromScrub - metrics.daysFromScrub)
            return "Photo: \(photoPart) • Metrics: \(metricsPart) (\(daysDiff) days apart)"
        } else {
            return formatDate(displayDate, short: false)
        }
    }

    private func formatDate(_ date: Date, short: Bool) -> String {
        let calendar = Calendar.current
        let now = Date()
        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0

        if daysDiff == 0 {
            return "Today"
        } else if daysDiff == 1 {
            return "Yesterday"
        } else if daysDiff < 7 {
            return "\(daysDiff) days ago"
        } else if daysDiff < 30 {
            let formatter = DateFormatter()
            formatter.dateFormat = short ? "MMM d" : "MMMM d"
            return formatter.string(from: date)
        } else if daysDiff < 365 {
            let formatter = DateFormatter()
            formatter.dateFormat = short ? "MMM d" : "MMMM d, yyyy"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = short ? "MMM yyyy" : "MMMM yyyy"
            return formatter.string(from: date)
        }
    }
}

/// Timeline position with metadata for rendering
struct TimelineAnchor: Identifiable {
    let id: String
    let date: Date
    let position: Double  // 0.0 to 1.0 normalized position
    let bodyMetrics: BodyMetrics
    let anchorType: AnchorType
    let importance: TimelineImportance

    enum AnchorType {
        case photo          // Has photo
        case metricsOnly    // Has metrics but no photo
        case photoWithMetrics  // Has both
    }

    enum TimelineImportance {
        case daily      // Last 7 days
        case weekly     // 8-30 days
        case monthly    // 1-12 months
        case yearly     // >1 year
    }
}
