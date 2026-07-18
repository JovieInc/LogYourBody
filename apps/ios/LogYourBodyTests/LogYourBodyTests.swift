//
// LogYourBodyTests.swift
// LogYourBody
//
import CoreData
import XCTest
@testable import LogYourBody

// swiftlint:disable single_test_class

@MainActor
final class OnboardingFlowViewModelTests: XCTestCase {
    func testMetricHeightEntryPersistsAndAdvancesToHealthConnect() {
        let viewModel = OnboardingFlowViewModel(entryContext: .preAuth)
        viewModel.currentStep = .height
        viewModel.updateHeightCentimetersText("170")

        viewModel.persistHeightEntry()
        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.bodyScoreInput.height, HeightValue(value: 170, unit: .centimeters))
        XCTAssertEqual(viewModel.currentStep, .healthConnect)
    }

    func testAdvanceAfterHealthConfirmationSkipsToLoadingWhenMetricsExist() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testAdvanceAfterHealthConfirmationRequestsBodyFatWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 185, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testAdvanceAfterHealthConfirmationRequiresWeightWhenMissing() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue()
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 18, source: .healthKit)
        viewModel.currentStep = .healthConfirmation

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .manualWeight)
    }

    func testManualWeightStepContinuesToBodyFatChoiceWhenNeeded() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue()
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .bodyFatChoice)
    }

    func testManualWeightStepSkipsBodyFatWhenAlreadyEntered() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.weight = WeightValue(value: 180, unit: .pounds)
        viewModel.bodyScoreInput.bodyFat = BodyFatValue(percentage: 17.5, source: .manualValue)
        viewModel.currentStep = .manualWeight

        viewModel.goToNextStep()

        XCTAssertEqual(viewModel.currentStep, .loading)
    }

    func testBuildOnboardingProfileUpdatesStoresCanonicalHeightAndPreferredUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.female)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 180, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesConvertsImperialHeightToCanonicalCentimeters() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["height"] as? Double, 182.88)
        XCTAssertEqual(updates["heightUnit"] as? String, "in")
    }

    func testBuildOnboardingProfileUpdatesAlwaysMarksOnboardingCompleted() {
        let viewModel = OnboardingFlowViewModel()

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testHeightUnitSwitchPreservesHeightAndMeasurementPreference() {
        let defaults = UserDefaults.standard
        let measurementKey = Constants.preferredMeasurementSystemKey
        let weightKey = Constants.preferredWeightUnitKey
        let originalMeasurementSystem = defaults.object(forKey: measurementKey)
        let originalWeightUnit = defaults.object(forKey: weightKey)
        defer {
            restore(defaults, value: originalMeasurementSystem, forKey: measurementKey)
            restore(defaults, value: originalWeightUnit, forKey: weightKey)
        }

        defaults.set(MeasurementSystem.metric.rawValue, forKey: measurementKey)
        let viewModel = OnboardingFlowViewModel(entryContext: .preAuth)
        viewModel.updateHeightCentimetersText("177.8")
        viewModel.persistHeightEntry()

        viewModel.setHeightUnit(.inches)

        XCTAssertEqual(viewModel.heightUnit, .inches)
        XCTAssertEqual(viewModel.heightFeet, 5)
        XCTAssertEqual(viewModel.heightInches, 10)
        XCTAssertEqual(viewModel.bodyScoreInput.measurementPreference, .imperial)

        viewModel.setHeightUnit(.centimeters)

        XCTAssertEqual(viewModel.heightUnit, .centimeters)
        XCTAssertEqual(viewModel.heightCentimetersText, "177.8")
        XCTAssertEqual(viewModel.bodyScoreInput.measurementPreference, .metric)
    }

    func testClearLocalSessionSetsExitReasonUserInitiated() {
        let manager = AuthManager()
        manager.isAuthenticated = true

        manager.clearLocalSession(reason: .userInitiated)

        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testClearLocalSessionSetsSessionExpired() {
        let manager = AuthManager()
        manager.isAuthenticated = true
        manager.lastExitReason = .none
        manager.currentUser = LocalUser(
            id: "test-user",
            email: "test@example.com",
            name: "Test User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )

        manager.clearLocalSession(reason: .sessionExpired)

        XCTAssertEqual(manager.lastExitReason, .sessionExpired)
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
    }

    func testUpdateLocalUserResetsExitReasonToNoneOnSignIn() {
        let manager = AuthManager()
        manager.lastExitReason = .sessionExpired

        struct FakeEmailAddress {
            let emailAddress: String
        }

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [FakeEmailAddress]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_123",
            emailAddresses: [FakeEmailAddress(emailAddress: "test@example.com")],
            firstName: "Test",
            lastName: "User",
            username: "testuser",
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertEqual(manager.lastExitReason, .none)
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "test@example.com")
    }

    private func restore(_ defaults: UserDefaults, value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

class StubSupabaseManager: SupabaseManager {
    private(set) var bodyMetricsBatches: [[[String: Any]]] = []
    private(set) var dailyMetricsBatches: [[[String: Any]]] = []
    private(set) var dexaPayloads: [[String: Any]] = []

    override func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        bodyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        dailyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func upsertData(table: String, data: Data, token: String) async throws {
        guard table == "dexa_results" else {
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let array = jsonObject as? [[String: Any]] ?? []
        dexaPayloads.append(contentsOf: array)
    }
}

final class AccountSwitchingSupabaseManager: StubSupabaseManager {
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
        super.init()
    }

    override func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let response = try await super.upsertBodyMetricsBatch(metrics, token: token)
        await MainActor.run {
            authManager.clearLocalSession(reason: .userInitiated)
        }
        return response
    }
}

@MainActor
final class SyncIntegrationTests: XCTestCase {
    private func authenticatedManager(for userId: String) -> AuthManager {
        let manager = AuthManager()
        manager.currentUser = LocalUser(
            id: userId,
            email: "\(userId)@example.com",
            name: "Test User",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        manager.isAuthenticated = true
        return manager
    }

    func testUpdateOrCreateBodyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.5,
            "weight_unit": "kg",
            "body_fat_percentage": 18.2,
            "body_fat_method": "health_kit",
            "muscle_mass": 35.0,
            "bone_mass": 4.2,
            "photo_url": "https://example.com/photo.jpg",
            "notes": "supabase-mapped",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 80.5, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")

        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 18.2, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "health_kit")

        let muscle = try XCTUnwrap(metric.muscleMass)
        XCTAssertEqual(muscle, 35.0, accuracy: 0.001)

        let bone = try XCTUnwrap(metric.boneMass)
        XCTAssertEqual(bone, 4.2, accuracy: 0.001)

        XCTAssertEqual(metric.photoUrl, "https://example.com/photo.jpg")
        XCTAssertEqual(metric.notes, "supabase-mapped")

        XCTAssertEqual(metric.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateDailyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let createdAt = date.addingTimeInterval(-120)
        let updatedAt = date
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "steps": 10_000,
            "notes": "daily-metrics-mapped",
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ]

        coreData.updateOrCreateDailyMetric(from: payload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.date.timeIntervalSince(date), 0, accuracy: 0.001)
        XCTAssertEqual(log.stepCount, 10_000)
        XCTAssertEqual(log.notes, "daily-metrics-mapped")
        XCTAssertEqual(log.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateBodyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_idempotent_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight_unit": "kg",
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["weight"] = 75.0
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["weight"] = 82.0
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateBodyMetric(from: firstPayload)
        coreData.updateOrCreateBodyMetric(from: secondPayload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.id, id)
        XCTAssertEqual(metric.userId, userId)

        let weight = try XCTUnwrap(metric.weight)
        XCTAssertEqual(weight, 82.0, accuracy: 0.001)
        XCTAssertEqual(metric.weightUnit, "kg")
        XCTAssertEqual(metric.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testUpdateOrCreateDailyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_idempotent_\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let createdAt = date.addingTimeInterval(-300)
        let updatedAt1 = date.addingTimeInterval(-120)
        let updatedAt2 = date
        let formatter = ISO8601DateFormatter()

        let basePayload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "created_at": formatter.string(from: createdAt)
        ]

        var firstPayload = basePayload
        firstPayload["steps"] = 5_000
        firstPayload["notes"] = "first"
        firstPayload["updated_at"] = formatter.string(from: updatedAt1)

        var secondPayload = basePayload
        secondPayload["steps"] = 12_000
        secondPayload["notes"] = "second"
        secondPayload["updated_at"] = formatter.string(from: updatedAt2)

        coreData.updateOrCreateDailyMetric(from: firstPayload)
        coreData.updateOrCreateDailyMetric(from: secondPayload)

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(logs.count, 1)

        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, id)
        XCTAssertEqual(log.userId, userId)
        XCTAssertEqual(log.stepCount, 12_000)
        XCTAssertEqual(log.notes, "second")
        XCTAssertEqual(log.updatedAt.timeIntervalSince(updatedAt2), 0, accuracy: 0.001)
    }

    func testProcessBatchHealthKitData_RespectsExistingEntriesWithinSameHour() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_existing_\(UUID().uuidString)"

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let existingDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 15), to: day) ?? day

        let existingMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: existingDate,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "existing-healthkit",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: existingDate,
            updatedAt: existingDate
        )

        coreData.saveBodyMetrics(existingMetric, userId: userId)

        let sameHourDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 45), to: day) ?? day
        let nextHourDate = calendar.date(byAdding: DateComponents(hour: 11, minute: 5), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 81.0, date: sameHourDate),
            (weight: 82.0, date: nextHourDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory,
            userIdOverride: userId,
            synchronizesAfterSaving: false
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 2)
    }

    func testProcessBatchHealthKitData_DeduplicatesMultipleWeightsInSameHour() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_batch_\(UUID().uuidString)"

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let firstDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 5), to: day) ?? day
        let secondDate = calendar.date(byAdding: DateComponents(hour: 9, minute: 50), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 70.0, date: firstDate),
            (weight: 71.0, date: secondDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = []

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory,
            userIdOverride: userId,
            synchronizesAfterSaving: false
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
    }

    func testProcessBatchHealthKitData_AssignsBodyFatForMatchingDate() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_bodyfat_\(UUID().uuidString)"

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let weightDate = calendar.date(byAdding: DateComponents(hour: 8, minute: 0), to: day) ?? day
        let bodyFatDate = calendar.date(byAdding: DateComponents(hour: 6, minute: 30), to: day) ?? day

        let weightHistory: [(weight: Double, date: Date)] = [
            (weight: 75.0, date: weightDate)
        ]

        let bodyFatHistory: [(percentage: Double, date: Date)] = [
            (percentage: 19.5, date: bodyFatDate)
        ]

        let result = await healthKitManager.processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory,
            userIdOverride: userId,
            synchronizesAfterSaving: false
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 0)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        let bodyFat = try XCTUnwrap(metric.bodyFatPercentage)
        XCTAssertEqual(bodyFat, 19.5, accuracy: 0.001)
        XCTAssertEqual(metric.bodyFatMethod, "HealthKit")
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksBodyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 80.5,
            weightUnit: "kg",
            bodyFatPercentage: 18.2,
            bodyFatMethod: "manual",
            muscleMass: 35.0,
            boneMass: 4.2,
            notes: "unsynced-local",
            photoUrl: "https://example.com/photo.jpg",
            dataSource: "Manual",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        coreData.saveBodyMetrics(metricModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let authManager = authenticatedManager(for: userId)
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(for: userId, token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        guard let batch = stubSupabase.bodyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No body metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        let payloadWeight = try XCTUnwrap(payload["weight"] as? Double)
        XCTAssertEqual(payloadWeight, 80.5, accuracy: 0.001)

        XCTAssertEqual(payload["weight_unit"] as? String, "kg")
        XCTAssertEqual(payload["photo_url"] as? String, "https://example.com/photo.jpg")
        XCTAssertEqual(payload["notes"] as? String, "unsynced-local")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertTrue(unsynced.bodyMetrics.isEmpty)
    }

    func testSyncLocalChangesRejectsDataForAnInactiveUser() async throws {
        let coreData = CoreDataManager.shared
        let storedUserId = "sync-stale-user-\(UUID().uuidString)"
        let activeUserId = "sync-active-user-\(UUID().uuidString)"
        let metric = BodyMetrics(
            id: UUID().uuidString,
            userId: storedUserId,
            date: Date(),
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: Date(),
            updatedAt: Date()
        )
        coreData.saveBodyMetrics(metric, userId: storedUserId)
        _ = await coreData.fetchBodyMetrics(for: storedUserId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authenticatedManager(for: activeUserId),
            supabaseManager: stubSupabase
        )

        do {
            try await manager.syncLocalChanges(for: storedUserId, token: "test-token")
            XCTFail("Sync should reject a stale user scope")
        } catch let error as SyncError {
            guard case .noAuthSession = error else {
                return XCTFail("Unexpected sync error: \(error)")
            }
        }

        XCTAssertTrue(stubSupabase.bodyMetricsBatches.isEmpty)
        let unsynced = await coreData.fetchUnsyncedEntries(for: storedUserId)
        XCTAssertEqual(unsynced.bodyMetrics.compactMap(\.id), [metric.id])
    }

    func testSyncLocalChangesStopsAfterTheActiveAccountChanges() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync-account-change-\(UUID().uuidString)"
        let date = Date()
        let bodyMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
        let dailyMetric = DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            steps: 10_000,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
        coreData.saveBodyMetrics(bodyMetric, userId: userId)
        coreData.saveDailyMetrics(dailyMetric, userId: userId)

        let authManager = authenticatedManager(for: userId)
        let stubSupabase = AccountSwitchingSupabaseManager(authManager: authManager)
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: stubSupabase
        )

        do {
            try await manager.syncLocalChanges(for: userId, token: "test-token")
            XCTFail("Sync should stop after the authenticated account changes")
        } catch let error as SyncError {
            guard case .noAuthSession = error else {
                return XCTFail("Unexpected sync error: \(error)")
            }
        }

        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        XCTAssertTrue(stubSupabase.dailyMetricsBatches.isEmpty)

        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertTrue(unsynced.bodyMetrics.isEmpty)
        XCTAssertEqual(unsynced.dailyMetrics.compactMap(\.id), [dailyMetric.id])
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksDailyMetricSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_realtime_\(UUID().uuidString)"
        let date = Date()
        let createdAt = date.addingTimeInterval(-60)
        let updatedAt = date

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 10_000,
            notes: "unsynced-daily",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let authManager = authenticatedManager(for: userId)
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(for: userId, token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dailyMetricsBatches.count, 1)
        guard let batch = stubSupabase.dailyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No daily metrics batch captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)

        if let stepsValue = payload["steps"] as? Int32 {
            XCTAssertEqual(stepsValue, 10_000)
        } else if let stepsValue = payload["steps"] as? Int {
            XCTAssertEqual(stepsValue, 10_000)
        } else {
            XCTFail("Expected steps field as Int or Int32")
        }

        XCTAssertEqual(payload["notes"] as? String, "unsynced-daily")

        if let dateString = payload["date"] as? String {
            let formatter = ISO8601DateFormatter()
            let sentDate = formatter.date(from: dateString)
            XCTAssertNotNil(sentDate)
        } else {
            XCTFail("Expected date field in payload")
        }

        // Verify Core Data entry for this user is no longer unsynced
        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertTrue(unsynced.dailyMetrics.isEmpty)
    }

    func testSyncLocalChanges_UsesSupabaseAndMarksDexaResultsSynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_dexa_realtime_\(UUID().uuidString)"
        let bodyMetricsId = UUID().uuidString
        let now = Date()
        let createdAt = now.addingTimeInterval(-120)
        let updatedAt = now

        let context = coreData.viewContext
        await context.perform {
            let result = CachedDexaResult(context: context)
            result.id = id
            result.userId = userId
            result.bodyMetricsId = bodyMetricsId
            result.externalSource = "BodySpec"
            result.externalResultId = "result-\(UUID().uuidString)"
            result.externalUpdateTime = now
            result.scannerModel = "TestScanner"
            result.locationId = "loc-123"
            result.locationName = "Test Location"
            result.acquireTime = now.addingTimeInterval(-3_600)
            result.analyzeTime = now.addingTimeInterval(-1_800)
            result.vatMassKg = 1.23
            result.vatVolumeCm3 = 456.0
            result.resultPdfUrl = "https://example.com/result.pdf"
            result.resultPdfName = "result.pdf"
            result.createdAt = createdAt
            result.updatedAt = updatedAt
            result.isSynced = false
            result.syncStatus = "pending"

            if context.hasChanges {
                try? context.save()
            }
        }

        let stubSupabase = StubSupabaseManager()
        let authManager = authenticatedManager(for: userId)
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(for: userId, token: "test-token")

        // Verify Supabase payload
        XCTAssertEqual(stubSupabase.dexaPayloads.count, 1)
        guard let payload = stubSupabase.dexaPayloads.first else {
            XCTFail("No Dexa payload captured")
            return
        }

        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["user_id"] as? String, userId)
        XCTAssertEqual(payload["body_metrics_id"] as? String, bodyMetricsId)
        XCTAssertEqual(payload["external_source"] as? String, "BodySpec")
        XCTAssertEqual(payload["result_pdf_url"] as? String, "https://example.com/result.pdf")
        XCTAssertEqual(payload["result_pdf_name"] as? String, "result.pdf")

        if let vatMass = payload["vat_mass_kg"] as? Double {
            XCTAssertEqual(vatMass, 1.23, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_mass_kg in payload")
        }

        if let vatVolume = payload["vat_volume_cm3"] as? Double {
            XCTAssertEqual(vatVolume, 456.0, accuracy: 0.001)
        } else {
            XCTFail("Expected vat_volume_cm3 in payload")
        }

        if let acquireTimeString = payload["acquire_time"] as? String {
            let formatter = ISO8601DateFormatter()
            let parsed = formatter.date(from: acquireTimeString)
            XCTAssertNotNil(parsed)
        } else {
            XCTFail("Expected acquire_time field in payload")
        }

        // Verify there are no remaining unsynced Dexa results for this user
        let unsyncedDexa = await coreData.fetchUnsyncedDexaResults(for: userId)
        XCTAssertTrue(unsyncedDexa.isEmpty)
    }

    func testCachedDexaResult_toDexaResultMapsFieldsAndNormalizesVatValues() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext

        let id = UUID().uuidString
        let userId = "mapping_test_user_\(UUID().uuidString)"
        let externalSource = "BodySpec"
        let externalResultId = "result-\(UUID().uuidString)"
        let now = Date()
        let createdAt = now.addingTimeInterval(-300)
        let updatedAt = now

        var mappedWithVat: DexaResult?
        var mappedWithoutVat: DexaResult?

        await context.perform {
            // Case 1: VAT values > 0 should be preserved
            let withVat = CachedDexaResult(context: context)
            withVat.id = id
            withVat.userId = userId
            withVat.bodyMetricsId = "bm-\(UUID().uuidString)"
            withVat.externalSource = externalSource
            withVat.externalResultId = externalResultId
            withVat.externalUpdateTime = now
            withVat.scannerModel = "TestScanner"
            withVat.locationId = "loc-123"
            withVat.locationName = "Test Location"
            withVat.acquireTime = now.addingTimeInterval(-3_600)
            withVat.analyzeTime = now.addingTimeInterval(-1_800)
            withVat.vatMassKg = 2.5
            withVat.vatVolumeCm3 = 789.0
            withVat.resultPdfUrl = "https://example.com/result.pdf"
            withVat.resultPdfName = "result.pdf"
            withVat.createdAt = createdAt
            withVat.updatedAt = updatedAt

            mappedWithVat = withVat.toDexaResult()

            // Case 2: VAT values <= 0 should map to nil
            let withoutVat = CachedDexaResult(context: context)
            withoutVat.id = UUID().uuidString
            withoutVat.userId = userId
            withoutVat.bodyMetricsId = nil
            withoutVat.externalSource = externalSource
            withoutVat.externalResultId = externalResultId
            withoutVat.externalUpdateTime = nil
            withoutVat.scannerModel = nil
            withoutVat.locationId = nil
            withoutVat.locationName = nil
            withoutVat.acquireTime = nil
            withoutVat.analyzeTime = nil
            withoutVat.vatMassKg = 0.0
            withoutVat.vatVolumeCm3 = -10.0
            withoutVat.resultPdfUrl = nil
            withoutVat.resultPdfName = nil
            withoutVat.createdAt = createdAt
            withoutVat.updatedAt = updatedAt

            mappedWithoutVat = withoutVat.toDexaResult()
        }

        let withVat = try XCTUnwrap(mappedWithVat)
        XCTAssertEqual(withVat.id, id)
        XCTAssertEqual(withVat.userId, userId)
        XCTAssertEqual(withVat.externalSource, externalSource)
        XCTAssertEqual(withVat.externalResultId, externalResultId)

        let vatMass = try XCTUnwrap(withVat.vatMassKg)
        XCTAssertEqual(vatMass, 2.5, accuracy: 0.001)

        let vatVolume = try XCTUnwrap(withVat.vatVolumeCm3)
        XCTAssertEqual(vatVolume, 789.0, accuracy: 0.001)

        XCTAssertEqual(withVat.resultPdfUrl, "https://example.com/result.pdf")
        XCTAssertEqual(withVat.resultPdfName, "result.pdf")
        XCTAssertEqual(withVat.createdAt.timeIntervalSince(createdAt), 0, accuracy: 0.001)
        XCTAssertEqual(withVat.updatedAt.timeIntervalSince(updatedAt), 0, accuracy: 0.001)

        let withoutVat = try XCTUnwrap(mappedWithoutVat)
        XCTAssertEqual(withoutVat.userId, userId)
        XCTAssertEqual(withoutVat.externalSource, externalSource)
        XCTAssertEqual(withoutVat.externalResultId, externalResultId)
        XCTAssertNil(withoutVat.vatMassKg)
        XCTAssertNil(withoutVat.vatVolumeCm3)
    }
}

