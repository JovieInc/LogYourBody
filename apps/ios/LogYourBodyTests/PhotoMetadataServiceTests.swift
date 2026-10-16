//
// PhotoMetadataAndImportPolicyTests.swift
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


final class PhotoMetadataServiceTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testBodyFatEstimateReflectsChangedValuesWithStableRecordIDs() {
        let id = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = estimateFixture(id: id, date: date, bodyFat: 28.123)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [first])?.value, 28.123)
        let edited = estimateFixture(id: id, date: date, bodyFat: 18.456)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [edited])?.value, 18.456)
    }

    func testBodyFatEstimateBecomesAbsentWhenTheLastValueIsRemoved() {
        let id = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = estimateFixture(id: id, date: date, bodyFat: 20)
        XCTAssertNotNil(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [original]))
        let cleared = estimateFixture(id: id, date: date, bodyFat: nil)
        XCTAssertNil(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [cleared]))
    }

    func testBodyFatEstimateReflectsChangedDatesWithStableRecordIDs() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let ids = [UUID().uuidString, UUID().uuidString]
        let first = estimateFixture(id: ids[0], date: date.addingTimeInterval(-100), bodyFat: 10)
        let last = estimateFixture(id: ids[1], date: date.addingTimeInterval(100), bodyFat: 30)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [first, last])?.value, 20)
        let moved = estimateFixture(id: ids[1], date: date.addingTimeInterval(300), bodyFat: 30)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [first, moved])?.value, 15)
    }

    func testBodyFatEstimateDoesNotReuseAnotherOwnersSameRecordID() {
        let id = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = estimateFixture(id: id, date: date, bodyFat: 30, owner: "first")
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [first])?.value, 30)
        let nextOwner = estimateFixture(id: id, date: date, bodyFat: 15, owner: "next")
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: [nextOwner])?.value, 15)
    }

    func testBodyFatEstimateDoesNotCollideOnCommaSeparatedIDs() {
        let token = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = [
            estimateFixture(id: "\(token),left", date: date, bodyFat: 30),
            estimateFixture(id: "right", date: date, bodyFat: nil)
        ]
        let second = [
            estimateFixture(id: token, date: date, bodyFat: 15),
            estimateFixture(id: "left,right", date: date, bodyFat: nil)
        ]
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: first)?.value, 30)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: second)?.value, 15)
    }

    func testBodyFatEstimatePreservesUnsortedInterpolationAndEqualDateSelection() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            estimateFixture(date: date.addingTimeInterval(100), bodyFat: 30),
            estimateFixture(date: date.addingTimeInterval(-100), bodyFat: 10),
            estimateFixture(date: date.addingTimeInterval(100), bodyFat: 40),
            estimateFixture(date: date.addingTimeInterval(-100), bodyFat: 20),
            estimateFixture(date: date, bodyFat: nil)
        ]
        let estimate = PhotoMetadataService.shared.estimateBodyFat(for: date, metrics: rows)
        XCTAssertEqual(estimate?.value, 25)
        XCTAssertEqual(estimate?.isEstimated, true)
        XCTAssertEqual(PhotoMetadataService.shared.estimateBodyFat(
            for: date.addingTimeInterval(-100), metrics: rows
        )?.value, 20)
    }

    private func estimateFixture(
        id: String = UUID().uuidString, date: Date, bodyFat: Double?, owner: String = "estimate-owner"
    ) -> BodyMetrics {
        BodyMetrics(
            id: id, userId: owner, date: date, weight: nil, weightUnit: nil,
            bodyFatPercentage: bodyFat, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: "manual", createdAt: date, updatedAt: date
        )
    }

    @MainActor
    func testRestoredScanOnboardingDoesNotTurnHistoricalMeasurementsIntoTodaysPhotoBaseline() async throws {
        let previousUser = AuthManager.shared.currentUser
        let previousSession = AuthManager.shared.authSession
        defer {
            AuthManager.shared.currentUser = previousUser
            AuthManager.shared.authSession = previousSession
        }
        typealias BaselineCase = (scanBodyFat: Double?, todayWeight: Double?, todayBodyFat: Double?,
                                  manualWeight: Double?, legacyDraft: Bool)
        let cases: [BaselineCase] = [
            (19, nil, nil, nil, false), (19, 77, nil, nil, false), (19, 77, 17, nil, false),
            (nil, nil, nil, nil, false), (19, nil, nil, 82, false), (19, nil, nil, nil, true)
        ]
        for values in cases {
            let userId = "scan-photo-truth-\(UUID().uuidString)"
            AuthManager.shared.currentUser = User(id: userId, email: "scan-photo@example.com", name: "Scan Photo")
            AuthManager.shared.authSession = .localFixture(
                subject: userId, email: "scan-photo@example.com", name: "Scan Photo"
            )
            let historicalDate = try XCTUnwrap(BodyMetricLocalDate.startOfDay(for: "2026-06-02"))
            let historical = try await PhotoMetadataService.shared.createOrUpdateMetrics(
                for: historicalDate, weight: 84, bodyFatPercentage: values.scanBodyFat,
                userId: userId, dataSource: BodyMetricSource.dexaPDF.rawValue
            )
            var genuineToday: BodyMetrics?
            if let weight = values.todayWeight {
                genuineToday = try await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: Date(), weight: weight, bodyFatPercentage: values.todayBodyFat,
                    userId: userId, dataSource: BodyMetricSource.healthKit.rawValue
                )
            }
            let original = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
            original.applyImportedScans([
                DexaPDFScan(date: "2026-06-02", weight: 84, weightUnit: "kg",
                            bodyFatPercentage: values.scanBodyFat,
                            muscleMass: nil, boneMass: nil, source: "BodySpec")
            ])
            original.setWeightUnit(.kilograms)
            if let manualWeight = values.manualWeight {
                original.manualWeightText = String(manualWeight)
                original.persistManualWeightEntry()
            }
            if values.scanBodyFat == nil {
                original.bodyFatPercentageText = "20"
                original.persistBodyFatPercentageEntry()
            }
            var storedInput = try JSONEncoder().encode(original.bodyScoreInput)
            if values.legacyDraft {
                var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: storedInput) as? [String: Any])
                legacy.removeValue(forKey: "weightSource")
                storedInput = try JSONSerialization.data(withJSONObject: legacy)
            }
            let restored = OnboardingFlowViewModel(healthKitManager: HealthKitManager())
            restored.bodyScoreInput = try JSONDecoder().decode(BodyScoreInput.self, from: storedInput)
            restored.scanImport = nil // Relaunch restores the durable input, not the transient comparison.
            let result = await restored.prepareFirstPhotoBaselineMetric()
            let today = try XCTUnwrap(result)
            XCTAssertEqual(today.weight, values.todayWeight ?? values.manualWeight,
                           "Only an actual new entry may supply today's weight")
            XCTAssertEqual(today.bodyFatPercentage, values.scanBodyFat == nil ? 20 : values.todayBodyFat)
            XCTAssertEqual(today.localDate, BodyMetricLocalDate.key(for: Date()))
            if let genuineToday {
                XCTAssertEqual(today.id, genuineToday.id)
                XCTAssertEqual(today.dataSource, BodyMetricSource.healthKit.rawValue)
            } else {
                XCTAssertEqual(today.dataSource, values.scanBodyFat == nil || values.manualWeight != nil
                    ? BodyMetricSource.manual.rawValue : BodyMetricSource.photo.rawValue)
            }
            let stored = await CoreDataManager.shared.fetchBodyMetrics(
                for: userId, localDate: historical.localDate
            ).first?.toBodyMetrics()
            XCTAssertEqual(stored?.id, historical.id)
            XCTAssertEqual(stored?.weight, 84)
            XCTAssertEqual(stored?.bodyFatPercentage, values.scanBodyFat)
            XCTAssertEqual(stored?.dataSource, BodyMetricSource.dexaPDF.rawValue)
            OnboardingProgressStore.shared.clearProgress(for: userId)
        }
    }

    func testCreateOrUpdateMetricsPreservesExistingMeasurementsForFirstPhotoBaseline() async throws {
        let userId = "photo_baseline_existing_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_764_000_000)
        let existing = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: 18.0,
            bodyFatMethod: "HealthKit",
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "Imported from HealthKit",
            photoUrl: nil,
            dataSource: BodyMetricSource.healthKit.rawValue,
            createdAt: date,
            updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(existing, userId: userId)

        let updated = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            photoUrl: "file:///first-photo.jpg",
            weight: 77.0,
            bodyFatPercentage: 14.0,
            userId: userId,
            dataSource: BodyMetricSource.manual.rawValue,
            preserveExistingMeasurements: true
        )

        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.weight, 80.0)
        XCTAssertEqual(updated.bodyFatPercentage, 18.0)
        XCTAssertEqual(updated.bodyFatMethod, "HealthKit")
        XCTAssertEqual(updated.dataSource, BodyMetricSource.healthKit.rawValue)
        XCTAssertEqual(updated.photoUrl, "file:///first-photo.jpg")
    }

    func testCreateOrUpdateMetricsAssignsDataSourceForNewFirstPhotoBaseline() async throws {
        let userId = "photo_baseline_new_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_000_000)

        let created = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 79.5,
            bodyFatPercentage: 16.5,
            bodyFatMethod: "visual_estimate",
            userId: userId,
            dataSource: BodyMetricSource.manual.rawValue,
            preserveExistingMeasurements: true
        )

        XCTAssertEqual(created.weight, 79.5)
        XCTAssertEqual(created.bodyFatPercentage, 16.5)
        XCTAssertEqual(created.bodyFatMethod, "visual_estimate")
        XCTAssertEqual(created.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertNil(created.photoUrl)
    }

    func testCreateOrUpdateMetricsDefaultsNewManualMeasurementsToManualSource() async throws {
        let userId = "manual_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_100_000)

        let weightEntry = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 82.4,
            userId: userId
        )

        let bodyFatEntry = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date.addingTimeInterval(86_400),
            bodyFatPercentage: 17.1,
            userId: userId
        )

        XCTAssertEqual(weightEntry.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertEqual(bodyFatEntry.dataSource, BodyMetricSource.manual.rawValue)
    }

    func testCreateOrUpdateMetricsKeepsPhotoDefaultForPhotoOnlyPlaceholder() async throws {
        let userId = "photo_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_200_000)

        let photoEntry = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            userId: userId
        )

        XCTAssertEqual(photoEntry.dataSource, BodyMetricSource.photo.rawValue)
        XCTAssertNil(photoEntry.weight)
        XCTAssertNil(photoEntry.bodyFatPercentage)
    }

    func testCreateOrUpdateMetricsWithResultDistinguishesNewPhotoPlaceholderFromExistingMetric() async throws {
        let userId = "photo_placeholder_result_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_300_000)

        let first = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let second = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )

        XCTAssertTrue(first.createdNewEntry)
        XCTAssertFalse(second.createdNewEntry)
        XCTAssertEqual(second.metrics.id, first.metrics.id)
    }

    func testDeleteEmptyPhotoPlaceholderRemovesUnsyncedPhotoOnlyMetric() async throws {
        let userId = "photo_placeholder_cleanup_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_400_000)

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )

        XCTAssertTrue(result.createdNewEntry)

        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: result.metrics.id,
            userId: userId
        )

        XCTAssertTrue(deleted)

        let visibleMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        XCTAssertFalse(visibleMetrics.contains { $0.id == result.metrics.id })

        let pending = try await CoreDataManager.shared.fetchPendingLocalSyncSnapshot(for: userId)
        XCTAssertFalse(pending.bodyMetrics.contains { $0.id == result.metrics.id })
    }

    func testDeleteEmptyPhotoPlaceholderCanRemoveExistingRetryPlaceholder() async throws {
        let userId = "photo_placeholder_retry_cleanup_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_450_000)

        let first = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let retry = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )

        XCTAssertTrue(first.createdNewEntry)
        XCTAssertFalse(retry.createdNewEntry)
        XCTAssertEqual(retry.metrics.id, first.metrics.id)

        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: retry.metrics.id,
            userId: userId
        )

        XCTAssertTrue(deleted)
        let cachedRetryMetric = await cachedMetric(id: retry.metrics.id)
        XCTAssertNil(cachedRetryMetric)
    }

    func testDeleteEmptyPhotoPlaceholderRemovesOriginalOnlyFailedUploadMetric() async throws {
        let userId = "photo_placeholder_original_only_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_475_000)

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        try await setOriginalPhotoUrl(id: result.metrics.id, value: "\(userId)/failed-upload.png")

        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: result.metrics.id,
            userId: userId
        )

        XCTAssertTrue(deleted)
        let cachedOriginalOnlyMetric = await cachedMetric(id: result.metrics.id)
        XCTAssertNil(cachedOriginalOnlyMetric)
    }

    func testDeleteEmptyPhotoPlaceholderKeepsStorageCommittedUpload() async throws {
        let userId = "photo_placeholder_committed_upload_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_485_000)
        let storagePath = "\(userId)/committed-upload.png"

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let markedCommitted = await CoreDataManager.shared.markPhotoUploadStorageCommitted(
            id: result.metrics.id,
            userId: userId,
            storagePath: storagePath
        )

        XCTAssertTrue(markedCommitted)

        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: result.metrics.id,
            userId: userId
        )

        XCTAssertFalse(deleted)
        let cachedCommittedMetric = await cachedMetric(id: result.metrics.id)
        XCTAssertEqual(cachedCommittedMetric?.originalPhotoUrl, storagePath)
        XCTAssertEqual(
            cachedCommittedMetric?.syncStatus,
            CoreDataManager.photoUploadStorageCommittedSyncStatus
        )
    }

    func testMarkPhotoPlaceholderUploadInFlightIsLocalOnly() async throws {
        let userId = "photo_placeholder_in_flight_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_490_000)

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let markedInFlight = await CoreDataManager.shared.markPhotoPlaceholderUploadInFlight(
            id: result.metrics.id,
            userId: userId
        )

        XCTAssertTrue(markedInFlight)

        let cachedInFlightMetric = await cachedMetric(id: result.metrics.id)
        XCTAssertEqual(cachedInFlightMetric?.syncStatus, CoreDataManager.photoUploadInFlightSyncStatus)
        XCTAssertNil(cachedInFlightMetric?.sourceMetadataJSON)
    }

    func testCreateOrUpdateMetricsForPhotoUploadMarksPlaceholderInFlightAtomically() async throws {
        let userId = "photo_placeholder_atomic_upload_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_495_000)

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: date,
            userId: userId
        )

        XCTAssertTrue(result.createdNewEntry)

        let pending = try await CoreDataManager.shared.fetchPendingLocalSyncSnapshot(for: userId)
        let item = try XCTUnwrap(pending.bodyMetrics.first { $0.id == result.metrics.id })
        XCTAssertEqual(item.syncStatus, CoreDataManager.photoUploadInFlightSyncStatus)
    }

    func testCreateOrUpdateMetricsForPhotoUploadDoesNotDowngradeCommittedStorageState() async throws {
        let userId = "photo_placeholder_committed_retry_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_496_000)
        let storagePath = "\(userId)/committed-retry.png"

        let first = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: date,
            userId: userId
        )
        let markedCommitted = await CoreDataManager.shared.markPhotoUploadStorageCommitted(
            id: first.metrics.id,
            userId: userId,
            storagePath: storagePath
        )
        let retry = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: date,
            userId: userId
        )

        XCTAssertTrue(markedCommitted)
        XCTAssertEqual(retry.metrics.id, first.metrics.id)

        let cachedRetryMetric = await cachedMetric(id: first.metrics.id)
        XCTAssertEqual(cachedRetryMetric?.syncStatus, CoreDataManager.photoUploadStorageCommittedSyncStatus)
        XCTAssertEqual(cachedRetryMetric?.originalPhotoUrl, storagePath)
    }

    func testPrepareExistingMetricsForPhotoUploadUsesSelectedMetricId() async throws {
        let userId = "photo_placeholder_selected_id_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_497_000)
        let first = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: nil,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.photo.rawValue,
            createdAt: date,
            updatedAt: date
        )
        let selected = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: nil,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.photo.rawValue,
            createdAt: date.addingTimeInterval(1),
            updatedAt: date.addingTimeInterval(1)
        )

        try await CoreDataManager.shared.saveBodyMetricsAndWait(first, userId: userId)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(selected, userId: userId)

        let prepared = try await PhotoMetadataService.shared.prepareExistingMetricsForPhotoUpload(
            id: selected.id,
            userId: userId
        )

        XCTAssertEqual(prepared.metrics.id, selected.id)
        let firstCached = await cachedMetric(id: first.id)
        let selectedCached = await cachedMetric(id: selected.id)
        XCTAssertEqual(firstCached?.syncStatus, "pending")
        XCTAssertEqual(selectedCached?.syncStatus, CoreDataManager.photoUploadInFlightSyncStatus)
    }

    func testDeleteEmptyPhotoPlaceholderKeepsExistingMeasurementMetric() async throws {
        let userId = "photo_placeholder_keep_measurement_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_500_000)
        let metric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: 82.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.photo.rawValue,
            createdAt: date,
            updatedAt: date
        )

        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: false)

        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: metric.id,
            userId: userId
        )

        XCTAssertFalse(deleted)

        let visibleMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        XCTAssertTrue(visibleMetrics.contains { $0.id == metric.id })
    }

    func testCreateOrUpdateMetricsPersistsWeightBeforeReturning() async throws {
        let userId = "persist_before_return_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let localDate = BodyMetricLocalDate.key(for: date)

        let created = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 82.4,
            userId: userId
        )

        let stored = await CoreDataManager.shared.fetchBodyMetrics(for: userId, localDate: localDate)
        let persisted = try XCTUnwrap(stored.first?.toBodyMetrics())

        XCTAssertEqual(persisted.id, created.id)
        XCTAssertEqual(try XCTUnwrap(persisted.weight), 82.4, accuracy: 0.001)
        XCTAssertEqual(persisted.localDate, localDate)
        XCTAssertEqual(persisted.dataSource, BodyMetricSource.manual.rawValue)
    }

    @MainActor
    func testWeightSaveReturnsUndoSnapshotFromTheActualDestinationDay() async throws {
        let today = undoFixture(weight: nil, bodyFat: nil, method: nil)
        let yesterday = undoFixture(weight: 80, bodyFat: 18, method: "dexa", daysAgo: 1, userId: today.userId)
        for metric in [today, yesterday] {
            try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: today.userId, markAsSynced: true)
        }
        let seededToday = await cachedMetric(id: today.id)
        let todayBaseline = try XCTUnwrap(seededToday?.toBodyMetrics())
        let seededYesterday = await cachedMetric(id: yesterday.id)
        let yesterdayBaseline = try XCTUnwrap(seededYesterday?.toBodyMetrics())

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: yesterday.date, weight: 82, userId: today.userId
        )
        let previous = try XCTUnwrap(result.previousMetric)
        XCTAssertEqual(previous, yesterdayBaseline, "Changing the destination must not reuse today's snapshot")
        XCTAssertEqual(result.metrics.id, yesterday.id)
        XCTAssertFalse(result.createdNewEntry)
        try await PhotoMetadataService.shared.restoreMeasurements(
            id: result.metrics.id, userId: today.userId, previous: previous
        )

        let restored = await cachedMetric(id: yesterday.id)
        XCTAssertEqual(restored?.toBodyMetrics()?.weight, 80)
        XCTAssertEqual(restored?.toBodyMetrics()?.bodyFatMethod, "dexa")
        let unchanged = await cachedMetric(id: today.id)
        XCTAssertEqual(unchanged?.toBodyMetrics(), todayBaseline, "Saving and undoing another day must leave today intact")

        let todayResult = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: today.date, weight: 83, userId: today.userId
        )
        let previousToday = try XCTUnwrap(todayResult.previousMetric)
        XCTAssertEqual(previousToday, todayBaseline, "Returning to today must capture today's existing photo-only row")
        try await PhotoMetadataService.shared.restoreMeasurements(
            id: todayResult.metrics.id, userId: today.userId, previous: previousToday
        )
        let restoredToday = await cachedMetric(id: today.id)
        XCTAssertNil(restoredToday?.toBodyMetrics()?.weight)
        XCTAssertEqual(restoredToday?.toBodyMetrics()?.photoUrl, today.photoUrl)
    }

    @MainActor
    func testWeightSaveForANewDestinationDoesNotReuseAnotherDaysUndoSnapshot() async throws {
        let today = undoFixture(weight: nil, bodyFat: nil, method: nil)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(today, userId: today.userId, markAsSynced: true)
        let seededToday = await cachedMetric(id: today.id)
        let todayBaseline = try XCTUnwrap(seededToday?.toBodyMetrics())
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today.date))

        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: yesterday, weight: 82, userId: today.userId
        )

        XCTAssertNil(result.previousMetric)
        XCTAssertTrue(result.createdNewEntry)
        XCTAssertNotEqual(result.metrics.id, today.id)
        XCTAssertEqual(result.metrics.localDate, BodyMetricLocalDate.key(for: yesterday))
        let unchanged = await cachedMetric(id: today.id)
        XCTAssertEqual(unchanged?.toBodyMetrics(), todayBaseline)
    }

    @MainActor
    func testUndoRestoresMissingMeasurementsWithoutChangingThePhotoOrSource() async throws {
        let previous = undoFixture(weight: nil, bodyFat: nil, method: nil)
        try await logOverUndoFixture(previous)

        try await PhotoMetadataService.shared.restoreMeasurements(
            id: previous.id, userId: previous.userId, previous: previous
        )

        let cached = await cachedMetric(id: previous.id)
        let stored = try XCTUnwrap(cached?.toBodyMetrics())
        XCTAssertNil(stored.weight)
        XCTAssertNil(stored.bodyFatPercentage)
        XCTAssertNil(stored.bodyFatMethod)
        XCTAssertEqual(stored.id, previous.id)
        XCTAssertEqual(stored.date, previous.date)
        XCTAssertEqual(stored.localDate, previous.localDate)
        XCTAssertEqual(stored.photoUrl, previous.photoUrl)
        XCTAssertEqual(stored.sourceMetadata, previous.sourceMetadata)
        XCTAssertEqual(stored.dataSource, previous.dataSource)
        XCTAssertEqual(stored.notes, previous.notes)
        XCTAssertEqual(stored.createdAt, previous.createdAt)
        XCTAssertEqual(cached?.isSynced, false)
        XCTAssertEqual(cached?.syncStatus, "pending")
    }

    @MainActor
    func testUndoRestoresWeightAndClearsNewBodyFat() async throws {
        let previous = undoFixture(weight: 80, bodyFat: nil, method: nil)
        try await logOverUndoFixture(previous)

        try await PhotoMetadataService.shared.restoreMeasurements(
            id: previous.id, userId: previous.userId, previous: previous
        )

        let cached = await cachedMetric(id: previous.id)
        let stored = try XCTUnwrap(cached?.toBodyMetrics())
        XCTAssertEqual(stored.weight, previous.weight)
        XCTAssertNil(stored.bodyFatPercentage)
        XCTAssertNil(stored.bodyFatMethod)
    }

    @MainActor
    func testUndoRestoresBodyFatMethodAndPreservesNewerUnrelatedFields() async throws {
        let previous = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await logOverUndoFixture(previous)
        let context = CoreDataManager.shared.viewContext
        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", previous.id)
            let cached = try XCTUnwrap(context.fetch(request).first)
            cached.photoUrl = "file:///newer-photo.jpg"
            cached.waistCircumference = 84
            cached.notes = "A newer note"
            try context.save()
        }

        try await PhotoMetadataService.shared.restoreMeasurements(
            id: previous.id, userId: previous.userId, previous: previous
        )

        let cached = await cachedMetric(id: previous.id)
        let stored = try XCTUnwrap(cached?.toBodyMetrics())
        XCTAssertEqual(stored.weight, previous.weight)
        XCTAssertEqual(stored.bodyFatPercentage, previous.bodyFatPercentage)
        XCTAssertEqual(stored.bodyFatMethod, "dexa")
        XCTAssertEqual(stored.photoUrl, "file:///newer-photo.jpg")
        XCTAssertEqual(stored.waistCm, 84)
        XCTAssertEqual(stored.notes, "A newer note")
    }

    @MainActor
    func testUndoRejectsAnotherAccountWithoutCreatingOrChangingAnyEntry() async throws {
        let previous = undoFixture(weight: nil, bodyFat: nil, method: nil)
        try await logOverUndoFixture(previous)

        do {
            try await PhotoMetadataService.shared.restoreMeasurements(
                id: previous.id, userId: "another-account", previous: previous
            )
            XCTFail("Undo must reject a receipt belonging to another account")
        } catch PhotoMetricsRestoreError.entryNotFound {
            // Expected: no write is admitted.
        }

        let cached = await cachedMetric(id: previous.id)
        XCTAssertEqual(cached?.toBodyMetrics()?.weight, 82)
        let otherRows = await CoreDataManager.shared.fetchBodyMetrics(for: "another-account")
        XCTAssertTrue(otherRows.isEmpty)
    }

    @MainActor
    func testUndoSaveFailureThrowsAndKeepsTheLoggedValuesInMemoryAndStorage() async throws {
        let previous = undoFixture(weight: nil, bodyFat: nil, method: nil)
        try await logOverUndoFixture(previous)
        let context = UndoFailingSaveContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = CoreDataManager.shared.persistentContainer.persistentStoreCoordinator

        do {
            try await PhotoMetadataService.shared.restoreMeasurements(
                id: previous.id, userId: previous.userId, previous: previous, context: context
            )
            XCTFail("A failed save must not report a successful Undo")
        } catch UndoTestSaveError.failed {
            // Expected: the persistence error reaches the caller.
        }

        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", previous.id)
            let cached = try XCTUnwrap(context.fetch(request).first)
            XCTAssertEqual(cached.weight, 82, "Failed Undo must not leave unsaved cleared values")
            XCTAssertEqual(cached.bodyFatPercentage, 23)
        }
        let cached = await cachedMetric(id: previous.id)
        XCTAssertEqual(cached?.toBodyMetrics()?.weight, 82)
        XCTAssertEqual(cached?.toBodyMetrics()?.bodyFatPercentage, 23)
    }

    private func undoFixture(
        weight: Double?, bodyFat: Double?, method: String?, daysAgo: Int = 0, userId: String? = nil
    ) -> BodyMetrics {
        let calendar = Calendar.current
        let baseline = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: baseline) ?? baseline
        return BodyMetrics(
            id: UUID().uuidString, userId: userId ?? "undo-\(UUID().uuidString)", date: date,
            weight: weight, weightUnit: "kg", bodyFatPercentage: bodyFat, bodyFatMethod: method,
            muscleMass: nil, boneMass: nil, notes: "Original note", photoUrl: "file:///original-photo.jpg",
            dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(sourceName: "Test scale"),
            createdAt: date, updatedAt: date
        )
    }

    private func logOverUndoFixture(_ previous: BodyMetrics) async throws {
        try await CoreDataManager.shared.saveBodyMetricsAndWait(previous, userId: previous.userId, markAsSynced: true)
        _ = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: previous.date, weight: 82, bodyFatPercentage: 23,
            bodyFatMethod: "bioelectrical", userId: previous.userId
        )
    }

    private func cachedMetric(id: String) async -> CachedBodyMetrics? {
        let context = CoreDataManager.shared.viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    private func setOriginalPhotoUrl(id: String, value: String) async throws {
        let context = CoreDataManager.shared.viewContext

        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            let metric = try XCTUnwrap(context.fetch(request).first)
            metric.originalPhotoUrl = value

            if context.hasChanges {
                try context.save()
            }
        }
    }
}

