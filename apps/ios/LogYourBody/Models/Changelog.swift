//
// Changelog.swift
// LogYourBody
//
import Foundation
import SwiftUI

struct ChangelogEntry {
    let version: String
    let date: Date
    let changes: [Change]

    struct Change {
        enum ChangeType {
            case feature
            case improvement
            case bugfix
            case performance

            var icon: String {
                switch self {
                case .feature: return "sparkles"
                case .improvement: return "arrow.up.circle.fill"
                case .bugfix: return "ladybug.fill"
                case .performance: return "speedometer"
                }
            }

            var color: String {
                switch self {
                case .feature: return "blue"
                case .improvement: return "green"
                case .bugfix: return "red"
                case .performance: return "orange"
                }
            }
        }

        let type: ChangeType
        let description: String
    }
}

class ChangelogManager {
    static let shared = ChangelogManager()

    private init() {}

    // Add new versions at the top
    private let hardcodedEntries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.4.0",
            date: Date(timeIntervalSince1970: 1_720_656_000), // July 11, 2025 (today)
            changes: [
                .init(type: .feature, description: "Frictionless Apple Sign In with post-auth consent"),
                .init(type: .feature, description: "Redesigned photo carousel with 16:9 aspect ratio"),
                .init(type: .improvement, description: "Monochrome gauge design for cleaner UI"),
                .init(type: .improvement, description: "Lightweight date slider with snap-to-value"),
                .init(type: .improvement, description: "Floating navigation bar without background"),
                .init(type: .bugfix, description: "Fixed progress photo zooming issues"),
                .init(type: .performance, description: "Optimized image loading in carousel")
            ]
        ),
        ChangelogEntry(
            version: "1.3.0",
            date: Date(timeIntervalSince1970: 1_719_792_000), // July 1, 2025
            changes: [
                .init(type: .feature, description: "AI-powered background removal for progress photos"),
                .init(type: .feature, description: "Advanced body composition analytics"),
                .init(type: .improvement, description: "Premium dashboard UI overhaul"),
                .init(type: .improvement, description: "Enhanced onboarding flow"),
                .init(type: .bugfix, description: "Fixed Core Data sync issues"),
                .init(type: .performance, description: "Faster photo processing")
            ]
        ),
        ChangelogEntry(
            version: "1.2.0",
            date: Date(timeIntervalSince1970: 1_718_928_000), // June 21, 2025
            changes: [
                .init(type: .feature, description: "Import all historical data from HealthKit"),
                .init(type: .feature, description: "What's New section in Settings"),
                .init(type: .improvement, description: "Moved sync status banner to bottom of screen"),
                .init(type: .improvement, description: "Bottom-justified metrics for better visibility"),
                .init(type: .bugfix, description: "Fixed pending sync count for HealthKit imports"),
                .init(type: .bugfix, description: "Fixed infinite sync loop"),
                .init(type: .performance, description: "Added automatic cache clearing on app updates"),
                .init(type: .performance, description: "Improved database optimization")
            ]
        ),
        ChangelogEntry(
            version: "1.1.0",
            date: Date(timeIntervalSince1970: 1_717_718_400), // June 7, 2025
            changes: [
                .init(type: .feature, description: "Redesigned profile settings with greyscale theme"),
                .init(type: .feature, description: "Real-time sync with cloud storage"),
                .init(type: .improvement, description: "Enhanced HealthKit integration"),
                .init(type: .improvement, description: "Better error handling for sync operations"),
                .init(type: .bugfix, description: "Fixed weight unit conversion issues"),
                .init(type: .bugfix, description: "Resolved app icon transparency for App Store")
            ]
        ),
        ChangelogEntry(
            version: "1.0.0",
            date: Date(timeIntervalSince1970: 1_716_508_800), // May 24, 2025
            changes: [
                .init(type: .feature, description: "Initial release"),
                .init(type: .feature, description: "Track body weight and body fat percentage"),
                .init(type: .feature, description: "HealthKit integration for automatic syncing"),
                .init(type: .feature, description: "Beautiful charts and visualizations"),
                .init(type: .feature, description: "Secure authentication with Clerk"),
                .init(type: .feature, description: "Cross-platform sync with web app")
            ]
        )
    ]

    /// Get all entries, ensuring the current app version is included
    var entries: [ChangelogEntry] {
        let currentVersion = AppVersion.current

        // Check if current version already exists in hardcoded entries
        if hardcodedEntries.first?.version == currentVersion {
            return hardcodedEntries
        }

        // If current version is newer, add a placeholder entry
        var allEntries = hardcodedEntries

        // Only add if current version is newer than the latest hardcoded version
        if let latestVersion = hardcodedEntries.first?.version,
           currentVersion.compare(latestVersion, options: NSString.CompareOptions.numeric) == .orderedDescending {
            let placeholderEntry = ChangelogEntry(
                version: currentVersion,
                date: Date(),
                changes: [
                    .init(type: .feature, description: "New features and improvements in this version")
                ]
            )
            allEntries.insert(placeholderEntry, at: 0)
        }

        return allEntries
    }

    /// Get changelog entries since a specific version
    func entriesSince(version: String) -> [ChangelogEntry] {
        guard let index = entries.firstIndex(where: { $0.version == version }) else {
            return entries // Return all if version not found
        }
        return Array(entries.prefix(index))
    }

    /// Check if there are new updates since last viewed version
    func hasNewUpdates() -> Bool {
        let lastViewedVersion = UserDefaults.standard.string(forKey: "lastViewedChangelogVersion") ?? "0.0.0"
        return entries.first?.version != lastViewedVersion
    }

    /// Mark changelog as viewed
    func markAsViewed() {
        if let latestVersion = entries.first?.version {
            UserDefaults.standard.set(latestVersion, forKey: "lastViewedChangelogVersion")
        }
    }
}
