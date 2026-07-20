//
// AppVersionManagerTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Integration tests for `AppVersionManager.performStartupMaintenance()`.
///
/// Seams and limits (per the test-hardening brief):
/// - `AppVersionManager` hardcodes `UserDefaults.standard`, so this suite
///   snapshots and restores every managed key instead of using a suite-named
///   domain.
/// - Cache clearing targets the real app-container tmp/Caches directories, so
///   tests seed uniquely-named files and remove leftovers in teardown.
/// - `clearImageCache()` replaces `URLCache.shared`; the shared instance is
///   snapshotted in setUp and restored in tearDown.
/// - Startup maintenance touches `CoreDataManager.shared` synchronously
///   (migration 1.1.0, `optimizeDatabase`), so tests invoke it on the main
///   thread to match production and keep the main-queue viewContext legal.
/// - Fire-and-forget Tasks (`RealtimeSyncManager.updatePendingSyncCount`,
///   `CoreDataManager.cleanupOldData`, the `pendingSyncCount > 1_000` guard)
///   are not deterministic and are intentionally not asserted.
/// - `cleanupKeychain()` is an empty no-op, so no KeychainAvailability gate is
///   needed here.
final class AppVersionManagerTests: XCTestCase {
    // Keys performStartupMaintenance reads, writes, or deletes.
    private let managedKeys = [
        "lastLaunchedAppVersion",
        "lastLaunchedBuildNumber",
        "firstLaunchDate",
        "lastMigrationVersion",
        "lastCoreDataOptimization",
        Constants.preferredWeightUnitKey,
        "healthKitSyncEnabled",
        "old_setting_key",
        "legacy_preference",
        "stuck_sync_flag"
    ]

    private var capturedDefaults: [String: Any] = [:]
    private var seededFiles: [URL] = []
    private var snapshotURLCache: URLCache?

    override func setUp() {
        super.setUp()
        snapshotURLCache = URLCache.shared
        captureAndRemoveManagedKeys()
        // Suppress the weekly CoreData optimize (and its shared-store rewrite)
        // except in the tests that exercise it explicitly.
        UserDefaults.standard.set(Date(), forKey: "lastCoreDataOptimization")
        seededFiles = []
    }

    override func tearDown() {
        for file in seededFiles {
            try? FileManager.default.removeItem(at: file)
        }
        seededFiles = []
        restoreManagedKeys()
        if let snapshotURLCache {
            URLCache.shared = snapshotURLCache
        }
        snapshotURLCache = nil
        super.tearDown()
    }

    // MARK: - Fresh install