private enum UndoTestSaveError: Error {
    case failed
}

private final class UndoFailingSaveContext: NSManagedObjectContext, @unchecked Sendable {
    override func save() throws {
        throw UndoTestSaveError.failed
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testEditorValidationPreservesMissingAndHistoricalFieldsThroughCommittedWrite() async throws {
        for weight in [nil, 31.234567] as [Double?] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: weight, bodyFat: 71.234567, method: "caliper")
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
            let before = try XCTUnwrap(try exactEditStoredRows(store).first)
            let session = HomeV2EditSession(
                metric: fixture,
                owner: AuthManager.ProfileSessionOwnership(subject: fixture.userId, generation: 1)
            )
            let inputWeight = try HomeV2EntryEditPolicy.weight(
                text: weight.map { HomeV2WeightStepPolicy.text($0) } ?? "",
                initialValue: weight, unit: "kg", preserving: true
            )
            let inputBodyFat = try HomeV2EntryEditPolicy.bodyFat(
                text: "71.2", initialValue: fixture.bodyFatPercentage, preserving: true
            )
            let retained = session.measurementReplacements(
                value: inputWeight, bodyFat: inputBodyFat,
                initialDisplayedWeight: weight ?? HomeV2WeightStepPolicy.defaultValue(unit: "kg")
            )
            XCTAssertNil(retained.weight)
            XCTAssertNil(retained.bodyFat)
            _ = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                id: session.id, userId: session.owner.subject, weight: retained.weight,
                bodyFatPercentage: retained.bodyFat, bodyFatMethod: nil,
                writeAdmission: {}, coreDataManager: store
            )
            XCTAssertEqual(try exactEditStoredRows(store), [before], "Untouched fields retain raw precision and source")
            let replacement = try HomeV2EntryEditPolicy.bodyFat(text: "21.3", initialValue: 71.234567, preserving: true)
            let changed = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                id: session.id, userId: session.owner.subject, weight: nil, bodyFatPercentage: replacement,
                bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}, coreDataManager: store
            )
            XCTAssertEqual(changed.metrics.weight, weight)
            XCTAssertEqual(changed.metrics.bodyFatPercentage, 21.3)
            XCTAssertEqual(changed.metrics.bodyFatMethod, "caliper")
            XCTAssertEqual(changed.metrics.date, fixture.date)
            XCTAssertEqual(changed.metrics.measurementSource(for: .bodyFat), .manual)
        }
    }

    func testPhotoPlaceholderCreationRejectsReplacementAtStoreAdmission() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let subject = "photo-create-admission-\(UUID().uuidString)"
        installPhotoAdmissionSession(subject: subject)
        let original = try XCTUnwrap(auth.captureAccountSession())
        let store = makePhotoAdmissionStore()
        var admissions = 0
        do {
            _ = try await store.createOrUpdatePhotoUploadMetricsPlaceholder(
                for: Date(), userId: subject, writeAdmission: {
                    admissions += 1
                    self.installPhotoAdmissionSession(subject: subject)
                    guard auth.ownsAccountSession(original) else { throw PhotoCallerAdmissionTestError.replacedLifetime }
                }
            )
            XCTFail("A replacement lifetime cannot create a delayed placeholder")
        } catch {
            XCTAssertEqual(error as? PhotoCallerAdmissionTestError, .replacedLifetime)
        }
        XCTAssertEqual(admissions, 1)
        XCTAssertFalse(auth.ownsAccountSession(original))
        XCTAssertEqual(try freshPhotoAdmissionRows(store).count, 0)
        XCTAssertFalse(store.viewContext.hasChanges)
    }

    func testPhotoPlaceholderPreparationRejectsReplacementWithoutChangingStoredRow() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let subject = "photo-prepare-admission-\(UUID().uuidString)"
        installPhotoAdmissionSession(subject: subject)
        let original = try XCTUnwrap(auth.captureAccountSession())
        let store = makePhotoAdmissionStore()
        let prepared = try await store.createOrUpdatePhotoUploadMetricsPlaceholder(for: Date(), userId: subject)
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        let beforeDate = Date(timeIntervalSince1970: 1_750_000_000)
        row.syncStatus = "pending"
        row.updatedAt = beforeDate
        row.lastModified = beforeDate
        try store.viewContext.save()
        var admissions = 0
        do {
            _ = try await store.prepareExistingPhotoUploadMetrics(
                id: prepared.metrics.id, userId: subject, writeAdmission: {
                    admissions += 1
                    self.installPhotoAdmissionSession(subject: subject)
                    guard auth.ownsAccountSession(original) else { throw PhotoCallerAdmissionTestError.replacedLifetime }
                }
            )
            XCTFail("A replacement lifetime cannot mutate the existing placeholder")
        } catch {
            XCTAssertEqual(error as? PhotoCallerAdmissionTestError, .replacedLifetime)
        }
        XCTAssertEqual(admissions, 1)
        let stored = try XCTUnwrap(try freshPhotoAdmissionRows(store).first)
        XCTAssertEqual(stored.id, prepared.metrics.id)
        XCTAssertEqual(stored.owner, subject)
        XCTAssertEqual(stored.status, "pending")
        XCTAssertEqual(stored.updated, beforeDate)
        XCTAssertEqual(stored.modified, beforeDate)
        XCTAssertFalse(store.viewContext.hasChanges)
    }

    func testPhotoPlaceholderCleanupRejectsReplacementWithoutRemovingStoredRow() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let subject = "photo-cleanup-admission-\(UUID().uuidString)"
        installPhotoAdmissionSession(subject: subject)
        let original = try XCTUnwrap(auth.captureAccountSession())
        let store = makePhotoAdmissionStore()
        let prepared = try await store.createOrUpdatePhotoUploadMetricsPlaceholder(for: Date(), userId: subject)
        var admissions = 0
        let deleted = await store.deleteEmptyPhotoPlaceholder(
            id: prepared.metrics.id, userId: subject, writeAdmission: {
                admissions += 1
                self.installPhotoAdmissionSession(subject: subject)
                guard auth.ownsAccountSession(original) else { throw PhotoCallerAdmissionTestError.replacedLifetime }
            }
        )
        XCTAssertFalse(deleted)
        XCTAssertEqual(admissions, 1)
        let stored = try freshPhotoAdmissionRows(store)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, prepared.metrics.id)
        XCTAssertEqual(stored.first?.owner, subject)
        XCTAssertFalse(store.viewContext.hasChanges)
    }

    func testPhotoMetadataForwardsCurrentAdmissionThroughPrepareAndCleanup() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let subject = "photo-current-admission-\(UUID().uuidString)"
        installPhotoAdmissionSession(subject: subject)
        let original = try XCTUnwrap(auth.captureAccountSession())
        var admissions = 0
        let admission: CoreDataManager.WriteAdmission = {
            admissions += 1
            guard auth.ownsAccountSession(original) else { throw PhotoCallerAdmissionTestError.replacedLifetime }
        }
        let created = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: Date(), userId: subject, writeAdmission: admission
        )
        let prepared = try await PhotoMetadataService.shared.prepareExistingMetricsForPhotoUpload(
            id: created.metrics.id, userId: subject, writeAdmission: admission
        )
        XCTAssertEqual(created.metrics.id, prepared.metrics.id)
        XCTAssertEqual(try freshPhotoAdmissionRows(CoreDataManager.shared).count, 1)
        let deleted = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
            id: prepared.metrics.id, userId: subject, writeAdmission: admission
        )
        XCTAssertTrue(deleted)
        XCTAssertEqual(admissions, 3)
        XCTAssertTrue(try freshPhotoAdmissionRows(CoreDataManager.shared).isEmpty)
        XCTAssertTrue(auth.ownsAccountSession(original))
    }

    private func installPhotoAdmissionSession(subject: String) {
        AuthManager.shared.authSession = .localFixture(subject: subject, email: "photo-admission@example.com")
        AuthManager.shared.currentUser = LocalUser(id: subject, email: "photo-admission@example.com", name: "Photo")
    }

    private func makePhotoAdmissionStore() -> CoreDataManager {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return CoreDataManager(persistentStoreDescriptions: [description])
    }

    private func freshPhotoAdmissionRows(_ store: CoreDataManager) throws -> [PhotoCallerStoredRow] {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        return try context.fetch(CachedBodyMetrics.fetchRequest()).map {
            PhotoCallerStoredRow(id: $0.id, owner: $0.userId, status: $0.syncStatus,
                                 updated: $0.updatedAt, modified: $0.lastModified)
        }
    }
}

