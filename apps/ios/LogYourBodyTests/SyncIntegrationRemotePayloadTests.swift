//
// SyncIntegrationRemotePayloadTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

@MainActor
final class SyncIntegrationRemotePayloadTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private var networkSession: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "SyncIntegrationRemotePayloadTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        networkSession = URLSession(configuration: configuration)
        auth = AuthManager(userDefaults: defaults, urlSession: networkSession)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        auth = nil
        coreData = nil
        defaults = nil
        networkSession?.invalidateAndCancel()
        networkSession = nil
        try await super.tearDown()
    }

    private func healthKitManager() -> HealthKitManager {
        HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            syncTrigger: {}, importCompletion: { _ in }
        )
    }

    private func setAccount(_ user: LocalUser) {
        auth.authSession = .localFixture(subject: user.id, email: user.email, accessToken: "synthetic")
        auth.currentUser = user
    }

    private func wholeSecondDate(_ offset: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_735_000_000 + offset)
    }

    private func cachedBodyMetric(id: String) async -> CachedBodyMetrics? {
        let context = coreData.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    private func cachedProfiles(id: String) async -> [CachedProfile] {
        let context = coreData.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)

            return (try? context.fetch(request)) ?? []
        }
    }

    private func makeBodySpecSummary(
        resultId: String,
        startTime: Date,
        serviceId: String = "svc-dxa"
    ) -> BodySpecResultSummary {
        BodySpecResultSummary(
            resultId: resultId,
            startTime: startTime,
            location: BodySpecLocation(locationId: "loc-santa-monica", name: "Santa Monica"),
            service: BodySpecService(
                name: "DEXA",
                description: "DEXA scan",
                serviceId: serviceId,
                serviceCode: "DXA"
            )
        )
    }

    private func makeBodySpecComposition(resultId: String) -> BodySpecDexaCompositionResponse {
        BodySpecDexaCompositionResponse(
            resultId: resultId,
            total: BodySpecBodyRegion(
                fatMassKg: 14.0,
                leanMassKg: 62.0,
                boneMassKg: 3.2,
                totalMassKg: 79.2,
                tissueFatPct: 18.4,
                regionFatPct: 17.7
            )
        )
    }

    func testUpdateOrCreateDailyMetric_MapsProductAPIPayload() async throws {
        let coreData = self.coreData!

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_\(UUID().uuidString)"
        let date = wholeSecondDate(1_000)
        let createdAt = date.addingTimeInterval(-120)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "steps": 10_000,
            "notes": "daily-metrics-mapped",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateDailyMetric(from: payload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.date.timeIntervalSince(date), 0, accuracy: 0.001)
        XCTAssertEqual(log.stepCount, 10_000)
        XCTAssertEqual(log.notes, "daily-metrics-mapped")
        XCTAssertEqual(log.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateProfile_IsIdempotentForSameId() async throws {
        let coreData = self.coreData!

        let userId = "sync_test_user_profile_\(UUID().uuidString)"
        let firstPayload: [String: Any] = [
            "id": userId,
            "full_name": "First Name",
            "username": "first_name",
            "height": 178.0,
            "height_unit": "cm",
            "gender": "male",
            "activity_level": "active",
            "date_of_birth": "1990-01-01T00:00:00Z"
        ]
        let secondPayload: [String: Any] = [
            "id": userId,
            "full_name": "Updated Name",
            "username": "updated_name",
            "height": 181.0,
            "height_unit": "cm",
            "gender": "male",
            "activity_level": "active",
            "date_of_birth": "1990-01-01T00:00:00Z"
        ]

        coreData.updateOrCreateProfile(from: firstPayload)
        coreData.updateOrCreateProfile(from: secondPayload)

        let profiles = await cachedProfiles(id: userId)
        XCTAssertEqual(profiles.count, 1)

        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(profile.id, userId)
        XCTAssertEqual(profile.fullName, "Updated Name")
        XCTAssertEqual(profile.username, "updated_name")
        XCTAssertEqual(profile.height, 181.0, accuracy: 0.001)
        XCTAssertEqual(profile.syncStatus, "synced")
        XCTAssertTrue(profile.isSynced)
    }

    func testSyncLocalChanges_OmitsMissingProfileHeight() async throws {
        let coreData = self.coreData!

        let userId = "sync_test_user_profile_no_height_\(UUID().uuidString)"
        let profile = UserProfile(
            id: userId,
            email: "profile-no-height@example.com",
            username: "profile_no_height",
            fullName: "Profile No Height",
            dateOfBirth: nil,
            height: nil,
            heightUnit: "cm",
            gender: "male",
            activityLevel: "active",
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )

        coreData.saveProfile(
            profile,
            userId: userId,
            email: "profile-no-height@example.com",
            markSynced: false
        )

        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        let pendingProfile = try XCTUnwrap(snapshot.profiles.first { $0.id == userId })
        XCTAssertNil(pendingProfile.height)

        let stubProductAPI = StubProductAPIClient()
        stubProductAPI.session = networkSession
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: auth,
            productAPIClient: stubProductAPI
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubProductAPI.profilePayloads.first)
        XCTAssertEqual(payload["id"] as? String, userId)
        XCTAssertNil(payload["height"])
        XCTAssertEqual(payload["height_unit"] as? String, "cm")

        let profiles = await cachedProfiles(id: userId)
        let cachedProfile = try XCTUnwrap(profiles.first)
        XCTAssertTrue(cachedProfile.isSynced)
        XCTAssertEqual(cachedProfile.syncStatus, "synced")
    }

    func testUpdateOrCreateBodyMetric_PreservesDateWhenServerSendsFractionalISO8601() async throws {
        let coreData = self.coreData!
        let id = UUID().uuidString
        let userId = "sync_test_user_fractional_iso_\(UUID().uuidString)"
        let measuredAt = Date(timeIntervalSince1970: 1_776_082_500) // 2026-04-13T12:15:00Z
        try await coreData.saveBodyMetricsAndWait(
            BodyMetrics(
                id: id,
                userId: userId,
                date: measuredAt,
                localDate: "2026-04-13",
                weight: 82.7,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: BodyMetricSource.manual.rawValue,
                createdAt: measuredAt,
                updatedAt: measuredAt
            ),
            userId: userId
        )

        coreData.updateOrCreateBodyMetric(from: [
            "id": id,
            "user_id": userId,
            "date": "2026-04-13T12:15:00.000Z",
            "local_date": "2026-04-13",
            "weight": 82.7,
            "weight_unit": "kg",
            "created_at": "2026-04-13T12:15:00.000Z",
            "updated_at": "2026-04-13T12:15:00.000Z"
        ])

        var stored: CachedBodyMetrics?
        for _ in 0..<20 {
            stored = await cachedBodyMetric(id: id)
            if stored?.date != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let persisted = try XCTUnwrap(stored)
        let parsed = try XCTUnwrap(persisted.date)
        XCTAssertEqual(parsed.timeIntervalSince1970, measuredAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNotNil(persisted.toBodyMetrics())
        let parsedFractional = try XCTUnwrap(
            BodyMetricSyncDateParser.date(from: "2026-04-13T12:15:00.000Z")
        )
        XCTAssertEqual(
            parsedFractional.timeIntervalSince1970,
            measuredAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testUpdateOrCreateBodyMetric_IsIdempotentForSameId() async throws {
        let coreData = self.coreData!

        let id = UUID().uuidString
        let userId = "sync_test_user_body_idempotent_\(UUID().uuidString)"
        let date = wholeSecondDate(2_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight_unit": "kg",
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["weight"] = 75.0
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["weight"] = 82.0
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateBodyMetric(from: firstPayload)
        coreData.updateOrCreateBodyMetric(from: secondPayload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 82.0, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateBodyMetric_DoesNotOverwriteDeletedLocalTombstone() async throws {
        let coreData = self.coreData!

        let id = UUID().uuidString
        let userId = "sync_test_user_body_deleted_payload_\(UUID().uuidString)"
        let date = wholeSecondDate(2_500)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt = date.addingTimeInterval(-120)

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "local-tombstone",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId, markAsSynced: true)
        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: id, userId: userId)
        XCTAssertTrue(didMarkDeleted)

        let formatter = ISO8601DateFormatter()
        let serverDate = date.addingTimeInterval(60)
        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: serverDate),
            "weight": 99.0,
            "weight_unit": "kg",
            "notes": "server-resurrection",
            "data_source": "manual",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: serverDate)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let tombstoneResult = await cachedBodyMetric(id: id)
        let tombstone = try XCTUnwrap(tombstoneResult)
        XCTAssertTrue(tombstone.isMarkedDeleted)
        XCTAssertFalse(tombstone.isSynced)
        XCTAssertEqual(tombstone.syncStatus, "pending")
        XCTAssertEqual(tombstone.notes, "local-tombstone")
        XCTAssertEqual(tombstone.weight, 81.0, accuracy: 0.001)
        let tombstoneDate = try XCTUnwrap(tombstone.date)
        XCTAssertEqual(tombstoneDate.timeIntervalSince(date), 0, accuracy: 0.001)

        let visibleMetrics = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertFalse(visibleMetrics.contains { $0.id == id })

        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertEqual(unsynced.bodyMetrics.map(\.id), [id])
        XCTAssertTrue(unsynced.bodyMetrics.allSatisfy(\.isMarkedDeleted))
    }

    func testUpdateOrCreateDailyMetric_IsIdempotentForSameId() async throws {
        let coreData = self.coreData!

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_idempotent_\(UUID().uuidString)"
        let date = wholeSecondDate(3_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["steps"] = 5_000
        firstPayload["notes"] = "first"
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["steps"] = 12_000
        secondPayload["notes"] = "second"
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateDailyMetric(from: firstPayload)
        coreData.updateOrCreateDailyMetric(from: secondPayload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.stepCount, 12_000)
        XCTAssertEqual(log.notes, "second")
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testProcessBatchHealthKitData_RespectsExistingEntriesWithinSameHour() async throws {
        let coreData = self.coreData!
        let healthKitManager = healthKitManager()

        let userId = "healthkit_test_user_existing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_existing@example.com",
            name: "HK Existing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        setAccount(user)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let existingDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 45), to: day) ?? day

        let existingMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: existingDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "existing-healthkit",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: existingDate,
            updatedAt: existingDate
        )

        try await coreData.saveBodyMetricsAndWait(existingMetric, userId: userId)

        let sameHourDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 15), to: day) ?? day
        let nextHourDate = calendar.date(byAdding: DateComponents(hour: 11, minute: 5), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 81.0, date: sameHourDate),
            (weight: 82.0, date: nextHourDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics.filter { $0.dataSource == "manual" }.count, 1)
        XCTAssertEqual(metrics.filter { $0.dataSource == "healthkit" }.count, 1)

        let manualMetric = try XCTUnwrap(metrics.first { $0.dataSource == "manual" })
        XCTAssertEqual(manualMetric.weight, 80.0)
        XCTAssertEqual(manualMetric.notes, "existing-healthkit")
    }

    func testProcessBatchHealthKitData_DeduplicatesMultipleWeightsInSameHour() async throws {
        let coreData = self.coreData!
        let healthKitManager = healthKitManager()

        let userId = "healthkit_test_user_batch_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_batch@example.com",
            name: "HK Batch",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        setAccount(user)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let firstDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 5), to: day) ?? day
        let secondDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 50), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 70.0, date: firstDate),
            (weight: 71.0, date: secondDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
    }

    func testProcessBatchHealthKitData_AssignsBodyFatForMatchingDate() async throws {
        let coreData = self.coreData!
        let healthKitManager = healthKitManager()

        let userId = "healthkit_test_user_bodyfat_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_bodyfat@example.com",
            name: "HK BodyFat",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        setAccount(user)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let weightDate = calendar.date(byAdding: DateComponents(hour: 8, minute: 0), to: day) ?? day
        let bodyFatDate = calendar.date(byAdding: DateComponents(hour: 6, minute: 30), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 75.0, date: weightDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = [
            (percentage: 19.5, date: bodyFatDate)
        ]

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 19.5, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "HealthKit")
        XCTAssertEqual(metric.dataSource, "healthkit")
    }

    func testProcessBatchHealthKitData_AttachesSourceMetadataToImportedMetrics() async throws {
        let coreData = self.coreData!
        let healthKitManager = healthKitManager()

        let userId = "healthkit_test_user_metadata_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_metadata@example.com",
            name: "HK Metadata",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        setAccount(user)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let weightDate = calendar.date(byAdding: DateComponents(hour: 7, minute: 10), to: day) ?? day
        let bodyFatDate = calendar.date(byAdding: DateComponents(hour: 7, minute: 12), to: day) ?? day

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                HealthKitWeightImportSample(
                    weight: 76.5,
                    date: weightDate,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health",
                        sourceName: "Apple Health",
                        sourceBundleId: "com.apple.Health",
                        deviceId: "scale-local-id",
                        deviceManufacturer: "Withings",
                        deviceModel: "Body Scan",
                        sampleId: "weight-sample-123",
                        quantityType: "HKQuantityTypeIdentifierBodyMass"
                    )
                )
            ],
            bodyFatHistory: [
                HealthKitBodyFatImportSample(
                    percentage: 18.4,
                    date: bodyFatDate,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "apple_health",
                        sourceName: "Apple Health",
                        sourceBundleId: "com.apple.Health",
                        sampleId: "body-fat-sample-456",
                        quantityType: "HKQuantityTypeIdentifierBodyFatPercentage"
                    )
                )
            ]
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        let metric = try XCTUnwrap(metrics.first)
        let sourceMetadata = try XCTUnwrap(metric.sourceMetadata)
        XCTAssertEqual(metric.dataSource, "healthkit")
        XCTAssertEqual(metric.bodyFatPercentage, 18.4)
        XCTAssertEqual(sourceMetadata.vendor, "apple_health")
        XCTAssertEqual(sourceMetadata.sourceName, "Apple Health")
        XCTAssertEqual(sourceMetadata.sourceBundleId, "com.apple.Health")
        XCTAssertEqual(sourceMetadata.deviceId, "scale-local-id")
        XCTAssertEqual(sourceMetadata.deviceManufacturer, "Withings")
        XCTAssertEqual(sourceMetadata.deviceModel, "Body Scan")
        XCTAssertEqual(sourceMetadata.sampleId, "weight-sample-123")
        XCTAssertEqual(sourceMetadata.bodyFatSampleId, "body-fat-sample-456")
        XCTAssertEqual(sourceMetadata.quantityType, "HKQuantityTypeIdentifierBodyMass")
    }
}