    func testFreshInstallSeedsFirstLaunchDateAndDefaultSettings() async throws {
        try await runStartup()

        let firstLaunch = try XCTUnwrap(UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date)
        XCTAssertEqual(firstLaunch.timeIntervalSinceNow, 0, accuracy: 5)
        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey), "lbs")
        XCTAssertEqual(UserDefaults.standard.object(forKey: "healthKitSyncEnabled") as? Bool, true)

        // Every launch records the current version/build.
        let manager = AppVersionManager.shared
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastLaunchedAppVersion"), manager.currentVersion)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastLaunchedBuildNumber"), manager.currentBuild)
    }

    func testFreshInstallPreservesExistingUserSettings() async throws {
        UserDefaults.standard.set("kg", forKey: Constants.preferredWeightUnitKey)
        UserDefaults.standard.set(false, forKey: "healthKitSyncEnabled")

        try await runStartup()

        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey), "kg")
        XCTAssertEqual(UserDefaults.standard.object(forKey: "healthKitSyncEnabled") as? Bool, false)
    }

    func testFreshInstallDoesNotRunMigrationsOrUpdateCleanup() async throws {
        let tempFile = try seedFile(in: tempDirectory(), named: "fresh-temp")
        let cacheFile = try seedFile(in: cachesDirectory(), named: "fresh-cache")
        UserDefaults.standard.set("stale", forKey: "old_setting_key")
        UserDefaults.standard.set("stale", forKey: "legacy_preference")
        UserDefaults.standard.set(true, forKey: "stuck_sync_flag")

        try await runStartup()

        // Migrations are update-only: no completion marker is recorded.
        XCTAssertNil(UserDefaults.standard.string(forKey: "lastMigrationVersion"))
        // Cache wiping and stale-key cleanup are update-only as well.
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "old_setting_key"), "stale")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "legacy_preference"), "stale")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "stuck_sync_flag"))
    }

    // MARK: - Update path

    func testUpdateRunsMigrationsAndRecordsCompletion() async throws {
        forceUpdateFrom(lastVersion: "1.0.0", lastBuild: "1")

        try await runStartup()

        let manager = AppVersionManager.shared
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastMigrationVersion"), manager.currentVersion)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastLaunchedAppVersion"), manager.currentVersion)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastLaunchedBuildNumber"), manager.currentBuild)
    }

    func testUpdateWipesTempAndCachesButPreservesDocuments() async throws {
        forceUpdateFrom(lastVersion: "1.0.0", lastBuild: "1")
        let tempFile = try seedFile(in: tempDirectory(), named: "update-temp")
        let cacheFile = try seedFile(in: cachesDirectory(), named: "update-cache")
        let documentFile = try seedFile(in: documentsDirectory(), named: "update-document")

        try await runStartup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: documentFile.path))
    }

    func testUpdateRemovesDeprecatedKeysAndStuckFlagsOnly() async throws {
        forceUpdateFrom(lastVersion: "1.0.0", lastBuild: "1")
        UserDefaults.standard.set("stale", forKey: "old_setting_key")
        UserDefaults.standard.set("stale", forKey: "legacy_preference")
        UserDefaults.standard.set(true, forKey: "stuck_sync_flag")
        UserDefaults.standard.set("kg", forKey: Constants.preferredWeightUnitKey)
        UserDefaults.standard.set("keep", forKey: "someUnrelatedKey")
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "someUnrelatedKey")
        }

        try await runStartup()

        XCTAssertNil(UserDefaults.standard.string(forKey: "old_setting_key"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "legacy_preference"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "stuck_sync_flag"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey), "kg")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "someUnrelatedKey"), "keep")
    }

    func testUpdateFromPartialMigrationRunsOnlyRemainingMigrations() async throws {
        // Marker says 1.1.0 already ran: only the 1.2.0 temp-file wipe remains.
        UserDefaults.standard.set("1.1.0", forKey: "lastMigrationVersion")
        forceUpdateFrom(lastVersion: "1.1.0", lastBuild: "1")
        let tempFile = try seedFile(in: tempDirectory(), named: "partial-migration")

        try await runStartup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "lastMigrationVersion"),
            AppVersionManager.shared.currentVersion
        )
    }

    func testUpdateWithCompletedMigrationsSkipsThemButStillClearsCaches() async throws {
        let manager = AppVersionManager.shared
        try XCTSkipUnless(
            manager.currentVersion.compare("1.2.0", options: .numeric) != .orderedAscending,
            "Migration idempotency requires currentVersion >= 1.2.0"
        )
        UserDefaults.standard.set(manager.currentVersion, forKey: "lastMigrationVersion")
        // Force the update path via a build-only bump so the version marker stays current.
        forceUpdateFrom(lastVersion: manager.currentVersion, lastBuild: "0")
        let tempFile = try seedFile(in: tempDirectory(), named: "idempotent-temp")
        let cacheFile = try seedFile(in: cachesDirectory(), named: "idempotent-cache")

        try await runStartup()

        // Both migrations are already recorded, so the 1.2.0 temp wipe must not re-run.
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        // clearCaches() is unconditional on the update path, independent of migration state.
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
    }

    func testSecondStartupDoesNotRerunMigrations() async throws {
        let manager = AppVersionManager.shared
        try XCTSkipUnless(
            manager.currentVersion.compare("1.2.0", options: .numeric) != .orderedAscending,
            "Migration idempotency requires currentVersion >= 1.2.0"
        )
        forceUpdateFrom(lastVersion: "1.0.0", lastBuild: "1")
        try await runStartup()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastMigrationVersion"), manager.currentVersion)

        let tempFile = try seedFile(in: tempDirectory(), named: "second-launch")
        try await runStartup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastMigrationVersion"), manager.currentVersion)
    }

    // MARK: - Same-version launch

    func testSameVersionLaunchKeepsDataAndSkipsCleanup() async throws {
        let manager = AppVersionManager.shared
        forceSameVersion()
        let originalFirstLaunch = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaults.standard.set(originalFirstLaunch, forKey: "firstLaunchDate")
        let tempFile = try seedFile(in: tempDirectory(), named: "same-version-temp")
        let cacheFile = try seedFile(in: cachesDirectory(), named: "same-version-cache")
        UserDefaults.standard.set("stale", forKey: "old_setting_key")

        try await runStartup()

        let firstLaunch = try XCTUnwrap(UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date)
        XCTAssertEqual(firstLaunch.timeIntervalSince1970, originalFirstLaunch.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "old_setting_key"), "stale")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastLaunchedAppVersion"), manager.currentVersion)
    }

    // MARK: - Routine maintenance (every launch)

    func testRoutineMaintenanceDeletesOnlyTempFilesOlderThan7Days() async throws {
        forceSameVersion()
        let recentFile = try seedFile(in: tempDirectory(), named: "recent-temp")
        let oldFile = try seedFile(in: tempDirectory(), named: "old-temp", createdDaysAgo: 8)

        try await runStartup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path))
    }

    func testOptimizeCoreDataRecordsRunWhenNeverRecorded() async throws {
        forceSameVersion()
        UserDefaults.standard.removeObject(forKey: "lastCoreDataOptimization")

        try await runStartup()

        let recorded = try XCTUnwrap(UserDefaults.standard.object(forKey: "lastCoreDataOptimization") as? Date)
        XCTAssertEqual(recorded.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testOptimizeCoreDataRerunsAfterMoreThanAWeek() async throws {
        forceSameVersion()
        UserDefaults.standard.set(
            Date().addingTimeInterval(-8 * 24 * 60 * 60),
            forKey: "lastCoreDataOptimization"
        )

        try await runStartup()

        let recorded = try XCTUnwrap(UserDefaults.standard.object(forKey: "lastCoreDataOptimization") as? Date)
        XCTAssertEqual(recorded.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testOptimizeCoreDataSkippedWithinAWeek() async throws {
        forceSameVersion()
        let recent = Date().addingTimeInterval(-24 * 60 * 60)
        UserDefaults.standard.set(recent, forKey: "lastCoreDataOptimization")

        try await runStartup()

        let recorded = try XCTUnwrap(UserDefaults.standard.object(forKey: "lastCoreDataOptimization") as? Date)
        XCTAssertEqual(recorded.timeIntervalSince1970, recent.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Migration 1.1.0 (Core Data effect)

    func testMigration110MarksOnlyHealthKitEntriesAsSynced() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        addTeardownBlock {
            try? await CoreDataManager.shared.deleteAllDataAndWait()
        }
        let userId = "avm-migration-\(UUID().uuidString)"
        let healthKitId = try await seedBodyMetric(
            userId: userId,
            notes: "Imported from HealthKit",
            dataSource: .healthKit
        )
        let manualId = try await seedBodyMetric(
            userId: userId,
            notes: "Manual weigh-in",
            dataSource: .manual
        )
        UserDefaults.standard.set("1.0.0", forKey: "lastMigrationVersion")
        forceUpdateFrom(lastVersion: "1.0.0", lastBuild: "1")

        try await runStartup()

        let metrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let healthKitEntry = try XCTUnwrap(metrics.first { $0.id == healthKitId })
        let manualEntry = try XCTUnwrap(metrics.first { $0.id == manualId })
        XCTAssertTrue(healthKitEntry.isSynced)
        XCTAssertEqual(healthKitEntry.syncStatus, "synced")
        XCTAssertFalse(manualEntry.isSynced)
        XCTAssertEqual(manualEntry.syncStatus, "pending")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "lastMigrationVersion"),
            AppVersionManager.shared.currentVersion
        )
    }

    func testMigration110SkippedWhenAlreadyRecorded() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        addTeardownBlock {
            try? await CoreDataManager.shared.deleteAllDataAndWait()
        }
        let userId = "avm-migration-\(UUID().uuidString)"
        let healthKitId = try await seedBodyMetric(
            userId: userId,
            notes: "Imported from HealthKit",
            dataSource: .healthKit
        )
        UserDefaults.standard.set("1.1.0", forKey: "lastMigrationVersion")
        forceUpdateFrom(lastVersion: "1.1.0", lastBuild: "1")

        try await runStartup()

        let metrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let healthKitEntry = try XCTUnwrap(metrics.first { $0.id == healthKitId })
        XCTAssertFalse(healthKitEntry.isSynced)
        XCTAssertEqual(healthKitEntry.syncStatus, "pending")
    }

    // MARK: - Helpers

    /// Runs startup maintenance on the main thread, matching production launch.
    private func runStartup() async throws {
        await MainActor.run {
            AppVersionManager.shared.performStartupMaintenance()
        }
    }

    private func forceUpdateFrom(lastVersion: String, lastBuild: String) {
        UserDefaults.standard.set(lastVersion, forKey: "lastLaunchedAppVersion")
        UserDefaults.standard.set(lastBuild, forKey: "lastLaunchedBuildNumber")
    }

    private func forceSameVersion() {
        let manager = AppVersionManager.shared
        forceUpdateFrom(lastVersion: manager.currentVersion, lastBuild: manager.currentBuild)
    }

    private func seedBodyMetric(
        userId: String,
        notes: String,
        dataSource: BodyMetricSource
    ) async throws -> String {
        let id = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        let metric = BodyMetrics(
            id: id,
            userId: userId,
            date: now,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: notes,
            photoUrl: nil,
            dataSource: dataSource.rawValue,
            sourceMetadata: nil,
            createdAt: now,
            updatedAt: now
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: false)
        return id
    }

    private func seedFile(
        in directory: URL,
        named name: String,
        createdDaysAgo days: Int? = nil
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent("lyb-avm-tests-\(name)-\(UUID().uuidString)")
        try Data("seed".utf8).write(to: fileURL)
        if let days {
            let creationDate = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            try FileManager.default.setAttributes([.creationDate: creationDate], ofItemAtPath: fileURL.path)
        }
        seededFiles.append(fileURL)
        return fileURL
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
    }

    private func cachesDirectory() -> URL {
        // Force-unwrap mirrors the app's own force-unwrap in clearAppCaches().
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func captureAndRemoveManagedKeys() {
        for key in managedKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                capturedDefaults[key] = value
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func restoreManagedKeys() {
        for key in managedKeys {
            UserDefaults.standard.removeObject(forKey: key)
            if let value = capturedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        capturedDefaults.removeAll()
    }
}