private enum PhotoCallerAdmissionTestError: Error, Equatable { case replacedLifetime }
private struct PhotoCallerStoredRow {
    let id: String?
    let owner: String?
    let status: String?
    let updated: Date?
    let modified: Date?
}

// The captured editor must retain its record after another same-day import arrives.
@MainActor
extension PhotoMetadataServiceTests {
    func testCapturedOlderEditorDoesNotOverwriteNewerSameDayImport() async throws {
        let captured = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            captured, userId: captured.userId, markAsSynced: true
        )
        let capturedRow = await cachedMetric(id: captured.id)
        let beforeCaptured = try XCTUnwrap(capturedRow?.toBodyMetrics())
        let arrivalDate = captured.date.addingTimeInterval(3_600)
        let arrival = BodyMetrics(
            id: UUID().uuidString, userId: captured.userId, date: arrivalDate,
            localDate: captured.localDate, weight: 91, weightUnit: "kg",
            bodyFatPercentage: 27, bodyFatMethod: "bioelectrical",
            muscleMass: nil, boneMass: nil, notes: "New import must remain unchanged",
            photoUrl: nil, dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(sourceName: "New same-day scale"),
            createdAt: arrivalDate, updatedAt: arrivalDate
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(
            arrival, userId: arrival.userId, markAsSynced: true
        )
        let arrivalRow = await cachedMetric(id: arrival.id)
        let beforeArrival = try XCTUnwrap(arrivalRow?.toBodyMetrics())

        let result = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
            id: captured.id, userId: captured.userId, weight: 82, bodyFatPercentage: 18.4,
            bodyFatMethod: nil, writeAdmission: {}
        )

