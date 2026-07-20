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
    private var previousIsAuthenticated = false
    private var previousMeasurementSystem: String?
    private var previousHealthKitAuthorization = false

    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()

        // Complete the one-time auth initialization before installing test
        // state so a stored-session restore cannot overwrite it mid-test.
        await AuthManager.shared.ensureAuthInitializationTask().value

        previousUser = AuthManager.shared.currentUser
        previousIsAuthenticated = AuthManager.shared.isAuthenticated
        // Signed out by default; keeps RealtimeSyncManager.syncIfNeeded inert.
        AuthManager.shared.currentUser = nil
        AuthManager.shared.isAuthenticated = false

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
        AuthManager.shared.isAuthenticated = previousIsAuthenticated

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

    // MARK: - Parameter glue

    func testWeightUnitStorageUnitMatchesValidationContract() {
        XCTAssertEqual(BodyMetricIntentWeightUnit.pounds.storageUnit, "lbs")
        XCTAssertEqual(BodyMetricIntentWeightUnit.kilograms.storageUnit, "kg")
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
