//
// BodyMetricContractTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
@testable import LogYourBody

@MainActor
final class BodyMetricContractTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testMarkAsSyncedDoesNotAcknowledgeANewerLocalEdit() async throws {
        let userId = "sync-ack-edit-\(UUID().uuidString)"
        let metricId = UUID().uuidString
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 80, notes: "uploaded"),
            userId: userId
        )
        _ = try await CoreDataManager.shared.fetchPendingLocalSyncSnapshot(for: userId)

        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 81, notes: "edited-after-upload"),
            userId: userId
        )
        await CoreDataManager.shared.markAsSynced(entityName: "CachedBodyMetrics", ids: [metricId])

        let stored = try await syncState(id: metricId)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "pending")
        XCTAssertEqual(stored.weight, 81, accuracy: 0.001)
        XCTAssertEqual(stored.notes, "edited-after-upload")
    }

    func testMarkAsSyncedIgnoresAResponseIdAbsentFromTheSnapshot() async throws {
        let userId = "sync-ack-extra-\(UUID().uuidString)"
        let uploadedId = UUID().uuidString
        let laterId = UUID().uuidString
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: uploadedId, userId: userId, weight: 70, notes: "in-snapshot"),
            userId: userId
        )
        _ = try await CoreDataManager.shared.fetchPendingLocalSyncSnapshot(for: userId)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: laterId, userId: userId, weight: 71, notes: "saved-after-snapshot"),
            userId: userId
        )

        await CoreDataManager.shared.markAsSynced(
            entityName: "CachedBodyMetrics",
            ids: [uploadedId, laterId]
        )

        let uploaded = try await syncState(id: uploadedId)
        let later = try await syncState(id: laterId)
        XCTAssertTrue(uploaded.isSynced)
        XCTAssertEqual(uploaded.syncStatus, "synced")
        XCTAssertFalse(later.isSynced)
        XCTAssertEqual(later.syncStatus, "pending")
        XCTAssertEqual(later.weight, 71, accuracy: 0.001)
        XCTAssertEqual(later.notes, "saved-after-snapshot")
    }

    func testMarkAsSyncedAcknowledgesTheSnapshotVersion() async throws {
        let userId = "sync-ack-match-\(UUID().uuidString)"
        let metricId = UUID().uuidString
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 75, notes: "unchanged"),
            userId: userId
        )
        _ = try await CoreDataManager.shared.fetchPendingLocalSyncSnapshot(for: userId)
        await CoreDataManager.shared.markAsSynced(entityName: "CachedBodyMetrics", ids: [metricId])

        let stored = try await syncState(id: metricId)
        XCTAssertTrue(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "synced")
        XCTAssertEqual(stored.weight, 75, accuracy: 0.001)
        XCTAssertEqual(stored.notes, "unchanged")
    }

    func testStaleBodyMetricPullDoesNotOverwriteANewerLocalEdit() async throws {
        let userId = "sync-pull-body-\(UUID().uuidString)"
        let metricId = UUID().uuidString
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 80, notes: "uploaded"),
            userId: userId
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 81, notes: "edited-after-upload"),
            userId: userId
        )

        CoreDataManager.shared.updateOrCreateBodyMetric(from: [
            "id": metricId,
            "user_id": userId,
            "weight": 80.0,
            "weight_unit": "kg",
            "notes": "uploaded",
            "updated_at": "2020-01-01T00:00:00Z"
        ])

        let stored = try await syncState(id: metricId)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "pending")
        XCTAssertEqual(stored.weight, 81, accuracy: 0.001)
        XCTAssertEqual(stored.notes, "edited-after-upload")
    }

    func testNewerBodyMetricPullAppliesAndAcknowledges() async throws {
        let userId = "sync-pull-body-new-\(UUID().uuidString)"
        let metricId = UUID().uuidString
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            bodyMetric(id: metricId, userId: userId, weight: 80, notes: "local"),
            userId: userId
        )

        CoreDataManager.shared.updateOrCreateBodyMetric(from: [
            "id": metricId,
            "user_id": userId,
            "weight": 82.0,
            "weight_unit": "kg",
            "notes": "server",
            "updated_at": "2099-01-01T00:00:00Z"
        ])

        let stored = try await syncState(id: metricId)
        XCTAssertTrue(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "synced")
        XCTAssertEqual(stored.weight, 82, accuracy: 0.001)
        XCTAssertEqual(stored.notes, "server")
    }

    func testStaleDailyMetricPullDoesNotOverwriteANewerLocalEdit() async throws {
        let userId = "sync-pull-daily-\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)
        try await CoreDataManager.shared.saveDailyMetricsAndWait(
            dailyMetric(id: metricId, userId: userId, steps: 1_000, notes: "uploaded", updatedAt: older),
            userId: userId
        )
        try await CoreDataManager.shared.saveDailyMetricsAndWait(
            dailyMetric(id: metricId, userId: userId, steps: 2_000, notes: "edited-after-upload", updatedAt: newer),
            userId: userId
        )

        CoreDataManager.shared.updateOrCreateDailyMetric(from: [
            "id": metricId,
            "user_id": userId,
            "steps": 1_000,
            "notes": "uploaded",
            "updated_at": "2023-11-14T22:13:20Z"
        ])

        let stored = try await dailyState(id: metricId)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "pending")
        XCTAssertEqual(stored.steps, 2_000)
        XCTAssertEqual(stored.notes, "edited-after-upload")
    }

    func testStaleProfilePullDoesNotOverwriteANewerLocalEdit() async throws {
        let userId = "sync-pull-profile-\(UUID().uuidString)"
        let uploaded = profile(id: userId, fullName: "Uploaded Name")
        let edited = profile(id: userId, fullName: "Edited Name")
        CoreDataManager.shared.saveProfile(
            uploaded,
            userId: userId,
            email: "pull-profile@example.invalid",
            markSynced: false
        )
        CoreDataManager.shared.saveProfile(
            edited,
            userId: userId,
            email: "pull-profile@example.invalid",
            markSynced: false
        )

        CoreDataManager.shared.updateOrCreateProfile(from: [
            "id": userId,
            "full_name": "Uploaded Name",
            "height": 180.0,
            "height_unit": "cm",
            "updated_at": "2020-01-01T00:00:00Z"
        ])

        let stored = try await profileState(id: userId)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.syncStatus, "pending")
        XCTAssertEqual(stored.fullName, "Edited Name")
    }

    private func bodyMetric(id: String, userId: String, weight: Double, notes: String) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: notes,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func syncState(id: String) async throws -> (weight: Double, isSynced: Bool, syncStatus: String?, notes: String?) {
        let context = CoreDataManager.shared.viewContext
        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else {
                throw SyncAckContractError.missingRow(id)
            }
            return (row.weight, row.isSynced, row.syncStatus, row.notes)
        }
    }

    private func dailyMetric(
        id: String,
        userId: String,
        steps: Int,
        notes: String,
        updatedAt: Date
    ) -> DailyMetrics {
        DailyMetrics(
            id: id,
            userId: userId,
            date: updatedAt,
            steps: steps,
            notes: notes,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            updatedAt: updatedAt
        )
    }

    private func dailyState(id: String) async throws -> (steps: Int, isSynced: Bool, syncStatus: String?, notes: String?) {
        let context = CoreDataManager.shared.viewContext
        return try await context.perform {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else {
                throw SyncAckContractError.missingRow(id)
            }
            return (Int(row.steps), row.isSynced, row.syncStatus, row.notes)
        }
    }

    private func profile(id: String, fullName: String) -> UserProfile {
        UserProfile(
            id: id,
            email: "pull-profile@example.invalid",
            username: "pull_profile",
            fullName: fullName,
            dateOfBirth: nil,
            height: 170,
            heightUnit: "cm",
            gender: "female",
            activityLevel: "moderate",
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: true
        )
    }

    private func profileState(id: String) async throws -> (fullName: String?, isSynced: Bool, syncStatus: String?) {
        let context = CoreDataManager.shared.viewContext
        return try await context.perform {
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let row = try context.fetch(request).first else {
                throw SyncAckContractError.missingRow(id)
            }
            return (row.fullName, row.isSynced, row.syncStatus)
        }
    }
}

private enum SyncAckContractError: Error {
    case missingRow(String)
}