        XCTAssertEqual(result.metrics.id, captured.id, "Edit must retain its original record identity")
        XCTAssertEqual(result.previousMetric, beforeCaptured, "Undo must describe the edited record")
        XCTAssertFalse(result.createdNewEntry)
        let storedCaptured = await cachedMetric(id: captured.id)
        let storedArrival = await cachedMetric(id: arrival.id)
        XCTAssertEqual(storedCaptured?.toBodyMetrics()?.weight, 82)
        XCTAssertEqual(storedCaptured?.toBodyMetrics()?.bodyFatPercentage, 18.4)
        XCTAssertEqual(storedCaptured?.toBodyMetrics()?.sourceMetadata, beforeCaptured.sourceMetadata)
        XCTAssertEqual(storedArrival?.toBodyMetrics(), beforeArrival,
                       "A later same-day import is not the record selected for Edit")
        let rows = await CoreDataManager.shared.fetchBodyMetrics(
            for: captured.userId, localDate: captured.localDate
        )
        XCTAssertEqual(Set(rows.compactMap(\.id)), Set([captured.id, arrival.id]))
    }
}


@MainActor
extension PhotoMetadataServiceTests {
    func testExactMetricEditRejectsMissingDeletedForeignAndAmbiguousTargetsWithoutFallback() async throws {
        for scenario in ["missing", "deleted", "foreign", "duplicate"] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
            let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
            if scenario == "deleted" { row.isMarkedDeleted = true }
            if scenario == "duplicate" {
                let duplicate = CachedBodyMetrics(context: store.viewContext)
                duplicate.setValuesForKeys(row.dictionaryWithValues(forKeys: Array(row.entity.attributesByName.keys)))
                duplicate.userId = "another-owner"
            }
            try store.viewContext.save()
            let before = try exactEditStoredRows(store)
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: scenario == "missing" ? "absent" : fixture.id,
                    userId: scenario == "foreign" ? "another-owner" : fixture.userId,
                    weight: 90, bodyFatPercentage: 22, bodyFatMethod: "manual", writeAdmission: {}
                )
                XCTFail("An exact edit must reject \(scenario), never create or choose another row")
            } catch PhotoMetricsEditError.entryNotFound {
                // Expected fail-closed identity outcome.
            }
            XCTAssertEqual(try exactEditStoredRows(store), before)
            XCTAssertFalse(store.viewContext.hasChanges)
        }
    }

    func testExactMetricEditPreservesUntouchedRawFieldsAndUnrelatedSharedDraft() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: nil, bodyFat: 18, method: "caliper")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        row.sourceMetadataJSON = "{\"vendor_field\":\"preserve exactly\",\"source_name\":\"Original\"}"
        row.dataSource = "original-opaque-source"
        row.originalPhotoUrl = "original-owner/photo.jpg"
        row.photoProcessedAt = fixture.date
        row.waistCircumference = 89.123
        row.hipCircumference = 99.456
        row.waistUnit = "cm"
        try store.viewContext.save()
        let before = try XCTUnwrap(try exactEditStoredRows(store).first)
        let draft = CachedBodyMetrics(context: store.viewContext)
        draft.id = "unrelated-incomplete-draft"
        draft.notes = "Do not save or discard me"
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: nil, bodyFatPercentage: 18.4,
            bodyFatMethod: nil, writeAdmission: {}
        )
        let after = try XCTUnwrap(try exactEditStoredRows(store).first)
        XCTAssertEqual(result.metrics.id, fixture.id)
        XCTAssertNil(result.metrics.weight)
        XCTAssertEqual(result.metrics.bodyFatMethod, "caliper")
        XCTAssertEqual(result.previousMetric?.bodyFatPercentage, 18)
        let changed = Set(["bodyFatPercentage", "updatedAt", "lastModified", "isSynced", "syncStatus"])
        for key in row.entity.attributesByName.keys where !changed.contains(key) {
            XCTAssertEqual(before[key] as? NSObject, after[key] as? NSObject, "Unexpected mutation of \(key)")
        }
        XCTAssertEqual(after["bodyFatPercentage"] as? Double, 18.4)
        XCTAssertEqual(try exactEditStoredRows(store).count, 1)
        XCTAssertTrue(draft.isInserted)
        XCTAssertEqual(draft.notes, "Do not save or discard me")
    }

    func testExactMetricEditRejectsDirtyTargetIncludingItsCommittedIdentity() async throws {
        for movedIdentity in [false, true] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: 80, bodyFat: nil, method: nil)
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
            let before = try exactEditStoredRows(store)
            let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
            row.notes = "Uncommitted target edit"
            if movedIdentity { row.id = "different-uncommitted-id" }
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: fixture.id, userId: fixture.userId, weight: 90, bodyFatPercentage: nil,
                    bodyFatMethod: nil, writeAdmission: {}
                )
                XCTFail("A pending target mutation must not be silently overwritten")
            } catch PhotoMetricsEditError.pendingEdit { }
            XCTAssertEqual(try exactEditStoredRows(store), before)
            XCTAssertEqual(row.notes, "Uncommitted target edit")
            XCTAssertTrue(row.hasChanges)
        }
    }

    func testExactMetricEditRejectsSessionReplacementAtQueuedAdmission() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        for sameSubject in [true, false] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
            installPhotoAdmissionSession(subject: fixture.userId)
            let owner = try XCTUnwrap(auth.captureAccountSession())
            let presentation = HomeV2EditSession(metric: fixture, owner: owner)
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
            let before = try exactEditStoredRows(store)
            var admissions = 0
            do {
                _ = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                    id: presentation.id, userId: presentation.owner.subject,
                    weight: 90, bodyFatPercentage: 22, bodyFatMethod: "manual",
                    writeAdmission: {
                        admissions += 1
                        if admissions == 2 {
                            self.installPhotoAdmissionSession(subject: sameSubject ? fixture.userId : "replacement")
                        }
                        guard auth.ownsAccountSession(presentation.owner) else {
                            throw PhotoCallerAdmissionTestError.replacedLifetime
                        }
                    }, coreDataManager: store
                )
                XCTFail("An admitted UI operation cannot survive an account-lifetime replacement")
            } catch PhotoCallerAdmissionTestError.replacedLifetime { }
            XCTAssertEqual(admissions, 2)
            XCTAssertFalse(auth.ownsAccountSession(owner))
            XCTAssertEqual(try exactEditStoredRows(store), before)
            XCTAssertFalse(store.viewContext.hasChanges)
        }
    }

    func testExactMetricEditRollsBackFailedCommitWithoutLatentMutation() async throws {
        for failure in ["throw", "no-save"] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
            let before = try exactEditStoredRows(store)
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: fixture.id, userId: fixture.userId, weight: 90, bodyFatPercentage: 22,
                    bodyFatMethod: "manual", writeAdmission: {}, commit: { _ in
                        if failure == "throw" { throw UndoTestSaveError.failed }
                    }
                )
                XCTFail("A failed or omitted commit cannot report a successful edit")
            } catch UndoTestSaveError.failed {
                XCTAssertEqual(failure, "throw")
            } catch PhotoMetricsEditError.uncommittedWrite {
                XCTAssertEqual(failure, "no-save")
            }
            XCTAssertEqual(try exactEditStoredRows(store), before)
            XCTAssertFalse(store.viewContext.hasChanges)
            try store.viewContext.save()
            XCTAssertEqual(try exactEditStoredRows(store), before, "A later save must not flush the failed edit")
        }
    }

    private func exactEditStoredRows(_ store: CoreDataManager) throws -> [NSDictionary] {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        return try context.performAndWait {
            let request = CachedBodyMetrics.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true),
                                       NSSortDescriptor(key: "userId", ascending: true)]
            return try context.fetch(request).map {
                NSDictionary(dictionary: $0.dictionaryWithValues(forKeys: Array($0.entity.attributesByName.keys)))
            }
        }
    }
}