@MainActor
final class DashboardViewModelHealthSyncWiringTests: XCTestCase {
    func testCanInitializeWithMockHealthSyncCoordinator() {
        let viewModel = DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        XCTAssertNotNil(viewModel)
    }

    func testLoadDataOrdersMetricsForNewestAndOldestFirstConsumers() async {
        let coreData = CoreDataManager.shared
        let userId = "dashboard-order-\(UUID().uuidString)"
        let oldestDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newestDate = oldestDate.addingTimeInterval(2 * 86_400)
        let oldest = makeMetric(userId: userId, date: oldestDate, weight: 80)
        let newest = makeMetric(userId: userId, date: newestDate, weight: 78)

        coreData.saveBodyMetrics(oldest, userId: userId)
        coreData.saveBodyMetrics(newest, userId: userId)
        _ = await coreData.fetchBodyMetrics(for: userId)

        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId,
            email: "\(userId)@example.com",
            name: "Dashboard Test",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        let viewModel = DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        await viewModel.loadData(authManager: authManager, selectedIndex: 0)

        XCTAssertEqual(viewModel.bodyMetrics.map(\.id), [newest.id, oldest.id])
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.map(\.id), [oldest.id, newest.id])
    }

    private func makeMetric(userId: String, date: Date, weight: Double) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

