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

    func testSaveGlp1DoseLogsDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "glp1-owner-\(UUID().uuidString)"
        let otherId = "glp1-other-\(UUID().uuidString)"
        let log = makeDoseLog(userId: ownerId, notes: "owner-dose")

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: ownerId, markAsSynced: true)

        let stolen = Glp1DoseLog(
            id: log.id,
            userId: otherId,
            takenAt: log.takenAt,
            medicationId: log.medicationId,
            doseAmount: 1.0,
            doseUnit: log.doseUnit,
            drugClass: log.drugClass,
            brand: log.brand,
            isCompounded: log.isCompounded,
            supplierType: log.supplierType,
            supplierName: log.supplierName,
            notes: "stolen-dose",
            createdAt: log.createdAt,
            updatedAt: log.updatedAt
        )
        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([stolen], userId: otherId, markAsSynced: false)

        let cached = await cachedDose(id: log.id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.doseAmount, 5.0, accuracy: 0.001)
        XCTAssertEqual(row.notes, "owner-dose")
    }

    func testSaveGlp1MedicationsDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "glp1-med-owner-\(UUID().uuidString)"
        let otherId = "glp1-med-other-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_735_000_000)
        let medication = makeMedication(
            id: UUID().uuidString,
            userId: ownerId,
            name: "Zepbound",
            notes: "owner-medication",
            date: date
        )

        CoreDataManager.shared.saveGlp1Medications([medication], userId: ownerId, markAsSynced: true)
        CoreDataManager.shared.saveGlp1Medications(
            [makeMedication(
                id: medication.id,
                userId: otherId,
                name: "Stolen",
                notes: "stolen-medication",
                date: date
            )],
            userId: otherId,
            markAsSynced: false
        )

        let cached = await cachedMedication(id: medication.id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.displayName, "Zepbound")
        XCTAssertEqual(row.notes, "owner-medication")
    }

    func testSaveDailyMetricsDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "daily-owner-\(UUID().uuidString)"
        let otherId = "daily-other-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_735_000_000)
        let id = UUID().uuidString
        let metric = DailyMetrics(
            id: id,
            userId: ownerId,
            date: date,
            steps: 10_000,
            notes: "owner-steps",
            createdAt: date,
            updatedAt: date
        )

        try await CoreDataManager.shared.saveDailyMetricsAndWait(metric, userId: ownerId)
        var refused = false
        do {
            try await CoreDataManager.shared.saveDailyMetricsAndWait(
                DailyMetrics(
                    id: id,
                    userId: otherId,
                    date: date,
                    steps: 1,
                    notes: "stolen-steps",
                    createdAt: date,
                    updatedAt: date
                ),
                userId: otherId
            )
        } catch {
            refused = true
        }

        XCTAssertTrue(refused, "A signed-in account must not save another account's daily steps")
        let cached = await cachedDailyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.steps, 10_000)
        XCTAssertEqual(row.notes, "owner-steps")
    }

    func testUpdateOrCreateDailyMetricDoesNotReassignAnotherAccountsRow() async throws {
        let ownerId = "daily-remote-owner-\(UUID().uuidString)"
        let otherId = "daily-remote-other-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_735_100_000)
        let id = UUID().uuidString
        try await CoreDataManager.shared.saveDailyMetricsAndWait(
            DailyMetrics(
                id: id,
                userId: ownerId,
                date: date,
                steps: 10_000,
                notes: "owner-steps",
                createdAt: date,
                updatedAt: date
            ),
            userId: ownerId
        )

        let formatter = ISO8601DateFormatter()
        CoreDataManager.shared.updateOrCreateDailyMetric(from: [
            "id": id,
            "user_id": otherId,
            "date": formatter.string(from: date),
            "steps": 1,
            "notes": "foreign-steps",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ])

        let cached = await cachedDailyMetric(id: id)
        let row = try XCTUnwrap(cached)
        XCTAssertEqual(row.userId, ownerId)
        XCTAssertEqual(row.steps, 10_000)
        XCTAssertEqual(row.notes, "owner-steps")
    }

    func testDoseLogNotesPersistThroughCoreData() async throws {
        let userId = "glp1-notes-\(UUID().uuidString)"
        let log = makeDoseLog(userId: userId, notes: "Left side injection")

        try await CoreDataManager.shared.saveGlp1DoseLogsAndWait([log], userId: userId, markAsSynced: true)

        let saved = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.notes, "Left side injection")
    }

    private func makeMedication(
        id: String,
        userId: String,
        name: String,
        notes: String,
        date: Date
    ) -> Glp1Medication {
        Glp1Medication(
            id: id,
            userId: userId,
            displayName: name,
            genericName: nil,
            drugClass: nil,
            brand: name,
            route: nil,
            frequency: nil,
            doseUnit: "mg",
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: date,
            endedAt: nil,
            notes: notes,
            createdAt: date,
            updatedAt: date
        )
    }

    func testWeeklyCheckInFixtureReseedKeepsTheNewUsersMedication() async throws {
        let firstUser = "synthetic-glp1-fixture-a"
        let secondUser = "synthetic-glp1-fixture-b"
        await CoreDataManager.shared.replaceUITestGlp1WeeklyCheckInFixture(userId: firstUser)
        let firstMeds = await CoreDataManager.shared.fetchGlp1Medications(for: firstUser)
        XCTAssertEqual(firstMeds.map(\.id), ["ui_test_glp1_medication"])

        await CoreDataManager.shared.replaceUITestGlp1WeeklyCheckInFixture(userId: secondUser)
        let secondMeds = await CoreDataManager.shared.fetchGlp1Medications(for: secondUser)
        XCTAssertEqual(secondMeds.map(\.displayName), ["Zepbound"])
        let secondDoses = await CoreDataManager.shared.fetchGlp1DoseLogs(for: secondUser)
        XCTAssertEqual(secondDoses.map(\.notes), ["UI test weekly check-in seed"])
        let owner = await cachedMedication(id: "ui_test_glp1_medication")
        XCTAssertEqual(owner?.userId, secondUser)
        let doseOwner = await cachedDose(id: "ui_test_glp1_dose_due")
        XCTAssertEqual(doseOwner?.userId, secondUser)
        let firstAfter = await CoreDataManager.shared.fetchGlp1Medications(for: firstUser)
        XCTAssertTrue(firstAfter.isEmpty)
    }

    private func cachedDose(id: String) async -> CachedGlp1DoseLog? {
        let context = CoreDataManager.shared.viewContext
        return await context.perform {
            let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    private func cachedMedication(id: String) async -> CachedGlp1Medication? {
        let context = CoreDataManager.shared.viewContext
        return await context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    private func cachedDailyMetric(id: String) async -> CachedDailyMetrics? {
        let context = CoreDataManager.shared.viewContext
        return await context.perform {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
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