@MainActor
extension PhotoMetadataServiceTests {
    func testUnboundDayLogStillChoosesNewestOwnedRecord() async throws {
        let old = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
        let later = BodyMetrics(
            id: UUID().uuidString, userId: old.userId, date: old.date.addingTimeInterval(3_600),
            localDate: old.localDate, weight: 91, weightUnit: "kg",
            bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: BodyMetricSource.manual.rawValue,
            createdAt: old.date, updatedAt: old.date
        )
        for row in [old, later] {
            try await CoreDataManager.shared.saveBodyMetricsAndWait(row, userId: old.userId)
        }
        let oldBefore = await cachedMetric(id: old.id)
        let original = try XCTUnwrap(oldBefore?.toBodyMetrics())
        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: old.date, weight: 82, userId: old.userId
        )
        XCTAssertEqual(result.metrics.id, later.id, "An unbound log still selects its destination day")
        XCTAssertFalse(result.createdNewEntry)
        let oldAfter = await cachedMetric(id: old.id)
        XCTAssertEqual(oldAfter?.toBodyMetrics(), original)
        XCTAssertEqual(result.previousMetric?.id, later.id)
    }

    func testExactMetricEditDoesNotPublishAfterSessionReplacementFollowingCommit() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        for sameSubject in [true, false] {
            let store = makePhotoAdmissionStore()
            let fixture = undoFixture(weight: 80, bodyFat: 18, method: "caliper")
            installPhotoAdmissionSession(subject: fixture.userId)
            let owner = try XCTUnwrap(auth.captureAccountSession())
            try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
            var admissions = 0
            do {
                _ = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                    id: fixture.id, userId: owner.subject, weight: nil, bodyFatPercentage: 18.4,
                    bodyFatMethod: nil, writeAdmission: {
                        admissions += 1
                        if admissions == 4 {
                            self.installPhotoAdmissionSession(subject: sameSubject ? fixture.userId : "replacement")
                        }
                        guard auth.ownsAccountSession(owner) else {
                            throw PhotoCallerAdmissionTestError.replacedLifetime
                        }
                    }, coreDataManager: store
                )
                XCTFail("The committed old-owner result cannot publish into a replacement lifetime")
            } catch PhotoCallerAdmissionTestError.replacedLifetime { }
            XCTAssertEqual(admissions, 4)
            XCTAssertFalse(auth.ownsAccountSession(owner))
            let stored = try XCTUnwrap(try exactEditStoredRows(store).first)
            XCTAssertEqual(stored["id"] as? String, fixture.id)
            XCTAssertEqual(stored["userId"] as? String, owner.subject)
            XCTAssertEqual(stored["bodyFatPercentage"] as? Double, 18.4,
                           "An already admitted original-owner commit must not be undone for a new session")
            XCTAssertEqual(stored["weight"] as? Double, 80)
            XCTAssertEqual(stored["bodyFatMethod"] as? String, "caliper")
            XCTAssertEqual(try exactEditStoredRows(store).count, 1)
        }
    }
}


