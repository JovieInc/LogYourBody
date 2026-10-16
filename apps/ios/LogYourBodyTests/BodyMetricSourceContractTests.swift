//
// BodyMetricContractTests.swift
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


final class BodyMetricSourceContractTests: XCTestCase {
    func testSourceNormalizationCoversLaunchImportSources() {
        XCTAssertEqual(BodyMetricSource.normalizedRawValue(nil), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Manual"), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("HealthKit"), "healthkit")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("smart scale"), "smart_scale")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("partner:bodyspec"), "bodyspec_dexa")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("DEXA PDF"), "dexa_pdf")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("InBody PDF"), "inbody_pdf")
        XCTAssertEqual(BodyMetricSource.dexaPDF.rawValue, "dexa_pdf")
        XCTAssertEqual(BodyMetricSource.inbodyPDF.rawValue, "inbody_pdf")
        XCTAssertTrue(BodyMetricSource.allowedRawValues.contains("dexa_pdf"))
        XCTAssertTrue(BodyMetricSource.allowedRawValues.contains("inbody_pdf"))
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("skinfold caliper"), "caliper")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Photo Import"), "photo")
    }

    func testExplicitPDFImportSourceIsCanonicalWithoutChangingUnknownFallback() {
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("pdf_import"), "pdf_import")
        XCTAssertTrue(BodyMetricSource.allowedRawValues.contains("pdf_import"))
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("unidentified device"), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Other"), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue(nil), "manual")
    }

    func testPDFImportSourceSurvivesBodyMetricDecodeAndEncode() throws {
        let payload: [String: Any] = [
            "id": "pdf-metric", "user_id": "pdf-user", "date": 0,
            "created_at": 0, "updated_at": 0, "data_source": "pdf_import",
            "source_metadata": ["vendor": "pdf_import", "source_name": "Unidentified device"]
        ]
        let metric = try JSONDecoder().decode(
            BodyMetrics.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertEqual(metric.dataSource, "pdf_import")
        XCTAssertEqual(metric.sourceMetadata?.sourceName, "Unidentified device")
        XCTAssertNil(metric.bodyFatMethod)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(metric)) as? [String: Any]
        )
        XCTAssertEqual(encoded["data_source"] as? String, "pdf_import")
    }

    func testSourceMetadataTrimsEmptyValuesAndSerializesPointersOnly() throws {
        let metadata = BodyMetricSourceMetadata(
            vendor: " BodySpec ",
            sourceName: "",
            deviceModel: "Scanner X",
            externalResultId: " result-123 "
        )

        let jsonString = try XCTUnwrap(metadata.jsonString)
        let decoded = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: jsonString))

        XCTAssertEqual(decoded.vendor, "BodySpec")
        XCTAssertNil(decoded.sourceName)
        XCTAssertEqual(decoded.deviceModel, "Scanner X")
        XCTAssertEqual(decoded.externalResultId, "result-123")
        XCTAssertEqual(decoded.jsonObject["vendor"] as? String, "BodySpec")
    }

    func testUnconfiguredBuildCannotClaimAnExistingConnectionIsAvailable() {
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: false, connected: true), "Unavailable")
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: false, connected: false), "Unavailable")
    }

    func testScanPresenceCannotEstablishBodySpecConnection() {
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: true, connected: false), "Not connected")
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: true, connected: true), "Connected")
    }

    func testHistoryRefreshCannotApplyAfterAccountSwitchSignOutOrCancellation() {
        XCTAssertTrue(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "owner", currentUserId: "owner", cancelled: false
        ))
        for userId in ["other", nil, ""] {
            XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
                requestedUserId: "owner", currentUserId: userId, cancelled: false
            ))
        }
        XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "owner", currentUserId: "owner", cancelled: true
        ))
        XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "", currentUserId: "", cancelled: false
        ))
    }

    func testHistoryUsesBodySpecAcquisitionDatesRatherThanOtherVendorsOrUpdateTime() {
        let older = scan(id: "older", source: "bodyspec", acquired: 100, updated: 900)
        let newer = scan(id: "newer", source: "BodySpec", acquired: 200, updated: 300)
        let other = scan(id: "other", source: "inbody_pdf", acquired: 800, updated: 800)
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecHistory([other, older, newer]).map(\.id), ["newer", "older"])
        XCTAssertEqual(IntegrationStatusPolicy.scanDate(older, directoryEnabled: true), older.acquireTime)
    }

    func testMissingAcquisitionDateDoesNotBecomeLastSyncTime() {
        let result = scan(id: "unknown", source: "bodyspec", acquired: nil, updated: 900)
        XCTAssertNil(IntegrationStatusPolicy.scanDate(result, directoryEnabled: true))
        XCTAssertEqual(IntegrationStatusPolicy.scanDate(result, directoryEnabled: false), result.updatedAt)
        let known = scan(id: "known", source: "bodyspec", acquired: 100, updated: 100)
        let unknown = scan(id: "another-unknown", source: "bodyspec", acquired: nil, updated: 800)
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecHistory([result, known, unknown]).first?.id, "known")
    }

    private func scan(id: String, source: String, acquired: TimeInterval?, updated: TimeInterval) -> DexaResult {
        DexaResult(
            id: id, userId: "owner", bodyMetricsId: nil, externalSource: source, externalResultId: id,
            externalUpdateTime: nil, scannerModel: nil, locationId: nil, locationName: nil,
            acquireTime: acquired.map { Date(timeIntervalSince1970: $0) }, analyzeTime: nil,
            vatMassKg: nil, vatVolumeCm3: nil, resultPdfUrl: nil, resultPdfName: nil,
            createdAt: Date(timeIntervalSince1970: updated), updatedAt: Date(timeIntervalSince1970: updated)
        )
    }
}

