//
// SyncIntegrationImportAndMappingTests.swift
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
final class SyncIntegrationImportAndMappingTests: XCTestCase {
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

    func testCleanupOldDataDeletesOnlyOldTombstonedBodyMetrics() async throws {
        let coreData = CoreDataManager.shared

        let userId = "cleanup_user_\(UUID().uuidString)"
        let oldDeletedId = UUID().uuidString
        let recentDeletedId = UUID().uuidString
        let oldLiveId = UUID().uuidString
        let now = Date()
        let oldDate = now.addingTimeInterval(-370 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-10 * 24 * 60 * 60)

        let oldDeletedMetric = BodyMetrics(
            id: oldDeletedId,
            userId: userId,
            date: oldDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let recentDeletedMetric = BodyMetrics(
            id: recentDeletedId,
            userId: userId,
            date: recentDate,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: recentDate,
            updatedAt: recentDate
        )
        let oldLiveMetric = BodyMetrics(
            id: oldLiveId,
            userId: userId,
            date: oldDate,
            weight: 82.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: oldDate,
            updatedAt: oldDate
        )

        try await coreData.saveBodyMetricsAndWait(oldDeletedMetric, userId: userId, markAsSynced: true)
        try await coreData.saveBodyMetricsAndWait(recentDeletedMetric, userId: userId, markAsSynced: true)
        try await coreData.saveBodyMetricsAndWait(oldLiveMetric, userId: userId, markAsSynced: true)

        let didMarkOldDeleted = await coreData.markBodyMetricDeleted(id: oldDeletedId)
        let didMarkRecentDeleted = await coreData.markBodyMetricDeleted(id: recentDeletedId)
        XCTAssertTrue(didMarkOldDeleted)
        XCTAssertTrue(didMarkRecentDeleted)

        await coreData.cleanupOldData()

        let context = coreData.viewContext
        let remainingIds = await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)

            let metrics = (try? context.fetch(request)) ?? []
            return Set(metrics.compactMap(\.id))
        }