@MainActor
extension PhotoMetadataServiceTests {
    func testCapturedEditorIntentPreservesRawMeasurementsAndMethodsUntilChanged() async throws {
        for method in [nil, "manual", "caliper"] as [String?] {
            for weight in [nil, 82.123456] as [Double?] {
                let store = makePhotoAdmissionStore()
                let fixture = undoFixture(weight: weight, bodyFat: 18.4567, method: method)
                try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
                let before = try XCTUnwrap(try exactEditStoredRows(store).first)
                let session = HomeV2EditSession(
                    metric: fixture,
                    owner: AuthManager.ProfileSessionOwnership(subject: fixture.userId, generation: 1)
                )
                let initial = weight ?? HomeV2WeightStepPolicy.defaultValue(unit: "kg")
                let displayed = try XCTUnwrap(HomeV2WeightStepPolicy.parse(HomeV2WeightStepPolicy.text(initial)))
                let retained = session.measurementReplacements(
                    value: displayed, bodyFat: 18.5, initialDisplayedWeight: initial
                )
                XCTAssertNil(retained.weight)
                XCTAssertNil(retained.bodyFat)
                _ = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                    id: session.id, userId: session.owner.subject, weight: retained.weight,
                    bodyFatPercentage: retained.bodyFat, bodyFatMethod: nil,
                    writeAdmission: {}, coreDataManager: store
                )
                XCTAssertEqual(try exactEditStoredRows(store), [before], "An unchanged editor is not a new observation")

                let edited = session.measurementReplacements(
                    value: displayed, bodyFat: 18.4, initialDisplayedWeight: initial
                )
                XCTAssertNil(edited.weight)
                XCTAssertEqual(edited.bodyFat, 18.4)
                let result = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                    id: session.id, userId: session.owner.subject, weight: edited.weight,
                    bodyFatPercentage: edited.bodyFat, bodyFatMethod: nil,
                    writeAdmission: {}, coreDataManager: store
                )
                XCTAssertEqual(result.metrics.weight, weight)
                XCTAssertEqual(result.metrics.bodyFatPercentage, 18.4)
                XCTAssertEqual(result.metrics.bodyFatMethod, method,
                               "Typing a replacement does not select a new measurement method")
                XCTAssertEqual(result.metrics.sourceMetadata, fixture.sourceMetadata)
                XCTAssertEqual(result.metrics.date, fixture.date)
            }
        }
    }
}


@MainActor
extension PhotoMetadataServiceTests {
    func testExactMetricEditSQLiteFailureReopenAndOlderIdentityPreservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("exact-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.sqlite")
        var managers: [CoreDataManager] = []
        defer {
            for manager in managers { try? closeExactEditStore(manager) }
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try makeExactEditSQLiteStore(at: url)
        managers.append(store)
        let selected = undoFixture(weight: 80.123456, bodyFat: 18.4567, method: "caliper")
        let newer = BodyMetrics(
            id: UUID().uuidString, userId: selected.userId, date: selected.date.addingTimeInterval(3_600),
            localDate: selected.localDate, weight: 91, weightUnit: "kg",
            bodyFatPercentage: 27, bodyFatMethod: "bioelectrical", muscleMass: nil, boneMass: nil,
            notes: "Newer import", photoUrl: nil, dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(sourceName: "Newer scale"),
            createdAt: selected.date, updatedAt: selected.date
        )
        for metric in [selected, newer] {
            try await store.saveBodyMetricsAndWait(metric, userId: selected.userId, markAsSynced: true)
        }
        let before = try exactEditStoredRows(store)
        do {
            _ = try await store.updateExistingMetricMeasurementsAndWait(
                id: selected.id, userId: selected.userId, weight: nil, bodyFatPercentage: 18.4,
                bodyFatMethod: nil, writeAdmission: {}, commit: { transaction in
                    let request = CachedBodyMetrics.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", selected.id)
                    let row = try XCTUnwrap(try transaction.fetch(request).first)
                    XCTAssertFalse(try XCTUnwrap(row.entity.attributesByName["createdAt"]).isOptional)
                    row.createdAt = nil // Exercise a real Core Data validation failure.
                    try transaction.save()
                }
            )
            XCTFail("An invalid commit must fail without changing either durable row")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, NSCocoaErrorDomain)
            XCTAssertTrue([NSValidationMissingMandatoryPropertyError, NSValidationMultipleErrorsError].contains(error.code))
        }
        XCTAssertEqual(try exactEditStoredRows(store), before)
        XCTAssertFalse(store.viewContext.hasChanges)
        try closeExactEditStore(store)

