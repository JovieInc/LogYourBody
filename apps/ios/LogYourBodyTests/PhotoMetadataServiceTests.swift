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