@MainActor
final class LoadingManagerHealthSyncTests: XCTestCase {
    func testRunWarmUpTasksInvokesHealthSyncWhenAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = true

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertTrue(mockCoordinator.didCallWarmUpAfterLogin)
    }

    func testRunWarmUpTasksSkipsWhenNotAuthenticated() async {
        let authManager = AuthManager()
        authManager.isAuthenticated = false

        let mockCoordinator = MockHealthSyncCoordinator()
        let manager = LoadingManager(
            authManager: authManager,
            healthSyncCoordinator: mockCoordinator
        )

        await manager.runWarmUpTasks()

        XCTAssertFalse(mockCoordinator.didCallWarmUpAfterLogin)
    }
}

final class RecordingHealthKitManager: HealthKitManager {
    private let eventLock = NSLock()
    private var recordedEvents: [String] = []

    var healthKitAvailable = true
    var authorizationStatusWhenChecked: Bool?
    var setupBackgroundDeliveryError: Error?
    var setupStepDeliveryError: Error?
    var weightSyncError: Error?
    var stepSyncError: Error?

    override var isHealthKitAvailable: Bool {
        healthKitAvailable
    }

    var events: [String] {
        eventLock.lock()
        defer { eventLock.unlock() }
        return recordedEvents
    }

    func eventCount(_ event: String) -> Int {
        events.filter { $0 == event }.count
    }

    override func checkAuthorizationStatus() {
        record("checkAuthorization")
        if let authorizationStatusWhenChecked {
            isAuthorized = authorizationStatusWhenChecked
        }
    }

    override func observeWeightChanges() {
        record("observeWeight")
    }

    override func observeStepChanges() {
        record("observeSteps")
    }

    override func setupBackgroundDelivery() async throws {
        record("setupBackgroundDelivery")
        if let setupBackgroundDeliveryError {
            throw setupBackgroundDeliveryError
        }
    }

    override func setupStepCountBackgroundDelivery() async throws {
        record("setupStepDelivery")
        if let setupStepDeliveryError {
            throw setupStepDeliveryError
        }
    }

    override func resetForCurrentUser() async {
        record("reset")
    }

    override func syncWeightFromHealthKit() async throws {
        record("syncWeight")
        if let weightSyncError {
            throw weightSyncError
        }
    }

    override func syncWeightFromHealthKitIncremental(
        days: Int,
        startDate: Date?
    ) async throws {
        record("syncIncrementalWeight")
        if let weightSyncError {
            throw weightSyncError
        }
    }

    override func syncStepsFromHealthKit() async throws {
        record("syncSteps")
        if let stepSyncError {
            throw stepSyncError
        }
    }

    override func fetchTodayStepCount() async throws -> Int {
        record("fetchTodaySteps")
        return 12_345
    }

    override func forceFullHealthKitSync() async {
        record("forceFullSync")
    }

    private func record(_ event: String) {
        eventLock.lock()
        recordedEvents.append(event)
        eventLock.unlock()
    }
}

private enum RecordingHealthKitError: Error {
    case expected
}

@MainActor
final class HealthSyncCoordinatorTests: XCTestCase {
    func testObserverWeightDebounceUsesTheReceivingHealthKitManager() async {
        let healthKit = RecordingHealthKitManager()

        healthKit.scheduleObserverWeightSync(userId: "observer-user", delay: 0.01)

        await waitForEvent("syncIncrementalWeight", count: 1, on: healthKit)
        XCTAssertEqual(healthKit.eventCount("syncIncrementalWeight"), 1)
    }

    func testBootstrapRequiresEnabledAvailableAuthorizedAndResetsForNewUser() async {
        let healthKit = RecordingHealthKitManager()
        let coordinator = HealthSyncCoordinator(healthKitManager: healthKit)

        healthKit.healthKitAvailable = false
        coordinator.bootstrapIfNeeded(syncEnabled: true)
        XCTAssertEqual(healthKit.eventCount("checkAuthorization"), 0)

        healthKit.healthKitAvailable = true
        coordinator.bootstrapIfNeeded(syncEnabled: false)
        XCTAssertEqual(healthKit.eventCount("checkAuthorization"), 0)

        healthKit.isAuthorized = false
        coordinator.bootstrapIfNeeded(syncEnabled: true)
        XCTAssertEqual(healthKit.eventCount("checkAuthorization"), 1)
        XCTAssertEqual(healthKit.eventCount("observeWeight"), 0)

        healthKit.isAuthorized = true
        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await waitForEvent("setupStepDelivery", count: 1, on: healthKit)
        XCTAssertEqual(healthKit.eventCount("observeWeight"), 1)
        XCTAssertEqual(healthKit.eventCount("observeSteps"), 1)

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        XCTAssertEqual(healthKit.eventCount("observeWeight"), 1)

        await coordinator.resetForCurrentUser()
        XCTAssertEqual(healthKit.eventCount("reset"), 1)

        coordinator.bootstrapIfNeeded(syncEnabled: true)
        await waitForEvent("setupStepDelivery", count: 2, on: healthKit)
        XCTAssertEqual(healthKit.eventCount("observeWeight"), 2)
        XCTAssertEqual(healthKit.eventCount("observeSteps"), 2)
    }

    func testAuthorizedPipelinesAndManualSyncsDelegateToHealthKit() async throws {
        let healthKit = RecordingHealthKitManager()
        healthKit.isAuthorized = true
        let coordinator = HealthSyncCoordinator(healthKitManager: healthKit)

        await coordinator.configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync()
        await waitForEvent("setupStepDelivery", count: 1, on: healthKit)
        await waitForEvent("syncWeight", count: 1, on: healthKit)

        await coordinator.configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
        await waitForEvent("syncWeight", count: 2, on: healthKit)
        await waitForEvent("syncSteps", count: 1, on: healthKit)

        await coordinator.warmUpAfterLoginIfNeeded()
        await waitForEvent("fetchTodaySteps", count: 1, on: healthKit)

        let eventCountBeforeConnect = healthKit.events.count
        try await coordinator.performInitialConnectSync()
        XCTAssertEqual(
            Array(healthKit.events.dropFirst(eventCountBeforeConnect)),
            ["setupBackgroundDelivery", "setupStepDelivery", "syncWeight", "fetchTodaySteps"]
        )

        await coordinator.runDeferredOnboardingWeightSync()
        XCTAssertEqual(healthKit.eventCount("syncWeight"), 4)

        try await coordinator.syncWeightFromHealthKit()
        try await coordinator.syncStepsFromHealthKit()
        await coordinator.forceFullHealthKitSync()
        XCTAssertEqual(healthKit.eventCount("syncWeight"), 5)
        XCTAssertEqual(healthKit.eventCount("syncSteps"), 2)
        XCTAssertEqual(healthKit.eventCount("forceFullSync"), 1)
    }

    func testDeferredSyncSwallowsErrorsWhileManualSyncPropagatesThem() async {
        let healthKit = RecordingHealthKitManager()
        healthKit.isAuthorized = true
        healthKit.weightSyncError = RecordingHealthKitError.expected
        healthKit.stepSyncError = RecordingHealthKitError.expected
        let coordinator = HealthSyncCoordinator(healthKitManager: healthKit)

        await coordinator.runDeferredOnboardingWeightSync()
        XCTAssertEqual(healthKit.eventCount("syncWeight"), 1)

        do {
            try await coordinator.syncWeightFromHealthKit()
            XCTFail("Manual weight sync should propagate adapter errors")
        } catch {
            XCTAssertTrue(error is RecordingHealthKitError)
        }

        do {
            try await coordinator.syncStepsFromHealthKit()
            XCTFail("Manual step sync should propagate adapter errors")
        } catch {
            XCTAssertTrue(error is RecordingHealthKitError)
        }
    }

    private func waitForEvent(
        _ event: String,
        count: Int,
        on healthKit: RecordingHealthKitManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if healthKit.eventCount(event) >= count {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for \(event)", file: file, line: line)
    }
}

final class UnitConversionTests: XCTestCase {
    func testWeightConversionRoundTripsWithinPrecision() {
        let kilograms = 82.35

        let pounds = UnitConversion.kgToLbs(kilograms)
        let roundTrip = UnitConversion.lbsToKg(pounds)

        XCTAssertEqual(roundTrip, kilograms, accuracy: 0.0001)
    }

    func testFormatWeightUsesSelectedMeasurementSystem() {
        XCTAssertEqual(UnitConversion.formatWeight(80, useMetric: true).value, "80.0")
        XCTAssertEqual(UnitConversion.formatWeight(80, useMetric: true).unit, "kg")
        XCTAssertEqual(UnitConversion.formatWeight(80, useMetric: false).value, "176.4")
        XCTAssertEqual(UnitConversion.formatWeight(80, useMetric: false).unit, "lbs")
    }