        let reopened = try makeExactEditSQLiteStore(at: url)
        managers.append(reopened)
        XCTAssertEqual(try exactEditStoredRows(reopened), before, "Failure must survive an actual store reopen")
        let result = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
            id: selected.id, userId: selected.userId, weight: nil, bodyFatPercentage: 18.4,
            bodyFatMethod: nil, writeAdmission: {}, coreDataManager: reopened
        )
        let after = try exactEditStoredRows(reopened)
        XCTAssertEqual(result.metrics.id, selected.id)
        XCTAssertEqual(result.previousMetric?.id, selected.id)
        XCTAssertEqual(result.metrics.weight, selected.weight)
        XCTAssertEqual(result.metrics.bodyFatMethod, "caliper")
        XCTAssertEqual(result.metrics.bodyFatPercentage, 18.4)
        XCTAssertEqual(result.metrics.sourceMetadata, selected.sourceMetadata)
        XCTAssertEqual(after.first { $0["id"] as? String == newer.id }, before.first { $0["id"] as? String == newer.id })
        XCTAssertEqual(after.count, 2)
        try closeExactEditStore(reopened)
        let verified = try makeExactEditSQLiteStore(at: url)
        managers.append(verified)
        XCTAssertEqual(try exactEditStoredRows(verified), after, "Success must be durable in only the selected row")
    }

    private func makeExactEditSQLiteStore(at url: URL) throws -> CoreDataManager {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        let manager = CoreDataManager(persistentStoreDescriptions: [description])
        guard manager.viewContext.persistentStoreCoordinator?.persistentStores.count == 1 else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreOpenError)
        }
        return manager
    }

    private func closeExactEditStore(_ manager: CoreDataManager) throws {
        try manager.viewContext.performAndWait {
            manager.viewContext.reset()
            let coordinator = try XCTUnwrap(manager.viewContext.persistentStoreCoordinator)
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testWeightUpdatePreservesCircumferencesAcrossIndependentRead() async throws {
        try await verifyUnrelatedCircumferencesSurvive(
            weight: 82.4, expected: (82.4, 18.2), manuallyEnteredFields: [.weight]
        )
    }

    func testBodyFatUpdatePreservesCircumferencesAcrossIndependentRead() async throws {
        try await verifyUnrelatedCircumferencesSurvive(
            bodyFat: 19.3, expected: (80.123, 19.3), manuallyEnteredFields: [.bodyFat]
        )
    }

    func testPhotoAttachPreservesCircumferencesAcrossIndependentRead() async throws {
        try await verifyUnrelatedCircumferencesSurvive(
            weight: 77, bodyFat: 14, photo: "file:///replacement-photo.jpg", preserve: true,
            expected: (80.123, 18.2)
        )
    }

    func testPhotoAttachKeepsMissingCircumferencesAbsent() async throws {
        try await verifyUnrelatedCircumferencesSurvive(
            photo: "file:///replacement-photo.jpg", preserve: true, circumferences: (nil, nil, nil),
            expected: (80.123, 18.2)
        )
    }

    private func verifyUnrelatedCircumferencesSurvive(
        weight: Double? = nil, bodyFat: Double? = nil, photo: String? = nil, preserve: Bool = false,
        circumferences: (waist: Double?, hip: Double?, unit: String?) = (85.123, 101.987, "in"),
        expected: (weight: Double, bodyFat: Double), manuallyEnteredFields: Set<BodyMetricField> = []
    ) async throws {
        let (waist, hip, unit) = circumferences
        let owner = "circumference-preservation-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = BodyMetrics(
            id: UUID().uuidString, userId: owner, date: date,
            weight: 80.123, weightUnit: "kg", bodyFatPercentage: 18.2, bodyFatMethod: "caliper",
            muscleMass: 56.789, boneMass: 3.123, waistCm: waist, hipCm: hip, waistUnit: unit,
            notes: "Keep the original measurements", photoUrl: "file:///original-photo.jpg",
            dataSource: BodyMetricSource.healthKit.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(sourceName: "Original scale", sampleId: "original-sample"),
            createdAt: date.addingTimeInterval(-60), updatedAt: date
        )
        let manager = CoreDataManager.shared
        try await manager.saveBodyMetricsAndWait(original, userId: owner, markAsSynced: true)
        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date, photoUrl: photo, weight: weight, bodyFatPercentage: bodyFat,
            userId: owner, preserveExistingMeasurements: preserve
        )
        XCTAssertFalse(result.createdNewEntry)
        XCTAssertEqual(result.previousMetric?.waistCm, waist)
        XCTAssertEqual(result.previousMetric?.hipCm, hip)
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = manager.viewContext.persistentStoreCoordinator
        let stored = try await reader.perform {
            let request = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND userId == %@", original.id, owner)
            let rows = try reader.fetch(request)
            XCTAssertEqual(rows.count, 1)
            return try XCTUnwrap(rows.first?.toBodyMetrics())
        }
        for metric in [result.metrics, stored] {
            XCTAssertEqual(metric.id, original.id)
            XCTAssertEqual(metric.userId, owner)
            XCTAssertEqual(metric.date, original.date)
            XCTAssertEqual(metric.localDate, original.localDate)
            XCTAssertEqual(metric.createdAt, original.createdAt)
            XCTAssertEqual(metric.weight, expected.weight)
            XCTAssertEqual(metric.bodyFatPercentage, expected.bodyFat)
            XCTAssertEqual(metric.bodyFatMethod, original.bodyFatMethod)
            XCTAssertEqual(metric.waistCm, waist)
            XCTAssertEqual(metric.hipCm, hip)
            XCTAssertEqual(metric.waistUnit, unit)
            XCTAssertEqual(metric.muscleMass, original.muscleMass)
            XCTAssertEqual(metric.boneMass, original.boneMass)
            XCTAssertEqual(metric.notes, original.notes)
            XCTAssertEqual(metric.photoUrl, photo ?? original.photoUrl)
            XCTAssertEqual(metric.dataSource, original.dataSource)
            XCTAssertEqual(metric.sourceMetadata, original.sourceMetadata?.settingEntrySource(
                .manual, fields: manuallyEnteredFields
            ))
        }
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testExactMetricEditClearsBodyFatAndMarksManualWithoutRewritingOtherFields() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80.123456, bodyFat: 18.4567, method: "caliper")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        row.waistCircumference = 85.5
        try store.viewContext.save()

        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: nil, bodyFatPercentage: nil,
            bodyFatMethod: nil, clearBodyFat: true, markManualCorrection: true, writeAdmission: {}
        )

        XCTAssertEqual(result.metrics.id, fixture.id)
        XCTAssertEqual(result.metrics.weight, 80.123456)
        XCTAssertNil(result.metrics.bodyFatPercentage)
        XCTAssertNil(result.metrics.bodyFatMethod)
        XCTAssertEqual(result.metrics.metricSource, .healthKit)
        XCTAssertEqual(result.metrics.measurementSource(for: .weight), .healthKit)
        XCTAssertEqual(result.metrics.sourceMetadata?.entrySource(for: .bodyFat), .manual)
        XCTAssertEqual(result.metrics.waistCm, 85.5)
        XCTAssertEqual(result.metrics.sourceMetadata?.sourceName, result.previousMetric?.sourceMetadata?.sourceName)
        XCTAssertEqual(result.previousMetric?.bodyFatPercentage, 18.4567)
        XCTAssertEqual(result.previousMetric?.bodyFatMethod, "caliper")
        XCTAssertEqual(result.previousMetric?.metricSource, .healthKit)
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testExactWeightCorrectionKeepsUntouchedBodyFatImportedAfterIndependentRead() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80.123456, bodyFat: 18.4567, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        let read = try XCTUnwrap(try reader.fetch(CachedBodyMetrics.fetchRequest()).first?.toBodyMetrics())
        for metric in [result.metrics, read] {
            XCTAssertEqual(metric.metricSource, .healthKit)
            XCTAssertEqual(metric.measurementSource(for: .weight), .manual)
            XCTAssertEqual(metric.measurementSource(for: .bodyFat), .healthKit)
            XCTAssertEqual(metric.bodyFatPercentage, 18.4567)
            XCTAssertEqual(metric.bodyFatMethod, "dexa")
            XCTAssertTrue(HomeV2Provenance.weightSubline(for: metric).hasPrefix("Typed"))
            XCTAssertEqual(HomeV2Provenance.bodyFatSubline(for: metric), "DEXA")
            XCTAssertEqual(metric.date, fixture.date)
            XCTAssertEqual(metric.createdAt, fixture.createdAt)
        }
    }

    func testExactBodyFatCorrectionCannotClaimTheUntouchedImportsMethod() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80.123456, bodyFat: 18.4567, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: nil, bodyFatPercentage: 20,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        let metric = result.metrics
        XCTAssertEqual(metric.weight, fixture.weight)
        XCTAssertEqual(metric.measurementSource(for: .weight), .healthKit)
        XCTAssertEqual(metric.measurementSource(for: .bodyFat), .manual)
        XCTAssertEqual(metric.bodyFatMethod, "dexa", "Original import method remains in the record")
        XCTAssertEqual(metric.attributedBodyFatMethod, "manual")
        XCTAssertTrue(HomeV2Provenance.bodyFatSubline(for: metric).hasPrefix("Typed"))
        XCTAssertEqual(HomeV2EditorialPolicy.bodyFat(in: metric)?.caption, "Entered by you")
    }

    func testUnchangedExactSaveDoesNotMarkAnyFieldManual() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80.123456, bodyFat: 18.4567, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let before = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first?.toBodyMetrics())
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: before.weight,
            bodyFatPercentage: before.bodyFatPercentage, bodyFatMethod: nil,
            markManualCorrection: true, writeAdmission: {}
        )
        XCTAssertEqual(result.metrics, before)
    }

    func testManualDayLogOverBodyFatOnlyImportKeepsBothSources() async throws {
        let fixture = undoFixture(weight: nil, bodyFat: 18.4567, method: "dexa")
        try await CoreDataManager.shared.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: fixture.date, weight: 82, userId: fixture.userId
        )
        XCTAssertEqual(result.metrics.measurementSource(for: .weight), .manual)
        XCTAssertEqual(result.metrics.measurementSource(for: .bodyFat), .healthKit)
        XCTAssertEqual(result.metrics.bodyFatPercentage, 18.4567)
        XCTAssertEqual(result.metrics.bodyFatMethod, "dexa")
        XCTAssertTrue(HomeV2Provenance.weightSubline(for: result.metrics).hasPrefix("Typed"))
    }

    func testFreshImportReplacesManualAttributionRatherThanInheritingIt() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        _ = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        // An import with explicit source metadata replaces the prior measurement source.
        let imported = BodyMetrics(
            id: fixture.id, userId: fixture.userId, date: fixture.date,
            weight: 82, weightUnit: "kg", bodyFatPercentage: 18, bodyFatMethod: "dexa",
            muscleMass: nil, boneMass: nil, notes: fixture.notes, photoUrl: fixture.photoUrl,
            dataSource: "healthkit", sourceMetadata: BodyMetricSourceMetadata(vendor: "apple_health", sampleId: "new-import"),
            createdAt: fixture.createdAt, updatedAt: Date()
        )
        try await store.saveBodyMetricsAndWait(imported, userId: fixture.userId, markAsSynced: true)
        let read = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first?.toBodyMetrics())
        XCTAssertEqual(read.measurementSource(for: .weight), .healthKit)
        XCTAssertNil(read.sourceMetadata?.entrySource(for: .weight))
        XCTAssertEqual(read.sourceMetadata?.sampleId, "new-import")
    }

    func testUndoWeightKeepsNewerBodyFatPhotoNoteAndUnknownMetadata() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        row.bodyFatPercentage = 19
        row.photoUrl = "local://newer-photo"
        row.notes = "newer note"
        var metadata = try XCTUnwrap(result.metrics.sourceMetadata).jsonObject
        metadata["future"] = ["keep": true]
        metadata["body_fat_entry_source"] = "manual"
        row.sourceMetadataJSON = try XCTUnwrap(BodyMetricSourceMetadata(jsonObject: metadata)?.jsonString)
        try store.viewContext.save()
        try await PhotoMetadataService.shared.restoreMeasurements(
            id: fixture.id, userId: fixture.userId, previous: try XCTUnwrap(result.previousMetric),
            replacing: result.metrics, context: store.viewContext
        )
        let restored = try XCTUnwrap(row.toBodyMetrics())
        XCTAssertEqual(restored.weight, 80)
        XCTAssertEqual(restored.measurementSource(for: .weight), .healthKit)
        XCTAssertEqual(restored.bodyFatPercentage, 19)
        XCTAssertEqual(restored.measurementSource(for: .bodyFat), .manual)
        XCTAssertEqual(restored.photoUrl, "local://newer-photo")
        XCTAssertEqual(restored.notes, "newer note")
        XCTAssertNotNil(restored.sourceMetadata?.jsonObject["future"])
    }

    func testUndoRejectsAChangedMeasurementWithoutTouchingIt() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        row.weight = 83
        try store.viewContext.save()
        let before = row.toBodyMetrics()
        do {
            try await PhotoMetadataService.shared.restoreMeasurements(
                id: fixture.id, userId: fixture.userId, previous: try XCTUnwrap(result.previousMetric),
                replacing: result.metrics, context: store.viewContext
            )
            XCTFail("A later measurement must not be overwritten by an old Undo")
        } catch PhotoMetricsRestoreError.entryChanged {}
        XCTAssertEqual(row.toBodyMetrics(), before)
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testFieldSourcesSurviveActualSyncPullStorageAndPendingUploadMapping() async throws {
        let store = makePhotoAdmissionStore()
        let owner = "synthetic-provenance-sync"
        let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000))
        let metadata: [String: Any] = [
            "vendor": "apple_health", "sample_id": "original-sample", "weight_entry_source": "manual",
            "future": ["retained": true]
        ]
        let payload: [String: Any] = [
            "id": "synthetic-provenance-record", "user_id": owner, "date": date,
            "weight": 82.0, "weight_unit": "kg", "body_fat_percentage": 18.4567,
            "body_fat_method": "dexa", "data_source": "healthkit", "source_metadata": metadata,
            "created_at": date, "updated_at": date
        ]
        await store.updateOrCreateBodyMetricAndWait(from: payload)
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        let metric = try XCTUnwrap(row.toBodyMetrics())
        XCTAssertEqual(metric.measurementSource(for: .weight), .manual)
        XCTAssertEqual(metric.measurementSource(for: .bodyFat), .healthKit)
        XCTAssertEqual(metric.bodyFatMethod, "dexa")
        let pending = row.pendingSyncItem()
        let uploadMetadata = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: pending.sourceMetadataJSON))
        XCTAssertEqual(uploadMetadata.entrySource(for: .weight), .manual)
        XCTAssertNil(uploadMetadata.entrySource(for: .bodyFat))
        XCTAssertEqual(uploadMetadata.sampleId, "original-sample")
        XCTAssertEqual((uploadMetadata.jsonObject["future"] as? [String: Bool])?["retained"], true)
        let exported = try JSONDecoder().decode(BodyMetrics.self, from: JSONEncoder().encode(metric))
        XCTAssertEqual(exported.sourceMetadata, metric.sourceMetadata)
        XCTAssertEqual(exported.bodyFatPercentage, 18.4567)
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testExplicitCaliperEntryKeepsTheChosenMethodWhileChangingOnlyBodyFatSource() async throws {
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await CoreDataManager.shared.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: fixture.date, bodyFatPercentage: 18, bodyFatMethod: "caliper", userId: fixture.userId
        )
        XCTAssertEqual(result.metrics.measurementSource(for: .weight), .healthKit)
        XCTAssertEqual(result.metrics.measurementSource(for: .bodyFat), .manual)
        XCTAssertEqual(result.metrics.attributedBodyFatMethod, "caliper")
        XCTAssertEqual(HomeV2Provenance.bodyFatSubline(for: result.metrics), "Calipers")
        XCTAssertEqual(HomeV2EditorialPolicy.bodyFat(in: result.metrics)?.caption, "Caliper estimate")
        let decoded = try JSONDecoder().decode(BodyMetrics.self, from: JSONEncoder().encode(result.metrics))
        XCTAssertEqual(decoded.attributedBodyFatMethod, "caliper")
    }

    func testMetadataFreeImportCannotRetainAStaleManualFieldOverride() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        _ = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId, markAsSynced: true)
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first?.toBodyMetrics())
        XCTAssertEqual(row.weight, 80)
        XCTAssertEqual(row.measurementSource(for: .weight), .healthKit)
        XCTAssertNil(row.sourceMetadata?.entrySource(for: .weight))
    }
}

