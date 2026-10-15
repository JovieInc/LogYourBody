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
        XCTAssertEqual(decoded.jsonObject["vendor"], "BodySpec")
    }

    @MainActor
    func testHistoryMetadataConversionServicesMainQueueBeforeFinishing() async throws {
        let (context, cached) = try cachedHistory(count: 151)
        defer { context.reset() }
        let heartbeat = expectation(description: "Main queue serviced during history conversion")
        var conversionFinished = false

        // Queue from inside the main actor, immediately before conversion. An uninterrupted
        // compactMap finishes decoding the entire history before this heartbeat can run.
        DispatchQueue.main.async {
            XCTAssertFalse(conversionFinished, "History metadata decoding monopolized the main queue")
            heartbeat.fulfill()
        }

        let metrics = await CachedBodyMetrics.bodyMetricsInBatches(from: cached)
        conversionFinished = true

        await fulfillment(of: [heartbeat], timeout: 1)
        XCTAssertEqual(metrics.map(\.id), cached.compactMap(\.id))
        XCTAssertEqual(metrics.last?.sourceMetadata?.sampleId, "sample-150")
    }

    @MainActor
    func testBatchedHistoryPreservesUnsavedValuesOrderAndCorruptRowHandling() async throws {
        let (context, cached) = try cachedHistory(count: 103)
        defer { context.reset() }
        cached[49].sourceMetadataJSON = "invalid-json"
        cached[50].id = nil
        cached[100].notes = "Unsaved local edit"
        let expected = cached.compactMap { $0.toBodyMetrics() }

        let metrics = await CachedBodyMetrics.bodyMetricsInBatches(from: cached)

        XCTAssertEqual(metrics, expected)
        XCTAssertEqual(metrics.count, 102)
        XCTAssertNil(metrics.first { $0.id == "metric-49" }?.sourceMetadata)
        XCTAssertEqual(metrics.first { $0.id == "metric-100" }?.notes, "Unsaved local edit")
        XCTAssertEqual(metrics.last?.sourceMetadata?.sampleId, "sample-102")
        XCTAssertTrue(cached[0].managedObjectContext?.hasChanges == true)
    }

    @MainActor
    func testBatchedHistoryHandlesEmptyAndSingleRecord() async throws {
        let empty = await CachedBodyMetrics.bodyMetricsInBatches(from: [])
        XCTAssertTrue(empty.isEmpty)

        let (context, cached) = try cachedHistory(count: 1)
        defer { context.reset() }
        let metrics = await CachedBodyMetrics.bodyMetricsInBatches(from: cached)
        XCTAssertEqual(metrics, cached.compactMap { $0.toBodyMetrics() })
    }

    @MainActor
    private func cachedHistory(count: Int) throws -> (NSManagedObjectContext, [CachedBodyMetrics]) {
        let model = CoreDataManager.makeManagedObjectModel()
        let entity = try XCTUnwrap(model.entitiesByName["CachedBodyMetrics"])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        let cached = (0..<count).map { index in
            let cached = CachedBodyMetrics(entity: entity, insertInto: context)
            let date = Date(timeIntervalSince1970: 1_800_000_000 - Double(index) * 86_400)
            cached.id = "metric-\(index)"
            cached.userId = "history-owner"
            cached.date = date
            cached.localDate = BodyMetricLocalDate.key(for: date)
            cached.createdAt = date
            cached.updatedAt = date
            cached.weight = 70
            cached.weightUnit = "kg"
            cached.dataSource = BodyMetricSource.healthKit.rawValue
            cached.sourceMetadataJSON = BodyMetricSourceMetadata(
                vendor: "apple_health", sourceName: "Test scale", sampleId: "sample-\(index)"
            ).jsonString
            return cached
        }
        return (context, cached)
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
