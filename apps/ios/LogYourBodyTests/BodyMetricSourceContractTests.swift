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

    func testSourceBundleIdentifierNormalizationAndRoundTrip() throws {
        let cases: [(String?, String?)] = [
            (nil, nil), ("", nil), (" \t\n ", nil),
            ("com.example.scale", "com.example.scale"),
            (" com.example.scale\n", "com.example.scale")
        ]
        for (raw, expected) in cases {
            let metadata = BodyMetricSourceMetadata(vendor: "apple_health", sourceBundleId: raw)
            XCTAssertEqual(metadata.sourceBundleId, expected)
            XCTAssertEqual(metadata.jsonObject["source_bundle_id"] as? String, expected)
            let decoded = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: metadata.jsonString))
            XCTAssertEqual(decoded.sourceBundleId, expected)
        }
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

extension BodyMetricSourceContractTests {
    func testImportedProvenanceRoundTripsEffectiveAndImportDatesIndependently() throws {
        let measured = Date(timeIntervalSince1970: 1_520_078_400) // March 3, 2018
        let imported = Date(timeIntervalSince1970: 1_792_929_600)
        let metadata = BodyMetricSourceMetadata(
            sourceName: " Test scale ", sourceBundleId: "com.example.scale",
            importedAt: ISO8601DateFormatter().string(from: imported)
        )
        let original = try provenanceMetric(source: "healthkit", date: measured, createdAt: imported, metadata: metadata)
        let decoded = try JSONDecoder().decode(BodyMetrics.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.provenance, original.provenance)
        XCTAssertEqual(decoded.provenance.sourceName, "Test scale")
        XCTAssertEqual(decoded.provenance.sourceBundleId, "com.example.scale")
        XCTAssertEqual(decoded.provenance.effectiveDate, measured)
        XCTAssertEqual(decoded.provenance.importedAt, imported)
        XCTAssertEqual(decoded.effectiveDate, measured)
    }

    func testMissingImportSourceStillExposesHonestRequiredProvenance() throws {
        let measured = Date(timeIntervalSince1970: 1_520_078_400)
        let imported = measured.addingTimeInterval(86_400)
        for source in ["healthkit", "smart_scale", "bodyspec_dexa", "dexa_pdf", "inbody_pdf", "pdf_import", "photo"] {
            for metadata in [nil, BodyMetricSourceMetadata(sourceName: " \n", sourceBundleId: " ")] {
                let metric = try provenanceMetric(source: source, date: measured, createdAt: imported, metadata: metadata)
                XCTAssertFalse(metric.provenance.sourceName.isEmpty)
                XCTAssertNotEqual(metric.provenance.sourceName, "Manual")
                XCTAssertEqual(metric.provenance.effectiveDate, measured)
                XCTAssertEqual(metric.provenance.importedAt, imported)
                XCTAssertNil(metric.provenance.sourceBundleId, "Do not invent an upstream bundle ID")
                XCTAssertEqual(metric.metricSource.rawValue, source)
            }
        }
    }

