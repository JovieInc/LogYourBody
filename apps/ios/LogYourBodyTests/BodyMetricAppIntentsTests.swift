//
// BodyMetricAppIntentsTests.swift
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

/// Integration coverage for the Siri/App Shortcuts logging path in
/// `BodyMetricAppIntents.swift`. Each intent's `perform()` is called directly
/// against the shared Core Data stack with an authenticated test user.
///
/// Reachability limit: `perform()` returns an opaque `some IntentResult`
/// whose dialog (`IntentDialog`) and snippet view expose no public accessors,
/// so the user-facing text cannot be read back from the result. The dialog
/// and snippet both render the exact `dialog` string of the
/// `BodyMetricLoggingService` result/summary the intent awaits, so these
/// tests assert that content through the same service call the intent makes,
/// plus the persisted Core Data outcome of `perform()` itself.
///
/// `LogYourBodyAppShortcuts` is intentionally not asserted: `AppShortcut` is
/// an init-only value type with no public accessors for its intent, phrases,
/// shortTitle, or systemImageName, so nothing beyond an existence/count check
/// is reachable — that would be an implementation-wiring check, not behavior.
@MainActor
final class BodyMetricAppIntentsTests: XCTestCase {
    private var previousUser: User?
    private var previousSession: ProductAuthSession?
    private var previousMeasurementSystem: String?
    private var previousHealthKitAuthorization = false

    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()

        // Complete the one-time auth initialization before installing test
        // state so a stored-session restore cannot overwrite it mid-test.
        await AuthManager.shared.ensureAuthInitializationTask().value

        previousUser = AuthManager.shared.currentUser
        previousSession = AuthManager.shared.authSession
        // Signed out by default; keeps RealtimeSyncManager.syncIfNeeded inert.
        AuthManager.shared.currentUser = nil
        AuthManager.shared.authSession = nil

