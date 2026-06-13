//
// DashboardDisplayMode.swift
// LogYourBody
//
// Defines the display mode for the dashboard's main content area
//

import Foundation

enum DefaultHomeMode: String, Codable, CaseIterable, Identifiable {
    case avatar
    case photo

    static let `default`: DefaultHomeMode = .avatar

    var id: String { rawValue }

    init(storedValue: String) {
        self = DefaultHomeMode(rawValue: storedValue) ?? Self.default
    }

    init(timelineMode: TimelineMode) {
        switch timelineMode {
        case .avatar:
            self = .avatar
        case .photo:
            self = .photo
        }
    }

    var timelineMode: TimelineMode {
        switch self {
        case .avatar:
            return .avatar
        case .photo:
            return .photo
        }
    }

    var title: String {
        switch self {
        case .avatar:
            return "Avatar"
        case .photo:
            return "Photo"
        }
    }

    var subtitle: String {
        switch self {
        case .avatar:
            return "Privacy-safe body timeline"
        case .photo:
            return "Real progress photos"
        }
    }

    var iconName: String {
        switch self {
        case .avatar:
            return "figure.stand"
        case .photo:
            return "photo.fill"
        }
    }
}

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