@MainActor
extension PhotoMetadataServiceTests {
    func testExactMethodOnlyCorrectionKeepsChosenMethodAndImportedWeight() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: nil, bodyFatPercentage: 18,
            bodyFatMethod: "caliper", markManualCorrection: true, writeAdmission: {}
        )
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        let read = try XCTUnwrap(try reader.fetch(CachedBodyMetrics.fetchRequest()).first?.toBodyMetrics())
        for metric in [result.metrics, read] {
            XCTAssertEqual(metric.measurementSource(for: .weight), .healthKit)
            XCTAssertEqual(metric.measurementSource(for: .bodyFat), .manual)
            XCTAssertEqual(metric.attributedBodyFatMethod, "caliper")
            XCTAssertEqual(HomeV2Provenance.bodyFatSubline(for: metric), "Calipers")
            XCTAssertEqual(metric.weight, fixture.weight)
            XCTAssertEqual(metric.bodyFatPercentage, fixture.bodyFatPercentage)
        }
    }

    func testUndoCannotOverwriteANewerEnteredBodyFatMethod() async throws {
        let store = makePhotoAdmissionStore()
        let fixture = undoFixture(weight: 80, bodyFat: 18, method: "dexa")
        try await store.saveBodyMetricsAndWait(fixture, userId: fixture.userId)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: fixture.id, userId: fixture.userId, weight: nil, bodyFatPercentage: 20,
            bodyFatMethod: nil, markManualCorrection: true, writeAdmission: {}
        )
        let row = try XCTUnwrap(try store.viewContext.fetch(CachedBodyMetrics.fetchRequest()).first)
        row.sourceMetadataJSON = result.metrics.sourceMetadata?.settingEntrySource(
            .manual, fields: [.bodyFat], bodyFatMethod: "caliper"
        ).jsonString
        try store.viewContext.save()
        let before = row.toBodyMetrics()
        do {
            try await PhotoMetadataService.shared.restoreMeasurements(
                id: fixture.id, userId: fixture.userId, previous: try XCTUnwrap(result.previousMetric),
                replacing: result.metrics, context: store.viewContext
            )
            XCTFail("A newer explicit method must not be overwritten by an old Undo")
        } catch PhotoMetricsRestoreError.entryChanged {}
        XCTAssertEqual(row.toBodyMetrics(), before)
    }
}