extension BodyMetricSourceContractTests {
    func testFieldAttributionRoundTripsWithoutDiscardingImportOrUnknownMetadata() throws {
        let raw = #"{"vendor":"apple_health","sample_id":"original-weight","body_fat_sample_id":"original-fat","# +
            #""future":{"enabled":true,"values":[null,9223372036854775807]}}"#
        let original = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: raw))
        let corrected = original.settingEntrySource(.manual, fields: [.weight])
        let encoded = try JSONEncoder().encode(corrected)
        let decoded = try JSONDecoder().decode(BodyMetricSourceMetadata.self, from: encoded)
        XCTAssertEqual(decoded, corrected)
        XCTAssertEqual(decoded.entrySource(for: .weight), .manual)
        XCTAssertNil(decoded.entrySource(for: .bodyFat))
        XCTAssertEqual(decoded.sampleId, "original-weight")
        XCTAssertEqual(decoded.bodyFatSampleId, "original-fat")
        let future = try XCTUnwrap(decoded.jsonObject["future"] as? [String: Any])
        XCTAssertEqual(future["enabled"] as? Bool, true)
        let values = try XCTUnwrap(future["values"] as? [Any])
        XCTAssertTrue(values[0] is NSNull)
        XCTAssertEqual((values[1] as? NSNumber)?.int64Value, Int64.max)
        XCTAssertEqual(try XCTUnwrap(BodyMetricSourceMetadata(jsonString: decoded.jsonString)), decoded)
    }

    func testUnknownFieldSourceNeverInventsAManualAttribution() throws {
        let metadata = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: #"{"weight_entry_source":"future-device"}"#))
        XCTAssertNil(metadata.entrySource(for: .weight))
        XCTAssertEqual(metadata.jsonObject["weight_entry_source"] as? String, "future-device")
    }

    func testUndoMetadataRestoresOnlySelectedFieldAttribution() throws {
        let previous = BodyMetricSourceMetadata(vendor: "apple_health")
        let current = try XCTUnwrap(BodyMetricSourceMetadata(
            jsonString: #"{"vendor":"apple_health","weight_entry_source":"manual","body_fat_entry_source":"manual","# +
                #""future":{"keep":true}}"#
        ))
        let restored = current.restoringEntrySources(from: previous, fields: [.weight])
        XCTAssertNil(restored.entrySource(for: .weight))
        XCTAssertEqual(restored.entrySource(for: .bodyFat), .manual)
        XCTAssertNotNil(restored.jsonObject["future"])
        XCTAssertEqual(restored.vendor, "apple_health")
    }
}
