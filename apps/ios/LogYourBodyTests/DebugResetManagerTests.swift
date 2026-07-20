//
// DebugResetManagerTests.swift
// LogYourBodyTests
//
import Security
import XCTest
@testable import LogYourBody

/// Integration tests for `DebugResetManager`'s reset steps (a data-loss-risk
/// debug surface).
///
/// Coverage boundary: `performCompleteReset()` itself is not exercisable
/// in-process — it presents a `UIAlertController` confirmation, awaits a tap,
/// and finishes with an intentional `fatalError` under `#if DEBUG`. The
/// shake → alert wiring is XCUITest/manual territory per the tier
/// definitions. What is covered here is the destructive payload: each
/// clear* step the confirmation would unleash.
///
/// Notes:
/// - `clearUserDefaults()` wipes the entire app persistent domain, so this
///   suite captures/restores the documented keys and asserts the full-wipe
///   contract on seeded keys only.
/// - `clearKeychain()` touches the real keychain and is gated on
///   `KeychainAvailability`.
/// - `clearCoreData()` operates on `CoreDataManager.shared`; the suite
///   cleans the shared store before/after via `deleteAllDataAndWait()`
///   (same pattern as `Glp1DoseCoreDataTests`). The verification fetch is
///   enqueued on the same serial context queue as the delete, so it
///   observes the completed wipe without sleeps.
final class DebugResetManagerTests: XCTestCase {
    private let documentedKeys = [
        Constants.hasCompletedOnboardingKey,
        Constants.onboardingCompletedVersionKey,
        Constants.onboardingCompletedUserIdKey,
        Constants.preferredMeasurementSystemKey,
        "healthKitSyncEnabled",
        "biometricLockEnabled",
        "appleSignInName",
        "HasSyncedHistoricalSteps",
        "lastSyncDate",
        "hasSeenWhatsNew"
    ]

    private var capturedDefaults: [String: Any] = [:]
    private var seededFiles: [URL] = []

