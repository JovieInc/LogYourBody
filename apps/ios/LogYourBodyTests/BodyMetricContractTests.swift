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
}

private enum SyncAckContractError: Error {
    case missingRow(String)
}