    func testInvalidImportTimestampFallsBackToCreationNeverMeasurementDate() throws {
        let measured = Date(timeIntervalSince1970: 1_520_078_400)
        let imported = measured.addingTimeInterval(86_400)
        let invalid = try provenanceMetric(
            source: "healthkit", date: measured, createdAt: imported,
            metadata: BodyMetricSourceMetadata(importedAt: "invalid")
        )
        XCTAssertEqual(invalid.provenance.importedAt, imported)
        XCTAssertEqual(invalid.provenance.effectiveDate, measured)
        let fractional = try provenanceMetric(
            source: "healthkit", date: measured, createdAt: imported,
            metadata: BodyMetricSourceMetadata(importedAt: "2026-10-25T12:00:00.125Z")
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        XCTAssertEqual(fractional.provenance.importedAt, formatter.date(from: "2026-10-25T12:00:00.125Z"))
    }

    func testLegacyManualEntriesRetainManualSourceAndEffectiveDate() throws {
        let date = Date(timeIntervalSince1970: 1_520_078_400)
        let manual = try provenanceMetric(source: nil, date: date, createdAt: date, metadata: nil)
        XCTAssertEqual(manual.metricSource, .manual)
        XCTAssertEqual(manual.measurementSource(for: .weight), .manual)
        XCTAssertEqual(manual.provenance.sourceName, "Manual")
        XCTAssertEqual(manual.provenance.effectiveDate, date)
        XCTAssertNil(manual.provenance.sourceBundleId)
    }

    func testRawHealthSampleKeepsHistoricalEffectiveDateAndImportProvenance() {
        let measured = Date(timeIntervalSince1970: 1_520_078_400)
        let imported = Date(timeIntervalSince1970: 1_792_929_600)
        let sample = HKRawSample(
            id: "raw", userId: "owner", hkUUID: "sample", quantityType: "bodyMass", value: 80, unit: "kg",
            startDate: measured, endDate: measured, sourceName: "Test scale", sourceBundleId: "com.example.scale",
            deviceManufacturer: nil, deviceModel: nil, deviceHardwareVersion: nil, deviceFirmwareVersion: nil,
            deviceSoftwareVersion: nil, deviceLocalIdentifier: nil, deviceUDI: nil, metadata: nil,
            createdAt: imported, updatedAt: imported
        )
        XCTAssertEqual(sample.effectiveDate, measured)
        XCTAssertEqual(sample.provenance.effectiveDate, measured)
        XCTAssertEqual(sample.provenance.importedAt, imported)
        XCTAssertEqual(sample.provenance.sourceName, "Test scale")
        XCTAssertEqual(sample.provenance.sourceBundleId, "com.example.scale")
        let missing = BodyMetricProvenance(
            sourceName: " ", sourceBundleId: nil, effectiveDate: measured, importedAt: imported
        )
        XCTAssertEqual(missing.sourceName, "Unknown source")
    }

    func testSmartScaleImportRetainsUpstreamBundleIdentifier() throws {
        let sample = try XCTUnwrap(HealthKitSmartScaleSyncPolicy.makeSample(
            sampleId: "sample", kind: .weight, value: 80, date: Date(),
            sourceName: "Test scale", sourceBundleId: "com.example.scale"
        ))
        XCTAssertEqual(sample.sourceBundleId, "com.example.scale")
        XCTAssertEqual(sample.sourceName, "Test scale")
    }

    func testCombinedHealthKitImportKeepsSourceAndImportDate() throws {
        let imported = Date(timeIntervalSince1970: 1_792_929_600)
        let metadata = BodyMetricSourceMetadata(
            sourceName: "Test scale", sourceBundleId: "com.example.scale", sampleId: "weight",
            importedAt: ISO8601DateFormatter().string(from: imported)
        ).recordingHealthKitContext(["time_zone": "America/Los_Angeles", "sync_identifier": "weight-edit"])
        let bodyFat = BodyMetricSourceMetadata(
            sourceBundleId: "com.example.body-fat", sampleId: "body-fat",
            importedAt: ISO8601DateFormatter().string(from: imported.addingTimeInterval(60))
        ).recordingHealthKitContext(["sync_identifier": "body-fat-edit", "sync_version": "2"])
        let combined = try XCTUnwrap(HealthKitManager.shared.combinedHealthKitMetadata(
            weightMetadata: metadata, bodyFatMetadata: bodyFat
        ))
        XCTAssertEqual(combined.sourceName, metadata.sourceName)
        XCTAssertEqual(combined.sourceBundleId, metadata.sourceBundleId)
        XCTAssertEqual(combined.importedAt, metadata.importedAt)
        XCTAssertEqual(combined.bodyFatSampleId, "body-fat")
        XCTAssertEqual(combined.healthKitContext, metadata.healthKitContext)
        XCTAssertEqual(combined.pairedHealthKitBodyFat, bodyFat)
        let bodyFatOnly = try XCTUnwrap(HealthKitManager.shared.combinedHealthKitMetadata(
            weightMetadata: nil, bodyFatMetadata: bodyFat
        ))
        XCTAssertEqual(bodyFatOnly.importedAt, bodyFat.importedAt)
        XCTAssertEqual(bodyFatOnly.healthKitContext, bodyFat.healthKitContext)
    }

    @MainActor
    func testCachedImportKeepsProvenanceAfterCoreDataConversion() throws {
        let (context, cached) = try cachedHistory(count: 1)
        defer { context.reset() }
        let measured = Date(timeIntervalSince1970: 1_520_078_400)
        let imported = Date(timeIntervalSince1970: 1_792_929_600)
        cached[0].date = measured
        cached[0].createdAt = imported
        cached[0].sourceMetadataJSON = BodyMetricSourceMetadata(
            sourceName: "Test scale", sourceBundleId: "com.example.scale",
            importedAt: ISO8601DateFormatter().string(from: imported)
        ).jsonString
        let metric = try XCTUnwrap(cached[0].toBodyMetrics())
        XCTAssertEqual(metric.provenance.sourceName, "Test scale")
        XCTAssertEqual(metric.provenance.sourceBundleId, "com.example.scale")
        XCTAssertEqual(metric.provenance.effectiveDate, measured)
        XCTAssertEqual(metric.provenance.importedAt, imported)
    }

    private func provenanceMetric(
        source: String?, date: Date, createdAt: Date, metadata: BodyMetricSourceMetadata?
    ) throws -> BodyMetrics {
        var payload: [String: Any] = [
            "id": "provenance", "user_id": "owner", "date": date.timeIntervalSinceReferenceDate,
            "created_at": createdAt.timeIntervalSinceReferenceDate,
            "updated_at": createdAt.timeIntervalSinceReferenceDate, "weight": 80
        ]
        payload["data_source"] = source
        payload["source_metadata"] = metadata?.jsonObject
        return try JSONDecoder().decode(BodyMetrics.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
