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

enum AvatarBodyFatCatalog {
    enum Sex: String {
        case male
        case female

        init(gender: String?) {
            let normalized = gender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

            if normalized == "f" ||
                normalized.contains("female") ||
                normalized.contains("woman") {
                self = .female
            } else {
                self = .male
            }
        }

        var title: String {
            switch self {
            case .male:
                return "Male"
            case .female:
                return "Female"
            }
        }

        var defaultBucket: Int {
            switch self {
            case .male:
                return 18
            case .female:
                return 28
            }
        }

        var buckets: [Int] {
            switch self {
            case .male:
                return [5, 8, 10, 12, 15, 18, 22, 27, 35, 45, 55]
            case .female:
                return [12, 15, 18, 21, 24, 28, 33, 40, 50, 60]
            }
        }
    }

    struct Match: Equatable {
        let sex: Sex
        let bucket: Int

        var assetName: String {
            "avatar_\(sex.rawValue)_\(String(format: "%02d", bucket))"
        }

        var badgeText: String {
            "\(sex.title) \(bucket)% body fat"
        }

        var accessibilityLabel: String {
            "\(sex.title) avatar, \(bucket) percent body fat bucket"
        }
    }

    static func match(bodyFatPercentage: Double?, gender: String?) -> Match {
        let sex = Sex(gender: gender)
        let target = bodyFatPercentage ?? Double(sex.defaultBucket)
        let bucket = nearestBucket(to: target, in: sex.buckets, fallback: sex.defaultBucket)

        return Match(sex: sex, bucket: bucket)
    }

    private static func nearestBucket(to value: Double, in buckets: [Int], fallback: Int) -> Int {
        buckets.min { lhs, rhs in
            let leftDistance = abs(Double(lhs) - value)
            let rightDistance = abs(Double(rhs) - value)

            if leftDistance == rightDistance {
                return lhs < rhs
            }

            return leftDistance < rightDistance
        } ?? fallback
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
