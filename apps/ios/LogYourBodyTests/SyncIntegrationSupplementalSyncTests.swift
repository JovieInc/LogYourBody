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

    func testSyncLocalChanges_UsesProductAPIAndMarksDailyMetricSynced() async throws {
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

        let stubProductAPI = StubProductAPIClient()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            productAPIClient: stubProductAPI
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify ProductAPI payload
        XCTAssertEqual(stubProductAPI.dailyMetricsBatches.count, 1)
        guard let batch = stubProductAPI.dailyMetricsBatches.first,
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

    func testSyncLocalChanges_UsesProductAPIAndMarksGlp1DoseLogSynced() async throws {
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

        let stubProductAPI = StubProductAPIClient()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            productAPIClient: stubProductAPI
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubProductAPI.glp1DoseLogPayloads.count, 1)
        let payload = try XCTUnwrap(stubProductAPI.glp1DoseLogPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["medication_id"] as? String, medicationId)
        XCTAssertEqual(payload["dose_amount"] as? Double, 2.5)
        XCTAssertEqual(payload["dose_unit"] as? String, "mg")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")

        let remaining = await coreData.fetchUnsyncedGlp1DoseLogs(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesProductAPIAndMarksGlp1MedicationSynced() async throws {
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

        let stubProductAPI = StubProductAPIClient()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            productAPIClient: stubProductAPI
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubProductAPI.endedActiveMedicationRequests.count, 1)
        XCTAssertEqual(stubProductAPI.endedActiveMedicationRequests.first?.userId, userId)
        XCTAssertEqual(stubProductAPI.glp1MedicationPayloads.count, 1)
        let payload = try XCTUnwrap(stubProductAPI.glp1MedicationPayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["display_name"] as? String, "Semaglutide")
        XCTAssertEqual(payload["brand"] as? String, "Ozempic")
        XCTAssertEqual(payload["ended_at"] as? String, ISO8601DateFormatter().string(from: endedAt))

        let remaining = await coreData.fetchUnsyncedGlp1Medications(for: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSyncLocalChanges_UsesProductAPIAndMarksDexaResultsSynced() async throws {
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
            result.scanWeight = 79.2
            result.scanWeightUnit = "kg"
            result.bodyFatPercentage = 18.4
            result.muscleMass = 62.0
            result.boneMass = 3.2
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

        let stubProductAPI = StubProductAPIClient()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            productAPIClient: stubProductAPI
        )

        try await manager.syncLocalChanges(token: "test-token")

        // Verify ProductAPI payload
        XCTAssertEqual(stubProductAPI.dexaPayloads.count, 1)
        guard let payload = stubProductAPI.dexaPayloads.first else {
            XCTFail("No Dexa payload captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["body_metrics_id"] as? String, bodyMetricsId)
        XCTAssertEqual(payload["external_source"] as? String, "BodySpec")
        XCTAssertEqual(payload["result_pdf_url"] as? String, "https://example.com/result.pdf")
        XCTAssertEqual(payload["result_pdf_name"] as? String, "result.pdf")
        XCTAssertEqual(payload["scan_weight"] as? Double, 79.2)
        XCTAssertEqual(payload["scan_weight_unit"] as? String, "kg")
        XCTAssertEqual(payload["body_fat_percentage"] as? Double, 18.4)
        XCTAssertEqual(payload["muscle_mass"] as? Double, 62.0)
        XCTAssertEqual(payload["bone_mass"] as? Double, 3.2)

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

    func testDexaUploadPreservesTypedAndFuturePayloadsWithoutChangingLegacyScalars() async throws {
        let coreData = CoreDataManager.shared
        let userId = "typed-upload-owner"
        let inputs = [ReportedMeasurementsTestFixture.knownJSON, ReportedMeasurementsTestFixture.futureJSON]
        for (index, json) in inputs.enumerated() {
            let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: json))
            let result = ReportedMeasurementsTestFixture.result(
                id: "typed-upload-\(index)", userId: userId, measurements: envelope
            )
            try await coreData.saveDexaResultsAndWait([result], userId: userId)
        }
        let stub = StubProductAPIClient()
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: stub
        )
        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        try await sync.syncDexaResultsBatch(snapshot.dexaResults, token: "test-token")
        XCTAssertEqual(stub.dexaPayloads.count, 2)
        for (index, json) in inputs.enumerated() {
            let payload = try XCTUnwrap(stub.dexaPayloads.first { $0["id"] as? String == "typed-upload-\(index)" })
            let actual = try XCTUnwrap(payload["reported_measurements"] as? [String: Any])
            let expected = try XCTUnwrap(ReportedMeasurements(jsonString: json))
            XCTAssertEqual(actual as NSDictionary, expected.jsonObject as NSDictionary)
            XCTAssertEqual(payload["muscle_mass"] as? Double, 12.5)
            XCTAssertEqual(payload["user_id"] as? String, userId)
        }
        let remaining = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertTrue(remaining.dexaResults.isEmpty)
    }

    func testDexaUploadOmitsAbsentOptionalPayloadInsteadOfSendingNull() async throws {
        let coreData = CoreDataManager.shared
        let userId = "legacy-upload-owner"
        let result = ReportedMeasurementsTestFixture.result(id: "legacy-upload", userId: userId)
        try await coreData.saveDexaResultsAndWait([result], userId: userId)
        let stub = StubProductAPIClient()
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: stub
        )
        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        try await sync.syncDexaResultsBatch(snapshot.dexaResults, token: "test-token")
        XCTAssertEqual(stub.dexaPayloads.count, 1)
        let payload = try XCTUnwrap(stub.dexaPayloads.first)
        XCTAssertNil(payload["reported_measurements"])
        XCTAssertEqual(payload["muscle_mass"] as? Double, 12.5)
    }

    func testDexaUploadKeepsCorruptStoredEnvelopePendingAndReportsFailure() async throws {
        let coreData = CoreDataManager.shared
        let userId = "corrupt-upload-owner"
        let result = ReportedMeasurementsTestFixture.result(id: "malformed-upload", userId: userId)
        try await coreData.saveDexaResultsAndWait([result], userId: userId)
        let context = coreData.viewContext
        try await context.perform {
            let request = CachedDexaResult.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", "malformed-upload")
            let row = try XCTUnwrap(context.fetch(request).first)
            row.reportedMeasurementsJSON = "{invalid-json"
            try context.save()
        }
        let stub = StubProductAPIClient()
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: stub
        )
        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        do {
            try await sync.syncDexaResultsBatch(snapshot.dexaResults, token: "test-token")
            XCTFail("A corrupt stored envelope must not be silently acknowledged")
        } catch let error as AppError {
            guard case .coreData(let operation, _) = error else { return XCTFail("Expected a cache error") }
            XCTAssertEqual(operation, "syncDexaReportedMeasurements")
        }
        XCTAssertTrue(stub.dexaPayloads.isEmpty)
        let remaining = try await coreData.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertEqual(remaining.dexaResults.first?.reportedMeasurementsJSON, "{invalid-json")
    }

    func testDexaDelayedAcknowledgmentCannotLoseEqualTimestampLocalEdit() async throws {
        let coreData = CoreDataManager.shared
        let originalEnvelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let nextEnvelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let original = ReportedMeasurementsTestFixture.result(measurements: originalEnvelope)
        let edited = ReportedMeasurementsTestFixture.result(id: original.id, measurements: nextEnvelope)
        XCTAssertEqual(original.updatedAt, edited.updatedAt, "Timestamp checks alone cannot protect this edit")
        try await coreData.saveDexaResultsAndWait([original], userId: original.userId)
        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: original.userId)
        let stub = DeferredDexaProductAPIClient {
            try await coreData.saveDexaResultsAndWait([edited], userId: edited.userId)
        }
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: stub
        )
        try await sync.syncDexaResultsBatch(snapshot.dexaResults, token: "test-token")
        try await coreData.saveDexaResultsAndWait([original], userId: original.userId, markAsSynced: true)
        let remaining = try await coreData.fetchPendingLocalSyncSnapshot(for: original.userId)
        XCTAssertEqual(remaining.dexaResults.count, 1)
        XCTAssertEqual(remaining.dexaResults.first?.reportedMeasurementsJSON, nextEnvelope.jsonString)
        let cached = await coreData.fetchDexaResults(for: original.userId, limit: 10)
        XCTAssertEqual(cached.first?.reportedMeasurements, nextEnvelope)
    }

    func testDexaDelayedAcknowledgmentCannotAcknowledgeReplacementOwner() async throws {
        let coreData = CoreDataManager.shared
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.knownJSON))
        let original = ReportedMeasurementsTestFixture.result(measurements: envelope)
        let replacement = ReportedMeasurementsTestFixture.result(
            id: original.id, userId: "replacement-owner", measurements: envelope
        )
        try await coreData.saveDexaResultsAndWait([original], userId: original.userId)
        let snapshot = try await coreData.fetchPendingLocalSyncSnapshot(for: original.userId)
        let stub = DeferredDexaProductAPIClient {
            try await coreData.deleteAllDataAndWait()
            try await coreData.saveDexaResultsAndWait([replacement], userId: replacement.userId)
        }
        let sync = RealtimeSyncManager(
            coreDataManager: coreData, authManager: AuthManager.shared, productAPIClient: stub
        )
        try await sync.syncDexaResultsBatch(snapshot.dexaResults, token: "test-token")
        let remaining = try await coreData.fetchPendingLocalSyncSnapshot(for: replacement.userId)
        XCTAssertEqual(remaining.dexaResults.count, 1)
        XCTAssertEqual(remaining.dexaResults.first?.userId, replacement.userId)
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
            withVat.scanWeight = 80.1
            withVat.scanWeightUnit = "kg"
            withVat.bodyFatPercentage = 18.5
            withVat.muscleMass = 63.0
            withVat.boneMass = 3.3
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
        XCTAssertEqual(withVat.scanWeight, 80.1)
        XCTAssertEqual(withVat.scanWeightUnit, "kg")
        XCTAssertEqual(withVat.bodyFatPercentage, 18.5)
        XCTAssertEqual(withVat.muscleMass, 63.0)
        XCTAssertEqual(withVat.boneMass, 3.3)

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

    func testLogBodyMetricsDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "sync_test_owner_\(UUID().uuidString)"
        let otherId = "sync_test_other_\(UUID().uuidString)"
        let id = UUID().uuidString
        let date = wholeSecondDate(90)
        let metric = BodyMetrics(
            id: id,
            userId: ownerId,
            date: date,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "owner-entry",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: ownerId, markAsSynced: true)

        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: otherId,
            email: "other@example.com",
            name: "Other",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        let manager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: authManager,
            productAPIClient: StubProductAPIClient()
        )
        manager.isOnline = false
        manager.logBodyMetrics(
            BodyMetrics(
                id: id,
                userId: ownerId,
                date: date,
                weight: 55,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "stolen",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: date,
                updatedAt: date
            )
        )

        let cached = await cachedBodyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.weight, 80, accuracy: 0.001)
        XCTAssertEqual(row.notes, "owner-entry")
        XCTAssertTrue(row.isSynced)
        XCTAssertFalse(row.isMarkedDeleted)
    }

    func testUpdateOrCreateBodyMetricDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "sync_test_owner_\(UUID().uuidString)"
        let otherId = "sync_test_other_\(UUID().uuidString)"
        let id = UUID().uuidString
        let date = wholeSecondDate(120)
        let metric = BodyMetrics(
            id: id,
            userId: ownerId,
            date: date,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "owner-entry",
            photoUrl: nil,
            dataSource: "Manual",
            sourceMetadata: BodyMetricSourceMetadata(vendor: "fixture", sampleId: "owned-sample"),
            createdAt: date,
            updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: ownerId, markAsSynced: true)

        let stored = await cachedBodyMetric(id: id)
        let before = try XCTUnwrap(stored)
        let storedUpdatedAt = before.updatedAt
        let storedMetadata = before.sourceMetadataJSON
        XCTAssertNotNil(storedMetadata)
        let formatter = ISO8601DateFormatter()
        let rejected = expectation(description: "Foreign-owner apply completes without mutation")
        CoreDataManager.shared.updateOrCreateBodyMetric(from: [
            "id": id,
            "user_id": otherId,
            "date": formatter.string(from: date),
            "weight": 55.0,
            "weight_unit": "kg",
            "notes": "foreign-payload",
            "data_source": "manual",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ], completion: { rejected.fulfill() })
        await fulfillment(of: [rejected], timeout: 2)

        let cached = await cachedBodyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.weight, 80, accuracy: 0.001)
        XCTAssertEqual(row.notes, "owner-entry")
        XCTAssertFalse(row.isMarkedDeleted)
        XCTAssertTrue(row.isSynced)
        XCTAssertEqual(row.date, date)
        XCTAssertEqual(row.createdAt, date)
        XCTAssertEqual(row.updatedAt, storedUpdatedAt)
        XCTAssertEqual(row.sourceMetadataJSON, storedMetadata)
    }

    func testPhotoTimelineFixtureReseedKeepsTheNewUsersMeasurements() async throws {
        let firstUser = "ui_test_photo_hud_user_first"
        let secondUser = "ui_test_photo_hud_user_second"
        let date = wholeSecondDate(180)
        let unrelatedId = "unrelated-\(UUID().uuidString)"
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            dashboardFixtureMetric(id: unrelatedId, userId: firstUser, date: date, notes: "unrelated"),
            userId: firstUser,
            markAsSynced: true
        )

        try await UITestFixtureIsolation.seedDashboardMetrics(userId: firstUser, photoURL: nil, now: date)
        try await UITestFixtureIsolation.seedDashboardMetrics(userId: secondUser, photoURL: nil, now: date)

        let saved = await CoreDataManager.shared.fetchBodyMetrics(for: secondUser)
        let savedIds = Set(saved.compactMap { $0.toBodyMetrics()?.id })
        XCTAssertEqual(savedIds, Set(UITestFixtureIsolation.dashboardMetricIDs))
        let firstSaved = await CoreDataManager.shared.fetchBodyMetrics(for: firstUser)
        let firstIds = Set(firstSaved.compactMap { $0.toBodyMetrics()?.id })
        XCTAssertFalse(firstIds.contains("ui_test_full_dashboard_metric_0"))
        let cachedUnrelated = await cachedBodyMetric(id: unrelatedId)
        let unrelated = try XCTUnwrap(cachedUnrelated)
        XCTAssertEqual(unrelated.userId, firstUser)
        XCTAssertEqual(unrelated.notes, "unrelated")
    }

    func testForeignLocalSaveReportsFailureAndPreservesStoredMeasurement() async throws {
        let owner = "sync_test_owner_\(UUID().uuidString)"
        let other = "sync_test_other_\(UUID().uuidString)"
        let id = UUID().uuidString
        let date = wholeSecondDate(200)
        let original = dashboardFixtureMetric(id: id, userId: owner, date: date, notes: "original")
        try await CoreDataManager.shared.saveBodyMetricsAndWait(original, userId: owner, markAsSynced: true)

        do {
            try await CoreDataManager.shared.saveBodyMetricsAndWait(
                dashboardFixtureMetric(id: id, userId: other, date: date, notes: "replacement"),
                userId: other
            )
            XCTFail("A foreign-owner save must report failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "CoreDataManager")
            XCTAssertEqual((error as NSError).code, 3)
        }

        let cached = await cachedBodyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, owner)
        XCTAssertEqual(row.weight, 82.1, accuracy: 0.001)
        XCTAssertEqual(row.bodyFatPercentage, 15.8, accuracy: 0.001)
        XCTAssertEqual(row.bodyFatMethod, "manual")
        XCTAssertEqual(row.notes, "original")
        XCTAssertEqual(row.date, date)
        XCTAssertEqual(row.createdAt, date)
        XCTAssertTrue(row.isSynced)
        XCTAssertFalse(row.isMarkedDeleted)
    }

    func testSameOwnerLocalAndRemoteBodyMetricUpdatesRemainAvailable() async throws {
        let owner = "sync_test_owner_\(UUID().uuidString)"
        let id = UUID().uuidString
        let date = wholeSecondDate(220)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            dashboardFixtureMetric(id: id, userId: owner, date: date, notes: "original"),
            userId: owner, markAsSynced: true
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            dashboardFixtureMetric(id: id, userId: owner, date: date, notes: "local correction"),
            userId: owner
        )
        let localCached = await cachedBodyMetric(id: id)
        let local = try XCTUnwrap(localCached)
        XCTAssertEqual(local.notes, "local correction")
        XCTAssertFalse(local.isSynced)

        let formatter = ISO8601DateFormatter()
        await CoreDataManager.shared.updateOrCreateBodyMetricAndWait(from: [
            "id": id, "user_id": owner,
            "date": formatter.string(from: date), "weight": 83.0, "weight_unit": "kg",
            "body_fat_percentage": 16.0, "body_fat_method": "manual",
            "notes": "remote correction", "data_source": "manual",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: Date().addingTimeInterval(60))
        ])
        let remoteCached = await cachedBodyMetric(id: id)
        let remote = try XCTUnwrap(remoteCached)
        XCTAssertEqual(remote.userId, owner)
        XCTAssertEqual(remote.weight, 83.0, accuracy: 0.001)
        XCTAssertEqual(remote.notes, "remote correction")
        XCTAssertEqual(remote.createdAt, date)
        XCTAssertFalse(remote.isMarkedDeleted)
    }

    func testMissingRemoteOwnerCannotEraseStoredOwnerAndStillCompletes() async throws {
        let owner = "sync_test_owner_\(UUID().uuidString)"
        let id = UUID().uuidString
        let date = wholeSecondDate(240)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            dashboardFixtureMetric(id: id, userId: owner, date: date, notes: "original"),
            userId: owner, markAsSynced: true
        )
        let rejected = expectation(description: "Missing-owner apply completes without mutation")
        CoreDataManager.shared.updateOrCreateBodyMetric(from: [
            "id": id, "weight": 55.0, "weight_unit": "kg", "notes": "missing owner"
        ], completion: { rejected.fulfill() })
        await fulfillment(of: [rejected], timeout: 2)
        let cached = await cachedBodyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, owner)
        XCTAssertEqual(row.weight, 82.1, accuracy: 0.001)
        XCTAssertEqual(row.notes, "original")
        XCTAssertTrue(row.isSynced)
    }

    func testDashboardFixtureRetainsCurrentHeroAndUndoVariants() async throws {
        let date = wholeSecondDate(260)
        let variants: [[String]] = [
            ["-lybUITestHomeV2WeightOnlyHeroFixture"],
            ["-lybUITestHomeV2SingleWeightHeroFixture"],
            ["-lybUITestHomeV2SingleReadingFixture"],
            ["-lybUITestHomeV2EstimateHeroFixture"],
            ["-lybUITestHomeV2UndoPhotoOnlyFixture"],
            ["-lybUITestHomeV2TimelineFixture"]
        ]
        for arguments in variants {
            let owner = "ui_test_variant_\(UUID().uuidString)"
            let ids = try await UITestFixtureIsolation.seedDashboardMetrics(
                userId: owner, photoURL: "fixture-default.jpg", now: date, arguments: arguments,
                timelinePhoto: { "fixture-timeline-\($0).jpg" }
            )
            let stored = await CoreDataManager.shared.fetchBodyMetrics(for: owner)
            let rows = stored.compactMap { $0.toBodyMetrics() }
            XCTAssertEqual(Set(rows.map(\.id)), Set(ids))
            let latest = try XCTUnwrap(rows.first { Calendar.current.isDate($0.date, inSameDayAs: date) })
            let single = arguments.contains("-lybUITestHomeV2SingleWeightHeroFixture") ||
                arguments.contains("-lybUITestHomeV2SingleReadingFixture")
            XCTAssertEqual(rows.count, single ? 1 : 5)
            if arguments.contains("-lybUITestHomeV2UndoPhotoOnlyFixture") {
                XCTAssertNil(latest.weight)
                XCTAssertNil(latest.bodyFatPercentage)
                XCTAssertEqual(latest.photoUrl, "fixture-default.jpg")
                XCTAssertTrue(ids.allSatisfy { $0.hasPrefix(owner + "_metric_") })
            } else {
                XCTAssertEqual(try XCTUnwrap(latest.weight), 82.1, accuracy: 0.001)
            }
            if arguments.contains("-lybUITestHomeV2WeightOnlyHeroFixture") ||
                arguments.contains("-lybUITestHomeV2SingleWeightHeroFixture") {
                XCTAssertTrue(rows.allSatisfy { $0.bodyFatPercentage == nil && $0.bodyFatMethod == nil })
            }
            if arguments.contains("-lybUITestHomeV2EstimateHeroFixture") {
                XCTAssertEqual(latest.bodyFatMethod, "visual_estimate")
            }
            if arguments.contains("-lybUITestHomeV2TimelineFixture") {
                XCTAssertEqual(latest.photoUrl, "fixture-timeline-0.jpg")
            }
        }
    }

    // Nil/empty owner compatibility is existing behavior for legacy unowned rows.
    // A populated owner remains immutable; these fixtures do not relax that guard.
    func testLegacyUnownedLocalBodyMetricCanStillReceiveItsOwner() async throws {
        let legacyOwners: [String?] = [nil, ""]
        for legacyOwner in legacyOwners {
            let owner = "sync_test_owner_\(UUID().uuidString)"
            let id = UUID().uuidString
            let date = wholeSecondDate(280)
            try await insertLegacyUnownedBodyMetric(id: id, owner: legacyOwner, date: date)
            try await CoreDataManager.shared.saveBodyMetricsAndWait(
                dashboardFixtureMetric(id: id, userId: owner, date: date, notes: "local owner claim"),
                userId: owner
            )
            let cached = await cachedBodyMetric(id: id)
            let row = try XCTUnwrap(cached)
            XCTAssertEqual(row.userId, owner)
            XCTAssertEqual(row.weight, 82.1, accuracy: 0.001)
            XCTAssertEqual(row.notes, "local owner claim")
            XCTAssertEqual(row.createdAt, date)
        }
    }

    func testLegacyUnownedRemoteBodyMetricCanStillReceiveItsOwner() async throws {
        let legacyOwners: [String?] = [nil, ""]
        for legacyOwner in legacyOwners {
            let owner = "sync_test_owner_\(UUID().uuidString)"
            let id = UUID().uuidString
            let date = wholeSecondDate(300)
            try await insertLegacyUnownedBodyMetric(id: id, owner: legacyOwner, date: date)
            let formatter = ISO8601DateFormatter()
            await CoreDataManager.shared.updateOrCreateBodyMetricAndWait(from: [
                "id": id, "user_id": owner, "date": formatter.string(from: date),
                "weight": 83.0, "weight_unit": "kg", "notes": "remote owner claim",
                "created_at": formatter.string(from: date),
                "updated_at": formatter.string(from: Date().addingTimeInterval(60))
            ])
            let cached = await cachedBodyMetric(id: id)
            let row = try XCTUnwrap(cached)
            XCTAssertEqual(row.userId, owner)
            XCTAssertEqual(row.weight, 83.0, accuracy: 0.001)
            XCTAssertEqual(row.notes, "remote owner claim")
            XCTAssertEqual(row.createdAt, date)
        }
    }

    private func insertLegacyUnownedBodyMetric(id: String, owner: String?, date: Date) async throws {
        let context = CoreDataManager.shared.viewContext
        try await context.perform {
            let row = CachedBodyMetrics(context: context)
            row.id = id
            row.userId = owner
            row.date = date
            row.localDate = BodyMetricLocalDate.key(for: date)
            row.weight = 70
            row.weightUnit = "kg"
            row.notes = "legacy unowned"
            row.createdAt = date
            row.updatedAt = date
            row.isSynced = true
            try context.save()
        }
    }

    private func dashboardFixtureMetric(id: String, userId: String, date: Date, notes: String) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 82.1,
            weightUnit: "kg",
            bodyFatPercentage: 15.8,
            bodyFatMethod: "manual",
            muscleMass: 66.2,
            boneMass: nil,
            notes: notes,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

private final class DeferredDexaProductAPIClient: ProductAPIClient {
    private let beforeResponse: () async throws -> Void

    init(beforeResponse: @escaping () async throws -> Void) {
        self.beforeResponse = beforeResponse
        super.init()
    }

    override func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        XCTAssertEqual(table, "dexa_results")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        // Suspend at the real port boundary while a newer local row is persisted.
        try await beforeResponse()
        return sent.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ["id": id]
        }
    }
}