    func testBodyCompositionCalculationsRejectInvalidInputs() {
        XCTAssertNil(UnitConversion.calculateBMI(weightKg: 0, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 100, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateLeanMass(weightKg: -1, bodyFatPercentage: 20, useMetric: true))
        XCTAssertNil(UnitConversion.calculateFatMass(weightKg: 80, bodyFatPercentage: 0, useMetric: true))
    }

    func testMeasurementSystemFallbackProtectsUnknownStoredValues() {
        XCTAssertEqual(MeasurementSystem.fromStored(rawValue: "unknown"), .imperial)
        XCTAssertEqual(MeasurementSystem.fromStored(rawValue: "Metric"), .metric)
        XCTAssertEqual(MeasurementSystem.imperial.weightUnit, "lbs")
        XCTAssertEqual(MeasurementSystem.metric.heightUnit, "cm")
    }
}

final class ValidationServiceTests: XCTestCase {
    func testValidateWeightSanitizesInputAndRoundsToOneDecimal() throws {
        let result = try ValidationService.shared.validateWeight("  180.26 lbs ", unit: "lbs")

        XCTAssertEqual(result, 180.3)
    }

    func testValidateBodyFatRejectsValuesOutsideSupportedRange() {
        XCTAssertThrowsError(try ValidationService.shared.validateBodyFat("2.9")) { error in
            guard case let ValidationError.invalidBodyFat(message) = error else {
                return XCTFail("Unexpected validation error: \(error)")
            }
            XCTAssertEqual(message, "Body fat must be between 3-50%")
        }
    }

    func testValidateHeightUsesUnitSpecificRanges() throws {
        XCTAssertEqual(try ValidationService.shared.validateHeight("5.75", unit: "ft"), 5.8)
        XCTAssertThrowsError(try ValidationService.shared.validateHeight("80", unit: "cm"))
    }
}

final class LRUCacheTests: XCTestCase {
    func testReadingAnEntryMakesItMostRecentlyUsed() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(1, for: "one")
        cache.setValue(2, for: "two")

        XCTAssertEqual(cache.value(for: "one"), 1)
        cache.setValue(3, for: "three")

        XCTAssertNil(cache.value(for: "two"))
        XCTAssertEqual(cache.value(for: "one"), 1)
        XCTAssertEqual(cache.value(for: "three"), 3)
    }

    func testPredicateRemovalAndClearRemoveOnlyExpectedEntries() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.setValue(1, for: "one")
        cache.setValue(2, for: "two")
        cache.setValue(3, for: "three")

        cache.removeAll { _, value in value.isMultiple(of: 2) }

        XCTAssertNil(cache.value(for: "two"))
        XCTAssertEqual(cache.value(for: "one"), 1)
        XCTAssertEqual(cache.value(for: "three"), 3)

        cache.removeAll()
        XCTAssertNil(cache.value(for: "one"))
        XCTAssertNil(cache.value(for: "three"))
    }
}

final class TimelineZoomLevelTests: XCTestCase {
    func testZoomLevelChangesAtTheConfiguredRangeBoundaries() {
        let calendar = Calendar.current
        let start = Date(timeIntervalSince1970: 0)

        let twoMonths = calendar.date(byAdding: .month, value: 2, to: start)!
        let threeMonths = calendar.date(byAdding: .month, value: 3, to: start)!
        let oneYear = calendar.date(byAdding: .month, value: 12, to: start)!
        let fiveYears = calendar.date(byAdding: .month, value: 60, to: start)!

        XCTAssertTrue({ if case .week = TimelineZoomLevel.calculate(from: start, to: twoMonths) { true } else { false } }())
        XCTAssertTrue({ if case .month = TimelineZoomLevel.calculate(from: start, to: threeMonths) { true } else { false } }())
        XCTAssertTrue({ if case .year = TimelineZoomLevel.calculate(from: start, to: oneYear) { true } else { false } }())
        XCTAssertTrue({ if case .all = TimelineZoomLevel.calculate(from: start, to: fiveYears) { true } else { false } }())
    }

    func testZoomLevelPresentationPropertiesMatchDensity() {
        XCTAssertEqual(TimelineZoomLevel.week.daysPerBucket, 2)
        XCTAssertEqual(TimelineZoomLevel.month.daysPerBucket, 7)
        XCTAssertEqual(TimelineZoomLevel.year.daysPerBucket, 30)
        XCTAssertEqual(TimelineZoomLevel.all.daysPerBucket, 90)
        XCTAssertTrue(TimelineZoomLevel.week.showMetricTicks)
        XCTAssertFalse(TimelineZoomLevel.year.showMetricTicks)
        XCTAssertEqual(TimelineZoomLevel.all.maxVisibleThumbnails, 20)
    }

    func testBucketsUseHalfOpenDateRanges() {
        let start = Date(timeIntervalSince1970: 0)
        let bucket = TimelineBucket(startDate: start, days: 2)

        XCTAssertTrue(bucket.contains(start))
        XCTAssertTrue(bucket.contains(start.addingTimeInterval(24 * 60 * 60)))
        XCTAssertFalse(bucket.contains(bucket.endDate))
    }
}

final class BodyScoreCalculatorTests: XCTestCase {
    func testCalculationRequiresAllCoreInputs() {
        let input = BodyScoreInput(
            height: HeightValue(value: 180, unit: .centimeters),
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 15)
        )

        XCTAssertThrowsError(try BodyScoreCalculator().calculateScore(
            context: BodyScoreCalculationContext(input: input)
        )) { error in
            guard let calculationError = error as? BodyScoreCalculationError,
                  case .missingRequiredInputs = calculationError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMaleCalculationConvertsInputsAndReportsStatusAndTargetRange() throws {
        let input = BodyScoreInput(
            sex: .male,
            birthYear: Calendar.current.component(.year, from: Date()) - 30,
            height: HeightValue(value: 180, unit: .centimeters),
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 15)
        )

        let result = try BodyScoreCalculator().calculateScore(
            context: BodyScoreCalculationContext(input: input)
        )

        XCTAssertEqual(result.ffmi, 21.0, accuracy: 0.1)
        XCTAssertEqual(result.ffmiStatus, "Athletic")
        XCTAssertEqual(result.targetBodyFat.lowerBound, 8)
        XCTAssertEqual(result.targetBodyFat.upperBound, 12)
        XCTAssertEqual(result.targetBodyFat.label, "Lean")
        XCTAssertEqual(result.leanPercentile, 86, accuracy: 0.1)
        XCTAssertEqual(result.score, 74)
        XCTAssertEqual(result.statusTagline, "Good starting point. Big upside.")
    }

    func testFemaleCalculationUsesFemaleRangesAndClampsPercentile() throws {
        let input = BodyScoreInput(
            sex: .female,
            height: HeightValue(value: 165, unit: .centimeters),
            weight: WeightValue(value: 60, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 10)
        )

        let result = try BodyScoreCalculator().calculateScore(
            context: BodyScoreCalculationContext(input: input)
        )

        XCTAssertEqual(result.targetBodyFat.lowerBound, 16)
        XCTAssertEqual(result.targetBodyFat.upperBound, 20)
        XCTAssertEqual(result.ffmiStatus, "Elite")
        XCTAssertEqual(result.leanPercentile, 99)
        XCTAssertGreaterThanOrEqual(result.score, 1)
        XCTAssertLessThanOrEqual(result.score, 100)
    }
}

final class TimelinePhotoSamplerTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyBucketHasNoRepresentative() {
        let bucket = TimelineBucket(startDate: baseDate, days: 7)

        XCTAssertNil(TimelinePhotoSampler.selectRepresentative(from: bucket, previousMetric: nil))
    }

    func testRepresentativePrioritizesCompleteMetricsAndMilestones() {
        let previous = makeMetric(id: "previous", weight: 80, bodyFat: 20)
        let complete = makeMetric(id: "complete", weight: 80, bodyFat: 18)
        let photoOnly = makeMetric(id: "photo", photoUrl: "photo.jpg")
        var bucket = TimelineBucket(startDate: baseDate, days: 7)
        bucket.addCandidate(complete)
        bucket.addCandidate(photoOnly)

        XCTAssertEqual(
            TimelinePhotoSampler.selectRepresentative(from: bucket, previousMetric: previous)?.id,
            "complete"
        )
    }

    func testFiltersAndThumbnailLimitPreserveMeaningfulPhotos() {
        let withPhoto = makeMetric(id: "photo", photoUrl: "photo.jpg")
        let emptyPhoto = makeMetric(id: "empty", photoUrl: "")
        let weightOnly = makeMetric(id: "weight", weight: 80)
        let noData = makeMetric(id: "none")

        XCTAssertEqual(TimelinePhotoSampler.metricsWithPhotos(from: [withPhoto, emptyPhoto, noData]).map(\.id), ["photo"])
        XCTAssertEqual(
            TimelinePhotoSampler.metricsWithData(from: [withPhoto, emptyPhoto, weightOnly, noData]).map(\.id),
            ["photo", "weight"]
        )

        var firstBucket = TimelineBucket(startDate: baseDate, days: 7)
        firstBucket.addCandidate(withPhoto)
        var secondBucket = TimelineBucket(startDate: baseDate.addingTimeInterval(7 * 86_400), days: 7)
        secondBucket.addCandidate(weightOnly)

        let sampled = TimelinePhotoSampler.samplePhotos(
            from: [firstBucket, secondBucket],
            maxThumbnails: 1,
            sortedMetrics: [withPhoto, weightOnly]
        )

        XCTAssertEqual(sampled.count, 1)
        XCTAssertEqual(sampled.first?.id, "photo")
    }

    private func makeMetric(
        id: String,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        return BodyMetrics(
            id: id,
            userId: "test-user",
            date: baseDate,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: "test",
            createdAt: baseDate,
            updatedAt: baseDate
        )
    }
}

final class TimelineCalculatorTests: XCTestCase {
    func testEmptyMetricsProduceNoTimelinePoints() {
        XCTAssertTrue(TimelineCalculator.calculateTimelinePoints(from: []).isEmpty)
    }

    func testNearestPointAndIndexPositionMappingsUseWeightedPositions() {
        let points = [
            TimelineDataPoint(
                id: "first",
                index: 4,
                date: Date(timeIntervalSince1970: 100),
                position: 0.2,
                displayLabel: "First",
                importance: .monthly
            ),
            TimelineDataPoint(
                id: "second",
                index: 9,
                date: Date(timeIntervalSince1970: 200),
                position: 0.8,
                displayLabel: "Second",
                importance: .daily
            )
        ]

        XCTAssertEqual(TimelineCalculator.findNearestPoint(to: 0.7, in: points)?.id, "second")
        XCTAssertEqual(TimelineCalculator.position(for: 4, in: points), 0.2)
        XCTAssertEqual(TimelineCalculator.index(for: 0.25, in: points), 4)
        XCTAssertNil(TimelineCalculator.position(for: 100, in: points))
        XCTAssertNil(TimelineCalculator.index(for: 0.5, in: []))
    }

