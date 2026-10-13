import XCTest
import CoreData
@testable import LogYourBody

private final class ObserverQueryCounter: @unchecked Sendable {
    var value = 0
}

@MainActor
final class BodyScoreHealthKitTriggerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private var cacheOwners: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "BodyScoreHealthKitTriggerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
        cacheOwners = []
    }

    override func tearDown() async throws {
        for owner in cacheOwners { BodyScoreCache.shared.invalidate(for: owner) }
        defaults?.removePersistentDomain(forName: suiteName)
        auth = nil
        coreData = nil
        defaults = nil
        try await super.tearDown()
    }

    private func manager(for user: LocalUser) -> HealthKitManager {
        auth.authSession = .localFixture(subject: user.id, email: user.email, accessToken: "synthetic")
        auth.currentUser = user
        return HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            syncTrigger: {}, bodyScoreRecalculationTrigger: {}
        )
    }

    func testHealthKitNoOpBatchDoesNotInvalidateBodyScoreCache() async throws {
        let userId = "healthkit_test_user_noop_cache_\(UUID().uuidString)"
        let otherUserId = "healthkit_test_user_other_cache_\(UUID().uuidString)"
        let healthKitManager = manager(for: makeUser(id: userId, email: "hk_noop_cache@example.com"))
        cacheOwners = [userId, otherUserId]

        let day = Calendar.current.startOfDay(for: Date())
        let existingDate = Calendar.current.date(
            byAdding: DateComponents(hour: 10, minute: 45),
            to: day
        ) ?? day
        let skippedDate = Calendar.current.date(
            byAdding: DateComponents(hour: 10, minute: 15),
            to: day
        ) ?? day

        try await coreData.saveBodyMetricsAndWait(
            makeBodyMetrics(userId: userId, date: existingDate),
            userId: userId
        )

        let cachedScore = makeBodyScoreResult(score: 82)
        let otherCachedScore = makeBodyScoreResult(score: 64)
        BodyScoreCache.shared.store(cachedScore, for: userId)
        BodyScoreCache.shared.store(otherCachedScore, for: otherUserId)

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [(weight: 81.0, date: skippedDate)],
            bodyFatHistory: []
        )

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(BodyScoreCache.shared.latestResult(for: userId), cachedScore)
        XCTAssertEqual(BodyScoreCache.shared.latestResult(for: otherUserId), otherCachedScore)
    }

    func testHealthKitImportInvalidatesOnlyAffectedBodyScoreCache() async {
        let userId = "healthkit_test_user_import_cache_\(UUID().uuidString)"
        let otherUserId = "healthkit_test_user_other_cache_\(UUID().uuidString)"
        let healthKitManager = manager(for: makeUser(id: userId, email: "hk_import_cache@example.com"))
        cacheOwners = [userId, otherUserId]

        let cachedScore = makeBodyScoreResult(score: 91)
        let otherCachedScore = makeBodyScoreResult(score: 73)
        BodyScoreCache.shared.store(cachedScore, for: userId)
        BodyScoreCache.shared.store(otherCachedScore, for: otherUserId)

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [(weight: 79.0, date: Date())],
            bodyFatHistory: []
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertNil(BodyScoreCache.shared.latestResult(for: userId))
        XCTAssertEqual(BodyScoreCache.shared.latestResult(for: otherUserId), otherCachedScore)
    }

    func testObserverDebounceDoesNotBurnCooldownAfterAccountSwitch() async throws {
        let userA = "observer-owner-\(UUID().uuidString)"
        let userB = "observer-replacement-\(UUID().uuidString)"
        auth.authSession = .localFixture(subject: userA, email: "observer-owner@example.com")
        auth.currentUser = makeUser(id: userA, email: "observer-owner@example.com")
        let queries = ObserverQueryCounter()
        let manager = HealthKitManager(
            userDefaults: defaults,
            authManager: auth,
            coreDataManager: coreData,
            weightImportQuery: { _, _ in
                queries.value += 1
                return []
            },
            bodyFatImportQuery: { _ in [] },
            syncTrigger: {}
        )
        manager.isAuthorized = true
        defer { manager.syncDebounceTimer?.invalidate() }

        manager.scheduleObservedBodyMetricSync(for: userA, debounce: 0.05)
        auth.authSession = .localFixture(subject: userB, email: "observer-replacement@example.com")
        auth.currentUser = makeUser(id: userB, email: "observer-replacement@example.com")
        try await Task.sleep(nanoseconds: 500_000_000)

        let ownerKey = HealthKitDefaultsKey.lastObserverSyncDate.scoped(with: userA)
        XCTAssertNil(defaults.object(forKey: ownerKey))
        XCTAssertEqual(queries.value, 0)
    }

    func testObserverDebounceSyncsWhileTheSchedulingAccountStaysSignedIn() async throws {
        let userA = "observer-stays-\(UUID().uuidString)"
        auth.authSession = .localFixture(subject: userA, email: "observer-stays@example.com")
        auth.currentUser = makeUser(id: userA, email: "observer-stays@example.com")
        let queries = ObserverQueryCounter()
        let manager = HealthKitManager(
            userDefaults: defaults,
            authManager: auth,
            coreDataManager: coreData,
            weightImportQuery: { _, _ in
                queries.value += 1
                return []
            },
            bodyFatImportQuery: { _ in [] },
            syncTrigger: {}
        )
        manager.isAuthorized = true
        defer { manager.syncDebounceTimer?.invalidate() }

        manager.scheduleObservedBodyMetricSync(for: userA, debounce: 0.05)
        try await Task.sleep(nanoseconds: 500_000_000)

        let ownerKey = HealthKitDefaultsKey.lastObserverSyncDate.scoped(with: userA)
        XCTAssertNotNil(defaults.object(forKey: ownerKey))
        XCTAssertEqual(queries.value, 1)
    }

    private func makeUser(id: String, email: String) -> LocalUser {
        LocalUser(
            id: id,
            email: email,
            name: "HealthKit BodyScore Cache",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
    }

    private func makeBodyMetrics(userId: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "existing-healthkit-cache",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeBodyScoreResult(score: Int) -> BodyScoreResult {
        BodyScoreResult(
            score: score,
            ffmi: Double(score) / 10,
            leanPercentile: Double(score),
            ffmiStatus: "Athletic",
            bodyFatReferenceRange: .init(lowerBound: 8, upperBound: 12, label: "Lean"),
            statusTagline: "HealthKit cache fixture"
        )
    }
}
