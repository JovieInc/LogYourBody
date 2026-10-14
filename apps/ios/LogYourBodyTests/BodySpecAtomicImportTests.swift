import XCTest
import CoreData
@testable import LogYourBody

@MainActor
final class BodySpecAtomicImportTests: XCTestCase {
    private var manager: CoreDataManager!
    private var storeURL: URL!
    private var auth: AuthManager!
    private var syncCount = 0
    private let owner = "synthetic-bodyspec-owner"
    private let scanDate = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() async throws {
        try await super.setUp()
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BodySpec-\(UUID()).sqlite")
        try openStore()
        auth = AuthManager()
        auth.authSession = .localFixture(subject: owner, email: "scan@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: owner, email: "scan@example.invalid", name: "Synthetic Scan", avatarUrl: nil,
            profile: nil, onboardingCompleted: true
        )
        syncCount = 0
    }

    override func tearDown() async throws {
        try closeStore()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
        auth = nil
        try await super.tearDown()
    }

    func testRetryRepairsDurableOrphanWithoutReplacingItsMetric() async throws {
        let original = metric(id: "original-metric", weight: 81, photo: "file:///synthetic-photo.jpg")
        try await manager.saveBodyMetricsAndWait(original, userId: owner)
        try closeStore()
        try openStore()
        let importer = importer(api: api())
        let outcome = await importer.importDexaResults()
        XCTAssertEqual(outcome.importedCount, 1)
        let rows = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.bodyMetricsId, original.id)
        let metrics = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.id, original.id)
        XCTAssertEqual(metrics.first?.weight, 81)
        XCTAssertEqual(metrics.first?.photoUrl, original.photoUrl)
        XCTAssertEqual(metrics.first?.muscleMass, 62, "Orphan repair must not relabel the historical scalar")
        XCTAssertEqual(metrics.first?.sourceMetadata, original.sourceMetadata)
        let repairedMeasurements = try XCTUnwrap(rows.first?.reportedMeasurements)
        XCTAssertEqual(repairedMeasurements.knownMeasurements.first?.kind, .leanMass)
        XCTAssertEqual(repairedMeasurements.knownMeasurements.first?.value, 62)
        let repeatOutcome = await importer.importDexaResults()
        XCTAssertEqual(repeatOutcome.importedCount, 0)
        XCTAssertEqual(repeatOutcome.skippedCount, 1)
        XCTAssertEqual(syncCount, 1)
    }

    func testConcurrentImportsAdmitOnlyOneCompletePair() async throws {
        let transport = api(holdForTwoCompositions: true)
        let first = importer(api: transport)
        let second = importer(api: transport)
        async let firstResult = first.importDexaResults()
        async let secondResult = second.importDexaResults()
        let outcomes = await [firstResult, secondResult]
        XCTAssertEqual(outcomes.map(\.importedCount).reduce(0, +), 1)
        XCTAssertEqual(outcomes.map(\.skippedCount).reduce(0, +), 1)
        let metrics = await manager.fetchAllBodyMetrics(for: owner)
        let rows = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.bodyMetricsId, metrics.first?.id)
        XCTAssertEqual(syncCount, 1)
    }

    func testNewPairSurvivesReopenWithBothRowsPending() async throws {
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.importedCount, 1)
        XCTAssertEqual(outcome.failedCount, 0)
        try closeStore()
        try openStore()
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertEqual(pending.bodyMetrics.count, 1)
        XCTAssertEqual(pending.dexaResults.count, 1)
        XCTAssertEqual(pending.dexaResults.first?.bodyMetricsId, pending.bodyMetrics.first?.id)
        XCTAssertEqual(pending.bodyMetrics.first?.weight, 79.2)
        XCTAssertEqual(pending.dexaResults.first?.externalResultId, "result-1")
        XCTAssertEqual(pending.bodyMetrics.first?.muscleMass, 0, "The existing pending snapshot uses a zero sentinel")
        let reopenedMetrics = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertNil(reopenedMetrics.first?.muscleMass)
        XCTAssertNil(pending.dexaResults.first?.muscleMass)
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: pending.dexaResults.first?.reportedMeasurementsJSON))
        XCTAssertEqual(envelope.knownMeasurements, [ReportedMeasurements.KnownMeasurement(
            kind: .leanMass, value: 62, unit: .kilograms, reportedLabel: "lean_mass_kg", reportedUnit: "kg"
        )])
        XCTAssertEqual(pending.dexaResults.first?.userId, owner)
        XCTAssertEqual(pending.dexaResults.first?.acquireTime, scanDate)
        XCTAssertEqual(pending.dexaResults.first?.analyzeTime, scanDate)

        let transport = StubProductAPIClient()
        let sync = RealtimeSyncManager(coreDataManager: manager, authManager: auth, productAPIClient: transport)
        try await sync.syncBodyMetricsBatch(pending.bodyMetrics, token: "synthetic")
        let metricPayload = try XCTUnwrap(transport.bodyMetricsBatches.first?.first)
        XCTAssertTrue(metricPayload["muscle_mass"] is NSNull)
        try await sync.syncDexaResultsBatch(pending.dexaResults, token: "synthetic")
        let payload = try XCTUnwrap(transport.dexaPayloads.first)
        let uploaded = try XCTUnwrap(payload["reported_measurements"] as? [String: Any])
        XCTAssertEqual(uploaded as NSDictionary, envelope.jsonObject as NSDictionary)
        XCTAssertTrue(payload["muscle_mass"] is NSNull)
        XCTAssertEqual(payload["user_id"] as? String, owner)
        XCTAssertEqual(payload["external_result_id"] as? String, "result-1")
        XCTAssertEqual(payload["body_metrics_id"] as? String, pending.bodyMetrics.first?.id)
        let acknowledged = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertTrue(acknowledged.dexaResults.isEmpty)
        XCTAssertTrue(acknowledged.bodyMetrics.isEmpty)
    }

    func testAtomicInsertPreservesOpaqueReportedMeasurementsWithoutProjection() async throws {
        let envelope = try XCTUnwrap(ReportedMeasurements(jsonString: ReportedMeasurementsTestFixture.futureJSON))
        let scan = result(measurements: envelope)
        XCTAssertEqual(try manager.commitBodySpecImportPair(
            metric: metric(), result: scan, userId: owner, writeAdmission: {}
        ), .inserted)
        try closeStore()
        try openStore()
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertEqual(pending.dexaResults.first?.reportedMeasurementsJSON, envelope.jsonString)
        XCTAssertEqual(pending.bodyMetrics.first?.muscleMass, 62, "The persistence seam never derives or relabels scalars")
        XCTAssertNil(pending.dexaResults.first?.muscleMass)
    }

    func testInvalidLeanMassFailsBeforeEitherRowOrSync() async throws {
        for leanMass in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            let outcome = await importer(api: api(leanMass: leanMass)).importDexaResults()
            XCTAssertEqual(outcome.failedCount, 1)
            XCTAssertEqual(outcome.importedCount, 0)
            XCTAssertEqual(outcome.skippedCount, 0)
            XCTAssertEqual(outcome.summaryTitle, "Sync incomplete")
            let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
            XCTAssertTrue(pending.bodyMetrics.isEmpty)
            XCTAssertTrue(pending.dexaResults.isEmpty)
            XCTAssertEqual(syncCount, 0)
            try await manager.deleteAllDataAndWait()
        }
        try closeStore()
        try openStore()
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertTrue(pending.bodyMetrics.isEmpty)
        XCTAssertTrue(pending.dexaResults.isEmpty)
    }

    func testExplicitPositiveLeanValuesKeepUnitsAndDoNotUseOtherCompositionFields() async throws {
        for leanMass in [0.000001, 62.345678] {
            let outcome = await importer(api: api(leanMass: leanMass)).importDexaResults()
            XCTAssertEqual(outcome.importedCount, 1)
            let metrics = await manager.fetchAllBodyMetrics(for: owner)
            let scans = await manager.fetchDexaResults(for: owner, limit: 10)
            let item = try XCTUnwrap(scans.first?.reportedMeasurements?.knownMeasurements.first)
            XCTAssertEqual(item.kind, .leanMass)
            XCTAssertEqual(item.value, leanMass)
            XCTAssertEqual(item.unit, .kilograms)
            XCTAssertEqual(item.reportedLabel, "lean_mass_kg")
            XCTAssertEqual(item.reportedUnit, "kg")
            XCTAssertNil(metrics.first?.muscleMass)
            XCTAssertEqual(metrics.first?.weight, 79.2)
            XCTAssertEqual(metrics.first?.bodyFatPercentage, 17.7, "Keep region percentage, not tissue percentage")
            XCTAssertEqual(metrics.first?.boneMass, 3.2)
            try await manager.deleteAllDataAndWait()
        }
    }

    func testReadOnlySQLiteSaveFailureLeavesNoPairAndPreservesUnrelatedEdit() async throws {
        try await manager.saveBodyMetricsAndWait(metric(id: "unrelated", source: "manual", externalID: nil), userId: owner)
        try closeStore()
        try openStore(readOnly: true)
        let unrelated = try cachedMetric("unrelated")
        unrelated.notes = "Unsaved work must survive"
        let failure = await importer(api: api()).importDexaResults()
        XCTAssertEqual(failure.importedCount, 0)
        XCTAssertEqual(failure.skippedCount, 0)
        XCTAssertEqual(failure.failedCount, 1)
        XCTAssertEqual(failure.summaryTitle, "Sync incomplete")
        XCTAssertEqual(syncCount, 0)
        XCTAssertTrue(unrelated.hasChanges)
        XCTAssertEqual(unrelated.notes, "Unsaved work must survive")
        let visibleResults = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(visibleResults.isEmpty)
        try closeStore()
        try openStore()
        let rows = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertEqual(rows.map(\.id), ["unrelated"])
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
        let retry = await importer(api: api()).importDexaResults()
        XCTAssertEqual(retry.importedCount, 1)
        XCTAssertEqual(syncCount, 1)
    }

    func testRepairDoesNotSaveOrOverwritePendingMetricEdits() async throws {
        try await manager.saveBodyMetricsAndWait(metric(id: "orphan"), userId: owner)
        let row = try cachedMetric("orphan")
        row.notes = "Unrelated pending note"
        row.photoUrl = "file:///pending-photo.jpg"
        row.weight = 83
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.importedCount, 1)
        XCTAssertEqual(row.notes, "Unrelated pending note")
        XCTAssertEqual(row.photoUrl, "file:///pending-photo.jpg")
        XCTAssertEqual(row.weight, 83)
        XCTAssertTrue(row.hasChanges)
        try closeStore()
        try openStore()
        let durable = try cachedMetric("orphan")
        XCTAssertEqual(durable.weight, 79.2)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertEqual(results.first?.bodyMetricsId, "orphan")
    }

    func testCompletePairPreservesPendingScanAndOpaqueMetricMetadata() async throws {
        try await manager.saveBodyMetricsAndWait(metric(), userId: owner)
        try await manager.saveDexaResultsAndWait([result()], userId: owner)
        let row = try cachedMetric("candidate-metric")
        // Use the model's canonical key while retaining an opaque future field.
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(
            try XCTUnwrap(metric().sourceMetadata?.jsonString).utf8
        )) as? [String: Any])
        metadata["future"] = ["a": 7]
        row.sourceMetadataJSON = String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)
        let bytes = row.sourceMetadataJSON
        XCTAssertEqual(row.muscleMass, 62)
        let request = CachedDexaResult.fetchRequest()
        let scan = try XCTUnwrap(manager.viewContext.fetch(request).first)
        // The independent main patch also runs composed with B1's additive model.
        let hasTypedModel = scan.entity.attributesByName["reportedMeasurementsJSON"] != nil
        let opaqueJSON = "{\"schema_version\":9,\"items\":[{\"kind\":\"future\",\"value\":123.5,\"unit\":\"unknown\"}]}"
        if hasTypedModel { scan.setValue(opaqueJSON, forKey: "reportedMeasurementsJSON") }
        try manager.viewContext.save()
        scan.scannerModel = "Pending scanner edit"
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.skippedCount, 1)
        XCTAssertEqual(outcome.failedCount, 0)
        XCTAssertEqual(scan.scannerModel, "Pending scanner edit")
        XCTAssertTrue(scan.hasChanges)
        XCTAssertFalse(scan.isSynced)
        XCTAssertEqual(row.sourceMetadataJSON, bytes)
        XCTAssertEqual(row.muscleMass, 62, "Duplicate admission must not rewrite historical muscle")
        if hasTypedModel {
            XCTAssertEqual(scan.value(forKey: "reportedMeasurementsJSON") as? String, opaqueJSON)
        }
        XCTAssertEqual(syncCount, 0)
        try closeStore()
        try openStore()
        let reopened = try XCTUnwrap(manager.viewContext.fetch(request).first)
        XCTAssertEqual(reopened.scannerModel, "Synthetic")
        if hasTypedModel {
            XCTAssertEqual(reopened.value(forKey: "reportedMeasurementsJSON") as? String, opaqueJSON)
            XCTAssertFalse(reopened.isSynced)
        }
    }

    func testForeignCandidateIDsCannotBeClaimed() async throws {
        try await manager.saveBodyMetricsAndWait(metric(userId: "other"), userId: "other")
        XCTAssertThrowsError(try commit()) { XCTAssertEqual($0 as? BodySpecImportPersistenceError, .conflictingRecords) }
        XCTAssertEqual(try cachedMetric("candidate-metric").userId, "other")
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testForeignResultIDCannotBeClaimed() async throws {
        try await manager.saveDexaResultsAndWait([result(userId: "other")], userId: "other")
        XCTAssertThrowsError(try commit()) { XCTAssertEqual($0 as? BodySpecImportPersistenceError, .conflictingRecords) }
        let other = await manager.fetchDexaResults(for: "other", limit: 10)
        XCTAssertEqual(other.first?.id, "candidate-result")
        let metrics = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertTrue(metrics.isEmpty)
    }

    func testAmbiguousOrphansFailWithoutCreatingAnotherPair() async throws {
        for id in ["orphan-a", "orphan-b"] {
            try await manager.saveBodyMetricsAndWait(metric(id: id), userId: owner)
        }
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.failedCount, 1)
        XCTAssertEqual(outcome.skippedCount, 0)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
        let metrics = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertEqual(metrics.count, 2)
    }

    func testDifferentOrForeignReverseScanLinkBlocksOrphanRepair() async throws {
        for scanOwner in [owner, "other"] {
            try await manager.deleteAllDataAndWait()
            try await manager.saveBodyMetricsAndWait(metric(), userId: owner)
            try await manager.saveDexaResultsAndWait(
                [result(userId: scanOwner, externalID: "different-result")], userId: scanOwner
            )
            let outcome = await importer(api: api()).importDexaResults()
            XCTAssertEqual(outcome.failedCount, 1)
            XCTAssertEqual(outcome.importedCount, 0)
            let results = try manager.viewContext.fetch(CachedDexaResult.fetchRequest())
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.externalResultId, "different-result")
        }
    }

    func testPendingMetricIdentityChangeBlocksConflictingInsert() async throws {
        try await manager.saveBodyMetricsAndWait(metric(id: "pending", externalID: "other-result"), userId: owner)
        let row = try cachedMetric("pending")
        row.sourceMetadataJSON = metric().sourceMetadata?.jsonString
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.failedCount, 1)
        XCTAssertEqual(outcome.importedCount, 0)
        XCTAssertTrue(row.hasChanges)
        XCTAssertEqual(row.sourceMetadataJSON, metric().sourceMetadata?.jsonString)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testPendingScanIdentityChangeBlocksConflictingInsert() async throws {
        try await manager.saveDexaResultsAndWait([result(externalID: "other-result")], userId: owner)
        let row = try XCTUnwrap(manager.viewContext.fetch(CachedDexaResult.fetchRequest()).first)
        row.externalResultId = "result-1"
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.failedCount, 1)
        XCTAssertEqual(outcome.importedCount, 0)
        XCTAssertTrue(row.hasChanges)
        XCTAssertEqual(row.externalResultId, "result-1")
        let results = try manager.viewContext.fetch(CachedDexaResult.fetchRequest())
        XCTAssertEqual(results.count, 1)
    }

    func testDurableAndPendingTombstonesAreNeverResurrected() async throws {
        try await manager.saveBodyMetricsAndWait(metric(), userId: owner)
        let row = try cachedMetric("candidate-metric")
        row.isMarkedDeleted = true
        let pending = await importer(api: api()).importDexaResults()
        XCTAssertEqual(pending.failedCount, 1)
        XCTAssertTrue(row.isMarkedDeleted)
        try manager.viewContext.save()
        let durable = await importer(api: api()).importDexaResults()
        XCTAssertEqual(durable.failedCount, 1)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(syncCount, 0)
    }

    func testDanglingResultAndForeignLinkAreNotSuccessfulDuplicates() async throws {
        try await manager.saveDexaResultsAndWait([result()], userId: owner)
        let dangling = await importer(api: api()).importDexaResults()
        XCTAssertEqual(dangling.failedCount, 1)
        XCTAssertEqual(dangling.skippedCount, 0)
        try await manager.saveBodyMetricsAndWait(metric(userId: "other"), userId: "other")
        let foreign = await importer(api: api()).importDexaResults()
        XCTAssertEqual(foreign.failedCount, 1)
        XCTAssertEqual(foreign.skippedCount, 0)
        XCTAssertEqual(syncCount, 0)
    }

    func testUnattributedLegacyMetricIsNotGivenAnInventedLink() async throws {
        try await manager.saveBodyMetricsAndWait(metric(externalID: nil), userId: owner)
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.failedCount, 1)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testWriteAdmissionAndInvalidLinksFailBeforeMutation() async throws {
        XCTAssertThrowsError(try manager.commitBodySpecImportPair(metric: metric(), result: result(), userId: owner) {
            throw CancellationError()
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try manager.commitBodySpecImportPair(
            metric: metric(), result: result(link: "wrong-link"), userId: owner, writeAdmission: {}
        )) { XCTAssertEqual($0 as? BodySpecImportPersistenceError, .invalidPair) }
        let rows = await manager.fetchAllBodyMetrics(for: owner)
        XCTAssertTrue(rows.isEmpty)
    }

    func testCancelledTaskCannotEnterCommitOrDuplicateAdmission() async throws {
        let task = Task { @MainActor in
            var admitted = false
            XCTAssertThrowsError(try manager.commitBodySpecImportPair(
                metric: metric(), result: result(), userId: owner, writeAdmission: { admitted = true }
            )) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertThrowsError(try manager.hasCompleteBodySpecImportPair(
                externalID: "result-1", userId: owner, writeAdmission: { admitted = true }
            )) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertFalse(admitted)
        }
        // This actor turn has not yielded, so cancellation precedes the synchronous commit attempt.
        task.cancel()
        try await task.value
        let metrics = await manager.fetchAllBodyMetrics(for: owner)
        let results = await manager.fetchDexaResults(for: owner, limit: 10)
        XCTAssertTrue(metrics.isEmpty)
        XCTAssertTrue(results.isEmpty)
    }

    func testCompletePairWithAdditionalReverseLinkIsNotSuccessfulDuplicate() async throws {
        try await manager.saveBodyMetricsAndWait(metric(), userId: owner)
        try await manager.saveDexaResultsAndWait([result()], userId: owner)
        let extra = CachedDexaResult(context: manager.viewContext)
        extra.id = "additional-scan"
        extra.userId = "other"
        extra.bodyMetricsId = "candidate-metric"
        extra.externalSource = "bodyspec"
        extra.externalResultId = "other-result"
        extra.createdAt = scanDate
        extra.updatedAt = scanDate
        try manager.viewContext.save()
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertEqual(outcome.failedCount, 1)
        XCTAssertEqual(outcome.skippedCount, 0)
        XCTAssertEqual(syncCount, 0)
    }

    func testCancelledSessionReportsIncompleteInsteadOfDuplicate() async {
        auth.authSession = nil
        auth.currentUser = nil
        let outcome = await importer(api: api()).importDexaResults()
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertEqual(outcome.skippedCount, 0)
        XCTAssertEqual(outcome.summaryTitle, "Sync incomplete")
        XCTAssertEqual(syncCount, 0)
    }

    func testConnectionReplacementAfterCompositionCannotCommitOrTriggerSync() async throws {
        let store = BodySpecMemoryTokenStore(token: syntheticBodySpecToken(owner: owner))
        let connection = BodySpecAuthManager(
            tokenStore: store,
            account: BodySpecAccountAccess(
                capture: { [auth] in auth?.captureAccountSession() },
                owns: { [auth] in auth?.ownsAccountSession($0) == true }
            ),
            configuration: { ("synthetic-client", "lyb-synthetic://callback") }
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let snapshot = try connection.connectionSnapshot(for: ownership)
        let transport = AtomicBodySpecAPI(
            scanDate: scanDate, holdForTwoCompositions: false,
            admission: { try snapshot.validate() },
            afterComposition: { try connection.disconnect() }
        )
        let outcome = await importer(api: transport).importDexaResults()
        XCTAssertTrue(auth.ownsAccountSession(ownership), "Only the provider connection changed")
        XCTAssertTrue(outcome.wasCancelled)
        XCTAssertEqual(outcome.importedCount, 0)
        XCTAssertEqual(outcome.skippedCount, 0)
        XCTAssertEqual(syncCount, 0)
        try closeStore()
        try openStore()
        let pending = try await manager.fetchPendingLocalSyncSnapshot(for: owner)
        XCTAssertTrue(pending.bodyMetrics.isEmpty)
        XCTAssertTrue(pending.dexaResults.isEmpty)
    }

    private func importer(api: BodySpecDexaAPIClient) -> BodySpecDexaImporter {
        BodySpecDexaImporter(api: api, authManager: auth, coreDataManager: manager) { [weak self] in
            self?.syncCount += 1
        }
    }

    private func api(holdForTwoCompositions: Bool = false, leanMass: Double = 62) -> AtomicBodySpecAPI {
        AtomicBodySpecAPI(scanDate: scanDate, holdForTwoCompositions: holdForTwoCompositions, leanMass: leanMass)
    }

    private func metric(
        id: String = "candidate-metric", weight: Double = 79.2, photo: String? = nil,
        userId: String? = nil, source: String = "bodyspec_dexa", externalID: String? = "result-1"
    ) -> BodyMetrics {
        BodyMetrics(
            id: id, userId: userId ?? owner, date: scanDate, weight: weight, weightUnit: "kg",
            bodyFatPercentage: 17.7, bodyFatMethod: "DEXA (BodySpec)", muscleMass: 62, boneMass: 3.2,
            notes: source == "manual" ? "Unrelated manual entry" : "Imported from BodySpec DEXA",
            photoUrl: photo, dataSource: source,
            sourceMetadata: BodyMetricSourceMetadata(vendor: "bodyspec", externalResultId: externalID),
            createdAt: scanDate, updatedAt: scanDate
        )
    }

    private func result(
        link: String = "candidate-metric", userId: String? = nil, externalID: String = "result-1",
        measurements: ReportedMeasurements? = nil
    ) -> DexaResult {
        DexaResult(
            id: "candidate-result", userId: userId ?? owner, bodyMetricsId: link, externalSource: "bodyspec",
            externalResultId: externalID, externalUpdateTime: scanDate, scannerModel: "Synthetic", locationId: nil,
            locationName: nil, acquireTime: scanDate, analyzeTime: scanDate, vatMassKg: nil, vatVolumeCm3: nil,
            reportedMeasurements: measurements, resultPdfUrl: nil, resultPdfName: nil, createdAt: scanDate, updatedAt: scanDate
        )
    }

    private func commit() throws -> BodySpecPairCommitOutcome {
        try manager.commitBodySpecImportPair(metric: metric(), result: result(), userId: owner, writeAdmission: {})
    }

    private func cachedMetric(_ id: String) throws -> CachedBodyMetrics {
        let request = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        return try XCTUnwrap(manager.viewContext.fetch(request).first)
    }

    private func openStore(readOnly: Bool = false) throws {
        let description = NSPersistentStoreDescription(url: storeURL)
        description.isReadOnly = readOnly
        description.shouldAddStoreAsynchronously = false
        manager = CoreDataManager(persistentStoreDescriptions: [description])
        XCTAssertEqual(manager.persistentContainer.persistentStoreCoordinator.persistentStores.count, 1)
    }

    private func closeStore() throws {
        guard let manager else { return }
        manager.viewContext.reset()
        for store in manager.persistentContainer.persistentStoreCoordinator.persistentStores {
            try manager.persistentContainer.persistentStoreCoordinator.remove(store)
        }
        self.manager = nil
    }
}

private actor AtomicBodySpecAPI: BodySpecDexaAPIClient {
    func importSession(for ownership: AuthManager.ProfileSessionOwnership) async throws -> BodySpecDexaImportSession {
        BodySpecDexaImportSession(api: self, admission: admission)
    }

    private let scanDate: Date
    private let holdForTwoCompositions: Bool
    private let leanMass: Double
    private var firstComposition: CheckedContinuation<Void, Never>?
    private let admission: @MainActor () throws -> Void
    private let afterComposition: @MainActor () throws -> Void

    init(
        scanDate: Date, holdForTwoCompositions: Bool, leanMass: Double = 62,
        admission: @escaping @MainActor () throws -> Void = {},
        afterComposition: @escaping @MainActor () throws -> Void = {}
    ) {
        self.scanDate = scanDate
        self.holdForTwoCompositions = holdForTwoCompositions
        self.leanMass = leanMass
        self.admission = admission
        self.afterComposition = afterComposition
    }

    func listResults(page: Int, pageSize: Int) -> BodySpecResultsListResponse {
        BodySpecResultsListResponse(results: [BodySpecResultSummary(
            resultId: "result-1", startTime: scanDate,
            location: BodySpecLocation(locationId: "synthetic-location", name: nil),
            service: BodySpecService(name: "DEXA", description: "Synthetic", serviceId: "service-1", serviceCode: "DXA")
        )])
    }

    func getDexaScanInfo(resultId: String) -> BodySpecDexaScanInfoResponse {
        BodySpecDexaScanInfoResponse(
            resultId: resultId, scannerModel: "Synthetic", acquireTime: scanDate, analyzeTime: scanDate
        )
    }

    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse {
        if holdForTwoCompositions {
            if let firstComposition {
                self.firstComposition = nil
                firstComposition.resume()
            } else {
                await withCheckedContinuation { firstComposition = $0 }
            }
        }
        try await afterComposition()
        return BodySpecDexaCompositionResponse(resultId: resultId, total: BodySpecBodyRegion(
            fatMassKg: 14, leanMassKg: leanMass, boneMassKg: 3.2, totalMassKg: 79.2,
            tissueFatPct: 18.4, regionFatPct: 17.7
        ))
    }
}
