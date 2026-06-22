//
// SyncIntegrationSupplementalSyncTests.swift
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
final class SyncIntegrationSupplementalSyncTests: XCTestCase {
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

    func testSyncLocalChanges_UsesSupabaseAndMarksDailyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 10_000,
            notes: "unsynced-daily",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try await coreData.saveDailyMetricsAndWait(dailyModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dailyMetricsBatches.count, 1)
        guard let batch = stubSupabase.dailyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No daily metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        if let stepsValue = payload["steps"] as? Int32 {
            XCTAssertEqual(stepsValue, 10_000)
        } else if let stepsValue = payload["steps"] as? Int {
            XCTAssertEqual(stepsValue, 10_000)
        } else {
            XCTFail("Expected steps field as Int or Int32")
        }

        XCTAssertEqual(payload["notes"] as? String, "unsynced-daily")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.dailyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksGlp1DoseLogSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_glp1_log_\(UUID().uuidString)"
        let medicationId = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_780_100_000)
        let log = Glp1DoseLog(
            id: id,
            userId: userId,
            takenAt: now,
            medicationId: medicationId,
            doseAmount: 2.5,
            doseUnit: "mg",
            drugClass: "semaglutide",
            brand: "Ozempic",
            isCompounded: false,
            supplierType: "pharmacy",
            supplierName: "Test Pharmacy",
            notes: "weekly dose",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now
        )

        try await coreData.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.glp1DoseLogPayloads.count, 1)
        let payload = try XCTUnwrap(stubSupabase.glp1DoseLogPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["medication_id"] as? String, medicationId)
        XCTAssertEqual(payload["dose_amount"] as? Double, 2.5)
        XCTAssertEqual(payload["dose_unit"] as? String, "mg")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")

        let remaining = await coreData.fetchUnsyncedGlp1DoseLogs(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksGlp1MedicationSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_glp1_med_\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: 1_780_200_000)
        let endedAt = now.addingTimeInterval(3_600)

        let context = coreData.viewContext
        await context.perform {
            let medication = CachedGlp1Medication(context: context)
            medication.id = id
            medication.userId = userId
            medication.displayName = "Semaglutide"
            medication.genericName = "semaglutide"
            medication.drugClass = "glp1"
            medication.brand = "Ozempic"
            medication.route = "injection"
            medication.frequency = "weekly"
            medication.doseUnit = "mg"
            medication.isCompounded = false
            medication.hkIdentifier = "hk-med-\(UUID().uuidString)"
            medication.startedAt = now
            medication.endedAt = endedAt
            medication.notes = "medication note"
            medication.createdAt = now.addingTimeInterval(-120)
            medication.updatedAt = endedAt
            medication.isSynced = false
            medication.syncStatus = "pending"

            if context.hasChanges {
                try? context.save()
            }
        }

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.endedActiveMedicationRequests.count, 1)
        XCTAssertEqual(stubSupabase.endedActiveMedicationRequests.first?.userId, userId)
        XCTAssertEqual(stubSupabase.glp1MedicationPayloads.count, 1)
        let payload = try XCTUnwrap(stubSupabase.glp1MedicationPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["display_name"] as? String, "Semaglutide")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")
        XCTAssertEqual(payload["ended_at"] as? String, ISO8601DateFormatter().string(from: endedAt))

        let remaining = await coreData.fetchUnsyncedGlp1Medications(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksDexaResultsSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_dexa_realtime_\(UUID().uuidString)"
        let bodyMetricsId = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let createdAt = now.addingTimeInterval(-120)
        let updatedAt = now
        let acquireTime = now.addingTimeInterval(-3_600)
        let analyzeTime = now.addingTimeInterval(-1_800)

        let context = coreData.viewContext
        await context.perform {
            let result = CachedDexaResult(context: context)
            result.id = id
            result.userId = userId
            result.bodyMetricsId = bodyMetricsId
            result.externalSource = "BodySpec"
            result.externalResultId = "result-\(UUID().uuidString)"
            result.externalUpdateTime = now
            result.scannerModel = "TestScanner"
            result.locationId = "loc-123"
            result.locationName = "Test Location"
            result.acquireTime = acquireTime
            result.analyzeTime = analyzeTime
            result.vatMassKg = 1.23
            result.vatVolumeCm3 = 456.0
            result.resultPdfUrl = "https://example.com/result.pdf"
            result.resultPdfName = "result.pdf"
            result.createdAt = createdAt
            result.updatedAt = updatedAt
            result.isSynced = false
            result.syncStatus = "pending"

            if context.hasChanges {
                try? context.save()
            }
        }

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dexaPayloads.count, 1)
        guard let payload = stubSupabase.dexaPayloads.first else {
            XCTFail("No Dexa payload captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["body_metrics_id"] as? String, bodyMetricsId)
        XCTAssertEqual(payload["external_source"] as? String, "BodySpec")
        XCTAssertEqual(payload["result_pdf_url"] as? String, "https://example.com/result.pdf")
        XCTAssertEqual(payload["result_pdf_name"] as? String, "result.pdf")

        if let vatMass = payload["vat_mass_kg"] as? Double {
            XCTAssertEqual(vatMass, 1.23, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_mass_kg in payload")
        }

        if let vatVolume = payload["vat_volume_cm3"] as? Double {
            XCTAssertEqual(vatVolume, 456.0, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_volume_cm3 in payload")
        }

        let formatter = ISO8601DateFormatter()
        let acquireTimeString = try XCTUnwrap(payload["acquire_time"] as? String)
        XCTAssertTrue(acquireTimeString.hasSuffix("Z"))
        XCTAssertEqual(acquireTimeString, formatter.string(from: acquireTime))
        let parsedAcquireTime = try XCTUnwrap(formatter.date(from: acquireTimeString))
        XCTAssertEqual(parsedAcquireTime.timeIntervalSince1970, acquireTime.timeIntervalSince1970, accuracy: 0.001)

        // Verify there are no remaining unsynced Dexa results for this user
        let unsyncedDexa = await coreData.fetchUnsyncedDexaResults()
        let unsyncedForUser = unsyncedDexa.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testCachedDexaResult_toDexaResultMapsFieldsAndNormalizesVatValues() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext

        let id = UUID().uuidString
        let userId = "mapping_test_user_\(UUID().uuidString)"
        let externalSource = "BodySpec"
        let externalResultId = "result-\(UUID().uuidString)"
        let now = Date()
        let createdAt = now.addingTimeInterval(-300)
        let updatedAt = now

        var mappedWithVat: DexaResult?
        var mappedWithoutVat: DexaResult?

        await context.perform {
            // Case 1: VAT values > 0 should be preserved
            let withVat = CachedDexaResult(context: context)
            withVat.id = id
            withVat.userId = userId
            withVat.bodyMetricsId = "bm-\(UUID().uuidString)"
            withVat.externalSource = externalSource
            withVat.externalResultId = externalResultId
            withVat.externalUpdateTime = now
            withVat.scannerModel = "TestScanner"
            withVat.locationId = "loc-123"
            withVat.locationName = "Test Location"
            withVat.acquireTime = now.addingTimeInterval(-3_600)
            withVat.analyzeTime = now.addingTimeInterval(-1_800)
            withVat.vatMassKg = 2.5
            withVat.vatVolumeCm3 = 789.0
            withVat.resultPdfUrl = "https://example.com/result.pdf"
            withVat.resultPdfName = "result.pdf"
            withVat.createdAt = createdAt
            withVat.updatedAt = updatedAt

            mappedWithVat = withVat.toDexaResult()

            // Case 2: VAT values <= 0 should map to nil
            let withoutVat = CachedDexaResult(context: context)
            withoutVat.id = UUID().uuidString
            withoutVat.userId = userId
            withoutVat.bodyMetricsId = nil
            withoutVat.externalSource = externalSource
            withoutVat.externalResultId = externalResultId
            withoutVat.externalUpdateTime = nil
            withoutVat.scannerModel = nil
            withoutVat.locationId = nil
            withoutVat.locationName = nil
            withoutVat.acquireTime = nil
            withoutVat.analyzeTime = nil
            withoutVat.vatMassKg = 0.0
            withoutVat.vatVolumeCm3 = -10.0
            withoutVat.resultPdfUrl = nil
            withoutVat.resultPdfName = nil
            withoutVat.createdAt = createdAt
            withoutVat.updatedAt = updatedAt

            mappedWithoutVat = withoutVat.toDexaResult()
        }

        let withVat = try XCTUnwrap(mappedWithVat)
        XCTAssertEqual(withVat.id, id)
        XCTAssertEqual(withVat.userId, userId)
        XCTAssertEqual(withVat.externalSource, externalSource)
        XCTAssertEqual(withVat.externalResultId, externalResultId)

        let vatMass = try XCTUnwrap(withVat.vatMassKg)
        XCTAssertEqual(vatMass, 2.5, accuracy: 0.001)

        let vatVolume = try XCTUnwrap(withVat.vatVolumeCm3)
        XCTAssertEqual(vatVolume, 789.0, accuracy: 0.001)

        XCTAssertEqual(withVat.resultPdfUrl, "https://example.com/result.pdf")
        XCTAssertEqual(withVat.resultPdfName, "result.pdf")
        XCTAssertEqual(withVat.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(withVat.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)

        let withoutVat = try XCTUnwrap(mappedWithoutVat)
        XCTAssertEqual(withoutVat.userId, userId)
        XCTAssertEqual(withoutVat.externalSource, externalSource)
        XCTAssertEqual(withoutVat.externalResultId, externalResultId)
        XCTAssertNil(withoutVat.vatMassKg)
        XCTAssertNil(withoutVat.vatVolumeCm3)
    }
}