    func testTimelineClassifiesTimeRangesAndKeepsWeightedPositionsMonotonic() {
        let calendar = Calendar.current
        let now = Date()
        let yearly = makeMetric(
            id: "yearly",
            date: calendar.date(byAdding: .year, value: -2, to: now)!
        )
        let monthly = makeMetric(
            id: "monthly",
            date: calendar.date(byAdding: .day, value: -90, to: now)!
        )
        let weekly = makeMetric(
            id: "weekly",
            date: calendar.date(byAdding: .day, value: -14, to: now)!
        )
        let daily = makeMetric(
            id: "daily",
            date: calendar.date(byAdding: .day, value: -2, to: now)!
        )

        let points = TimelineCalculator.calculateTimelinePoints(
            from: [daily, monthly, yearly, weekly]
        )

        XCTAssertEqual(points.map(\.id), ["yearly", "monthly", "weekly", "daily"])
        XCTAssertEqual(points.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(points.map { String(describing: $0.importance) }, ["yearly", "monthly", "weekly", "daily"])
        XCTAssertTrue(points.allSatisfy { (0...1).contains($0.position) })
        let positions = points.map(\.position)
        XCTAssertEqual(positions, positions.sorted())
    }

    private func makeMetric(id: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "timeline-user",
            date: date,
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: 20,
            bodyFatMethod: "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "test",
            createdAt: date,
            updatedAt: date
        )
    }
}

final class MetricsInterpolationServiceTests: XCTestCase {
    private let baseDate = Calendar.current.startOfDay(
        for: Date(timeIntervalSince1970: 1_700_000_000)
    )

    func testConfidenceLevelsCoverAllSupportedGapBoundaries() {
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 0), .high)
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 7), .high)
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 8), .medium)
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 14), .medium)
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 15), .low)
        XCTAssertEqual(InterpolatedMetric.confidence(forDaysGap: 30), .low)
        XCTAssertNil(InterpolatedMetric.confidence(forDaysGap: 31))
    }

    func testWeightInterpolationHandlesExactInterpolatedLastKnownAndOutOfRangeDates() {
        let first = makeMetric(id: "first", dayOffset: 0, weight: 80)
        let second = makeMetric(id: "second", dayOffset: 10, weight: 100)
        let metrics = [second, first]
        let service = MetricsInterpolationService.shared

        let interpolated = service.estimateWeight(
            for: date(dayOffset: 5),
            metrics: metrics
        )
        XCTAssertEqual(interpolated?.value, 90)
        XCTAssertEqual(interpolated?.confidenceLevel, .medium)
        XCTAssertTrue(interpolated?.isInterpolated == true)

        let exact = service.estimateWeight(for: first.date, metrics: metrics)
        XCTAssertEqual(exact?.value, 80)
        XCTAssertFalse(exact?.isInterpolated == true)

        let lastKnown = service.estimateWeight(for: date(dayOffset: 11), metrics: metrics)
        XCTAssertEqual(lastKnown?.value, 100)
        XCTAssertTrue(lastKnown?.isLastKnown == true)

        XCTAssertNil(service.estimateWeight(for: date(dayOffset: -1), metrics: metrics))
    }

    func testInterpolationRejectsGapsLongerThanThirtyDays() {
        let metrics = [
            makeMetric(id: "first", dayOffset: 0, weight: 80),
            makeMetric(id: "second", dayOffset: 31, weight: 100)
        ]

        XCTAssertNil(MetricsInterpolationService.shared.estimateWeight(
            for: date(dayOffset: 15),
            metrics: metrics
        ))
    }

    func testSameDayQueriesUseActualEntryEvenWhenTargetTimeDiffers() throws {
        let metric = makeMetric(
            id: "same-day",
            dayOffset: 0,
            weight: 80,
            bodyFat: 20,
            timeOffset: 12 * 60 * 60
        )
        let target = Calendar.current.startOfDay(for: metric.date)
        let service = MetricsInterpolationService.shared

        let directWeight = try XCTUnwrap(service.estimateWeight(for: target, metrics: [metric]))
        XCTAssertEqual(directWeight.value, 80)
        XCTAssertFalse(directWeight.isInterpolated)
        XCTAssertFalse(directWeight.isLastKnown)

        let directBodyFat = try XCTUnwrap(service.estimateBodyFat(for: target, metrics: [metric]))
        XCTAssertEqual(directBodyFat.value, 20)
        XCTAssertFalse(directBodyFat.isInterpolated)
        XCTAssertFalse(directBodyFat.isLastKnown)

        let weightContext = try XCTUnwrap(service.makeWeightInterpolationContext(for: [metric]))
        let contextualWeight = try XCTUnwrap(weightContext.estimate(for: target))
        XCTAssertEqual(contextualWeight.value, 80)
        XCTAssertFalse(contextualWeight.isLastKnown)

        let bodyFatContext = try XCTUnwrap(service.makeBodyFatInterpolationContext(for: [metric]))
        let contextualBodyFat = try XCTUnwrap(bodyFatContext.estimate(for: target))
        XCTAssertEqual(contextualBodyFat.value, 20)
        XCTAssertFalse(contextualBodyFat.isLastKnown)
    }

    func testInterpolationContextsUseTheLatestEntryOnTheSameDay() throws {
        let earlier = makeMetric(
            id: "earlier",
            dayOffset: 0,
            weight: 80,
            bodyFat: 20,
            timeOffset: 8 * 60 * 60
        )
        let later = makeMetric(
            id: "later",
            dayOffset: 0,
            weight: 82,
            bodyFat: 22,
            timeOffset: 18 * 60 * 60
        )
        let target = Calendar.current.startOfDay(for: earlier.date)
        let service = MetricsInterpolationService.shared

        let weightContext = try XCTUnwrap(service.makeWeightInterpolationContext(for: [later, earlier]))
        XCTAssertEqual(weightContext.estimate(for: target)?.value, 82)

        let bodyFatContext = try XCTUnwrap(service.makeBodyFatInterpolationContext(for: [later, earlier]))
        XCTAssertEqual(bodyFatContext.estimate(for: target)?.value, 22)
    }

    func testFFMIInterpolationContextRejectsInvalidHeight() {
        let metrics = [makeMetric(id: "metric", dayOffset: 0, weight: 80, bodyFat: 20)]

        XCTAssertNil(MetricsInterpolationService.shared.makeFFMIInterpolationContext(
            for: metrics,
            heightInches: 0
        ))
    }

    func testFFMIUsesTrendWeightAndPreservesInterpolationConfidence() throws {
        let metrics = [
            makeMetric(id: "first", dayOffset: 0, weight: 80, bodyFat: 20),
            makeMetric(id: "second", dayOffset: 10, weight: 100, bodyFat: 30)
        ]
        let service = MetricsInterpolationService.shared
        let target = date(dayOffset: 5)
        let context = try XCTUnwrap(service.makeFFMIInterpolationContext(
            for: metrics,
            heightInches: 70
        ))

        let contextualResult = try XCTUnwrap(context.estimate(for: target))
        let directResult = try XCTUnwrap(service.estimateFFMI(
            for: target,
            metrics: metrics,
            heightInches: 70
        ))

        XCTAssertEqual(contextualResult.value, 20.3)
        XCTAssertEqual(contextualResult.confidenceLevel, .medium)
        XCTAssertTrue(contextualResult.isInterpolated)
        XCTAssertFalse(contextualResult.isLastKnown)
        XCTAssertEqual(directResult.value, contextualResult.value)
        XCTAssertEqual(directResult.confidenceLevel, contextualResult.confidenceLevel)
    }

    private func date(dayOffset: Int) -> Date {
        baseDate.addingTimeInterval(Double(dayOffset) * 86_400)
    }

    private func makeMetric(
        id: String,
        dayOffset: Int,
        weight: Double?,
        bodyFat: Double? = nil,
        timeOffset: TimeInterval = 0
    ) -> BodyMetrics {
        let metricDate = date(dayOffset: dayOffset).addingTimeInterval(timeOffset)

        return BodyMetrics(
            id: id,
            userId: "test-user",
            date: metricDate,
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "test",
            createdAt: metricDate,
            updatedAt: metricDate
        )
    }
}

@MainActor
final class PhotoMetadataPersistenceTests: XCTestCase {
    func testCreateOrUpdateMetricsMergesSameDayValuesWithoutDuplicatingEntry() async throws {
        let userId = "photo-metadata-\(UUID().uuidString)"
        let calendar = Calendar.current
        let selectedDate = calendar.date(
            from: DateComponents(year: 2_025, month: 3, day: 15, hour: 9)
        )!
        let service = PhotoMetadataService.shared

        let created = await service.createOrUpdateMetrics(
            for: selectedDate,
            photoUrl: "https://example.com/first.jpg",
            weight: 82,
            userId: userId
        )
        let updated = await service.createOrUpdateMetrics(
            for: selectedDate.addingTimeInterval(8 * 60 * 60),
            bodyFatPercentage: 18.5,
            userId: userId
        )

        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.weight, 82)
        XCTAssertEqual(updated.bodyFatPercentage, 18.5)
        XCTAssertEqual(updated.photoUrl, "https://example.com/first.jpg")

        let stored = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, created.id)
        XCTAssertEqual(stored.first?.weight, 82)
        XCTAssertEqual(stored.first?.bodyFatPercentage, 18.5)
        XCTAssertEqual(stored.first?.photoUrl, "https://example.com/first.jpg")
    }
}

@MainActor
final class ProfileSyncPersistenceTests: XCTestCase {
    func testServerProfileUpdateRoundTripsAndUpsertsById() async throws {
        let coreData = CoreDataManager.shared
        let userId = "profile-sync-\(UUID().uuidString)"
        let birthDate = Date(timeIntervalSince1970: 631_152_000)
        let dateFormatter = ISO8601DateFormatter()

        coreData.updateOrCreateProfile(from: [
            "id": userId,
            "full_name": "Original Name",
            "username": "original",
            "height": 70.0,
            "height_unit": "in",
            "gender": "Female",
            "activity_level": "moderate",
            "date_of_birth": dateFormatter.string(from: birthDate)
        ])

        coreData.updateOrCreateProfile(from: [
            "id": userId,
            "full_name": "Updated Name",
            "username": "updated",
            "height": 172.0,
            "height_unit": "cm",
            "gender": "Female",
            "activity_level": "active",
            "date_of_birth": dateFormatter.string(from: birthDate)
        ])

        let fetchedProfile = await coreData.fetchProfile(for: userId)
        let cachedProfile = try XCTUnwrap(fetchedProfile)
        let profile = cachedProfile.toUserProfile()

        XCTAssertEqual(profile.id, userId)
        XCTAssertEqual(profile.fullName, "Updated Name")
        XCTAssertEqual(profile.username, "updated")
        XCTAssertEqual(profile.height, 172)
        XCTAssertEqual(profile.heightUnit, "cm")
        XCTAssertEqual(profile.gender, "Female")
        XCTAssertEqual(profile.activityLevel, "active")
        let storedBirthDate = try XCTUnwrap(profile.dateOfBirth)
        XCTAssertEqual(storedBirthDate.timeIntervalSince1970, birthDate.timeIntervalSince1970, accuracy: 0.001)

        let context = coreData.viewContext
        let savedCount = await context.perform { () -> Int in
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            return (try? context.count(for: request)) ?? 0
        }
        XCTAssertEqual(savedCount, 1)
    }
}

