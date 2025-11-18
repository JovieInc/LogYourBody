//
// AppVersionManager.swift
// LogYourBody
//
import Foundation
import UIKit

/// Manages app version tracking and handles migrations/cleanup after updates
class AppVersionManager {
    static let shared = AppVersionManager()

    private let lastVersionKey = "lastLaunchedAppVersion"
    private let lastBuildKey = "lastLaunchedBuildNumber"
    private let firstLaunchDateKey = "firstLaunchDate"
    private let migrationVersionKey = "lastMigrationVersion"

    private init() {}

    /// Current app version (e.g., "1.0.0")
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Current build number (e.g., "100")
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Last launched version
    var lastLaunchedVersion: String? {
        UserDefaults.standard.string(forKey: lastVersionKey)
    }

    /// Last launched build
    var lastLaunchedBuild: String? {
        UserDefaults.standard.string(forKey: lastBuildKey)
    }

    /// Check if this is a fresh install
    var isFreshInstall: Bool {
        lastLaunchedVersion == nil
    }

    /// Check if app was just updated
    var wasUpdated: Bool {
        guard let lastVersion = lastLaunchedVersion,
              let lastBuild = lastLaunchedBuild else {
            return false
        }

        return lastVersion != currentVersion || lastBuild != currentBuild
    }

    /// Perform necessary setup and migrations
    func performStartupMaintenance() {
        // print("🚀 App Version Manager")
        // print("  Current: \(currentVersion) (\(currentBuild))")
        // print("  Previous: \(lastLaunchedVersion ?? "None") (\(lastLaunchedBuild ?? "None"))")

        if isFreshInstall {
            handleFreshInstall()
        } else if wasUpdated {
            handleAppUpdate()
        }

        // Always update version info
        updateVersionInfo()

        // Perform routine maintenance
        performRoutineMaintenance()
    }

    private func handleFreshInstall() {
        // print("📱 Fresh install detected")

        // Set first launch date
        UserDefaults.standard.set(Date(), forKey: firstLaunchDateKey)

        // Initialize any default settings
        setupDefaultSettings()
    }

    private func handleAppUpdate() {
        // print("🔄 App update detected")

        // Perform version-specific migrations
        performMigrations()

        // Clear caches
        clearCaches()

        // Clean up old data
        cleanupOldData()

        // Reset any problematic states
        resetProblematicStates()
    }

    private func performMigrations() {
        let lastMigration = UserDefaults.standard.string(forKey: migrationVersionKey) ?? "0.0.0"

        // Version 1.1.0 - Fix HealthKit sync status
        if lastMigration.compare("1.1.0", options: .numeric) == .orderedAscending {
            // print("🔧 Running migration for v1.1.0")
            CoreDataManager.shared.markHealthKitEntriesAsSynced()
            Task { @MainActor in
                RealtimeSyncManager.shared.updatePendingSyncCount()
            }
        }

        // Version 1.2.0 - Clear old cache data
        if lastMigration.compare("1.2.0", options: .numeric) == .orderedAscending {
            // print("🔧 Running migration for v1.2.0")
            clearImageCache()
            clearTempFiles()
        }

        // Add more version-specific migrations here as needed

        // Update migration version
        UserDefaults.standard.set(currentVersion, forKey: migrationVersionKey)
    }

    private func clearCaches() {
        // print("🧹 Clearing caches...")

        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()

        // Clear image cache
        clearImageCache()

        // Clear any app-specific caches
        clearAppCaches()
    }

