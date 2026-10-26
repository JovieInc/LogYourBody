import XCTest
import CoreData
import HealthKit
@testable import LogYourBody

@MainActor
final class HealthImportIdempotencyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var auth: AuthManager!
    private var coreData: CoreDataManager!
    private let owner = "health-import-idempotency"
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "HealthImportIdempotencyTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        auth.authSession = .localFixture(subject: owner, email: "health@example.invalid", accessToken: "synthetic")
        auth.currentUser = LocalUser(
            id: owner, email: "health@example.invalid", name: "Health fixture",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        store.shouldAddStoreAsynchronously = false
        coreData = CoreDataManager(persistentStoreDescriptions: [store])
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        auth = nil
        coreData = nil
        defaults = nil
        super.tearDown()
    }

    private func manager() -> HealthKitManager {
        HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            syncTrigger: {}, importCompletion: { _ in }, bodyFatOnlyImportEnabled: { true }
        )
    }

    private func metadata(
        id: String, source: String = "test.scale", kind: HKQuantityTypeIdentifier = .bodyMass,
        context: [String: String] = [:]
    ) -> BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: "apple_health", sourceName: source == "test.scale" ? "Scale" : "Apple Watch",
            sourceBundleId: source, sampleId: id, quantityType: kind.rawValue
        ).recordingHealthKitContext(context)
    }

    private func durableRows() async throws -> [BodyMetrics] {
        let context = coreData.persistentContainer.newBackgroundContext()
        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            return try context.fetch(request).compactMap { $0.toBodyMetrics() }
        }
    }

    func testDoubleImportTableKeepsRowsAndTimestampsUnchanged() async throws {
        let importer = manager()
        for index in 0..<3 {
            let day = date.addingTimeInterval(Double(index) * 86_400)
            let weights = index == 1 ? [] : [HealthKitWeightImportSample(
                weight: 80, date: day, sourceMetadata: metadata(id: "weight-\(index)")
                )
        ]
            let fats = index == 0 ? [] : [HealthKitBodyFatImportSample(
                percentage: 18.4, date: day,
                sourceMetadata: metadata(id: "fat-\(index)", kind: .bodyFatPercentage)
                )
        ]
            _ = await importer.processBatchHealthKitData(
                weightHistory: weights, bodyFatHistory: fats, sampleIdentityPolicy: true
            )
            let before = try await durableRows()
            let repeated = await manager().processBatchHealthKitData(
                weightHistory: weights + weights, bodyFatHistory: fats + fats, sampleIdentityPolicy: true
            )
            let after = try await durableRows()
            XCTAssertEqual(after.count, index + 1)
            XCTAssertEqual(Set(after.map(\.id)), Set(before.map(\.id)))
            XCTAssertEqual(after.sorted { $0.id < $1.id }, before.sorted { $0.id < $1.id })
            XCTAssertEqual(repeated.imported, 0)
        }
    }

    func testConcurrentImportsAdmitOneRow() async throws {
        let sample = HealthKitWeightImportSample(weight: 80, date: date, sourceMetadata: metadata(id: "concurrent"))
        let importer = manager()
        async let first = importer.processBatchHealthKitData(
            weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        async let second = importer.processBatchHealthKitData(
            weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        let results = await (first, second)
        XCTAssertEqual(results.0.imported + results.1.imported, 1)
        XCTAssertEqual(results.0.skipped + results.1.skipped, 1)
        let rows = try await durableRows()
        XCTAssertEqual(rows.count, 1)
    }

    func testTwoSourcesAndDistinctSamplesInSameHourAreRetainedWithExistingDisplayRule() async throws {
        // Even a UUID reused by two sources must be scoped to its bundle ID.
        let weights = [
            HealthKitWeightImportSample(weight: 80, date: date, sourceMetadata: metadata(id: "shared-uuid")),
            HealthKitWeightImportSample(
                weight: 81, date: date, sourceMetadata: metadata(id: "shared-uuid", source: "com.apple.watch")
            ),
            HealthKitWeightImportSample(weight: 82, date: date, sourceMetadata: metadata(id: "second-reading"))
        ]
        let fats = [
            HealthKitBodyFatImportSample(
                percentage: 18.4, date: date, sourceMetadata: metadata(id: "shared-fat", kind: .bodyFatPercentage)
            ),
            HealthKitBodyFatImportSample(
                percentage: 20, date: date,
                sourceMetadata: metadata(id: "shared-fat", source: "com.apple.watch", kind: .bodyFatPercentage)
            )
        ]
        let result = await manager().processBatchHealthKitData(
            weightHistory: weights, bodyFatHistory: fats, sampleIdentityPolicy: true
        )
        let rows = try await durableRows()
        XCTAssertEqual(result.imported, 3)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.compactMap { $0.sourceMetadata?.sourceBundleId }), ["test.scale", "com.apple.watch"])
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertEqual(rows.first { $0.weight == 80 }?.bodyFatPercentage, 18.4)
        XCTAssertEqual(rows.first { $0.weight == 81 }?.bodyFatPercentage, 20)
        XCTAssertNil(rows.first { $0.weight == 82 }?.bodyFatPercentage)
        let visible = EntryVisibilityManager.shared.resolvedVisibleMetrics(rows, userId: owner)
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.updatedAt, rows.map(\.updatedAt).max())
    }

    func testQuantityFixturesNormalizeKilogramsPoundsAndPercent() async throws {
        let importer = manager()
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        for (index, fixture) in [(HKUnit.gramUnit(with: .kilo), 80.0), (HKUnit.pound(), 176.3698097479)].enumerated() {
            let sampleDate = date.addingTimeInterval(Double(index) * 86_400)
            let sample = HKQuantitySample(
                type: type, quantity: HKQuantity(unit: fixture.0, doubleValue: fixture.1),
                start: sampleDate, end: sampleDate
            )
            let mapped = importer.weightImportSample(from: sample)
            XCTAssertEqual(mapped.weight, 80, accuracy: 1e-6)
            _ = await importer.processBatchHealthKitData(
                weightHistory: [mapped], bodyFatHistory: [], sampleIdentityPolicy: true
            )
        }
        let fatType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage))
        let fat = HKQuantitySample(
            type: fatType, quantity: HKQuantity(unit: .percent(), doubleValue: 0.184), start: date, end: date
        )
        let mapped = importer.bodyFatImportSample(from: fat)
        XCTAssertEqual(mapped.percentage, 18.4, accuracy: 1e-6)
        _ = await importer.processBatchHealthKitData(
            weightHistory: [], bodyFatHistory: [mapped], sampleIdentityPolicy: true
        )
        let rows = try await durableRows()
        XCTAssertEqual(rows.count, 3)
        for row in rows.filter({ $0.weight != nil }) {
            XCTAssertEqual(try XCTUnwrap(row.weight), 80, accuracy: 1e-6)
            XCTAssertEqual(row.weightUnit, "kg")
        }
        XCTAssertEqual(try XCTUnwrap(rows.first { $0.weight == nil }?.bodyFatPercentage), 18.4, accuracy: 1e-6)
    }

    func testSampleTimezoneKeepsOriginalDayAcrossOffsetsAndDaylightTransitions() async throws {
        let importer = manager()
        let type = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        let fixtures = [
            ("America/Los_Angeles", "2026-06-10T06:58:00Z", "2026-06-09"),
            ("Asia/Tokyo", "2026-06-09T15:01:00Z", "2026-06-10"),
            ("America/Los_Angeles", "2026-03-08T09:59:00Z", "2026-03-08"),
            ("America/Los_Angeles", "2026-11-01T09:30:00Z", "2026-11-01")
        ]
        for (zone, instant, expectedDay) in fixtures {
            let sampleDate = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
            let sample = HKQuantitySample(
                type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80),
                start: sampleDate, end: sampleDate, metadata: [HKMetadataKeyTimeZone: zone]
            )
            let mapped = importer.weightImportSample(from: sample)
            _ = await importer.processBatchHealthKitData(
                weightHistory: [mapped], bodyFatHistory: [], sampleIdentityPolicy: true
            )
            let rows = try await durableRows()
            let row = try XCTUnwrap(rows.first { $0.sourceMetadata?.sampleId == sample.uuid.uuidString })
            XCTAssertEqual(row.localDate, expectedDay)
            XCTAssertEqual(row.date, sampleDate)
            XCTAssertEqual(row.sourceMetadata?.healthKitContext["time_zone"], zone)
        }
    }

    func testTimezonePolicyDoesNotRequireSourceIdentity() async throws {
        let importer = manager()
        for enabled in [true, false] {
            let instant = enabled ? "2026-06-10T06:58:00Z" : "2026-06-11T06:58:00Z"
            let sampleDate = try XCTUnwrap(ISO8601DateFormatter().date(from: instant))
            let source = BodyMetricSourceMetadata(
                vendor: "apple_health", sampleId: "missing-source-\(enabled)",
                quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
            ).recordingHealthKitContext(["time_zone": "America/Los_Angeles"])
            XCTAssertNil(source.healthKitSampleKey)
            let sample = HealthKitWeightImportSample(weight: 80, date: sampleDate, sourceMetadata: source)
            let result = await importer.processBatchHealthKitData(
                weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: enabled
            )
            XCTAssertEqual(result.imported, 1)
            let rows = try await durableRows()
            let row = try XCTUnwrap(rows.first { $0.sourceMetadata?.sampleId == source.sampleId })
            let expectedDay = enabled ? "2026-06-09" : BodyMetricLocalDate.key(for: sampleDate)
            XCTAssertEqual(row.localDate, expectedDay)
            XCTAssertEqual(row.date, sampleDate)
            let repeated = await importer.processBatchHealthKitData(
                weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: enabled
            )
            XCTAssertEqual(repeated.imported, 0)
            XCTAssertEqual(repeated.skipped, 1)
        }
    }

    func testEditedSampleReplacesSameSyncVersionAndRejectsOldUUIDReplay() async throws {
        for (index, kind) in [HKQuantityTypeIdentifier.bodyMass, .bodyFatPercentage].enumerated() {
            var context = ["sync_identifier": "edit-\(index)", "sync_version": "1", "time_zone": "Asia/Tokyo"]
            let edits = [("original-\(index)", 80.0, "1"), ("edited-\(index)", 79.0, "1"),
                         ("original-\(index)", 80.0, "1"), ("stale-\(index)", 81.0, "0")]
            for (id, value, version) in edits {
                context["sync_version"] = version
                let source = metadata(id: id, kind: kind, context: context)
                _ = await manager().processBatchHealthKitData(
                    weightHistory: kind == .bodyMass ? [.init(weight: value, date: date, sourceMetadata: source)] : [],
                    bodyFatHistory: kind == .bodyFatPercentage
                        ? [.init(percentage: value, date: date, sourceMetadata: source)] : [],
                    sampleIdentityPolicy: true
                )
            }
            let rows = try await durableRows()
            let row = try XCTUnwrap(rows.first { $0.sourceMetadata?.healthKitContext["sync_identifier"] == "edit-\(index)" })
            XCTAssertEqual(rows.count, index + 1)
            XCTAssertEqual(row.sourceMetadata?.sampleId, "edited-\(index)")
            XCTAssertEqual(kind == .bodyMass ? row.weight : row.bodyFatPercentage, 79)
        }
    }

    func testPairingUsesEachSamplesLocalDayAndSource() async throws {
        let weightDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-10T06:58:00Z"))
        let fatDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T07:01:00Z"))
        let context = ["time_zone": "America/Los_Angeles"]
        let weight = HealthKitWeightImportSample(
            weight: 80, date: weightDate, sourceMetadata: metadata(id: "timezone-weight", context: context)
        )
        let fats = [
            HealthKitBodyFatImportSample(
                percentage: 18.4, date: fatDate,
                sourceMetadata: metadata(id: "timezone-fat", kind: .bodyFatPercentage, context: context)
            ),
            HealthKitBodyFatImportSample(
                percentage: 20, date: fatDate,
                sourceMetadata: metadata(id: "watch-fat", source: "com.apple.watch", kind: .bodyFatPercentage, context: context)
            )
        ]
        _ = await manager().processBatchHealthKitData(
            weightHistory: [weight], bodyFatHistory: fats, sampleIdentityPolicy: true
        )
        let rows = try await durableRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.localDate == "2026-06-09" })
        XCTAssertEqual(rows.first { $0.weight != nil }?.bodyFatPercentage, 18.4)
        XCTAssertEqual(rows.first { $0.weight == nil }?.bodyFatPercentage, 20)
    }

    func testRawPersistenceNormalizesUnitsEvenWhenCallerRequestsPounds() async throws {
        var persisted: [HKRawSample] = []
        let importer = HealthKitManager(
            userDefaults: defaults, authManager: auth, coreDataManager: coreData,
            rawImportStore: { samples in await MainActor.run { persisted.append(contentsOf: samples) } }
        )
        let mass = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        let fat = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage))
        let samples = [
            HKQuantitySample(
                type: mass, quantity: HKQuantity(unit: .pound(), doubleValue: 176.3698097479), start: date, end: date
            ),
            HKQuantitySample(
                type: fat, quantity: HKQuantity(unit: .percent(), doubleValue: 0.184), start: date, end: date
            )
        ]
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let task = try XCTUnwrap(importer.persistHealthKitSamples(samples, unit: .pound(), ownership: ownership))
        await task.value
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted[0].value, 80, accuracy: 1e-6)
        XCTAssertEqual(persisted[0].unit, "kg")
        XCTAssertEqual(persisted[1].value, 0.184, accuracy: 1e-6)
        XCTAssertEqual(persisted[1].unit, "%")
    }

    func testEditedPairedBodyFatUpdatesItsRowWithoutChangingWeightOrDay() async throws {
        let importer = manager()
        let weight = HealthKitWeightImportSample(weight: 80, date: date, sourceMetadata: metadata(id: "paired-weight"))
        let context = ["sync_identifier": "paired-fat", "sync_version": "2"]
        let fat = HealthKitBodyFatImportSample(
            percentage: 18.4, date: date,
            sourceMetadata: metadata(id: "paired-original", kind: .bodyFatPercentage, context: context)
        )
        _ = await importer.processBatchHealthKitData(
            weightHistory: [weight], bodyFatHistory: [fat], bodyFatOnlyPolicy: false, sampleIdentityPolicy: true
        )
        let initialRows = try await durableRows()
        let before = try XCTUnwrap(initialRows.first)
        let edited = HealthKitBodyFatImportSample(
            percentage: 17.9, date: date.addingTimeInterval(60),
            sourceMetadata: metadata(id: "paired-edited", kind: .bodyFatPercentage, context: context)
        )
        _ = await importer.processBatchHealthKitData(
            weightHistory: [], bodyFatHistory: [edited, fat], bodyFatOnlyPolicy: false, sampleIdentityPolicy: true
        )
        let rows = try await durableRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, before.id)
        XCTAssertEqual(rows.first?.weight, 80)
        XCTAssertEqual(rows.first?.bodyFatPercentage, 17.9)
        XCTAssertEqual(rows.first?.date, before.date)
        XCTAssertEqual(rows.first?.sourceMetadata?.bodyFatSampleId, "paired-edited")
    }

    func testReinstallUsesSameCloudIDAndSyncProvenance() async throws {
        let sample = HealthKitWeightImportSample(weight: 80, date: date, sourceMetadata: metadata(id: "reinstall"))
        let api = StubProductAPIClient()
        for _ in 0..<2 {
            _ = await manager().processBatchHealthKitData(
                weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
            )
            let sync = RealtimeSyncManager(
                coreDataManager: coreData, authManager: auth, productAPIClient: api, userDefaults: defaults
            )
            try await sync.syncLocalChanges(for: owner, token: "synthetic")
            try await coreData.deleteAllDataAndWait()
            defaults.removeObject(forKey: HealthKitAccountSyncPolicy.accountIdKey)
        }
        let payloads = api.bodyMetricsBatches.flatMap { $0 }
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0]["id"] as? String, payloads[1]["id"] as? String)
        let provenance = try XCTUnwrap(payloads[0]["source_metadata"] as? [String: Any])
        XCTAssertEqual(provenance["sample_id"] as? String, "reinstall")
        XCTAssertEqual(provenance["source_bundle_id"] as? String, "test.scale")
    }

    func testEditedFatArrivingWithNewWeightReplacesItsExistingPair() async throws {
        let importer = manager()
        let context = ["sync_identifier": "scale/\"reading\"", "sync_version": "1"]
        for index in 0..<2 {
            let weight = HealthKitWeightImportSample(
                weight: 80 - Double(index), date: date,
                sourceMetadata: metadata(id: "new-weight-\(index)")
            )
            let fat = HealthKitBodyFatImportSample(
                percentage: 20 - Double(index), date: date,
                sourceMetadata: metadata(id: "edited-fat-\(index)", kind: .bodyFatPercentage, context: context)
            )
            _ = await importer.processBatchHealthKitData(
                weightHistory: [weight], bodyFatHistory: [fat], bodyFatOnlyPolicy: false, sampleIdentityPolicy: true
            )
        }
        let rows = try await durableRows()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.weight == 80 }?.bodyFatPercentage, 19)
        XCTAssertEqual(rows.first { $0.weight == 80 }?.sourceMetadata?.bodyFatSampleId, "edited-fat-1")
        XCTAssertNil(rows.first { $0.weight == 79 }?.bodyFatPercentage)
    }

    func testIdentityGateDefaultsOffAndForwardsItsKey() {
        var keys: [String] = []
        XCTAssertFalse(HealthKitImportIdentityPolicy.isEnabled { keys.append($0); return false })
        XCTAssertEqual(keys, ["healthkit_sample_identity_v1"])
        XCTAssertTrue(HealthKitImportIdentityPolicy.isEnabled { _ in true })
    }

    func testRawSampleRetriesSourcesAndSameVersionEditAreIdempotent() async throws {
        func raw(_ id: String, source: String = "test.scale", value: Double = 80) -> HKRawSample {
            HKRawSample(
                id: UUID().uuidString, userId: owner, hkUUID: id,
                quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue, value: value, unit: "kg",
                startDate: date, endDate: date, sourceName: source, sourceBundleId: source,
                deviceManufacturer: nil, deviceModel: nil, deviceHardwareVersion: nil,
                deviceFirmwareVersion: nil, deviceSoftwareVersion: nil, deviceLocalIdentifier: nil, deviceUDI: nil,
                metadata: [HKMetadataKeySyncIdentifier: "raw-reading", HKMetadataKeySyncVersion: "1"],
                createdAt: date, updatedAt: date
            )
        }
        let samples = [raw("raw-original"), raw("raw-original", source: "com.apple.watch")]
        async let first: Void = coreData.saveHKSamples(samples)
        async let second: Void = coreData.saveHKSamples(samples)
        _ = await (first, second)
        await coreData.saveHKSamples([raw("raw-edited", value: 79), raw("raw-original")])
        let context = coreData.persistentContainer.newBackgroundContext()
        let rows = try await context.perform {
            let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
            return try context.fetch(request).map { ($0.hkUUID, $0.sourceBundleId, $0.value) }
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.1 == "test.scale" }?.0, "raw-edited")
        XCTAssertEqual(rows.first { $0.1 == "test.scale" }?.2, 79)
        XCTAssertEqual(rows.first { $0.1 == "com.apple.watch" }?.0, "raw-original")
        let wrongSource = await coreData.hkSampleExists(hkUUID: "raw-original", sourceBundleId: "test.scale", userId: owner)
        let watch = await coreData.hkSampleExists(hkUUID: "raw-original", sourceBundleId: "com.apple.watch", userId: owner)
        XCTAssertFalse(wrongSource)
        XCTAssertTrue(watch)
    }

    func testRepeatedOrEditedWeightCannotResurrectTombstone() async throws {
        let context = ["sync_identifier": "deleted", "sync_version": "1"]
        let sample = HealthKitWeightImportSample(
            weight: 80, date: date, sourceMetadata: metadata(id: "deleted-original", context: context)
        )
        let importer = manager()
        _ = await importer.processBatchHealthKitData(
            weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        let viewContext = coreData.viewContext
        try await viewContext.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            let row = try XCTUnwrap(try viewContext.fetch(request).first)
            row.isMarkedDeleted = true
            try viewContext.save()
        }
        let edited = HealthKitWeightImportSample(
            weight: 79, date: date, sourceMetadata: metadata(id: "deleted-edit", context: context)
        )
        let result = await importer.processBatchHealthKitData(
            weightHistory: [sample, edited], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.skipped, 2)
        let tombstones = try await viewContext.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            return try viewContext.fetch(request).map(\.isMarkedDeleted)
        }
        XCTAssertEqual(tombstones, [true])
    }

    func testIdentityWriteRejectsStaleOwnershipBeforeMutation() async throws {
        let source = metadata(id: "stale-owner")
        let metric = BodyMetrics(
            id: UUID().uuidString, userId: owner, date: date, weight: 80, weightUnit: "kg",
            bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: "healthkit", sourceMetadata: source,
            createdAt: date, updatedAt: date
        )
        do {
            try await coreData.saveHealthKitBodyMetricsAndWait(metric) { throw HealthKitError.notAuthorized }
            XCTFail("Stale ownership must reject the queued write")
        } catch HealthKitError.notAuthorized {
            let rows = try await durableRows()
            XCTAssertTrue(rows.isEmpty)
        }
        XCTAssertNotEqual(source.healthKitRecordID(userId: owner), source.healthKitRecordID(userId: "another-account"))
    }

    func testCorruptProvenanceCannotDuplicateAnExistingStableID() async throws {
        let sample = HealthKitWeightImportSample(
            weight: 80, date: date, sourceMetadata: metadata(id: "corrupt-provenance")
        )
        let importer = manager()
        _ = await importer.processBatchHealthKitData(
            weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        let viewContext = coreData.viewContext
        try await viewContext.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            let row = try XCTUnwrap(try viewContext.fetch(request).first)
            row.sourceMetadataJSON = "invalid-json"
            try viewContext.save()
        }
        let repeated = await importer.processBatchHealthKitData(
            weightHistory: [sample], bodyFatHistory: [], sampleIdentityPolicy: true
        )
        let rows = try await durableRows()
        XCTAssertEqual(repeated.imported, 0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.weight, 80)
    }
}