@MainActor
final class DailyLogExportTests: XCTestCase {
    func testExportedDailyLogsKeepMissingStepsNil() async throws {
        let coreData = CoreDataManager.shared
        let userId = "daily-log-export-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        coreData.updateOrCreateDailyMetric(from: [
            "id": UUID().uuidString,
            "user_id": userId,
            "date": ISO8601DateFormatter().string(from: date),
            "notes": "No steps recorded"
        ])

        let logs = await coreData.fetchAllDailyLogs(for: userId)
        let log = try XCTUnwrap(logs.first)

        XCTAssertNil(log.stepCount)
        XCTAssertEqual(log.notes, "No steps recorded")

        await coreData.saveAsync()
        let hasUnsavedChanges = await coreData.viewContext.perform {
            coreData.viewContext.hasChanges
        }
        XCTAssertFalse(hasUnsavedChanges)
    }
}

@MainActor
final class CoreDataCleanupTests: XCTestCase {
    func testCleanupDeletedEntriesPurgesExpiredTombstonesAndKeepsRecentOnes() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "cleanup-\(UUID().uuidString)"
        let now = Date()
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let staleBodyId = UUID().uuidString
        let recentBodyId = UUID().uuidString
        let staleDailyId = UUID().uuidString
        let recentDailyId = UUID().uuidString

        await context.perform {
            let staleBody = CachedBodyMetrics(context: context)
            staleBody.id = staleBodyId
            staleBody.userId = userId
            staleBody.date = now.addingTimeInterval(-7 * 24 * 60 * 60)
            staleBody.createdAt = now.addingTimeInterval(-7 * 24 * 60 * 60)
            staleBody.updatedAt = now.addingTimeInterval(-2 * 24 * 60 * 60)
            staleBody.lastModified = now.addingTimeInterval(-2 * 24 * 60 * 60)
            staleBody.isMarkedDeleted = true

            let recentBody = CachedBodyMetrics(context: context)
            recentBody.id = recentBodyId
            recentBody.userId = userId
            recentBody.date = now
            recentBody.createdAt = now
            recentBody.updatedAt = now
            recentBody.lastModified = now
            recentBody.isMarkedDeleted = true

            let staleDaily = CachedDailyMetrics(context: context)
            staleDaily.id = staleDailyId
            staleDaily.userId = userId
            staleDaily.date = now.addingTimeInterval(-7 * 24 * 60 * 60)
            staleDaily.createdAt = now.addingTimeInterval(-7 * 24 * 60 * 60)
            staleDaily.updatedAt = now.addingTimeInterval(-2 * 24 * 60 * 60)
            staleDaily.lastModified = now.addingTimeInterval(-2 * 24 * 60 * 60)
            staleDaily.isMarkedDeleted = true

            let recentDaily = CachedDailyMetrics(context: context)
            recentDaily.id = recentDailyId
            recentDaily.userId = userId
            recentDaily.date = now
            recentDaily.createdAt = now
            recentDaily.updatedAt = now
            recentDaily.lastModified = now
            recentDaily.isMarkedDeleted = true

            try? context.save()
        }

        coreData.cleanupDeletedEntries(olderThan: cutoff)

        let remainingIds = await context.perform { () -> Set<String> in
            let bodyRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            bodyRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let dailyRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            dailyRequest.predicate = NSPredicate(format: "userId == %@", userId)
            let bodies = (try? context.fetch(bodyRequest)) ?? []
            let daily = (try? context.fetch(dailyRequest)) ?? []
            return Set(bodies.compactMap(\.id) + daily.compactMap(\.id))
        }

        XCTAssertFalse(remainingIds.contains(staleBodyId))
        XCTAssertFalse(remainingIds.contains(staleDailyId))
        XCTAssertTrue(remainingIds.contains(recentBodyId))
        XCTAssertTrue(remainingIds.contains(recentDailyId))
    }
}

@MainActor
final class CoreDataDomainPersistenceTests: XCTestCase {
    func testDailyMetricFetchesAreUserScopedDateAwareAndSkipSoftDeletes() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "daily-fetch-\(UUID().uuidString)"
        let otherUserId = "daily-fetch-other-\(UUID().uuidString)"
        let calendar = Calendar.current
        let targetDate = calendar.date(
            from: DateComponents(year: 2_025, month: 3, day: 15, hour: 14)
        )!
        let olderDate = calendar.date(byAdding: .day, value: -2, to: targetDate)!
        let target = makeDailyMetric(userId: userId, date: targetDate, steps: 9_000)
        let older = makeDailyMetric(userId: userId, date: olderDate, steps: 8_000)
        let otherUser = makeDailyMetric(userId: otherUserId, date: targetDate, steps: 12_000)

        coreData.saveDailyMetrics(target, userId: userId)
        coreData.saveDailyMetrics(older, userId: userId)
        coreData.saveDailyMetrics(otherUser, userId: otherUserId)

        let deletedId = UUID().uuidString
        await context.perform {
            let deleted = CachedDailyMetrics(context: context)
            deleted.id = deletedId
            deleted.userId = userId
            deleted.date = targetDate
            deleted.steps = 7_000
            deleted.createdAt = targetDate
            deleted.updatedAt = targetDate
            deleted.lastModified = targetDate
            deleted.isMarkedDeleted = true
            deleted.isSynced = false
            deleted.syncStatus = "pending"
            try? context.save()
        }

        let exact = await coreData.fetchDailyMetrics(for: userId, date: targetDate)
        let ranged = await coreData.fetchDailyMetrics(
            for: userId,
            from: olderDate,
            to: targetDate
        )