        previousMeasurementSystem = UserDefaults.standard.string(
            forKey: Constants.preferredMeasurementSystemKey
        )
        UserDefaults.standard.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )

        previousHealthKitAuthorization = HealthKitManager.shared.isAuthorized
        HealthKitManager.shared.isAuthorized = false
    }

    override func tearDown() async throws {
        AuthManager.shared.currentUser = previousUser
        AuthManager.shared.authSession = previousSession

        if let previousMeasurementSystem {
            UserDefaults.standard.set(
                previousMeasurementSystem,
                forKey: Constants.preferredMeasurementSystemKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.preferredMeasurementSystemKey)
        }

        HealthKitManager.shared.isAuthorized = previousHealthKitAuthorization

        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    // MARK: - LogWeightIntent

    func testLogWeightIntentPersistsPoundsAsKilograms() async throws {
        let userId = installTestUser(named: "log-weight-lbs")
        var intent = LogWeightIntent()
        intent.weight = 180
        intent.unit = .pounds

        let startedAt = Date()
        _ = try await intent.perform()

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.userId, userId)
        XCTAssertEqual(metric.weight ?? 0, 81.6467, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")
        XCTAssertNil(metric.bodyFatPercentage)
        XCTAssertEqual(metric.dataSource, BodyMetricSource.manual.rawValue)
        XCTAssertGreaterThanOrEqual(metric.date, startedAt)
        XCTAssertEqual(metric.localDate, BodyMetricLocalDate.key(for: metric.date))
    }

    func testLogWeightIntentPersistsKilogramsWithoutConversion() async throws {
        let userId = installTestUser(named: "log-weight-kg")
        var intent = LogWeightIntent()
        intent.weight = 82.5
        intent.unit = .kilograms

        _ = try await intent.perform()

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.weight, 82.5)
        XCTAssertEqual(metrics.first?.weightUnit, "kg")
        XCTAssertEqual(metrics.first?.dataSource, BodyMetricSource.manual.rawValue)
    }

    func testLogWeightIntentRejectsOutOfRangeWeight() async throws {
        let userId = installTestUser(named: "log-weight-range")
        var intent = LogWeightIntent()
        intent.weight = 700
        intent.unit = .pounds

        let message = await captureValidationError {
            _ = try await intent.perform()
        }

        XCTAssertEqual(message, "Enter a weight between 70 and 660 lbs")
        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(metrics.isEmpty)
    }

    func testLogWeightIntentRequiresSignedInUser() async throws {
        let userId = "appintents-signed-out-\(UUID().uuidString)"
        var intent = LogWeightIntent()
        intent.weight = 180
        intent.unit = .pounds

        do {
            _ = try await intent.perform()
            XCTFail("Expected logging without a signed-in user to fail")
        } catch let error as BodyMetricLoggingError {
            guard case .notAuthenticated = error else {
                return XCTFail("Unexpected logging error: \(error)")
            }
            XCTAssertEqual(
                error.errorDescription,
                "Sign in to LogYourBody before logging body metrics."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(metrics.isEmpty)
    }

    // MARK: - LogBodyFatIntent

    func testLogBodyFatIntentPersistsPercentage() async throws {
        let userId = installTestUser(named: "log-bodyfat")
        var intent = LogBodyFatIntent()
        intent.bodyFatPercentage = 15.5

        _ = try await intent.perform()

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.bodyFatPercentage, 15.5)
        XCTAssertEqual(metric.bodyFatMethod, "Manual")
        XCTAssertNil(metric.weight)
        XCTAssertNil(metric.sourceMetadata?.weightOperationId)
        XCTAssertEqual(metric.dataSource, BodyMetricSource.manual.rawValue)
    }

    func testLogBodyFatIntentRejectsOutOfRangePercentage() async throws {
        let userId = installTestUser(named: "log-bodyfat-range")
        var intent = LogBodyFatIntent()
        intent.bodyFatPercentage = 61

        let message = await captureValidationError {
            _ = try await intent.perform()
        }

        XCTAssertEqual(message, "Body fat must be between 3-60%")
        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(metrics.isEmpty)
    }

    // MARK: - ShowLatestMetricsIntent

    func testShowLatestMetricsIntentSurfacesMostRecentSeededMetric() async throws {
        let userId = installTestUser(named: "latest-metrics")

        let older = seedMetric(
            userId: userId,
            date: Date(timeIntervalSince1970: 1_735_000_000),
            weight: 80,
            bodyFatPercentage: nil
        )
        let newer = seedMetric(
            userId: userId,
            date: Date(timeIntervalSince1970: 1_736_000_000),
            weight: 75,
            bodyFatPercentage: 12.5
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(older, userId: userId, markAsSynced: true)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(newer, userId: userId, markAsSynced: true)

        _ = try await ShowLatestMetricsIntent().perform()

        // The intent's dialog/snippet are not readable headlessly; assert the
        // exact summary the intent renders via the same call it makes.
        let summary = try await BodyMetricLoggingService.shared.latestMetricsSummary()
        XCTAssertEqual(summary.metrics.id, newer.id)
        XCTAssertEqual(summary.metrics.bodyFatPercentage, 12.5)
        XCTAssertEqual(
            summary.dialog,
            "Your latest metrics are 165.3 lbs and 12.5% body fat."
        )
    }

    func testShowLatestMetricsIntentWithoutMetricsThrowsNoMetrics() async throws {
        _ = installTestUser(named: "latest-empty")

        do {
            _ = try await ShowLatestMetricsIntent().perform()
            XCTFail("Expected the empty store to fail")
        } catch let error as BodyMetricLoggingError {
            guard case .noMetrics = error else {
                return XCTFail("Unexpected logging error: \(error)")
            }
            XCTAssertEqual(
                error.errorDescription,
                "No body metrics have been logged yet."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLogWeightIntentRetryKeepsTheSameRecordAndOperation() async throws {
        let userId = installTestUser(named: "log-weight-retry")
        var intent = LogWeightIntent()
        intent.weight = 180
        intent.unit = .pounds

        _ = try await intent.perform()
        _ = try await intent.perform()

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.id, intent.recordId)
        XCTAssertEqual(metrics.first?.sourceMetadata?.weightOperationId, intent.operationId)
        XCTAssertEqual(metrics.first?.sourceMetadata?.weightRevision, 1)
    }

    func testASecondLogWeightIntentGetsANewRecord() async throws {
        let userId = installTestUser(named: "log-weight-second")
        var first = LogWeightIntent()
        first.weight = 180
        first.unit = .pounds
        var second = LogWeightIntent()
        second.weight = 181
        second.unit = .pounds

        _ = try await first.perform()
        _ = try await second.perform()

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)
        XCTAssertNotEqual(first.recordId, second.recordId)
        XCTAssertEqual(Set(metrics.map(\.id)), Set([first.recordId, second.recordId]))
    }

    func testDeniedHealthKitStillSavesLocallyAndDoesNotClaimCloud() async throws {
        let userId = installTestUser(named: "log-weight-healthkit-denied")
        XCTAssertFalse(HealthKitManager.shared.isAuthorized)
        let identity = BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        let result = try await BodyMetricLoggingService.shared.log(
            weight: "82.5",
            bodyFat: nil,
            unit: "kg",
            identity: identity,
            protectedDataAvailable: true
        )

        XCTAssertEqual(result.completion.local, .saved)
        XCTAssertEqual(result.completion.healthKit, .denied)
        XCTAssertEqual(result.completion.cloud, .notClaimed)
        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.weight, 82.5)
    }

    func testLockedDeviceAndCancelledClarificationDoNotSave() async throws {
        let userId = installTestUser(named: "log-weight-locked")
        let service = BodyMetricLoggingService.shared

        do {
            _ = try await service.log(
                weight: "180", bodyFat: nil, unit: "lbs", protectedDataAvailable: false
            )
            XCTFail("Expected a locked device to reject the log")
        } catch BodyMetricLoggingError.protectedDataUnavailable {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await service.log(
                weight: "180", bodyFat: nil, unit: "lbs", clarificationCancelled: true
            )
            XCTFail("Expected a cancelled clarification to reject the log")
        } catch BodyMetricLoggingError.clarificationCancelled {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(metrics.isEmpty)
    }

    func testBackdatedMidnightAndSameDayEntriesKeepTheirLocalDates() async throws {
        let userId = installTestUser(named: "log-weight-midnight")
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        parser.timeZone = zone
        let midnight = try XCTUnwrap(parser.date(from: "2026-10-13T00:00:00-07:00"))
        let yesterday = try XCTUnwrap(parser.date(from: "2026-10-12T23:30:00-07:00"))
        let service = BodyMetricLoggingService.shared
        let first = try await service.log(
            weight: "180", bodyFat: nil, unit: "lbs", date: midnight, timeZone: zone,
            identity: BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        )
        let second = try await service.log(
            weight: "181", bodyFat: nil, unit: "lb", date: midnight, timeZone: zone,
            identity: BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        )
        let prior = try await service.log(
            weight: "179", bodyFat: nil, unit: "lbs", date: yesterday, timeZone: zone,
            identity: BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        )

        XCTAssertEqual(first.metrics.localDate, "2026-10-13")
        XCTAssertEqual(second.metrics.localDate, "2026-10-13")
        XCTAssertEqual(prior.metrics.localDate, "2026-10-12")
        XCTAssertNotEqual(first.metrics.id, second.metrics.id)
        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(first.completion.cloud, .notClaimed)
    }

    func testSameOperationDoesNotResurrectADeleteOrOverwriteADifferentWeight() async throws {
        let userId = installTestUser(named: "log-weight-tombstone")
        let service = BodyMetricLoggingService.shared
        let identity = BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        let created = try await service.log(
            weight: "180", bodyFat: nil, unit: "lbs", identity: identity
        )
        let deleted = await CoreDataManager.shared.markBodyMetricDeleted(id: identity.recordId, userId: userId)
        XCTAssertTrue(deleted)

        _ = try await service.log(weight: "180", bodyFat: nil, unit: "lbs", identity: identity)
        let stillDeleted = await cachedFlag(id: identity.recordId)
        XCTAssertEqual(stillDeleted?.isMarkedDeleted, true)
        XCTAssertEqual(stillDeleted?.weight ?? 0, created.metrics.weight ?? 0, accuracy: 0.001)

        let liveIdentity = BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        let live = try await service.log(weight: "80", bodyFat: nil, unit: "kg", identity: liveIdentity)
        let replacement = BodyMetrics(
            id: live.metrics.id,
            userId: userId,
            date: live.metrics.date,
            localDate: live.metrics.localDate,
            weight: 90,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: live.metrics.sourceMetadata,
            createdAt: live.metrics.createdAt,
            updatedAt: live.metrics.updatedAt
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(replacement, userId: userId)
        let conflicted = await cachedFlag(id: liveIdentity.recordId)
        XCTAssertEqual(conflicted?.syncStatus, "conflict")
        XCTAssertEqual(conflicted?.weight ?? 0, 80, accuracy: 0.001)
        XCTAssertFalse(conflicted?.isMarkedDeleted ?? true)
    }

    func testSaveForAnotherOwnersRecordFailsWithoutChangingIt() async throws {
        let owner = installTestUser(named: "log-weight-owner")
        let identity = BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
        _ = try await BodyMetricLoggingService.shared.log(
            weight: "82.5", bodyFat: nil, unit: "kg", identity: identity
        )
        _ = installTestUser(named: "log-weight-other")

        do {
            _ = try await BodyMetricLoggingService.shared.log(
                weight: "70", bodyFat: nil, unit: "kg", identity: identity
            )
            XCTFail("Expected another account's record to be rejected")
        } catch {
            XCTAssertFalse(error is BodyMetricLoggingError)
        }

        let metrics = await CoreDataManager.shared.fetchAllBodyMetrics(for: owner)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.weight, 82.5)
    }

    // MARK: - Parameter glue

    func testWeightUnitStorageUnitMatchesValidationContract() {
        XCTAssertEqual(BodyMetricIntentWeightUnit.pounds.storageUnit, "lbs")
        XCTAssertEqual(BodyMetricIntentWeightUnit.kilograms.storageUnit, "kg")
    }

    func testLogWeightIntentDefaultsToPreferredMeasurementSystem() {
        UserDefaults.standard.set(
            MeasurementSystem.metric.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        XCTAssertEqual(LogWeightIntent().unit, .kilograms)

        UserDefaults.standard.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        XCTAssertEqual(LogWeightIntent().unit, .pounds)
    }

    // MARK: - Helpers

    @discardableResult
    private func installTestUser(named name: String) -> String {
        let userId = "appintents-\(name)-\(UUID().uuidString)"
        AuthManager.shared.currentUser = User(
            id: userId,
            email: "\(name)@example.com",
            name: "App Intents Test",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        return userId
    }

    private func seedMetric(
        userId: String,
        date: Date,
        weight: Double,
        bodyFatPercentage: Double?
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatPercentage != nil ? "Manual" : nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func cachedFlag(id: String) async -> (isMarkedDeleted: Bool, weight: Double, syncStatus: String?)? {
        let context = CoreDataManager.shared.viewContext
        return await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            guard let row = try? context.fetch(request).first else { return nil }
            return (row.isMarkedDeleted, row.weight, row.syncStatus)
        }
    }

    private func captureValidationError(
        from expression: () async throws -> Void
    ) async -> String? {
        do {
            try await expression()
            XCTFail("Expected validation to fail")
            return nil
        } catch let error as ValidationError {
            return error.errorDescription
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }
}