extension SyncIntegrationRemotePayloadTests {
    func testBodyApplyStalePayloadCompletesOnceWithoutChangingStoredRow() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionBody(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateBodyMetric(from: [
                "id": id, "user_id": "completion-owner", "weight": 99.0, "notes": "stale",
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(-60))
            ], completion: done)
        }
        let after = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
        XCTAssertEqual(after, before)
    }

    func testBodyApplyForeignOwnerAndDeletedRowsCompleteOnceWithoutChangingStorage() async throws {
        for deleted in [false, true] {
            let id = UUID().uuidString
            let before = try await seedCompletionBody(id: id, deleted: deleted)
            await assertApplyCompletesOnce { done in
                coreData.updateOrCreateBodyMetric(from: [
                    "id": id, "user_id": deleted ? "completion-owner" : "different-owner",
                    "weight": 99.0, "notes": "rejected",
                    "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(60))
                ], completion: done)
            }
            let after = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
            XCTAssertEqual(after, before)
        }
    }

    func testBodyApplyAdmissionRejectionCompletesOnceWithoutInserting() async throws {
        let id = UUID().uuidString
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateBodyMetric(
                from: ["id": id, "user_id": "completion-owner", "weight": 80.0],
                writeAdmission: { throw CancellationError() }, completion: done
            )
        }
        let row = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
        XCTAssertNil(row)
    }

    func testBodyApplyAcceptedPayloadCompletesOnceAndAppliesValues() async throws {
        let id = UUID().uuidString
        _ = try await seedCompletionBody(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateBodyMetric(from: [
                "id": id, "user_id": "completion-owner", "weight": 80.0, "weight_unit": "kg",
                "body_fat_percentage": 18.4, "notes": "accepted",
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(60))
            ], completion: done)
        }
        let row = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
        XCTAssertEqual(row?["weight"] as? Double, 80)
        XCTAssertEqual(row?["bodyFatPercentage"] as? Double, 18.4)
        XCTAssertEqual(row?["notes"] as? String, "accepted")
    }

    func testSkippedBodyAsyncApplyAllowsNextBatchRecord() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionBody(id: id)
        let nextID = UUID().uuidString
        let finished = expectation(description: "Stale body apply returns to the batch")
        let store = coreData!
        let stale = ISO8601DateFormatter().string(from: wholeSecondDate(-60))
        let nextDate = ISO8601DateFormatter().string(from: wholeSecondDate(60))
        Task { @MainActor in
            await store.updateOrCreateBodyMetricAndWait(from: [
                "id": id, "user_id": "completion-owner", "weight": 99.0, "updated_at": stale
            ])
            await store.updateOrCreateBodyMetricAndWait(from: [
                "id": nextID, "user_id": "completion-owner", "weight": 80.0, "weight_unit": "kg",
                "date": nextDate, "created_at": nextDate, "updated_at": nextDate
            ])
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        let after = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
        let next = try await completionStoredRow(entity: "CachedBodyMetrics", id: nextID)
        XCTAssertEqual(after, before)
        XCTAssertEqual(next?["weight"] as? Double, 80)
    }

    func testDailyApplyStalePayloadCompletesOnceWithoutChangingStoredRow() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionDaily(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateDailyMetric(from: [
                "id": id, "user_id": "completion-owner", "steps": 7, "notes": "stale",
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(-60))
            ], completion: done)
        }
        let after = try await completionStoredRow(entity: "CachedDailyMetrics", id: id)
        XCTAssertEqual(after, before)
    }

    func testDailyApplyForeignOwnerCompletesOnceWithoutChangingStoredRow() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionDaily(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateDailyMetric(from: [
                "id": id, "user_id": "different-owner", "steps": 7, "notes": "foreign",
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(60))
            ], completion: done)
        }
        let after = try await completionStoredRow(entity: "CachedDailyMetrics", id: id)
        XCTAssertEqual(after, before)
    }

    func testProfileApplyStalePayloadCompletesOnceWithoutChangingStoredRow() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionProfile(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateProfile(from: [
                "id": id, "full_name": "Stale profile", "height": 1,
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(-60))
            ], completion: done)
        }
        let after = try await completionStoredRow(entity: "CachedProfile", id: id)
        XCTAssertEqual(after, before)
    }

    func testDailyAndProfileAdmissionRejectionCompleteOnceWithoutInserting() async throws {
        let dailyID = UUID().uuidString
        let profileID = UUID().uuidString
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateDailyMetric(
                from: ["id": dailyID, "user_id": "completion-owner", "steps": 123],
                writeAdmission: { throw CancellationError() }, completion: done
            )
        }
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateProfile(
                from: ["id": profileID, "full_name": "Rejected"],
                writeAdmission: { throw CancellationError() }, completion: done
            )
        }
        let daily = try await completionStoredRow(entity: "CachedDailyMetrics", id: dailyID)
        let profile = try await completionStoredRow(entity: "CachedProfile", id: profileID)
        XCTAssertNil(daily)
        XCTAssertNil(profile)
    }

    func testDailyApplyInvalidStepsCompletesOnceWithoutChangingStoredRow() async throws {
        let id = UUID().uuidString
        let before = try await seedCompletionDaily(id: id)
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateDailyMetric(from: [
                "id": id, "user_id": "completion-owner", "steps": -1,
                "updated_at": ISO8601DateFormatter().string(from: wholeSecondDate(60))
            ], completion: done)
        }
        let after = try await completionStoredRow(entity: "CachedDailyMetrics", id: id)
        XCTAssertEqual(after, before)
    }

    func testDailyAndProfileAcceptedPayloadsCompleteOnceAndApplyValues() async throws {
        let dailyID = UUID().uuidString
        let profileID = UUID().uuidString
        _ = try await seedCompletionDaily(id: dailyID)
        _ = try await seedCompletionProfile(id: profileID)
        let updated = ISO8601DateFormatter().string(from: wholeSecondDate(60))
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateDailyMetric(from: [
                "id": dailyID, "user_id": "completion-owner", "steps": 123, "notes": "accepted",
                "updated_at": updated
            ], completion: done)
        }
        await assertApplyCompletesOnce { done in
            coreData.updateOrCreateProfile(from: [
                "id": profileID, "full_name": "Accepted profile", "height": 180.0, "updated_at": updated
            ], completion: done)
        }
        let daily = try await completionStoredRow(entity: "CachedDailyMetrics", id: dailyID)
        let profile = try await completionStoredRow(entity: "CachedProfile", id: profileID)
        XCTAssertEqual(daily?["steps"] as? Int, 123)
        XCTAssertEqual(daily?["notes"] as? String, "accepted")
        XCTAssertEqual(profile?["fullName"] as? String, "Accepted profile")
        XCTAssertEqual(profile?["height"] as? Double, 180)
    }

    func testSkippedDailyAndProfileAsyncAppliesAllowNextBatchRecord() async throws {
        let dailyID = UUID().uuidString
        let profileID = UUID().uuidString
        _ = try await seedCompletionDaily(id: dailyID)
        _ = try await seedCompletionProfile(id: profileID)
        let finished = expectation(description: "All rejected applies returned to the batch")
        let store = coreData!
        let stale = ISO8601DateFormatter().string(from: wholeSecondDate(-60))
        let nextID = UUID().uuidString
        let nextDate = ISO8601DateFormatter().string(from: wholeSecondDate(60))
        Task { @MainActor in
            await store.updateOrCreateDailyMetricAndWait(from: [
                "id": dailyID, "user_id": "completion-owner", "steps": 7, "updated_at": stale
            ])
            await store.updateOrCreateDailyMetricAndWait(from: [
                "id": dailyID, "user_id": "different-owner", "steps": 7
            ])
            await store.updateOrCreateProfileAndWait(from: ["id": profileID, "updated_at": stale])
            await store.updateOrCreateDailyMetricAndWait(from: [
                "id": nextID, "user_id": "completion-owner", "steps": 456,
                "date": nextDate, "created_at": nextDate, "updated_at": nextDate
            ])
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        let next = try await completionStoredRow(entity: "CachedDailyMetrics", id: nextID)
        XCTAssertEqual(next?["steps"] as? Int, 456)
    }

    private func assertApplyCompletesOnce(_ apply: (@escaping () -> Void) -> Void) async {
        let completed = expectation(description: "Remote apply completion")
        completed.assertForOverFulfill = true
        var calls = 0
        apply {
            calls += 1
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2)
        await coreData.viewContext.perform { }
        XCTAssertEqual(calls, 1)
    }

    private func seedCompletionDaily(id: String) async throws -> NSDictionary {
        let context = coreData.viewContext
        let date = wholeSecondDate()
        try await context.perform {
            let row = CachedDailyMetrics(context: context)
            row.id = id
            row.userId = "completion-owner"
            row.date = date
            row.steps = 8_765
            row.notes = "Keep these notes"
            row.createdAt = date.addingTimeInterval(-300)
            row.updatedAt = date
            row.lastModified = date
            row.syncStatus = "pending"
            row.isSynced = false
            try context.save()
        }
        let saved = try await completionStoredRow(entity: "CachedDailyMetrics", id: id)
        return try XCTUnwrap(saved)
    }

    private func seedCompletionBody(id: String, deleted: Bool = false) async throws -> NSDictionary {
        let context = coreData.viewContext
        let date = wholeSecondDate()
        try await context.perform {
            let row = CachedBodyMetrics(context: context)
            row.id = id
            row.userId = "completion-owner"
            row.date = date
            row.weight = 81
            row.weightUnit = "kg"
            row.bodyFatPercentage = 19.5
            row.notes = "Keep these notes"
            row.createdAt = date.addingTimeInterval(-300)
            row.updatedAt = date
            row.lastModified = date
            row.syncStatus = "pending"
            row.isSynced = false
            row.isMarkedDeleted = deleted
            try context.save()
        }
        let saved = try await completionStoredRow(entity: "CachedBodyMetrics", id: id)
        return try XCTUnwrap(saved)
    }

    private func seedCompletionProfile(id: String) async throws -> NSDictionary {
        let context = coreData.viewContext
        let date = wholeSecondDate()
        try await context.perform {
            let row = CachedProfile(context: context)
            row.id = id
            row.fullName = "Keep this profile"
            row.email = "completion-owner@example.com"
            row.createdAt = date.addingTimeInterval(-300)
            row.height = 180
            row.updatedAt = date
            row.lastModified = date
            row.syncStatus = "pending"
            row.isSynced = false
            try context.save()
        }
        let saved = try await completionStoredRow(entity: "CachedProfile", id: id)
        return try XCTUnwrap(saved)
    }

    private func completionStoredRow(entity: String, id: String) async throws -> NSDictionary? {
        let context = coreData.viewContext
        return try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "id == %@", id)
            let rows = try context.fetch(request)
            XCTAssertLessThanOrEqual(rows.count, 1)
            return rows.first.map { $0.dictionaryWithValues(forKeys: Array($0.entity.attributesByName.keys)) as NSDictionary }
        }
    }
}
