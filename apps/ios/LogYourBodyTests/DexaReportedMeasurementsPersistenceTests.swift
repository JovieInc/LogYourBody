import XCTest
import CoreData
@testable import LogYourBody

@MainActor
final class DexaReportedMeasurementsPersistenceTests: XCTestCase {
    private var manager: CoreDataManager!
    private var storeURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Reported-\(UUID()).sqlite")
        try await openStore()
    }

    override func tearDown() async throws {
        try closeStore()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        try await super.tearDown()
    }

    func testTypedPayloadSurvivesReopenAndPendingSnapshotWithoutChangingScalars() async throws {
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let result = ReportedMeasurementsTestFixture.result(measurements: envelope)
        try await manager.saveDexaResultsAndWait([result], userId: result.userId)
        let before = try await cached(id: result.id)
        let bytes = before.reportedMeasurementsJSON
        try closeStore()
        try await openStore()
        let after = try await cached(id: result.id)
        XCTAssertEqual(after.reportedMeasurementsJSON, bytes)
        XCTAssertEqual(after.toDexaResult()?.reportedMeasurements, envelope)
        XCTAssertEqual(after.muscleMass, 12.5)
        XCTAssertEqual(after.bodyMetricsId, "metric-link")
        XCTAssertEqual(after.externalResultId, "original-report-id")
        XCTAssertFalse(after.isSynced)
        XCTAssertEqual(after.syncStatus, "pending")
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: result.userId)
        XCTAssertEqual(pending.dexaResults.count, 1)
        XCTAssertEqual(pending.dexaResults.first?.reportedMeasurementsJSON, bytes)
        let other = try await manager.fetchPendingLocalSyncSnapshot(for: "other-owner")
        XCTAssertTrue(other.dexaResults.isEmpty)
    }

    func testLegacyAndMalformedOptionalResponsesPreserveStoredRawBytes() async throws {
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let result = ReportedMeasurementsTestFixture.result(measurements: envelope)
        try await manager.saveDexaResultsAndWait([result], userId: result.userId, markAsSynced: true)
        let row = try await cached(id: result.id)
        let bytes = row.reportedMeasurementsJSON
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        for value: Any? in [nil, NSNull(), ["schema_version": 1, "items": [["kind": "lean_mass", "value": -1]]]] {
            object["reported_measurements"] = value
            let legacy = try JSONDecoder().decode(DexaResult.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(legacy.reportedMeasurements)
            try await manager.saveDexaResultsAndWait([legacy], userId: result.userId, markAsSynced: true)
            XCTAssertEqual(row.reportedMeasurementsJSON, bytes)
            XCTAssertEqual(row.toDexaResult()?.reportedMeasurements, envelope)
        }
    }

    func testExplicitEnvelopeReplacementAndEmptyItemsAreRetained() async throws {
        let known = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let result = ReportedMeasurementsTestFixture.result(measurements: known)
        try await manager.saveDexaResultsAndWait([result], userId: result.userId, markAsSynced: true)
        for json in [ReportedMeasurementsTestFixture.futureJSON, "{\"schema_version\":1,\"items\":[]}"] {
            let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: json))
            let replacement = ReportedMeasurementsTestFixture.result(id: result.id, measurements: envelope)
            try await manager.saveDexaResultsAndWait([replacement], userId: result.userId)
            let row = try await cached(id: result.id)
            XCTAssertEqual(row.toDexaResult()?.reportedMeasurements, envelope)
            XCTAssertFalse(row.isSynced)
        }
    }

    func testRemoteRefreshCannotAcknowledgeOrOverwritePendingTypedEdit() async throws {
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let result = ReportedMeasurementsTestFixture.result(measurements: envelope)
        try await manager.saveDexaResultsAndWait([result], userId: result.userId)
        let legacy = ReportedMeasurementsTestFixture.result(id: result.id, muscleMass: 99)
        try await manager.saveDexaResultsAndWait([legacy], userId: result.userId, markAsSynced: true)
        let row = try await cached(id: result.id)
        XCTAssertEqual(row.toDexaResult()?.reportedMeasurements, envelope)
        XCTAssertEqual(row.muscleMass, 12.5)
        XCTAssertFalse(row.isSynced)
        XCTAssertEqual(row.syncStatus, "pending")
    }

    func testMixedBatchPreservesForeignOwnerAndSavesAuthorizedRow() async throws {
        let known = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let future = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let original = ReportedMeasurementsTestFixture.result(measurements: known)
        try await manager.saveDexaResultsAndWait([original], userId: original.userId, markAsSynced: true)
        let foreign = ReportedMeasurementsTestFixture.result(id: original.id, userId: "other-owner", measurements: future)
        let authorized = ReportedMeasurementsTestFixture.result(userId: "other-owner", measurements: future)
        try await manager.saveDexaResultsAndWait([foreign, authorized], userId: "other-owner")
        let oldRow = try await cached(id: original.id)
        XCTAssertEqual(oldRow.userId, original.userId)
        XCTAssertEqual(oldRow.toDexaResult()?.reportedMeasurements, known)
        XCTAssertTrue(oldRow.isSynced)
        let ownRow = try await cached(id: authorized.id)
        XCTAssertEqual(ownRow.userId, "other-owner")
        XCTAssertEqual(ownRow.toDexaResult()?.reportedMeasurements, future)
    }

    func testPayloadOwnerMismatchCannotCreateARowForAnotherSubject() async throws {
        let result = ReportedMeasurementsTestFixture.result(userId: "payload-owner")
        try await manager.saveDexaResultsAndWait([result], userId: "caller-owner")
        let caller = await manager.fetchDexaResults(for: "caller-owner", limit: 10)
        let payload = await manager.fetchDexaResults(for: "payload-owner", limit: 10)
        XCTAssertTrue(caller.isEmpty)
        XCTAssertTrue(payload.isEmpty)
    }

    func testFailedAcknowledgmentSaveRestoresPendingStateWithoutDiscardingOtherEdits() async throws {
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let result = ReportedMeasurementsTestFixture.result(measurements: envelope)
        try await manager.saveDexaResultsAndWait([result], userId: result.userId)
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: result.userId)
        let context = manager.viewContext
        let invalid = CachedBodyMetrics(context: context)
        invalid.notes = "Unrelated unsaved edit"
        // Missing required fields trigger a real Core Data validation failure.
        do {
            try await manager.markDexaResultsAsSynced(pending.dexaResults)
            XCTFail("Expected the invalid unrelated row to make the save fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
        let row = try await cached(id: result.id)
        XCTAssertFalse(row.isSynced)
        XCTAssertEqual(row.syncStatus, "pending")
        XCTAssertTrue(invalid.isInserted)
        XCTAssertEqual(invalid.notes, "Unrelated unsaved edit")
        context.delete(invalid)
        try context.save()
        try await manager.markDexaResultsAsSynced(pending.dexaResults)
        XCTAssertTrue(row.isSynced)
        XCTAssertEqual(row.reportedMeasurementsJSON, envelope.jsonString)
    }

    private func openStore() async throws {
        manager = CoreDataManager(persistentStoreDescriptions: [NSPersistentStoreDescription(url: storeURL)])
        let ready = NSPredicate { [weak self] _, _ in
            self?.manager.persistentStoreLoadState == .ready
        }
        await fulfillment(of: [expectation(for: ready, evaluatedWith: manager)], timeout: 10)
        XCTAssertEqual(manager.persistentStoreLoadState, .ready)
    }

    private func closeStore() throws {
        guard let manager else { return }
        manager.viewContext.reset()
        for store in manager.persistentContainer.persistentStoreCoordinator.persistentStores {
            try manager.persistentContainer.persistentStoreCoordinator.remove(store)
        }
        self.manager = nil
    }

    private func cached(id: String) async throws -> CachedDexaResult {
        let context = manager.viewContext
        return try await context.perform {
            let request = CachedDexaResult.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            return try XCTUnwrap(context.fetch(request).first)
        }
    }
}
