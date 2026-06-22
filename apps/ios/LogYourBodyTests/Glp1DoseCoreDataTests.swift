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


final class Glp1DoseCoreDataTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    func testDeletedDoseLogsAreHiddenButRemainPendingForSync() async throws {
        let userId = "glp1-delete-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId)

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)
        let savedLogIds = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId).map(\.id)

        XCTAssertEqual(savedLogIds, [log.id])

        let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: userId)
        let visibleLogsAfterDelete = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)

        XCTAssertTrue(deleted)
        XCTAssertTrue(visibleLogsAfterDelete.isEmpty)

        let unsynced = await CoreDataManager.shared.fetchUnsyncedGlp1DoseLogs(for: userId)

        XCTAssertEqual(unsynced.count, 1)
        XCTAssertEqual(unsynced.first?.id, log.id)
        XCTAssertEqual(unsynced.first?.isMarkedDeleted, true)
        XCTAssertEqual(unsynced.first?.isSynced, false)
        XCTAssertEqual(unsynced.first?.syncStatus, "pending")
    }

    func testRemoteDoseRefreshDoesNotResurrectPendingDeletedLog() async throws {
        let userId = "glp1-tombstone-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId)

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)

        let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: userId)
        XCTAssertTrue(deleted)

        let staleServerLog = Glp1DoseLog(
            id: log.id,
            userId: log.userId,
            takenAt: log.takenAt,
            medicationId: log.medicationId,
            doseAmount: log.doseAmount,
            doseUnit: log.doseUnit,
            drugClass: log.drugClass,
            brand: log.brand,
            isCompounded: log.isCompounded,
            supplierType: log.supplierType,
            supplierName: log.supplierName,
            notes: "stale server copy",
            createdAt: log.createdAt,
            updatedAt: log.updatedAt.addingTimeInterval(60)
        )

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([staleServerLog], userId: userId, markAsSynced: true)

        let visibleLogs = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
        let unsynced = await CoreDataManager.shared.fetchUnsyncedGlp1DoseLogs(for: userId)

        XCTAssertTrue(visibleLogs.isEmpty)
        XCTAssertEqual(unsynced.count, 1)
        XCTAssertEqual(unsynced.first?.id, log.id)
        XCTAssertEqual(unsynced.first?.isMarkedDeleted, true)
        XCTAssertEqual(unsynced.first?.isSynced, false)
        XCTAssertEqual(unsynced.first?.syncStatus, "pending")
    }

    func testDoseLogNotesPersistThroughCoreData() async throws {
        let userId = "glp1-notes-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId, notes: "Left side injection")

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)

        let saved = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.notes, "Left side injection")
    }

    private func makeDoseLog(userId: String, notes: String? = nil) -> Glp1DoseLog {
        let now = Date(timeIntervalSince1970: 1_735_000_000)

        return Glp1DoseLog(
            id: UUID().uuidString,
            userId: userId,
            takenAt: now,
            medicationId: "medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
    }
}
