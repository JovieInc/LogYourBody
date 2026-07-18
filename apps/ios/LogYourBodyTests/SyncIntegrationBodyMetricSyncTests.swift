//
// SyncIntegrationBodyMetricSyncTests.swift
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
final class SyncIntegrationBodyMetricSyncTests: XCTestCase {
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

    func testProcessBatchHealthKitData_DeduplicatesLateNightWeightsAndPreservesLocalDate() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_late_night_dedup_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_late_night@example.com",
            name: "HK Late Night",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let firstDate = calendar.date(byAdding: DateComponents(hour: 23, minute: 30), to: day) ?? day
        let duplicateDate = calendar.date(byAdding: DateComponents(hour: 23, minute: 55), to: day) ?? day
        let expectedLocalDate = BodyMetricLocalDate.key(for: firstDate)

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                (weight: 84.0, date: firstDate),
                (weight: 84.3, date: duplicateDate)
            ],
            bodyFatHistory: []
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.weight, 84.0)
        XCTAssertEqual(metric.localDate, expectedLocalDate)
        XCTAssertEqual(BodyMetricLocalDate.hourKey(for: metric.date), "23")
    }

    func testProcessBatchHealthKitData_PairsBodyFatByLocalDateAcrossMidnight() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_midnight_pairing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_midnight_pairing@example.com",
            name: "HK Midnight Pairing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let lateNightWeight = calendar.date(byAdding: DateComponents(hour: 23, minute: 30), to: day) ?? day
        let duplicateLateNightWeight = calendar.date(byAdding: DateComponents(hour: 23, minute: 55), to: day) ?? day
        let sameLocalDateBodyFat = calendar.date(byAdding: DateComponents(hour: 23, minute: 45), to: day) ?? day
        let nextDayWeight = calendar.date(byAdding: DateComponents(day: 1, hour: 0, minute: 10), to: day) ?? day
        let nextLocalDateBodyFat = calendar.date(byAdding: DateComponents(day: 1, hour: 0, minute: 5), to: day) ?? day

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: [
                (weight: 84.0, date: lateNightWeight),
                (weight: 84.3, date: duplicateLateNightWeight),
                (weight: 83.8, date: nextDayWeight)
            ],
            bodyFatHistory: [
                (percentage: 18.2, date: sameLocalDateBodyFat),
                (percentage: 22.5, date: nextLocalDateBodyFat)
            ]
        )

        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)

        let lateNightLocalDate = BodyMetricLocalDate.key(for: lateNightWeight)
        let nextLocalDate = BodyMetricLocalDate.key(for: nextDayWeight)

        let lateNightMetric = try XCTUnwrap(metrics.first { $0.localDate == lateNightLocalDate })
        XCTAssertEqual(lateNightMetric.weight, 84.0)
        XCTAssertEqual(lateNightMetric.bodyFatPercentage, 18.2)
        XCTAssertEqual(lateNightMetric.bodyFatMethod, "HealthKit")

        let nextDayMetric = try XCTUnwrap(metrics.first { $0.localDate == nextLocalDate })
        XCTAssertEqual(nextDayMetric.weight, 83.8)
        XCTAssertEqual(nextDayMetric.bodyFatPercentage, 22.5)
        XCTAssertEqual(nextDayMetric.bodyFatMethod, "HealthKit")
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksBodyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 80.5,
            weightUnit: "kg",
            bodyFatPercentage: 18.2,
            bodyFatMethod: "manual",
            muscleMass: 35.0,
            boneMass: 4.2,
            notes: "unsynced-local",
            photoUrl: "https://example.com/photo.jpg",
            dataSource: "Manual",
            sourceMetadata: BodyMetricSourceMetadata(
                legacyDataSource: "Manual"
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await Task.detached {
            try await manager.syncLocalChanges(token: "test-token")
        }.value

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        guard let batch = stubSupabase.bodyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No body metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        let payloadWeight = try XCTUnwrap(payload["weight"] as? Double)
        XCTAssertEqual(payloadWeight, 80.5, accuracy: 0.001)

        XCTAssertEqual(payload["weight_unit"] as? String, "kg")
        XCTAssertEqual(payload["photo_url"] as? String, "https://example.com/photo.jpg")
        XCTAssertEqual(payload["notes"] as? String, "unsynced-local")
        XCTAssertEqual(payload["data_source"] as? String, "manual")

        let sourceMetadata = try XCTUnwrap(payload["source_metadata"] as? [String: String])
        XCTAssertEqual(sourceMetadata["legacy_data_source"], "Manual")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.bodyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChangesScopesUnsyncedRowsToActiveUser() async throws {
        let coreData = CoreDataManager.shared

        let activeUserId = "sync_active_user_\(UUID().uuidString)"
        let otherUserId = "sync_other_user_\(UUID().uuidString)"
        let activeMetricId = UUID().uuidString
        let otherMetricId = UUID().uuidString
        let date = Date()

        let activeMetric = BodyMetrics(
            id: activeMetricId,
            userId: activeUserId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
        let otherMetric = BodyMetrics(
            id: otherMetricId,
            userId: otherUserId,
            date: date,
            weight: 82.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        try await coreData.saveBodyMetricsAndWait(activeMetric, userId: activeUserId)
        try await coreData.saveBodyMetricsAndWait(otherMetric, userId: otherUserId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(for: activeUserId, token: "test-token")

        let syncedPayloads = stubSupabase.bodyMetricsBatches.flatMap { $0 }
        XCTAssertEqual(syncedPayloads.count, 1)
        XCTAssertEqual(syncedPayloads.first?["id"] as? String, activeMetricId)
        XCTAssertEqual(syncedPayloads.first?["user_id"] as? String, activeUserId)

        let activeUnsynced = await coreData.fetchUnsyncedEntries(for: activeUserId)
        XCTAssertTrue(activeUnsynced.bodyMetrics.isEmpty)

        let otherUnsynced = await coreData.fetchUnsyncedEntries(for: otherUserId)
        XCTAssertEqual(otherUnsynced.bodyMetrics.map(\.id), [otherMetricId])
    }

    func testPendingSyncOperationsAreScopedToActiveUser() async throws {
        UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        defer {
            UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        }

        let activeUserId = "pending_active_user_\(UUID().uuidString)"
        let otherUserId = "pending_other_user_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: activeUserId,
            email: "pending-active@example.com",
            name: "Pending Active",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        authManager.isAuthenticated = true

        let manager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )
        manager.isOnline = false

        manager.queueOperation(
            RealtimeSyncManager.SyncOperation(
                id: UUID().uuidString,
                userId: otherUserId,
                type: .delete,
                data: Data(),
                tableName: "body_metrics",
                timestamp: Date()
            )
        )
        let hasOtherUserPendingOperations = await manager.hasPendingSyncOperations()
        XCTAssertFalse(hasOtherUserPendingOperations)

        manager.queueOperation(
            RealtimeSyncManager.SyncOperation(
                id: UUID().uuidString,
                userId: activeUserId,
                type: .delete,
                data: Data(),
                tableName: "body_metrics",
                timestamp: Date()
            )
        )
        let hasActiveUserPendingOperations = await manager.hasPendingSyncOperations()
        XCTAssertTrue(hasActiveUserPendingOperations)
    }

    func testSyncAllRequeuesPendingOperationsWhenTokenIsUnavailable() async throws {
        UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        defer {
            UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        }

        let userId = "retry_pending_operation_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId,
            email: "retry@example.com",
            name: "Retry User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        authManager.isAuthenticated = true

        let manager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )
        manager.isOnline = false
        let operation = RealtimeSyncManager.SyncOperation(
            id: UUID().uuidString,
            userId: userId,
            type: .delete,
            data: Data(),
            tableName: "body_metrics",
            timestamp: Date()
        )
        let unidentifiedOperation = RealtimeSyncManager.SyncOperation(
            id: UUID().uuidString,
            userId: nil,
            type: .delete,
            data: Data(),
            tableName: "body_metrics",
            timestamp: Date()
        )
        manager.queueOperation(operation)
        manager.queueOperation(unidentifiedOperation)
        manager.isOnline = true

        await manager.syncAllAwaitingCompletion()

        XCTAssertFalse(manager.isSyncing)
        guard case .error = manager.syncStatus else {
            XCTFail("Expected sync to report an authentication error")
            return
        }
        XCTAssertEqual(
            Set(manager.pendingOperations.map(\.id)),
            Set([operation.id, unidentifiedOperation.id])
        )
        XCTAssertEqual(manager.pendingOperations.first?.retryCount, 0)

        let persistedData = try XCTUnwrap(
            UserDefaults.standard.data(forKey: "pendingSyncOperations")
        )
        let persistedOperations = try JSONDecoder().decode(
            [RealtimeSyncManager.SyncOperation].self,
            from: persistedData
        )
        XCTAssertEqual(
            Set(persistedOperations.map(\.id)),
            Set([operation.id, unidentifiedOperation.id])
        )
        XCTAssertTrue(persistedOperations.allSatisfy { $0.retryCount == 0 })
    }

    func testDeleteBodyMetricWithoutIdentifiedUserFailsBeforeQueuing() async {
        UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        defer {
            UserDefaults.standard.removeObject(forKey: "pendingSyncOperations")
        }

        let authManager = AuthManager()
        authManager.currentUser = nil
        authManager.isAuthenticated = false
        let manager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )

        let deleted = await manager.deleteBodyMetric(id: UUID().uuidString)

        XCTAssertFalse(deleted)
        XCTAssertTrue(manager.pendingOperations.isEmpty)
        XCTAssertNil(UserDefaults.standard.data(forKey: "pendingSyncOperations"))
    }

    func testSyncLocalChangesDeletesMarkedBodyMetricInsteadOfUpserting() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_deleted_realtime_\(UUID().uuidString)"
        let date = Date()

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
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date.addingTimeInterval(-60),
            updatedAt: date
        )

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId, markAsSynced: true)
        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: id)
        XCTAssertTrue(didMarkDeleted)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        XCTAssertEqual(stubSupabase.deletedRecords.count, 1)
        XCTAssertEqual(stubSupabase.deletedRecords.first?.table, "body_metrics")
        XCTAssertEqual(stubSupabase.deletedRecords.first?.id, id)

        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.bodyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChangesDiscardsEmptyPhotoPlaceholdersInsteadOfUpserting() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync_test_user_empty_photo_placeholder_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_600_000)

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )

        XCTAssertTrue(result.createdNewEntry)

        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertEqual(snapshot.bodyMetrics.map(\.id), [result.metrics.id])

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        XCTAssertTrue(stubSupabase.deletedRecords.isEmpty)
        let cachedMetric = await cachedBodyMetric(id: result.metrics.id)
        XCTAssertNil(cachedMetric)

        let pending = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertTrue(pending.bodyMetrics.isEmpty)
    }

    func testSyncLocalChangesSkipsInFlightPhotoPlaceholderWithoutDeleting() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync_test_user_in_flight_photo_placeholder_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_610_000)

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let markedInFlight = await coreData.markPhotoPlaceholderUploadInFlight(
            id: result.metrics.id,
            userId: userId
        )

        XCTAssertTrue(markedInFlight)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        XCTAssertTrue(stubSupabase.deletedRecords.isEmpty)
        let cachedMetric = await cachedBodyMetric(id: result.metrics.id)
        XCTAssertEqual(cachedMetric?.syncStatus, CoreDataManager.photoUploadInFlightSyncStatus)

        let pending = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertEqual(pending.bodyMetrics.map(\.id), [result.metrics.id])
    }

    func testSyncLocalChangesSkipsStorageCommittedPhotoPlaceholderWithoutDeleting() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync_test_user_committed_photo_placeholder_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_620_000)
        let storagePath = "\(userId)/committed-upload.png"

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let markedCommitted = await coreData.markPhotoUploadStorageCommitted(
            id: result.metrics.id,
            userId: userId,
            storagePath: storagePath
        )

        XCTAssertTrue(markedCommitted)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        XCTAssertTrue(stubSupabase.deletedRecords.isEmpty)
        let cachedMetric = await cachedBodyMetric(id: result.metrics.id)
        XCTAssertEqual(cachedMetric?.syncStatus, CoreDataManager.photoUploadStorageCommittedSyncStatus)
        XCTAssertEqual(cachedMetric?.originalPhotoUrl, storagePath)

        let pending = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertEqual(pending.bodyMetrics.map(\.id), [result.metrics.id])
    }

    func testSyncLocalChangesUpsertsCompletedPhotoAfterStorageCommit() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync_test_user_completed_photo_placeholder_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_630_000)
        let storagePath = "\(userId)/completed-upload.png"
        let processedUrl = "https://res.cloudinary.com/logyourbody/image/upload/completed.png"

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: date,
            userId: userId
        )
        let markedCommitted = await coreData.markPhotoUploadStorageCommitted(
            id: result.metrics.id,
            userId: userId,
            storagePath: storagePath
        )
        let didUpdatePhoto = try await coreData.updateBodyMetricPhoto(
            id: result.metrics.id,
            userId: userId,
            storagePath: storagePath,
            processedUrl: processedUrl
        )

        XCTAssertTrue(markedCommitted)
        XCTAssertTrue(didUpdatePhoto)

        let cachedBeforeSync = await cachedBodyMetric(id: result.metrics.id)
        XCTAssertEqual(cachedBeforeSync?.photoUrl, processedUrl)
        XCTAssertEqual(cachedBeforeSync?.syncStatus, "pending")

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        let payload = try XCTUnwrap(stubSupabase.bodyMetricsBatches.first?.first)
        XCTAssertEqual(payload["id"] as? String, result.metrics.id)
        XCTAssertEqual(payload["photo_url"] as? String, processedUrl)

        let cachedAfterSync = await cachedBodyMetric(id: result.metrics.id)
        XCTAssertEqual(cachedAfterSync?.syncStatus, "synced")
        XCTAssertEqual(cachedAfterSync?.photoUrl, processedUrl)
    }
}
