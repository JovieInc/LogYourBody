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
            return "Quick answer"
        case .photo:
            return "Visual timeline"
        }
    }

    var subtitle: String {
        switch self {
        case .avatar:
            return "Trend, meaning, and next action"
        case .photo:
            return "Private progress photos over time"
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

        /// Family gate for a future calibrated tier. Not a displayed percentage.
        var supportedBodyFatPercent: ClosedRange<Double> {
            switch self {
            case .male:
                return BodyShapeCalibration.adultMale.bodyFatMin...BodyShapeCalibration.adultMale.bodyFatMax
            case .female:
                return BodyShapeCalibration.adultFemale.bodyFatMin...BodyShapeCalibration.adultFemale.bodyFatMax
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
            BodyShapeCalibration.shapeBadge
        }

        var accessibilityLabel: String {
            BodyShapeCalibration.shapeAccessibilityLabel(sexTitle: sex.title)
        }
    }

    static func match(bodyFatPercentage: Double?, gender: String?) -> Match {
        let sex = Sex(gender: gender)
        let bucket = BodyShapeCalibration.displayedBucket(
            bodyFatPercentage: bodyFatPercentage,
            supported: sex.supportedBodyFatPercent,
            buckets: sex.buckets,
            fallback: sex.defaultBucket,
            compositionPromoted: BodyShapeCalibration.compositionAppearancePromoted
        )
        return Match(sex: sex, bucket: bucket)
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
