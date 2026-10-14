import XCTest
import CoreFoundation
@testable import LogYourBody

final class ReportedMeasurementsTests: XCTestCase {
    func testKnownKindsStaySeparateAndNeverProjectIntoLegacyMuscle() throws {
        let items = ["lean_mass", "fat_free_mass", "muscle_mass", "skeletal_muscle_mass", "unidentified_mass"]
            .map { kind in
                ["kind": kind, "value": 62, "unit": "kg", "reported_label": kind,
                 "reported_unit": "kg"] as [String: Any]
            }
        let envelope = try decode(["schema_version": 1, "items": items])
        XCTAssertEqual(envelope.knownMeasurements.map(\.kind.rawValue), items.compactMap { $0["kind"] as? String })
        let result = ReportedMeasurementsTestFixture.result(measurements: envelope)
        XCTAssertEqual(result.muscleMass, 12.5, "The old scalar must not be derived from the new envelope")
        let roundTrip = try JSONDecoder().decode(DexaResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(roundTrip.reportedMeasurements, envelope)
        XCTAssertEqual(roundTrip.muscleMass, 12.5)
    }

    func testUnknownKindsAndFutureVersionsRemainOpaque() throws {
        for version in [1, 2] {
            let kind = version == 1 ? "future_ratio" : "lean_mass"
            let raw: [String: Any] = [
                "schema_version": version,
                "items": [["kind": kind, "value": ["nested": [true, NSNull(), "text"]], "unit": "future"]],
                "future_field": ["keep": "original"]
            ]
            let envelope = try decode(raw)
            XCTAssertTrue(envelope.knownMeasurements.isEmpty)
            XCTAssertEqual(envelope.jsonObject as NSDictionary, raw as NSDictionary)
            XCTAssertEqual(ReportedMeasurements(jsonString: envelope.jsonString), envelope)
        }
    }

    func testUnknownUnitsRetainTheReportWithoutInterpretedMass() throws {
        let envelope = try decode([
            "schema_version": 1,
            "items": [["kind": "lean_mass", "value": 62, "unit": NSNull(),
                       "reported_label": "Lean", "reported_unit": "unidentified"]]
        ])
        XCTAssertTrue(envelope.knownMeasurements.isEmpty)
        let item = try XCTUnwrap((envelope.jsonObject["items"] as? [[String: Any]])?.first)
        XCTAssertTrue(item["unit"] is NSNull)
        XCTAssertEqual(item["reported_unit"] as? String, "unidentified")
    }

    func testMalformedOptionalEnvelopeDoesNotDiscardScanHistory() throws {
        let invalid: [Any] = [
            NSNull(), [], ["schema_version": 0, "items": []],
            ["schema_version": 1, "items": [["kind": "lean_mass", "value": -1]]],
            ["schema_version": 1, "items": [["kind": "lean_mass", "value": 62,
                                             "unit": ["kg"], "reported_label": "Lean", "reported_unit": "kg"]]]
        ]
        for value in invalid {
            var record = try ReportedMeasurementsTestFixture.jsonRecord()
            record["reported_measurements"] = value
            let data = try JSONSerialization.data(withJSONObject: [record, ReportedMeasurementsTestFixture.jsonRecord()])
            let records = try JSONDecoder().decode([DexaResult].self, from: data)
            XCTAssertEqual(records.count, 2)
            XCTAssertNil(records[0].reportedMeasurements)
            XCTAssertEqual(records[0].muscleMass, 12.5)
        }
    }

    func testLegacyEncodingOmitsTheNewField() throws {
        let record = try ReportedMeasurementsTestFixture.jsonRecord()
        XCTAssertNil(record["reported_measurements"])
        let decoded = try JSONDecoder().decode(DexaResult.self, from: JSONSerialization.data(withJSONObject: record))
        XCTAssertNil(decoded.reportedMeasurements)
    }

    func testBoundsMatchUTF16AndRejectOversizedOpaqueJSON() throws {
        let accepted = ["schema_version": 2, "items": [["kind": String(repeating: "🧪", count: 40)]]] as [String: Any]
        XCTAssertNoThrow(try decode(accepted))
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": [["kind": String(repeating: "🧪", count: 41)]]]))
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": [], "data": String(repeating: "界", count: 6_000)]))
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": Array(repeating: ["kind": "future"], count: 65)]))
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": [], String(repeating: "🧪", count: 81): true]))
    }

    func testDepthAndNodeBudgetsApplyToFuturePayloads() throws {
        var nested: [String: Any] = ["value": 1]
        for _ in 0..<7 { nested = ["nested": nested] }
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": [], "future": nested]))
        let items = Array(repeating: ["kind": "future", "values": Array(0..<7)] as [String: Any], count: 64)
        XCTAssertThrowsError(try decode(["schema_version": 2, "items": items]))
    }

    func testOpaqueNumbersSurviveNativeJSONBridgesAndCache() throws {
        let tokens = ["9007199254740993", "18446744073709551615", "-9223372036854775808",
                      "0.1", "0.12345678901234567", "1e100", "1e-200", "1e308", "5e-324"]
        for token in tokens {
            let input = Data("{\"schema_version\":2,\"items\":[{\"kind\":\"future\",\"value\":\(token),\"flag\":true,\"empty\":null}]}".utf8)
            // Exercise the actual JSONSerialization bridges used by ProductAPIClient.
            let original = try JSONSerialization.jsonObject(with: input) as? [String: Any]
            let bridged = try JSONSerialization.data(withJSONObject: XCTUnwrap(original))
            let envelope = try JSONDecoder().decode(ReportedMeasurements.self, from: bridged)
            let cached = try XCTUnwrap(ReportedMeasurements(jsonString: envelope.jsonString))
            let output = try JSONSerialization.data(withJSONObject: cached.jsonObject)
            let decoded = try JSONSerialization.jsonObject(with: output) as? [String: Any]
            XCTAssertEqual(decoded as NSDictionary?, original as NSDictionary?, token)
            let item = try XCTUnwrap((decoded?["items"] as? [[String: Any]])?.first)
            let flag = try XCTUnwrap(item["flag"] as? NSNumber)
            XCTAssertEqual(CFGetTypeID(flag), CFBooleanGetTypeID())
            XCTAssertTrue(item["empty"] is NSNull)
            XCTAssertTrue(cached.knownMeasurements.isEmpty)
        }
    }

    private func decode(_ object: [String: Any]) throws -> ReportedMeasurements {
        try JSONDecoder().decode(ReportedMeasurements.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

enum ReportedMeasurementsTestFixture {
    static let knownJSON = """
    {"schema_version":1,"items":[{"kind":"lean_mass","value":62,"unit":"kg","reported_label":"Lean Mass","reported_unit":"kg"}]}
    """
    static let futureJSON = """
    {"schema_version":2,"items":[{"kind":"future","value":{"raw":true,"identifier":9007199254740993}}]}
    """

    static func result(
        id: String = UUID().uuidString, userId: String = "measurement-owner",
        measurements: ReportedMeasurements? = nil, muscleMass: Double = 12.5
    ) -> DexaResult {
        let date = Date(timeIntervalSince1970: 1_735_200_000)
        return DexaResult(
            id: id, userId: userId, bodyMetricsId: "metric-link", externalSource: "bodyspec",
            externalResultId: "original-report-id", externalUpdateTime: date, scannerModel: nil,
            locationId: nil, locationName: "Original clinic", acquireTime: date, analyzeTime: date,
            vatMassKg: 1.2, vatVolumeCm3: 123, scanWeight: 80, scanWeightUnit: "kg",
            bodyFatPercentage: 20, muscleMass: muscleMass, boneMass: 3,
            reportedMeasurements: measurements, resultPdfUrl: nil, resultPdfName: nil,
            createdAt: date, updatedAt: date
        )
    }

    static func jsonRecord() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result())) as? [String: Any])
    }
}
