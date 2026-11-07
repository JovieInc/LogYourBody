import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class MetricCorrectionTests: XCTestCase {
    private var manager: CoreDataManager!
    private var service: MetricCorrectionService!
    private var syncCount = 0
    private var invalidatedEvidence: [(String, [String])] = []
    private let owner = "metric-correction-owner"

    override func setUp() async throws {
        try await super.setUp()
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        manager = CoreDataManager(persistentStoreDescriptions: [store])
        service = MetricCorrectionService(
            coreDataManager: manager, isEnabled: { true }, admission: { _ in {} },
            syncTrigger: { self.syncCount += 1 },
            invalidateVisualizationDerivatives: { accountId, evidenceIds in
                self.invalidatedEvidence.append((accountId, evidenceIds))
            }
        )
    }

    override func tearDown() async throws {
        service = nil
        manager = nil
        try await super.tearDown()
    }

    func testExcludeThenUndoRestoresPriorCorrectionAndEveryOriginalField() async throws {
        let original = try await seed()
        let correction = try await service.correct(original, to: .init(weight: 79.125))
        XCTAssertEqual(invalidatedEvidence.first?.0, owner)
        XCTAssertEqual(invalidatedEvidence.first?.1, [original.id])
        let excluded = try await service.exclude(correction.metrics)
        XCTAssertTrue(excluded.metrics.isExcluded)
        XCTAssertEqual(excluded.metrics.correctedValue, correction.metrics.correctedValue)
        let restored = try await service.undo(excluded)
        try assertSameReading(restored.metrics, correction.metrics)
        XCTAssertFalse(restored.metrics.isExcluded)
        XCTAssertEqual(restored.metrics.originalWeight, 81.234567)
        XCTAssertEqual(restored.metrics.weight, 79.125)
        XCTAssertEqual(syncCount, 3)
        let row = try cached(original.id)
        XCTAssertEqual(row.weight, 81.234567)
        XCTAssertFalse(row.isSynced)
        XCTAssertEqual(row.syncStatus, "pending")
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertEqual(pending.bodyMetrics.first?.weight, 81.234567)
        XCTAssertEqual(pending.bodyMetrics.first?.isExcluded, false)
        XCTAssertEqual(MetricCorrectedValue(jsonString: pending.bodyMetrics.first?.correctedValueJSON)?.weight, 79.125)
    }

    func testCorrectionsLayerOverDexaAndUndoDoesNotMutateReportPayload() async throws {
        let original = try await seed(source: "bodyspec_dexa")
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let result = DexaResult(
            id: UUID().uuidString, userId: owner, bodyMetricsId: original.id, externalSource: "bodyspec",
            externalResultId: "report-243", externalUpdateTime: original.date, scannerModel: "scanner",
            locationId: nil, locationName: nil, acquireTime: original.date, analyzeTime: original.date,
            vatMassKg: nil, vatVolumeCm3: nil, scanWeight: 81.234567, scanWeightUnit: "kg",
            bodyFatPercentage: 18.25, muscleMass: nil, boneMass: 3.1,
            reportedMeasurements: envelope,
            resultPdfUrl: "https://example.com/original.pdf", resultPdfName: "original.pdf",
            createdAt: original.date, updatedAt: original.date
        )
        try await manager.saveDexaResultsAndWait([result], userId: owner)
        let before = await manager.fetchDexaResults(for: owner, limit: 10)
        let weight = try await service.correct(original, to: .init(weight: 80))
        let fat = try await service.correct(weight.metrics, to: .init(bodyFatPercentage: 17))
        XCTAssertEqual(fat.metrics.weight, 80)
        XCTAssertEqual(fat.metrics.bodyFatPercentage, 17)
        XCTAssertEqual(fat.metrics.originalBodyFatPercentage, 18.25)
        XCTAssertEqual(fat.metrics.bodyFatMethod, "DEXA (BodySpec)")
        XCTAssertEqual(fat.metrics.attributedBodyFatMethod, "manual")
        XCTAssertEqual(fat.metrics.measurementSource(for: .bodyFat), .manual)
        let undone = try await service.undo(fat)
        try assertSameReading(undone.metrics, weight.metrics)
        let after = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertEqual(before, after)
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertEqual(pending.dexaResults.first?.reportedMeasurementsJSON, envelope.jsonString)
    }

    func testExcludedReadingsRemainInFetchButNotLatestStatsTrendOrHero() async throws {
        let earlier = try await seed(offset: -86_400)
        let latest = try await seed(offset: 0, weight: 150)
        let excluded = try await service.exclude(latest)
        let readings = await manager.fetchBodyMetrics(for: owner)
        XCTAssertEqual(readings.count, 2)
        XCTAssertTrue(readings.contains { $0.id == latest.id && $0.isExcluded })
        let current = await manager.fetchLatestBodyMetric(for: owner)
        XCTAssertEqual(current?.id, earlier.id)
        XCTAssertEqual(current?.weight, 81.234567)
        let corrected = try await service.correct(earlier, to: .init(weight: 79.876543))
        let restored = try await service.undo(corrected)
        let cache = HeroMetricInterpolationCache()
        // Exercise the same exclusion contract before correction, after correction,
        // and after undo, including invalidation of the reused hero cache.
        for (reading, expectedEstimate) in [(earlier, 81.2), (corrected.metrics, 79.9), (restored.metrics, 81.2)] {
            try assertExcludedReadingIgnored(
                excluded.metrics, eligible: reading, expectedEstimate: expectedEstimate, cache: cache
            )
        }
        XCTAssertEqual(try cached(earlier.id).weight, 81.234567)
        XCTAssertEqual(try cached(latest.id).weight, 150)
    }

    private func assertExcludedReadingIgnored(
        _ excluded: BodyMetrics, eligible: BodyMetrics, expectedEstimate: Double,
        cache: HeroMetricInterpolationCache, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let all = [eligible, excluded]
        let stats = try XCTUnwrap(computeRangeStats(metrics: all) { $0.weight })
        XCTAssertEqual(stats.average, eligible.weight, file: file, line: line)
        let estimate = MetricsInterpolationService.shared.estimateWeight(for: excluded.date, metrics: all)
        // Estimates round to tenths; stored and effective measurements keep precision.
        XCTAssertEqual(estimate?.value, expectedEstimate, file: file, line: line)
        XCTAssertEqual(estimate?.isLastKnown, true, file: file, line: line)
        let hero = cache.values(for: excluded, in: all, heightInches: nil)
        XCTAssertEqual(hero.weight, expectedEstimate, file: file, line: line)
        let measured = cache.values(for: eligible, in: all, heightInches: nil)
        XCTAssertEqual(measured.weight, eligible.weight, file: file, line: line)
        XCTAssertEqual(eligible.originalWeight, 81.234567, file: file, line: line)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: all, owner: owner)
        XCTAssertEqual(snapshot.metrics.map(\.id), [eligible.id], file: file, line: line)
    }

    func testStaleUndoCannotOverwriteANewerCorrection() async throws {
        let original = try await seed()
        let first = try await service.correct(original, to: .init(weight: 80))
        let second = try await service.correct(first.metrics, to: .init(weight: 79))
        do {
            _ = try await service.undo(first)
            XCTFail("Stale receipt was accepted")
        } catch MetricCorrectionError.entryChanged {}
        XCTAssertEqual(try cached(original.id).toBodyMetrics(), second.metrics)
    }

    func testGateAndAccountAdmissionFailBeforeMutationAndUndoSurvivesGateOff() async throws {
        let original = try await seed()
        var enabled = false
        let gated = MetricCorrectionService(
            coreDataManager: manager, isEnabled: { enabled }, admission: { _ in {} }, syncTrigger: {}
        )
        do {
            _ = try await gated.exclude(original)
            XCTFail("Disabled feature accepted a mutation")
        } catch MetricCorrectionError.featureDisabled {}
        enabled = true
        let receipt = try await gated.exclude(original)
        enabled = false
        let undone = try await gated.undo(receipt)
        try assertSameReading(undone.metrics, original)
        let denied = MetricCorrectionService(
            coreDataManager: manager, isEnabled: { true }, admission: { _ in
                { throw MetricCorrectionError.notAuthorized }
            }, syncTrigger: { XCTFail("Denied mutation triggered sync") }
        )
        do {
            _ = try await denied.exclude(undone.metrics)
            XCTFail("Expired account accepted a mutation")
        } catch MetricCorrectionError.notAuthorized {}
        XCTAssertFalse(try cached(original.id).isExcluded)
    }

    func testInvalidValuesManualRowsAndMissingImportedFieldsAreRejected() async throws {
        let original = try await seed()
        for value in [Double.nan, .infinity, -1, 0, 301] {
            do {
                _ = try await service.correct(original, to: .init(weight: value))
                XCTFail("Invalid weight accepted")
            } catch MetricCorrectionError.invalidValue {}
        }
        let manual = try await seed(source: "manual")
        do {
            _ = try await service.exclude(manual)
            XCTFail("Manual entry accepted by import service")
        } catch MetricCorrectionError.notImported {}
        let row = try cached(original.id)
        row.bodyFatPercentage = 0
        try manager.viewContext.save()
        let missing = try XCTUnwrap(row.toBodyMetrics())
        do {
            _ = try await service.correct(missing, to: .init(bodyFatPercentage: 17))
            XCTFail("A missing imported field was replaced")
        } catch MetricCorrectionError.invalidValue {}
        XCTAssertEqual(syncCount, 0)
    }

    func testForeignOwnerMissingRowsAndTombstonesCannotBeEdited() async throws {
        let original = try await seed()
        let row = try cached(original.id)
        row.userId = "other-owner"
        try manager.viewContext.save()
        do {
            _ = try await service.exclude(original)
            XCTFail("Foreign row was edited")
        } catch MetricCorrectionError.entryChanged {}
        row.userId = owner
        row.isMarkedDeleted = true
        try manager.viewContext.save()
        do {
            _ = try await service.exclude(original)
            XCTFail("Deleted row was edited")
        } catch MetricCorrectionError.entryChanged {}
        manager.viewContext.delete(row)
        try manager.viewContext.save()
        do {
            _ = try await service.exclude(original)
            XCTFail("Missing row was recreated")
        } catch MetricCorrectionError.entryChanged {}
        XCTAssertEqual(syncCount, 0)
    }

    func testSaveFailureRollsBackOverlayAndPreservesUnrelatedPendingEdits() async throws {
        let original = try await seed()
        let unrelated = try await seed(offset: -86_400)
        let other = try cached(unrelated.id)
        other.notes = "unsaved photo note"
        do {
            _ = try await manager.updateMetricOverlayAndWait(
                expected: original, excluded: true, correctedValue: .init(weight: 79), writeAdmission: {},
                commit: { _ in throw MetricCorrectionError.notAuthorized }
            )
            XCTFail("Failed commit reported success")
        } catch MetricCorrectionError.notAuthorized {}
        XCTAssertFalse(try cached(original.id).isExcluded)
        XCTAssertNil(try cached(original.id).correctedValueJSON)
        XCTAssertTrue(other.hasChanges)
        XCTAssertEqual(other.notes, "unsaved photo note")
        manager.viewContext.rollback()
    }

    func testWireRoundTripKeepsOriginalsAndRemoteApplyKeepsOverlay() async throws {
        let original = try await seed()
        let receipt = try await service.correct(original, to: .init(weight: 78.123456))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(receipt.metrics)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(wire["weight"] as? Double, 81.234567)
        XCTAssertEqual((wire["corrected_value"] as? [String: Double])?["weight"], 78.123456)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BodyMetrics.self, from: data)
        XCTAssertEqual(decoded.originalWeight, original.originalWeight)
        XCTAssertEqual(decoded.weight, 78.123456)
        var server = wire
        server["is_excluded"] = true
        server["updated_at"] = "2099-01-01T00:00:00Z"
        await manager.updateOrCreateBodyMetricAndWait(from: server)
        let applied = try XCTUnwrap(cached(original.id).toBodyMetrics())
        XCTAssertTrue(applied.isExcluded)
        XCTAssertEqual(applied.weight, 78.123456)
        XCTAssertEqual(applied.originalWeight, 81.234567)
        server["corrected_value"] = NSNull()
        server["is_excluded"] = false
        await manager.updateOrCreateBodyMetricAndWait(from: server)
        let cleared = try XCTUnwrap(cached(original.id).toBodyMetrics())
        XCTAssertNil(cleared.correctedValue)
        XCTAssertEqual(cleared.weight, 81.234567)
    }

    private func seed(
        offset: TimeInterval = 0, weight: Double = 81.234567, source: String = "healthkit"
    ) async throws -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_780_000_000 + offset)
        let metric = BodyMetrics(
            id: UUID().uuidString, userId: owner, date: date, weight: weight, weightUnit: "kg",
            bodyFatPercentage: 18.25, bodyFatMethod: "DEXA (BodySpec)", muscleMass: nil, boneMass: 3.1,
            notes: "original note", photoUrl: "https://example.com/photo.png", dataSource: source,
            sourceMetadata: .init(vendor: source, sampleId: UUID().uuidString), createdAt: date, updatedAt: date
        )
        try await manager.saveBodyMetricsAndWait(metric, userId: owner, markAsSynced: true)
        return try XCTUnwrap(cached(metric.id).toBodyMetrics())
    }

    private func cached(_ id: String) throws -> CachedBodyMetrics {
        let request = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        return try XCTUnwrap(manager.viewContext.fetch(request).first)
    }

    private func assertSameReading(_ actual: BodyMetrics, _ expected: BodyMetrics) throws {
        // Updated-at is the sync version, not a measurement; undo must advance it.
        func fields(_ metric: BodyMetrics) throws -> NSDictionary {
            let data = try JSONEncoder().encode(metric)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.removeValue(forKey: "updated_at")
            return object as NSDictionary
        }
        XCTAssertEqual(try fields(actual), try fields(expected))
    }
}