    override func setUp() {
        super.setUp()
        for key in documentedKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                capturedDefaults[key] = value
            }
        }
        seededFiles = []
    }

    override func tearDown() {
        for file in seededFiles {
            try? FileManager.default.removeItem(at: file)
        }
        seededFiles = []
        for key in documentedKeys {
            UserDefaults.standard.removeObject(forKey: key)
            if let value = capturedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        capturedDefaults.removeAll()
        super.tearDown()
    }

    // MARK: - UserDefaults

    func testClearUserDefaultsWipesEntireAppDomain() {
        for key in documentedKeys {
            UserDefaults.standard.set("seed", forKey: key)
        }
        UserDefaults.standard.set("seed", forKey: "lyb-debug-reset-arbitrary")

        DebugResetManager.shared.clearUserDefaults()

        for key in documentedKeys {
            XCTAssertNil(
                UserDefaults.standard.object(forKey: key),
                "Expected \(key) to be removed"
            )
        }
        // The real contract is a full app-domain wipe, not just the documented list.
        XCTAssertNil(UserDefaults.standard.object(forKey: "lyb-debug-reset-arbitrary"))
    }

    func testClearUserDefaultsPreservesOtherDefaultsSuites() throws {
        let suiteName = "DebugResetManagerTests.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.set("keep", forKey: "suiteKey")
        addTeardownBlock {
            suite.removePersistentDomain(forName: suiteName)
        }

        DebugResetManager.shared.clearUserDefaults()

        XCTAssertEqual(suite.string(forKey: "suiteKey"), "keep")
    }

    // MARK: - Core Data

    func testClearCoreDataDeletesSeededRecords() async throws {
        let coreData = CoreDataManager.shared
        try await coreData.deleteAllDataAndWait()
        addTeardownBlock {
            try? await CoreDataManager.shared.deleteAllDataAndWait()
        }
        let userId = "debug-reset-\(UUID().uuidString)"
        try await coreData.saveBodyMetricsAndWait(makeBodyMetric(userId: userId), userId: userId)
        try await coreData.saveGlp1DoseLogsAndWait([makeDoseLog(userId: userId)], userId: userId, markAsSynced: true)
        let seededMetrics = await coreData.fetchBodyMetrics(for: userId)
        let seededLogs = await coreData.fetchGlp1DoseLogs(for: userId)
        XCTAssertFalse(seededMetrics.isEmpty)
        XCTAssertFalse(seededLogs.isEmpty)

        DebugResetManager.shared.clearCoreData()

        // Both the delete and the fetch are enqueued on the same serial
        // viewContext queue, so the fetch observes the completed wipe.
        let remainingMetrics = await coreData.fetchBodyMetrics(for: userId)
        let remainingLogs = await coreData.fetchGlp1DoseLogs(for: userId)
        XCTAssertTrue(remainingMetrics.isEmpty)
        XCTAssertTrue(remainingLogs.isEmpty)
    }

    // MARK: - Keychain

    func testClearKeychainRemovesManagedItemsButKeepsUnrelatedEntries() throws {
        try XCTSkipUnless(
            KeychainAvailability.isAvailable(),
            "Keychain unavailable on unsigned CI test host (errSecMissingEntitlement); "
                + "runs fully on signed hosts and local dev. "
                + "TODO(@itstimwhite): enable when CI signs the test host."
        )
        let keychain = KeychainManager.shared
        try keychain.saveAuthToken("debug-reset-auth-token")
        try keychain.saveRefreshToken("debug-reset-refresh-token")
        try keychain.save("debug-reset-session", forKey: "debugResetSession")

        let unrelatedService = "com.logyourbody.tests.unrelated.\(UUID().uuidString)"
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unrelatedService,
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("keep".utf8)
        ]
        XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)
        addTeardownBlock {
            try? KeychainManager.shared.clearAll()
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: unrelatedService
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        DebugResetManager.shared.clearKeychain()

        XCTAssertNil(try keychain.getAuthToken())
        XCTAssertNil(try keychain.getRefreshToken())
        XCTAssertNil(try keychain.get(forKey: "debugResetSession", as: String.self))

        // clearAll() scopes deletion to the app's own keychain services only.
        var copied: AnyObject?
        let copyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unrelatedService,
            kSecAttrAccount as String: "probe",
            kSecReturnData as String: true
        ]
        XCTAssertEqual(SecItemCopyMatching(copyQuery as CFDictionary, &copied), errSecSuccess)
        XCTAssertEqual(copied as? Data, Data("keep".utf8))
    }

    // MARK: - File caches

    func testClearImageCacheWipesOnlyTempDirectory() throws {
        let tempFile = try seedFile(in: FileManager.default.temporaryDirectory, named: "image-cache-temp")
        let cacheFile = try seedFile(in: cachesDirectory(), named: "image-cache-cache")
        let documentFile = try seedFile(in: documentsDirectory(), named: "image-cache-document")

        DebugResetManager.shared.clearImageCache()

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: documentFile.path))
    }

    func testClearDerivedDataCacheWipesOnlyCachesDirectory() throws {
        let cacheFile = try seedFile(in: cachesDirectory(), named: "derived-cache")
        let tempFile = try seedFile(in: FileManager.default.temporaryDirectory, named: "derived-temp")
        let documentFile = try seedFile(in: documentsDirectory(), named: "derived-document")

        DebugResetManager.shared.clearDerivedDataCache()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: documentFile.path))
    }

    // MARK: - Helpers

    private func makeBodyMetric(userId: String) -> BodyMetrics {
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        return BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: now,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "Debug reset seed",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeDoseLog(userId: String) -> Glp1DoseLog {
        let now = Date(timeIntervalSince1970: 1_735_000_000)
        return Glp1DoseLog(
            id: UUID().uuidString,
            userId: userId,
            takenAt: now,
            medicationId: "medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func seedFile(in directory: URL, named name: String) throws -> URL {
        let fileURL = directory.appendingPathComponent("lyb-debug-reset-tests-\(name)-\(UUID().uuidString)")
        try Data("seed".utf8).write(to: fileURL)
        seededFiles.append(fileURL)
        return fileURL
    }

    private func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}
