//
// DashboardDisplayMode.swift
// LogYourBody
//
// Defines the display mode for the dashboard's main content area
//

import Foundation

enum DashboardDisplayMode: String, Codable, CaseIterable {
    case photo          // Photo carousel view (default)
    case bodyFatChart   // Body fat percentage chart
    case weightChart    // Weight trend chart
    case ffmiChart      // FFMI (Fat-Free Mass Index) chart

    var title: String {
        switch self {
        case .photo:
            return "Progress Photos"
        case .bodyFatChart:
            return "Body Fat %"
        case .weightChart:
            return "Weight"
        case .ffmiChart:
            return "FFMI"
        }
    }

    var isChartMode: Bool {
        return self != .photo
    }
}

// Metric type for chart views
enum MetricType: String {
    case bodyFat = "Body Fat %"
    case weight = "Weight"
    case ffmi = "FFMI"

    var unit: String {
        switch self {
        case .bodyFat:
            return "%"
        case .weight:
            return "lbs" // Will be determined by user preference
        case .ffmi:
            return ""
        }
    }

    var color: String {
        switch self {
        case .bodyFat:
            return "liquidAccent" // Blue
        case .weight:
            return "liquidAccent" // Blue
        case .ffmi:
            return "liquidAccent" // Blue
        }
    }
}
