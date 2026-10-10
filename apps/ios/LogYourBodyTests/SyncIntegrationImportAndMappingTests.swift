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

    func testUpdateOrCreateBodyMetric_MapsProductAPIPayload() async throws {
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
            "notes": "productAPI-mapped",
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
        XCTAssertEqual(metric.notes, "productAPI-mapped")
        XCTAssertEqual(metric.dataSource, "healthkit")
        XCTAssertEqual(metric.sourceMetadata?.sampleId, "hk-sample-123")
        XCTAssertEqual(metric.sourceMetadata?.deviceModel, "Withings Body Scan")

        XCTAssertEqual(metric.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateBodyMetricNormalizesDisplayUnitsForLocalStorage() async throws {
        let coreData = CoreDataManager.shared
        let id = UUID().uuidString
        let userId = "sync_test_user_body_imperial_\(UUID().uuidString)"
        let date = wholeSecondDate(1_500)
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 180.0,
            "weight_unit": "lbs",
            "waist_circumference": 40.0,
            "hip_circumference": 42.0,
            "waist_unit": "in"
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let cachedMetric = await cachedBodyMetric(id: id)
        let metric = try XCTUnwrap(cachedMetric)
        XCTAssertEqual(metric.weight, UnitConversion.lbsToKg(180), accuracy: 0.0001)
        XCTAssertEqual(metric.weightUnit, "kg")
        XCTAssertEqual(metric.waistCircumference, 101.6, accuracy: 0.0001)
        XCTAssertEqual(metric.hipCircumference, 106.68, accuracy: 0.0001)
        XCTAssertEqual(metric.waistUnit, "cm")
    }

    private func provenanceScan(source: String?) -> DexaPDFScan {
        DexaPDFScan(
            date: "2026-09-20", weight: 82.4, weightUnit: "kg",
            bodyFatPercentage: 21.2, muscleMass: nil, boneMass: nil, source: source
        )
    }

    private func legacyPDFResult(sourceLabel: String) -> DexaResult {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return DexaResult(
            id: "legacy-result", userId: "pdf-user", bodyMetricsId: "legacy-metric",
            externalSource: "dexa_pdf",
            externalResultId: "442b94e3684e5af7e8e7daba5bd8b1b4d89ef71662c7317d9cac4e898cc27e50",
            externalUpdateTime: nil, scannerModel: sourceLabel, locationId: nil, locationName: nil,
            acquireTime: date, analyzeTime: nil, vatMassKg: nil, vatVolumeCm3: nil,
            scanWeight: 82.4, scanWeightUnit: "kg", bodyFatPercentage: 21.2,
            resultPdfUrl: nil, resultPdfName: nil, createdAt: date, updatedAt: date
        )
    }

    func testPDFPreviewUsesTheReportedLabelOrAnUnidentifiedFallback() {
        XCTAssertEqual(PDFScanProvenance(source: nil).displayLabel, "Source not identified")
        XCTAssertEqual(PDFScanProvenance(source: "  ").displayLabel, "Source not identified")
        XCTAssertEqual(PDFScanProvenance(source: "Other").displayLabel, "Other")
        XCTAssertEqual(PDFScanProvenance(source: " InBody 770 ").displayLabel, "InBody 770")
    }

    func testUnidentifiedPDFsDoNotInventDexaProvenance() throws {
        let sources: [String?] = [
            nil, "", "  ", "Other", "Unidentified device", "Not DEXA", "DEXA / InBody",
            "DEXA not confirmed", "InBody unknown", "DXA unconfirmed", "In Body possibly",
            "DEXA?", "InBody (method uncertain)", "DEXA confirmation pending", "DXA cannot confirm"
        ]
        for source in sources {
            let plan = DexaPDFScanMapper.makePlan(
                scans: [provenanceScan(source: source)], userId: "pdf-user", existingResults: []
            )
            let metric = try XCTUnwrap(plan.metrics.first)
            XCTAssertEqual(metric.dataSource, "pdf_import", "Source: \(source ?? "nil")")
            XCTAssertNil(metric.bodyFatMethod)
            XCTAssertEqual(metric.notes, "Imported from PDF")
            let reportedLabel = source?.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(metric.sourceMetadata?.sourceName, reportedLabel?.isEmpty == false ? reportedLabel : nil)
            XCTAssertEqual(plan.results.first?.externalSource, "pdf_import")
        }
    }

    func testExplicitPDFMethodsAndRawLabelsArePreserved() throws {
        let cases = [
            ("DEXA Scan", "dexa_pdf", "dexa"), ("DXA (Hologic)", "dexa_pdf", "dexa"),
            ("InBody 770", "inbody_pdf", "inbody"), ("In Body 770", "inbody_pdf", "inbody"),
            ("In-Body 770", "inbody_pdf", "inbody")
        ]
        for (label, source, method) in cases {
            let plan = DexaPDFScanMapper.makePlan(
                scans: [provenanceScan(source: label)], userId: "pdf-user", existingResults: []
            )
            let metric = try XCTUnwrap(plan.metrics.first)
            XCTAssertEqual(metric.dataSource, source)
            XCTAssertEqual(metric.bodyFatMethod, method)
            XCTAssertEqual(metric.sourceMetadata?.sourceName, label)
            XCTAssertNil(plan.results.first?.scannerModel, "A report label is not a scanner-model field")
        }
    }

    func testKnownPDFStableIdentifiersRemainCompatible() throws {
        let cases = [
            ("DEXA Scan", "442b94e3684e5af7e8e7daba5bd8b1b4d89ef71662c7317d9cac4e898cc27e50"),
            ("InBody 770", "13829dde213f237873778139a889ac40ca88922eead9f4ab957b5e530054a970")
        ]
        for (label, expected) in cases {
            let plan = DexaPDFScanMapper.makePlan(
                scans: [provenanceScan(source: label)], userId: "pdf-user", existingResults: []
            )
            XCTAssertEqual(plan.results.first?.externalResultId, expected)
        }
    }

    func testLegacyPDFImportsAreSkippedWithoutRelabelingTheExistingResult() {
        let cases: [(String?, String)] = [("Other", "Other"), (nil, "DEXA Scan"), ("In Body 770", "In Body 770")]
        for (source, oldLabel) in cases {
            let legacy = legacyPDFResult(sourceLabel: oldLabel)
            let plan = DexaPDFScanMapper.makePlan(
                scans: [provenanceScan(source: source)], userId: "pdf-user", existingResults: [legacy]
            )
            XCTAssertTrue(plan.metrics.isEmpty)
            XCTAssertTrue(plan.results.isEmpty)
            XCTAssertEqual(plan.skippedDuplicateCount, 1)
            XCTAssertEqual(legacy.externalSource, "dexa_pdf")
            XCTAssertEqual(legacy.scannerModel, oldLabel)
        }
    }

    func testLegacyAliasDoesNotHideADifferentReportedSource() {
        let plan = DexaPDFScanMapper.makePlan(
            scans: [provenanceScan(source: "Other")], userId: "pdf-user",
            existingResults: [legacyPDFResult(sourceLabel: "DEXA Scan")]
        )
        XCTAssertEqual(plan.metrics.count, 1)
        XCTAssertEqual(plan.results.first?.externalSource, "pdf_import")
        XCTAssertEqual(plan.skippedDuplicateCount, 0)
    }

    func testNewKnownAndUnknownPDFImportsDoNotCollideThroughLegacyAliases() {
        let unknown = provenanceScan(source: nil)
        let known = provenanceScan(source: "DEXA Scan")
        for scans in [[unknown, known], [known, unknown]] {
            let first = DexaPDFScanMapper.makePlan(scans: scans, userId: "pdf-user", existingResults: [])
            XCTAssertEqual(first.results.count, 2)
            XCTAssertEqual(Set(first.results.map(\.externalSource)), ["pdf_import", "dexa_pdf"])
            let repeated = DexaPDFScanMapper.makePlan(
                scans: scans, userId: "pdf-user", existingResults: first.results
            )
            XCTAssertTrue(repeated.results.isEmpty)
            XCTAssertEqual(repeated.skippedDuplicateCount, 2)
        }
        let knownPlan = DexaPDFScanMapper.makePlan(scans: [known], userId: "pdf-user", existingResults: [])
        let unknownPlan = DexaPDFScanMapper.makePlan(
            scans: [unknown], userId: "pdf-user", existingResults: knownPlan.results
        )
        XCTAssertEqual(unknownPlan.results.count, 1)
        XCTAssertEqual(unknownPlan.results.first?.externalSource, "pdf_import")
    }

    func testPDFImportProvenanceSurvivesLocalStorageAndPendingSync() async throws {
        let plan = DexaPDFScanMapper.makePlan(
            scans: [provenanceScan(source: "Unidentified device")], userId: "pdf-user", existingResults: []
        )
        let metric = try XCTUnwrap(plan.metrics.first)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: "pdf-user", markAsSynced: false)
        let cached = await cachedBodyMetric(id: metric.id)
        let saved = try XCTUnwrap(cached)
        XCTAssertEqual(saved.dataSource, "pdf_import")
        XCTAssertEqual(saved.toBodyMetrics()?.dataSource, "pdf_import")
        let pending = saved.pendingSyncItem()
        XCTAssertEqual(pending.dataSource, "pdf_import")
        XCTAssertNil(pending.bodyFatMethod)
        XCTAssertEqual(
            BodyMetricSourceMetadata(jsonString: pending.sourceMetadataJSON)?.sourceName, "Unidentified device"
        )
    }

    func testPDFImportProvenanceSurvivesRemotePullMapping() async throws {
        let id = UUID().uuidString
        CoreDataManager.shared.updateOrCreateBodyMetric(from: [
            "id": id, "user_id": "pdf-user", "date": "2026-09-20T12:00:00Z",
            "created_at": "2026-09-20T12:00:00Z", "updated_at": "2026-09-20T12:00:00Z",
            "local_date": "2026-09-20", "weight": 82.4, "weight_unit": "kg",
            "data_source": "pdf_import",
            "source_metadata": ["vendor": "pdf_import", "source_name": "Unidentified device"]
        ])
        let cached = await cachedBodyMetric(id: id)
        let saved = try XCTUnwrap(cached)
        XCTAssertEqual(saved.dataSource, "pdf_import")
        let metric = try XCTUnwrap(saved.toBodyMetrics())
        XCTAssertEqual(metric.dataSource, "pdf_import")
        XCTAssertNil(metric.bodyFatMethod)
        XCTAssertEqual(metric.sourceMetadata?.sourceName, "Unidentified device")
    }

    func testInBodyScanMapsToDatedMetricAndDurableDexaRecord() throws {
        let scan = DexaPDFScan(
            date: "2026-09-20",
            weight: 82.4,
            weightUnit: "kg",
            bodyFatPercentage: 21.2,
            muscleMass: 61.8,
            boneMass: 3.1,
            source: "InBody 770"
        )

        let plan = DexaPDFScanMapper.makePlan(
            scans: [scan],
            userId: "pdf-import-user",
            existingResults: [],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let metric = try XCTUnwrap(plan.metrics.first)
        let result = try XCTUnwrap(plan.results.first)
        XCTAssertEqual(plan.metrics.count, 1)
        XCTAssertEqual(plan.results.count, 1)
        XCTAssertEqual(metric.localDate, "2026-09-20")
        XCTAssertEqual(metric.dataSource, "inbody_pdf")
        XCTAssertEqual(metric.bodyFatPercentage, 21.2)
        XCTAssertEqual(metric.sourceMetadata?.sourceName, "InBody 770")
        XCTAssertEqual(result.externalSource, "inbody_pdf")
        XCTAssertEqual(result.scanWeight, 82.4)
        XCTAssertEqual(result.muscleMass, 61.8)
        XCTAssertNil(result.resultPdfName)
        XCTAssertEqual(result.bodyMetricsId, metric.id)
    }

    func testDexaImportExplainsEmptyAndUnusableReports() {
        XCTAssertEqual(
            DexaPDFImportMessagePolicy.readErrorMessage(for: []),
            DexaPDFImportMessagePolicy.noScansFound
        )

        let undatedScan = DexaPDFScan(
            date: "not a date",
            weight: 82.4,
            weightUnit: "kg",
            bodyFatPercentage: 21.2,
            muscleMass: nil,
            boneMass: nil,
            source: "DEXA"
        )
        XCTAssertNil(DexaPDFImportMessagePolicy.readErrorMessage(for: [undatedScan]))

        let plan = DexaPDFScanMapper.makePlan(scans: [undatedScan], userId: "pdf-import-user", existingResults: [])
        XCTAssertEqual(
            DexaPDFImportMessagePolicy.savedSummary(
                resultCount: plan.results.count,
                metricCount: plan.metrics.count,
                skippedDuplicateCount: plan.skippedDuplicateCount
            ),
            DexaPDFImportMessagePolicy.unusableScans
        )
        XCTAssertEqual(
            DexaPDFImportMessagePolicy.savedSummary(resultCount: 0, metricCount: 0, skippedDuplicateCount: 2),
            "These scans were already imported."
        )
        XCTAssertEqual(
            DexaPDFImportMessagePolicy.savedSummary(resultCount: 1, metricCount: 1, skippedDuplicateCount: 0),
            "Added 1 scan and 1 new dated timeline entry."
        )
    }

    func testSameDayEntryIsPreservedAndRepeatImportIsDeduplicated() throws {
        let scan = DexaPDFScan(
            date: "2026-09-20",
            weight: 82.4,
            weightUnit: "kg",
            bodyFatPercentage: 21.2,
            muscleMass: nil,
            boneMass: nil,
            source: "DEXA Scan"
        )
        let existingMetric = BodyMetrics(
            id: "manual-same-day",
            userId: "pdf-import-user",
            date: Date(timeIntervalSince1970: 1_790_000_000),
            localDate: "2026-09-20",
            weight: 83,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let firstImport = DexaPDFScanMapper.makePlan(
            scans: [scan],
            userId: existingMetric.userId,
            existingResults: []
        )

        XCTAssertEqual(firstImport.metrics.count, 1)
        XCTAssertNotEqual(firstImport.results.first?.bodyMetricsId, existingMetric.id)
        XCTAssertEqual(existingMetric.weight, 83)

        let repeatedImport = DexaPDFScanMapper.makePlan(
            scans: [scan],
            userId: existingMetric.userId,
            existingResults: firstImport.results
        )
        XCTAssertTrue(repeatedImport.metrics.isEmpty)
        XCTAssertTrue(repeatedImport.results.isEmpty)
        XCTAssertEqual(repeatedImport.skippedDuplicateCount, 1)
    }
}
