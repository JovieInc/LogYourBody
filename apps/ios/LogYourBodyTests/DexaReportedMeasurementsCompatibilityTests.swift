import XCTest
@testable import LogYourBody

/// These regressions use only pre-existing APIs so they also execute against V3.
@MainActor
final class DexaReportedMeasurementsCompatibilityTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testWireRoundTripRetainsExplicitReportedMeasurementKinds() throws {
        let result = try fixture()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        XCTAssertEqual(encoded["reported_measurements"] as? NSDictionary, envelope as NSDictionary)
        XCTAssertEqual(encoded["muscle_mass"] as? Double, 12.5)
    }

    func testCacheRoundTripRetainsExplicitReportedMeasurementKinds() async throws {
        let result = try fixture()
        try await CoreDataManager.shared.saveDexaResultsAndWait([result], userId: result.userId)
        let rows = await CoreDataManager.shared.fetchDexaResults(for: result.userId, limit: 10)
        let cached = try XCTUnwrap(rows.first)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cached)) as? [String: Any])
        XCTAssertEqual(encoded["reported_measurements"] as? NSDictionary, envelope as NSDictionary)
        XCTAssertEqual(cached.muscleMass, 12.5)
    }

    func testPendingUploadRetainsExplicitReportedMeasurementKinds() async throws {
        let coreData = CoreDataManager.shared
        let result = try fixture()
        try await coreData.saveDexaResultsAndWait([result], userId: result.userId)
        let port = StubProductAPIClient()
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: port
        )
        let pending = try await coreData.fetchPendingLocalSyncSnapshot(for: result.userId)
        try await sync.syncDexaResultsBatch(pending.dexaResults, token: "test-token")
        let payload = try XCTUnwrap(port.dexaPayloads.first)
        XCTAssertEqual(payload["reported_measurements"] as? NSDictionary, envelope as NSDictionary)
        XCTAssertEqual(payload["muscle_mass"] as? Double, 12.5)
    }

    private var envelope: [String: Any] {
        ["schema_version": 1,
         "items": [["kind": "lean_mass", "value": 62, "unit": "kg",
                    "reported_label": "Lean Mass", "reported_unit": "kg"]]]
    }

    private func fixture() throws -> DexaResult {
        let record: [String: Any] = [
            "id": "compatibility-scan", "user_id": "compatibility-owner",
            "external_source": "bodyspec", "external_result_id": "compatibility-report",
            "created_at": 0, "updated_at": 0, "muscle_mass": 12.5,
            "reported_measurements": envelope
        ]
        return try JSONDecoder().decode(DexaResult.self, from: JSONSerialization.data(withJSONObject: record))
    }
}