        XCTAssertFalse(remainingIds.contains(oldDeletedId))
        XCTAssertTrue(remainingIds.contains(recentDeletedId))
        XCTAssertTrue(remainingIds.contains(oldLiveId))
    }

    func testBodySpecDexaImporter_AddsProvenanceWithoutOverwritingManualOrHealthKit() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager()

        let userId = "bodyspec_import_user_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "bodyspec@example.com",
            name: "BodySpec Import",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        authManager.currentUser = user

        let scanDate = wholeSecondDate(20_000)
        let manualMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: scanDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: 20.0,
            bodyFatMethod: "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: "same-day manual entry",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: scanDate,
            updatedAt: scanDate
        )
        try await coreData.saveBodyMetricsAndWait(manualMetric, userId: userId, markAsSynced: false)

        let healthKitMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: scanDate.addingTimeInterval(600),
            weight: 80.4,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "same-day HealthKit entry",
            photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(vendor: "apple_health", sampleId: "hk-sample"),
            createdAt: scanDate,
            updatedAt: scanDate
        )
        try await coreData.saveBodyMetricsAndWait(healthKitMetric, userId: userId, markAsSynced: false)

        let resultId = "bodyspec-result-123"
        let stubAPI = StubBodySpecDexaAPI()
        stubAPI.pages[1] = BodySpecResultsListResponse(results: [
            makeBodySpecSummary(resultId: resultId, startTime: scanDate)
        ])
        stubAPI.scanInfos[resultId] = BodySpecDexaScanInfoResponse(
            resultId: resultId,
            scannerModel: "Hologic Horizon A",
            acquireTime: scanDate.addingTimeInterval(1_200),
            analyzeTime: scanDate.addingTimeInterval(1_500)
        )
        stubAPI.compositions[resultId] = makeBodySpecComposition(resultId: resultId)

        let importer = BodySpecDexaImporter(
            api: stubAPI,
            authManager: authManager,
            coreDataManager: coreData
        )

        let importResult = await importer.importDexaResults()

        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.skippedCount, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 3)

        let manual = try XCTUnwrap(metrics.first { $0.id == manualMetric.id })
        XCTAssertEqual(manual.dataSource, "manual")
        XCTAssertEqual(try XCTUnwrap(manual.weight), 80.0, accuracy: 0.001)

        let healthKit = try XCTUnwrap(metrics.first { $0.id == healthKitMetric.id })
        XCTAssertEqual(healthKit.dataSource, "healthkit")
        XCTAssertEqual(try XCTUnwrap(healthKit.weight), 80.4, accuracy: 0.001)

        let dexa = try XCTUnwrap(metrics.first { $0.dataSource == BodyMetricSource.bodySpecDexa.rawValue })
        XCTAssertEqual(dexa.bodyFatMethod, "DEXA (BodySpec)")
        XCTAssertEqual(try XCTUnwrap(dexa.weight), 79.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.bodyFatPercentage), 17.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.muscleMass), 62.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dexa.boneMass), 3.2, accuracy: 0.001)

        let sourceMetadata = try XCTUnwrap(dexa.sourceMetadata)
        XCTAssertEqual(sourceMetadata.vendor, "bodyspec")
        XCTAssertEqual(sourceMetadata.sourceName, "BodySpec DEXA")
        XCTAssertEqual(sourceMetadata.externalId, "svc-dxa")
        XCTAssertEqual(sourceMetadata.externalResultId, resultId)
        XCTAssertEqual(sourceMetadata.scannerModel, "Hologic Horizon A")
        XCTAssertEqual(sourceMetadata.locationId, "loc-santa-monica")
        XCTAssertEqual(sourceMetadata.locationName, "Santa Monica")
        XCTAssertNotNil(sourceMetadata.importedAt)

        let dexaResults = await coreData.fetchDexaResults(for: userId, limit: 10)
        XCTAssertEqual(dexaResults.count, 1)
        XCTAssertEqual(dexaResults.first?.bodyMetricsId, dexa.id)
        XCTAssertEqual(dexaResults.first?.externalSource, "bodyspec")
        XCTAssertEqual(dexaResults.first?.externalResultId, resultId)
    }

    func testBodySpecDexaImporter_SkipsExistingExternalResultId() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager()

        let userId = "bodyspec_duplicate_user_\(UUID().uuidString)"
        authManager.currentUser = LocalUser(
            id: userId,
            email: "bodyspec-duplicate@example.com",
            name: "BodySpec Duplicate",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )

        let scanDate = wholeSecondDate(30_000)
        let resultId = "bodyspec-result-duplicate"
        let stubAPI = StubBodySpecDexaAPI()
        stubAPI.pages[1] = BodySpecResultsListResponse(results: [
            makeBodySpecSummary(resultId: resultId, startTime: scanDate)
        ])
        stubAPI.scanInfos[resultId] = BodySpecDexaScanInfoResponse(
            resultId: resultId,
            scannerModel: "Hologic Horizon A",
            acquireTime: scanDate,
            analyzeTime: scanDate.addingTimeInterval(300)
        )
        stubAPI.compositions[resultId] = makeBodySpecComposition(resultId: resultId)

        let importer = BodySpecDexaImporter(
            api: stubAPI,
            authManager: authManager,
            coreDataManager: coreData
        )

        let firstImport = await importer.importDexaResults()
        let secondImport = await importer.importDexaResults()

        XCTAssertEqual(firstImport.importedCount, 1)
        XCTAssertEqual(firstImport.skippedCount, 0)
        XCTAssertEqual(secondImport.importedCount, 0)
        XCTAssertEqual(secondImport.skippedCount, 1)
        XCTAssertEqual(stubAPI.compositionRequests.filter { $0 == resultId }.count, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.filter { $0.dataSource == BodyMetricSource.bodySpecDexa.rawValue }.count, 1)
    }

    func testUpdateOrCreateBodyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_\(UUID().uuidString)"
        let date = wholeSecondDate()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.5,
            "weight_unit": "kg",
            "body_fat_percentage": 18.2,
            "body_fat_method": "health_kit",
            "muscle_mass": 35.0,
            "bone_mass": 4.2,
            "photo_url": "https://example.com/photo.jpg",
            "notes": "supabase-mapped",
            "data_source": "HealthKit",
            "source_metadata": [
                "sample_id": "hk-sample-123",
                "device_model": "Withings Body Scan"
            ],
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 80.5, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")

        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 18.2, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "health_kit")

        let muscle = try XCTUnwrap(metric.muscleMass)
        XCTAssertEqual(muscle, 35.0, accuracy: 0.001)

        let bone = try XCTUnwrap(metric.boneMass)
        XCTAssertEqual(bone, 4.2, accuracy: 0.001)

        XCTAssertEqual(metric.photoUrl, "https://example.com/photo.jpg")
        XCTAssertEqual(metric.notes, "supabase-mapped")
        XCTAssertEqual(metric.dataSource, "healthkit")
        XCTAssertEqual(metric.sourceMetadata?.sampleId, "hk-sample-123")
        XCTAssertEqual(metric.sourceMetadata?.deviceModel, "Withings Body Scan")

        XCTAssertEqual(metric.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }
}