        XCTAssertEqual(exact?.id, target.id)
        XCTAssertEqual(Int(exact?.steps ?? -1), 9_000)
        XCTAssertEqual(ranged.compactMap(\.id), [target.id, older.id])
        XCTAssertFalse(ranged.compactMap(\.id).contains(deletedId))
    }

    func testUpdatingBodyMetricNormalizesDateAndRestoresSyncState() async throws {
        let coreData = CoreDataManager.shared
        let userId = "body-update-\(UUID().uuidString)"
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metric = makeBodyMetric(userId: userId, date: originalDate, weight: 80)
        let updatedDate = Calendar.current.date(
            from: DateComponents(year: 2_025, month: 5, day: 20, hour: 16)
        )!

        coreData.saveBodyMetrics(metric, userId: userId, markAsSynced: true)

        let updatedValue = await coreData.updateBodyMetric(
            id: metric.id,
            date: updatedDate,
            weight: 76.5,
            bodyFatPercentage: 17.2
        )
        let storedValue = await coreData.fetchLatestBodyMetric(for: userId)
        let updated = try XCTUnwrap(updatedValue)
        let stored = try XCTUnwrap(storedValue)

        XCTAssertEqual(updated.date, Calendar.current.startOfDay(for: updatedDate))
        XCTAssertEqual(updated.weight, 76.5)
        XCTAssertEqual(updated.bodyFatPercentage, 17.2)
        XCTAssertEqual(stored.id, metric.id)
        XCTAssertEqual(stored.date, Calendar.current.startOfDay(for: updatedDate))
        XCTAssertEqual(stored.weight, 76.5)
        XCTAssertEqual(stored.bodyFatPercentage, 17.2)

        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertEqual(unsynced.bodyMetrics.compactMap(\.id), [metric.id])
    }

    func testProfileSaveUpsertsChangesAndRecordsSyncLifecycle() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "profile-save-\(UUID().uuidString)"
        let birthDate = Date(timeIntervalSince1970: 631_152_000)
        let firstProfile = UserProfile(
            id: userId,
            email: "first@example.com",
            username: "first",
            fullName: "First Profile",
            dateOfBirth: birthDate,
            height: 170,
            heightUnit: "cm",
            gender: "Female",
            activityLevel: "moderate",
            goalWeight: 65,
            goalWeightUnit: "kg",
            onboardingCompleted: true
        )
        let updatedProfile = UserProfile(
            id: userId,
            email: "updated@example.com",
            username: "updated",
            fullName: "Updated Profile",
            dateOfBirth: birthDate,
            height: 172,
            heightUnit: "cm",
            gender: "Female",
            activityLevel: "active",
            goalWeight: 63,
            goalWeightUnit: "kg",
            onboardingCompleted: true
        )

        coreData.saveProfile(firstProfile, userId: userId, email: "first@example.com")
        coreData.saveProfile(updatedProfile, userId: userId, email: "updated@example.com")

        let cachedProfileValue = await coreData.fetchProfile(for: userId)
        let cachedProfile = try XCTUnwrap(cachedProfileValue)
        let profile = cachedProfile.toUserProfile()
        XCTAssertEqual(profile.fullName, "Updated Profile")
        XCTAssertEqual(profile.email, "updated@example.com")
        XCTAssertEqual(profile.username, "updated")
        XCTAssertEqual(profile.height, 172)
        XCTAssertEqual(profile.goalWeight, 63)
        XCTAssertEqual(profile.activityLevel, "active")
        XCTAssertFalse(cachedProfile.isSynced)
        XCTAssertEqual(cachedProfile.syncStatus, "pending")

        let profileCount = await context.perform { () -> Int in
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            return (try? context.count(for: request)) ?? 0
        }
        XCTAssertEqual(profileCount, 1)

        coreData.updateSyncStatus(
            entityName: "CachedProfile",
            id: userId,
            status: "failed",
            error: "offline"
        )

        let failedSync = await syncMetadata(for: "CachedProfile", id: userId, in: context)
        XCTAssertEqual(failedSync.retryCount, 1)
        XCTAssertEqual(failedSync.error, "offline")
        XCTAssertNotNil(failedSync.attempt)
        XCTAssertNil(failedSync.success)

        coreData.updateSyncStatus(entityName: "CachedProfile", id: userId, status: "synced")

        let completedSync = await syncMetadata(for: "CachedProfile", id: userId, in: context)
        XCTAssertEqual(completedSync.retryCount, 0)
        XCTAssertNil(completedSync.error)
        XCTAssertNotNil(completedSync.success)
    }

    func testSuccessfulSyncAcknowledgementMarksEveryCachedEntitySynced() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "sync-acknowledgement-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let bodyMetric = makeBodyMetric(userId: userId, date: date, weight: 80)
        let dailyMetric = makeDailyMetric(userId: userId, date: date, steps: 9_000)
        let profile = UserProfile(
            id: userId,
            email: "\(userId)@example.com",
            username: nil,
            fullName: "Sync Test",
            dateOfBirth: nil,
            height: 170,
            heightUnit: "cm",
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: true
        )

        coreData.saveBodyMetrics(bodyMetric, userId: userId)
        coreData.saveDailyMetrics(dailyMetric, userId: userId)
        coreData.saveProfile(profile, userId: userId, email: "\(userId)@example.com")
        _ = await context.perform { () -> Bool in context.hasChanges }

        coreData.markAsSynced(entityName: "CachedBodyMetrics", id: bodyMetric.id)
        coreData.markAsSynced(entityName: "CachedDailyMetrics", id: dailyMetric.id)
        coreData.markAsSynced(entityName: "CachedProfile", id: userId)

        let statuses = await context.perform { () -> [String: (Bool, String?)] in
            let bodyRequest: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            bodyRequest.predicate = NSPredicate(format: "id == %@", bodyMetric.id)
            let dailyRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            dailyRequest.predicate = NSPredicate(format: "id == %@", dailyMetric.id)
            let profileRequest: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            profileRequest.predicate = NSPredicate(format: "id == %@", userId)

            return [
                "body": ((try? context.fetch(bodyRequest).first?.isSynced) ?? false,
                         try? context.fetch(bodyRequest).first?.syncStatus),
                "daily": ((try? context.fetch(dailyRequest).first?.isSynced) ?? false,
                          try? context.fetch(dailyRequest).first?.syncStatus),
                "profile": ((try? context.fetch(profileRequest).first?.isSynced) ?? false,
                            try? context.fetch(profileRequest).first?.syncStatus)
            ]
        }

        for status in statuses.values {
            XCTAssertTrue(status.0)
            XCTAssertEqual(status.1, "synced")
        }

        let unsynced = await coreData.fetchUnsyncedEntries(for: userId)
        XCTAssertTrue(unsynced.bodyMetrics.isEmpty)
        XCTAssertTrue(unsynced.dailyMetrics.isEmpty)
        XCTAssertTrue(unsynced.profiles.isEmpty)
    }

    func testDeviceUpsertsRetainOneRecordPerDeviceAndPairing() async throws {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let deviceId = "device-\(UUID().uuidString)"
        let userDeviceId = "user-device-\(UUID().uuidString)"
        let userId = "device-user-\(UUID().uuidString)"
        let firstSeen = Date(timeIntervalSince1970: 1_700_000_000)
        let lastSeen = firstSeen.addingTimeInterval(86_400)

        let createdDeviceValue = await coreData.upsertDevice(withId: deviceId) { device in
            device.manufacturer = "Acme"
            device.model = "Scale One"
            device.confidence = 0.7
        }
        let createdDevice = try XCTUnwrap(createdDeviceValue)
        XCTAssertEqual(createdDevice.manufacturer, "Acme")
        XCTAssertEqual(createdDevice.model, "Scale One")

        let updatedDeviceValue = await coreData.upsertDevice(withId: deviceId) { device in
            device.firmwareVersion = "2.0"
            device.confidence = 0.9
        }
        let updatedDevice = try XCTUnwrap(updatedDeviceValue)
        XCTAssertEqual(updatedDevice.firmwareVersion, "2.0")
        XCTAssertEqual(updatedDevice.confidence, 0.9, accuracy: 0.001)

        let createdPairingValue = await coreData.upsertUserDevice(withId: userDeviceId) { device in
            device.userId = userId
            device.deviceId = deviceId
            device.firstSeenAt = firstSeen
            device.lastSeenAt = firstSeen
            device.nickname = "Bathroom scale"
            device.isPrimary = true
        }
        _ = try XCTUnwrap(createdPairingValue)
        let updatedPairingValue = await coreData.upsertUserDevice(withId: userDeviceId) { device in
            device.lastSeenAt = lastSeen
            device.nickname = "Primary scale"
        }
        let updatedPairing = try XCTUnwrap(updatedPairingValue)
        XCTAssertEqual(updatedPairing.userId, userId)
        XCTAssertEqual(updatedPairing.deviceId, deviceId)
        XCTAssertEqual(updatedPairing.lastSeenAt, lastSeen)
        XCTAssertEqual(updatedPairing.nickname, "Primary scale")

        let counts = await context.perform { () -> (Int, Int) in
            let deviceRequest: NSFetchRequest<CachedDevice> = CachedDevice.fetchRequest()
            deviceRequest.predicate = NSPredicate(format: "id == %@", deviceId)
            let pairingRequest: NSFetchRequest<CachedUserDevice> = CachedUserDevice.fetchRequest()
            pairingRequest.predicate = NSPredicate(format: "id == %@", userDeviceId)
            return (
                (try? context.count(for: deviceRequest)) ?? 0,
                (try? context.count(for: pairingRequest)) ?? 0
            )
        }
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 1)
    }

    func testBodyMetricFetchesAreUserScopedRangeFilteredAndRespectSoftDeletes() async throws {
        let coreData = CoreDataManager.shared
        let userId = "body-persistence-\(UUID().uuidString)"
        let otherUserId = "body-persistence-other-\(UUID().uuidString)"
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = makeBodyMetric(userId: userId, date: baseDate.addingTimeInterval(-2 * 86_400), weight: 81)
        let newest = makeBodyMetric(userId: userId, date: baseDate, weight: 79)
        let otherUser = makeBodyMetric(userId: otherUserId, date: baseDate.addingTimeInterval(86_400), weight: 70)

        coreData.saveBodyMetrics(oldest, userId: userId)
        coreData.saveBodyMetrics(newest, userId: userId)
        coreData.saveBodyMetrics(otherUser, userId: otherUserId)

        let allMetrics = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertEqual(allMetrics.compactMap(\.id), [newest.id, oldest.id])

        let rangedMetrics = await coreData.fetchBodyMetrics(
            for: userId,
            from: baseDate.addingTimeInterval(-86_400),
            to: baseDate
        )
        XCTAssertEqual(rangedMetrics.compactMap(\.id), [newest.id])
        let latestMetric = await coreData.fetchLatestBodyMetric(for: userId)
        XCTAssertEqual(latestMetric?.id, newest.id)

        let didMarkDeleted = await coreData.markBodyMetricDeleted(id: newest.id)
        XCTAssertTrue(didMarkDeleted)
        let visibleMetrics = await coreData.fetchBodyMetrics(for: userId)
        XCTAssertEqual(visibleMetrics.compactMap(\.id), [oldest.id])
        let otherUserLatestMetric = await coreData.fetchLatestBodyMetric(for: otherUserId)
        XCTAssertEqual(otherUserLatestMetric?.id, otherUser.id)
    }

    func testGlp1PersistenceIsUserScopedAndPreservesMedicationAndDoseHistory() async throws {
        let coreData = CoreDataManager.shared
        let userId = "glp1-persistence-\(UUID().uuidString)"
        let otherUserId = "glp1-persistence-other-\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let historicalMedication = makeMedication(
            userId: userId,
            displayName: "Historical",
            startedAt: now.addingTimeInterval(-30 * 86_400),
            endedAt: now.addingTimeInterval(-10 * 86_400)
        )
        let activeMedication = makeMedication(
            userId: userId,
            displayName: "Active",
            startedAt: now.addingTimeInterval(-7 * 86_400)
        )
        let otherMedication = makeMedication(
            userId: otherUserId,
            displayName: "Other",
            startedAt: now.addingTimeInterval(-5 * 86_400)
        )

        coreData.saveGlp1Medications([historicalMedication, activeMedication], userId: userId, markAsSynced: false)
        coreData.saveGlp1Medications([otherMedication], userId: otherUserId, markAsSynced: false)

        let firstDose = makeDoseLog(
            userId: userId,
            medicationId: historicalMedication.id,
            takenAt: now.addingTimeInterval(-20 * 86_400)
        )
        let secondDose = makeDoseLog(
            userId: userId,
            medicationId: activeMedication.id,
            takenAt: now.addingTimeInterval(-86_400)
        )
        let otherDose = makeDoseLog(
            userId: otherUserId,
            medicationId: otherMedication.id,
            takenAt: now
        )

        coreData.saveGlp1DoseLogs([secondDose, firstDose], userId: userId, markAsSynced: false)
        coreData.saveGlp1DoseLogs([otherDose], userId: otherUserId, markAsSynced: false)

        let medications = await coreData.fetchGlp1Medications(for: userId)
        let doseLogs = await coreData.fetchGlp1DoseLogs(for: userId)
        let unsyncedMedications = await coreData.fetchUnsyncedGlp1Medications(for: userId)
        let unsyncedDoseLogs = await coreData.fetchUnsyncedGlp1DoseLogs(for: userId)
        XCTAssertEqual(medications.map(\.id), [historicalMedication.id, activeMedication.id])
        XCTAssertEqual(doseLogs.map(\.id), [firstDose.id, secondDose.id])
        XCTAssertEqual(unsyncedMedications.count, 2)
        XCTAssertEqual(unsyncedDoseLogs.count, 2)

        coreData.endActiveGlp1Medications(for: userId, endedAt: now)

        let medicationsAfterEnding = await coreData.fetchGlp1Medications(for: userId)
        let endedMedication = try XCTUnwrap(medicationsAfterEnding.first { $0.id == activeMedication.id })
        let otherUserMedications = await coreData.fetchGlp1Medications(for: otherUserId)
        XCTAssertEqual(endedMedication.endedAt, now)
        XCTAssertNil(otherUserMedications.first?.endedAt)
    }

    func testDexaPersistenceUsesUserScopeAndAcquisitionOrder() async throws {
        let coreData = CoreDataManager.shared
        let userId = "dexa-persistence-\(UUID().uuidString)"
        let otherUserId = "dexa-persistence-other-\(UUID().uuidString)"
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = makeDexaResult(userId: userId, acquireTime: baseDate.addingTimeInterval(-3 * 86_400))
        let middle = makeDexaResult(userId: userId, acquireTime: baseDate.addingTimeInterval(-2 * 86_400))
        let newest = makeDexaResult(userId: userId, acquireTime: baseDate.addingTimeInterval(-86_400))
        let otherUser = makeDexaResult(userId: otherUserId, acquireTime: baseDate)

        coreData.saveDexaResults([oldest, newest, middle], userId: userId, markAsSynced: false)
        coreData.saveDexaResults([otherUser], userId: otherUserId, markAsSynced: false)

        let latestTwo = await coreData.fetchDexaResults(for: userId, limit: 2)
        let otherUserLatest = await coreData.fetchDexaResults(for: otherUserId, limit: 1)
        let unsyncedResults = await coreData.fetchUnsyncedDexaResults(for: userId)
        XCTAssertEqual(latestTwo.map(\.id), [newest.id, middle.id])
        XCTAssertEqual(otherUserLatest.map(\.id), [otherUser.id])
        XCTAssertEqual(unsyncedResults.compactMap(\.id).sorted(), [oldest.id, middle.id, newest.id].sorted())
    }

    func testHealthKitSamplesDeduplicateByUUIDAndRefreshMutableFields() async throws {
        let coreData = CoreDataManager.shared
        let userId = "healthkit-raw-\(UUID().uuidString)"
        let sampleId = UUID().uuidString
        let hkUUID = UUID().uuidString
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let initialSample = HKRawSample(
            id: sampleId,
            userId: userId,
            hkUUID: hkUUID,
            quantityType: "HKQuantityTypeIdentifierBodyMass",
            value: 80,
            unit: "kg",
            startDate: date,
            endDate: date,
            sourceName: "Scale",
            sourceBundleId: "com.example.scale",
            deviceManufacturer: "Example",
            deviceModel: "Scale 1",
            deviceHardwareVersion: nil,
            deviceFirmwareVersion: nil,
            deviceSoftwareVersion: nil,
            deviceLocalIdentifier: nil,
            deviceUDI: nil,
            metadata: ["origin": "initial"],
            createdAt: date,
            updatedAt: date
        )
        let refreshedSample = HKRawSample(
            id: UUID().uuidString,
            userId: userId,
            hkUUID: hkUUID,
            quantityType: "HKQuantityTypeIdentifierBodyMass",
            value: 79.5,
            unit: "kg",
            startDate: date,
            endDate: date,
            sourceName: "Scale",
            sourceBundleId: "com.example.scale",
            deviceManufacturer: "Example",
            deviceModel: "Scale 2",
            deviceHardwareVersion: nil,
            deviceFirmwareVersion: nil,
            deviceSoftwareVersion: nil,
            deviceLocalIdentifier: nil,
            deviceUDI: nil,
            metadata: ["origin": "refreshed"],
            createdAt: date,
            updatedAt: date.addingTimeInterval(60)
        )

        await coreData.saveHKSample(initialSample)
        await coreData.saveHKSamples([refreshedSample])

        let sampleExists = await coreData.hkSampleExists(hkUUID: hkUUID)
        XCTAssertTrue(sampleExists)

        let context = coreData.viewContext
        let stored = await context.perform {
            () -> (id: String?, value: Double, deviceModel: String?, metadata: [String: String]?)? in
            let request: NSFetchRequest<CachedHKSample> = CachedHKSample.fetchRequest()
            request.predicate = NSPredicate(format: "hkUUID == %@", hkUUID)
            request.fetchLimit = 1
            guard let sample = try? context.fetch(request).first else { return nil }
            let metadata = sample.metadataJSON.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            return (sample.id, sample.value, sample.deviceModel, metadata)
        }

        let sample = try XCTUnwrap(stored)
        XCTAssertEqual(sample.id, sampleId)
        XCTAssertEqual(sample.value, 79.5, accuracy: 0.001)
        XCTAssertEqual(sample.deviceModel, "Scale 2")
        XCTAssertEqual(sample.metadata, ["origin": "refreshed"])
    }

    private func makeBodyMetric(userId: String, date: Date, weight: Double) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeDailyMetric(userId: String, date: Date, steps: Int) -> DailyMetrics {
        DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeMedication(
        userId: String,
        displayName: String,
        startedAt: Date,
        endedAt: Date? = nil
    ) -> Glp1Medication {
        Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: displayName,
            genericName: "semaglutide",
            drugClass: "GLP-1 receptor agonist",
            brand: "Wegovy",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }

    private func makeDoseLog(userId: String, medicationId: String, takenAt: Date) -> Glp1DoseLog {
        Glp1DoseLog(
            id: UUID().uuidString,
            userId: userId,
            takenAt: takenAt,
            medicationId: medicationId,
            doseAmount: 1,
            doseUnit: "mg/week",
            drugClass: "GLP-1 receptor agonist",
            brand: "Wegovy",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: nil,
            createdAt: takenAt,
            updatedAt: takenAt
        )
    }

    private func makeDexaResult(userId: String, acquireTime: Date) -> DexaResult {
        DexaResult(
            id: UUID().uuidString,
            userId: userId,
            bodyMetricsId: nil,
            externalSource: "BodySpec",
            externalResultId: UUID().uuidString,
            externalUpdateTime: acquireTime,
            scannerModel: "DEXA",
            locationId: nil,
            locationName: nil,
            acquireTime: acquireTime,
            analyzeTime: nil,
            vatMassKg: 1.2,
            vatVolumeCm3: 300,
            resultPdfUrl: nil,
            resultPdfName: nil,
            createdAt: acquireTime,
            updatedAt: acquireTime
        )
    }

    private func syncMetadata(
        for entityName: String,
        id: String,
        in context: NSManagedObjectContext
    ) async -> (retryCount: Int, error: String?, attempt: Date?, success: Date?) {
        await context.perform {
            let request: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
            request.predicate = NSPredicate(
                format: "entityName == %@ AND entityId == %@",
                entityName,
                id
            )
            request.fetchLimit = 1
            let metadata = try? context.fetch(request).first
            return (
                Int(metadata?.syncRetryCount ?? 0),
                metadata?.lastSyncError,
                metadata?.lastSyncAttempt,
                metadata?.lastSyncSuccess
            )
        }
    }
}