    private func clearImageCache() {
        // Clear any image caches used by the app
        let imageCache = URLCache(
            memoryCapacity: 0,
            diskCapacity: 0,
            diskPath: nil
        )
        URLCache.shared = imageCache
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1_024 * 1_024,  // 50 MB
            diskCapacity: 100 * 1_024 * 1_024,   // 100 MB
            diskPath: nil
        )
    }

    private func clearTempFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            )
            for file in tempFiles {
                try? FileManager.default.removeItem(at: file)
            }
            // print("✅ Cleared \(tempFiles.count) temp files")
        } catch {
            // print("Failed to clear temp files: \(error)")
        }
    }

    private func clearAppCaches() {
        // Clear any custom app caches
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )

            var clearedSize: Int64 = 0
            for file in cacheFiles {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int64 {
                    clearedSize += fileSize
                }
                try? FileManager.default.removeItem(at: file)
            }

            let megabytes = Double(clearedSize) / (1_024 * 1_024)
            // print("✅ Cleared \(String(format: "%.1f", megabytes)) MB from cache")
        } catch {
            // print("Failed to clear app caches: \(error)")
        }
    }

    private func cleanupOldData() {
        // print("🗑️ Cleaning up old data...")

        // Clean up CoreData
        CoreDataManager.shared.cleanupOldData()

        // Clean up old user defaults
        cleanupOldUserDefaults()

        // Clean up keychain if needed
        cleanupKeychain()
    }

    private func cleanupOldUserDefaults() {
        // Remove deprecated keys
        let deprecatedKeys = [
            "old_setting_key",
            "legacy_preference"
            // Add any deprecated UserDefaults keys here
        ]

        for key in deprecatedKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func cleanupKeychain() {
        // Clean up any old keychain items if needed
        // This is sensitive, so be careful about what you delete
    }

    private func resetProblematicStates() {
        // print("🔄 Resetting problematic states...")

        // Reset any sync flags that might be stuck
        Task { @MainActor in
            if RealtimeSyncManager.shared.pendingSyncCount > 1_000 {
                // print("⚠️ Excessive pending sync count detected, marking HealthKit entries as synced")
                CoreDataManager.shared.markHealthKitEntriesAsSynced()
            }
        }

        // Reset any other problematic states
        UserDefaults.standard.removeObject(forKey: "stuck_sync_flag")
    }

    private func performRoutineMaintenance() {
        // Perform maintenance tasks that should run on every launch

        // Clean temp files older than 7 days
        cleanOldTempFiles(olderThan: 7)

        // Optimize CoreData if needed
        optimizeCoreData()

        // Check and repair any data inconsistencies
        checkDataIntegrity()
    }

    private func cleanOldTempFiles(olderThan days: Int) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)

        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey]
            )

            var cleanedCount = 0
            for file in tempFiles {
                if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attributes.creationDate,
                   creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: file)
                    cleanedCount += 1
                }
            }

            if cleanedCount > 0 {
                // print("✅ Cleaned \(cleanedCount) old temp files")
            }
        } catch {
            // print("Failed to clean old temp files: \(error)")
        }
    }

    private func optimizeCoreData() {
        // Vacuum SQLite database periodically
        let lastOptimization = UserDefaults.standard.object(forKey: "lastCoreDataOptimization") as? Date ?? Date.distantPast

        if Date().timeIntervalSince(lastOptimization) > 7 * 24 * 60 * 60 { // Weekly
            CoreDataManager.shared.optimizeDatabase()
            UserDefaults.standard.set(Date(), forKey: "lastCoreDataOptimization")
        }
    }

    private func checkDataIntegrity() {
        // Check for any data inconsistencies and fix them
        // For example, orphaned records, invalid dates, etc.
    }

    private func setupDefaultSettings() {
        // Set up any default settings for fresh installs
        if UserDefaults.standard.object(forKey: Constants.preferredWeightUnitKey) == nil {
            UserDefaults.standard.set("lbs", forKey: Constants.preferredWeightUnitKey)
        }

        if UserDefaults.standard.object(forKey: "healthKitSyncEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "healthKitSyncEnabled")
        }
    }

    private func updateVersionInfo() {
        UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)
        UserDefaults.standard.set(currentBuild, forKey: lastBuildKey)
        UserDefaults.standard.synchronize()
    }

    /// Get formatted version string for display
    func formattedVersionString() -> String {
        "Version \(currentVersion) (\(currentBuild))"
    }

    /// Get just the version string
    func versionString() -> String {
        currentVersion
    }

    /// Get just the build string
    func buildString() -> String {
        currentBuild
    }

    /// Check if a specific feature should be enabled based on version
    func isFeatureEnabled(_ feature: String) -> Bool {
        // Add feature flags based on version if needed
        return true
    }
}
