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

        let updated = await PhotoMetadataService.shared.createOrUpdateMetrics(
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

    func testCreateOrUpdateMetricsAssignsDataSourceForNewFirstPhotoBaseline() async {
        let userId = "photo_baseline_new_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_000_000)

        let created = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 79.5,
            bodyFatPercentage: 16.5,
            userId: userId,
            dataSource: BodyMetricSource.manual.rawValue,
            preserveExistingMeasurements: true
        )

        XCTAssertEqual(created.weight, 79.5)
        XCTAssertEqual(created.bodyFatPercentage, 16.5)
        XCTAssertEqual(created.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertNil(created.photoUrl)
    }

    func testCreateOrUpdateMetricsDefaultsNewManualMeasurementsToManualSource() async {
        let userId = "manual_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_100_000)

        let weightEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            weight: 82.4,
            userId: userId
        )

        let bodyFatEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date.addingTimeInterval(86_400),
            bodyFatPercentage: 17.1,
            userId: userId
        )

        XCTAssertEqual(weightEntry.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertEqual(bodyFatEntry.dataSource, BodyMetricSource.manual.rawValue)
    }

    func testCreateOrUpdateMetricsKeepsPhotoDefaultForPhotoOnlyPlaceholder() async {
        let userId = "photo_entry_default_source_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_200_000)

        let photoEntry = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            userId: userId
        )

        XCTAssertEqual(photoEntry.dataSource, BodyMetricSource.photo.rawValue)
        XCTAssertNil(photoEntry.weight)
        XCTAssertNil(photoEntry.bodyFatPercentage)
    }

    func testCreateOrUpdateMetricsWithResultDistinguishesNewPhotoPlaceholderFromExistingMetric() async {
        let userId = "photo_placeholder_result_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_765_300_000)

        let first = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let second = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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

        let first = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
            for: date,
            userId: userId
        )
        let retry = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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

        let result = await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
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