@MainActor
final class MetricChartDataHelperPersistenceTests: XCTestCase {
    func testStepSparklineUsesDailyLogsInWindowAndSkipsMissingValues() async {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "chart-steps-\(UUID().uuidString)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let outsideWindow = calendar.date(byAdding: .day, value: -7, to: today)!

        MetricChartDataHelper.clearCache(for: userId)
        coreData.saveDailyMetrics(makeDailyMetric(userId: userId, date: today, steps: 10_000), userId: userId)
        coreData.saveDailyMetrics(makeDailyMetric(userId: userId, date: twoDaysAgo, steps: 8_000), userId: userId)
        coreData.saveDailyMetrics(makeDailyMetric(userId: userId, date: outsideWindow, steps: 15_000), userId: userId)
        _ = await context.perform { () -> Bool in context.hasChanges }

        let points = MetricChartDataHelper.generateStepsChartData(for: userId)

        XCTAssertEqual(points.map(\.index), [4, 6])
        XCTAssertEqual(points.map(\.value), [8_000, 10_000])
        XCTAssertFalse(points.contains(where: { $0.isEstimated }))
    }

    func testMetricChartsComposeMetricTypesAndAsyncFetches() async {
        let coreData = CoreDataManager.shared
        let userId = "chart-metrics-\(UUID().uuidString)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today)!
        let profile = UserProfile(
            id: userId,
            email: "\(userId)@example.com",
            username: nil,
            fullName: nil,
            dateOfBirth: nil,
            height: 180,
            heightUnit: "cm",
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: true
        )

        MetricChartDataHelper.clearCache(for: userId)
        coreData.saveBodyMetrics(
            makeChartMetric(userId: userId, date: fourDaysAgo, weight: 70, bodyFat: 20, waist: 80),
            userId: userId
        )
        coreData.saveBodyMetrics(
            makeChartMetric(userId: userId, date: twoDaysAgo, weight: 71, bodyFat: nil, waist: nil),
            userId: userId
        )
        coreData.saveBodyMetrics(
            makeChartMetric(userId: userId, date: today, weight: 72, bodyFat: 18, waist: 84),
            userId: userId
        )
        coreData.saveDailyMetrics(makeDailyMetric(userId: userId, date: today, steps: 7_500), userId: userId)
        _ = await coreData.fetchBodyMetrics(for: userId)

        let metricWeight = MetricChartDataHelper.generateChartData(
            for: userId,
            days: 7,
            metricType: .weight,
            useMetric: true,
            profile: profile
        )
        let imperialWeight = MetricChartDataHelper.generateWeightChartData(
            for: userId,
            useMetric: false,
            profile: profile
        )
        let bodyFat = MetricChartDataHelper.generateBodyFatChartData(for: userId, profile: profile)
        let ffmi = MetricChartDataHelper.generateFFMIChartData(for: userId, profile: profile)
        let metricWaist = MetricChartDataHelper.generateWaistChartData(
            for: userId,
            useMetric: true,
            profile: profile
        )
        let imperialWaist = MetricChartDataHelper.generateWaistChartData(
            for: userId,
            useMetric: false,
            profile: profile
        )
        let steps = MetricChartDataHelper.generateChartData(
            for: userId,
            days: 7,
            metricType: .steps
        )
        let asyncWeight = await MetricChartDataHelper.generateChartDataAsync(
            for: userId,
            days: 7,
            metricType: .weight,
            useMetric: true,
            profile: profile
        )

        XCTAssertEqual(metricWeight.map(\.index), [0, 1, 2])
        XCTAssertEqual(metricWeight.map(\.value), [72, 71, 70])
        XCTAssertEqual(imperialWeight.count, 3)
        XCTAssertEqual(imperialWeight[0].value, 72 * 2.20462, accuracy: 0.0001)
        XCTAssertEqual(bodyFat.map(\.value), [18, 19, 20])
        XCTAssertFalse(bodyFat[0].isEstimated)
        XCTAssertTrue(bodyFat[1].isEstimated)
        XCTAssertFalse(bodyFat[2].isEstimated)
        XCTAssertEqual(ffmi.count, 3)
        XCTAssertTrue(ffmi.allSatisfy { $0.value > 0 })
        XCTAssertTrue(ffmi[1].isEstimated)
        XCTAssertEqual(metricWaist.map(\.value), [84, 80])
        XCTAssertEqual(imperialWaist.count, 2)
        XCTAssertEqual(imperialWaist[0].value, 84 / 2.54, accuracy: 0.0001)
        XCTAssertEqual(steps.map(\.value), [7_500])
        XCTAssertEqual(asyncWeight.map(\.value), metricWeight.map(\.value))
    }

    func testLongMetricHistoryDownsamplesWithoutDroppingEitherEndpoint() async {
        let coreData = CoreDataManager.shared
        let context = coreData.viewContext
        let userId = "chart-history-\(UUID().uuidString)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        MetricChartDataHelper.clearCache(for: userId)
        await context.perform {
            for offset in 0..<180 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                    continue
                }

                let metric = CachedBodyMetrics(context: context)
                metric.id = "\(userId)-\(offset)"
                metric.userId = userId
                metric.date = date
                metric.weight = Double(180 - offset)
                metric.weightUnit = "kg"
                metric.createdAt = date
                metric.updatedAt = date
                metric.lastModified = date
                metric.isMarkedDeleted = false
                metric.isSynced = true
                metric.syncStatus = "synced"
            }
            try? context.save()
        }

        let points = MetricChartDataHelper.generateChartData(
            for: userId,
            days: 180,
            metricType: .weight,
            useMetric: true
        )

        XCTAssertEqual(points.count, 150)
        XCTAssertEqual(points.first?.index, 0)
        XCTAssertEqual(points.first?.value, 180)
        XCTAssertEqual(points.last?.index, 179)
        XCTAssertEqual(points.last?.value, 1)
    }

    private func makeDailyMetric(userId: String, date: Date, steps: Int) -> DailyMetrics {
        DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func makeChartMetric(
        userId: String,
        date: Date,
        weight: Double,
        bodyFat: Double?,
        waist: Double?
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            waistCm: waist,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

// swiftlint:enable single_test_class
