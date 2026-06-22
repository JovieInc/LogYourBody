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
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    private func wholeSecondDate(_ offset: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_735_000_000 + offset)
    }

    private func cachedBodyMetric(id: String) async -> CachedBodyMetrics? {
        let context = CoreDataManager.shared.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    private func cachedProfiles(id: String) async -> [CachedProfile] {
        let context = CoreDataManager.shared.viewContext

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

    func testUpdateOrCreateDailyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

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
        let coreData = CoreDataManager.shared

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
        let coreData = CoreDataManager.shared

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

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.profilePayloads.first)
        XCTAssertEqual(payload["id"] as? String, userId)
        XCTAssertNil(payload["height"])
        XCTAssertEqual(payload["height_unit"] as? String, "cm")

        let profiles = await cachedProfiles(id: userId)
        let cachedProfile = try XCTUnwrap(profiles.first)
        XCTAssertTrue(cachedProfile.isSynced)
        XCTAssertEqual(cachedProfile.syncStatus, "synced")
    }

    func testUpdateOrCreateBodyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

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
        let coreData = CoreDataManager.shared

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
        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: id)
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
        let coreData = CoreDataManager.shared

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
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_existing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_existing@example.com",
            name: "HK Existing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_batch_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_batch@example.com",
            name: "HK Batch",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_bodyfat_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_bodyfat@example.com",
            name: "HK BodyFat",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_metadata_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_metadata@example.com",
            name: "HK Metadata",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
