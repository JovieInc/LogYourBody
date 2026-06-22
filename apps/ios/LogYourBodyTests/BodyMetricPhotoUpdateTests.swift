//
// CoreDataAndPhotoPolicyTests.swift
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
final class BodyMetricPhotoUpdateTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testUpdateBodyMetricPhotoMarksMetricPendingInsideContext() async throws {
        let userId = "photo_update_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_766_000_000)
        let metric = makePhotoUpdateMetric(id: metricId, userId: userId, date: date)

        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: true)

        let didUpdate = try await CoreDataManager.shared.updateBodyMetricPhoto(
            id: metricId,
            userId: userId,
            storagePath: "\(userId)/\(metricId).png",
            processedUrl: "https://cdn.example.com/\(metricId).png"
        )

        XCTAssertTrue(didUpdate)

        let updated = try await cachedPhotoState(metricId: metricId)
        XCTAssertEqual(updated.photoUrl, "https://cdn.example.com/\(metricId).png")
        XCTAssertEqual(updated.originalPhotoUrl, "\(userId)/\(metricId).png")
        XCTAssertFalse(updated.isSynced)
        XCTAssertEqual(updated.syncStatus, "pending")
    }

    func testUpdateBodyMetricPhotoDoesNotCrossUsers() async throws {
        let ownerId = "photo_owner_\(UUID().uuidString)"
        let otherUserId = "photo_other_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_766_100_000)
        let metric = makePhotoUpdateMetric(id: metricId, userId: ownerId, date: date)

        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: ownerId, markAsSynced: true)

        let didUpdate = try await CoreDataManager.shared.updateBodyMetricPhoto(
            id: metricId,
            userId: otherUserId,
            storagePath: "\(otherUserId)/\(metricId).png",
            processedUrl: "https://cdn.example.com/wrong-user.png"
        )

        XCTAssertFalse(didUpdate)

        let updated = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(updated.photoUrl)
        XCTAssertNil(updated.originalPhotoUrl)
        XCTAssertTrue(updated.isSynced)
        XCTAssertEqual(updated.syncStatus, "synced")
    }

    private func makePhotoUpdateMetric(id: String, userId: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.2,
            weightUnit: "kg",
            bodyFatPercentage: 16.4,
            bodyFatMethod: "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func cachedPhotoState(metricId: String) async throws -> (
        photoUrl: String?,
        originalPhotoUrl: String?,
        isSynced: Bool,
        syncStatus: String?
    ) {
        let context = CoreDataManager.shared.viewContext

        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", metricId)
            request.fetchLimit = 1

            guard let metric = try context.fetch(request).first else {
                throw CoreDataPhotoUpdateTestError.missingMetric
            }

            return (
                metric.photoUrl,
                metric.originalPhotoUrl,
                metric.isSynced,
                metric.syncStatus
            )
        }
    }

    private enum CoreDataPhotoUpdateTestError: Error {
        case missingMetric
    }
}
