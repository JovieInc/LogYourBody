//
// LogYourBodyTests.swift
// LogYourBody
//
import XCTest
@testable import LogYourBody

// swiftlint:disable single_test_class

@MainActor
final class OnboardingFlowViewModelTests: XCTestCase {
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

    func testBuildOnboardingProfileUpdatesIncludesGenderDobAndHeight() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.updateSex(.female)
        viewModel.updateBirthYear(1_990)
        viewModel.bodyScoreInput.height = HeightValue(value: 180, unit: .centimeters)
        viewModel.setHeightUnit(.centimeters)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["gender"] as? String, "Female")

        let dateOfBirth = updates["dateOfBirth"] as? Date
        XCTAssertNotNil(dateOfBirth)

        if let dateOfBirth {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: dateOfBirth)
            XCTAssertEqual(components.year, 1_990)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 1)
        }

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            let expectedInches = 180.0 / 2.54
            XCTAssertEqual(height, expectedInches, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesRespectsImperialHeightUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["height"] as? Double, 72)
        XCTAssertEqual(updates["heightUnit"] as? String, "in")
    }

    func testBuildOnboardingProfileUpdatesAlwaysMarksOnboardingCompleted() {
        let viewModel = OnboardingFlowViewModel()

        let updates = viewModel.buildOnboardingProfileUpdates()

        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testLogoutSetsExitReasonUserInitiated() async {
        let manager = AuthManager()
        manager.isAuthenticated = true

        await manager.logout()

        XCTAssertEqual(manager.lastExitReason, .userInitiated)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testHandleSupabaseUnauthorizedSetsSessionExpired() async {
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

        await manager.handleSupabaseUnauthorized()

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
}

final class StubSupabaseManager: SupabaseManager {
    struct EndActiveGlp1Call {
        let userId: String
        let endedAt: Date
    }

    private(set) var bodyMetricsBatches: [[[String: Any]]] = []
    private(set) var dailyMetricsBatches: [[[String: Any]]] = []
    private(set) var dexaPayloads: [[String: Any]] = []
    private(set) var glp1DosePayloads: [[String: Any]] = []
    private(set) var glp1MedicationPayloads: [[String: Any]] = []
    private(set) var endActiveGlp1Calls: [EndActiveGlp1Call] = []
    private(set) var profilePayloads: [[String: Any]] = []
    var fetchedGlp1Medications: [Glp1Medication] = []
    var fetchedGlp1DoseLogs: [Glp1DoseLog] = []
    var fetchedDexaResults: [DexaResult] = []

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

    override func updateProfile(_ profile: [String: Any], token: String) async throws {
        profilePayloads.append(profile)
    }

    override func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        endActiveGlp1Calls.append(EndActiveGlp1Call(userId: userId, endedAt: endedAt))
    }

    override func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication] {
        fetchedGlp1Medications.filter { $0.userId == userId }
    }

    override func fetchGlp1DoseLogs(userId: String, limit: Int = 100) async throws -> [Glp1DoseLog] {
        Array(fetchedGlp1DoseLogs.filter { $0.userId == userId }.prefix(limit))
    }

    override func fetchDexaResults(userId: String, limit: Int = 50) async throws -> [DexaResult] {
        Array(fetchedDexaResults.filter { $0.userId == userId }.prefix(limit))
    }

    override func upsertData(table: String, data: Data, token: String) async throws {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let array = jsonObject as? [[String: Any]] ?? []
        switch table {
        case "dexa_results":
            dexaPayloads.append(contentsOf: array)
        case "glp1_dose_logs":
            glp1DosePayloads.append(contentsOf: array)
        case "glp1_medications":
            glp1MedicationPayloads.append(contentsOf: array)
        default:
            return
        }
    }
}

@MainActor
final class SyncIntegrationTests: XCTestCase {
    func testUpdateOrCreateBodyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_\(UUID().uuidString)"
        let date = Date()
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

    func testUpdateOrCreateBodyMetric_NormalizesPoundPayloadToKilograms() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_lbs_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 180.0,
            "weight_unit": "LBS",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.weight ?? 0, 81.6, accuracy: 0.2)
        XCTAssertEqual(metric.weightUnit, "kg")
    }

    func testUpdateOrCreateBodyMetric_NormalizesInchCircumferencePayloadToCentimeters() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_inches_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.0,
            "weight_unit": "kg",
            "waist_circumference": 32.0,
            "hip_circumference": 40.0,
            "waist_unit": "IN",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)

        let metric = try XCTUnwrap(metrics.first)
        XCTAssertEqual(metric.waistCm ?? 0, 81.28, accuracy: 0.01)
        XCTAssertEqual(metric.hipCm ?? 0, 101.6, accuracy: 0.01)
        XCTAssertEqual(metric.waistUnit, "cm")
    }

    func testUpdateOrCreateBodyMetric_MapsServerDataSource() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_source_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.0,
            "weight_unit": "kg",
            "data_source": "HealthKit",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ]

        coreData.updateOrCreateBodyMetric(from: payload)

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.dataSource, "HealthKit")
    }

    func testUpdateOrCreateDailyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_\(UUID().uuidString)"
        let date = Date()
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
        let date = Date()
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

    func testUpdateOrCreateBodyMetricClearsDeletedFlagWhenServerRecordReturns() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_restore_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        let metric = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 75.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "local",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveBodyMetrics(metric, userId: userId)
        XCTAssertTrue(await coreData.markBodyMetricDeleted(id: id))

        coreData.updateOrCreateBodyMetric(from: [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.0,
            "weight_unit": "kg",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ])

        let metrics = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.weight ?? 0, 80.0, accuracy: 0.001)
    }

    func testUpdateOrCreateBodyMetricMarksDeletedWhenServerPayloadIsDeleted() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_remote_delete_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        coreData.updateOrCreateBodyMetric(from: [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "weight": 80.0,
            "weight_unit": "kg",
            "is_deleted": true,
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ])

        let fetched = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(fetched.isEmpty)

        let rawDeletedState = await coreData.viewContext.perform { () -> Bool in
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            return (try? coreData.viewContext.fetch(request).first?.isMarkedDeleted) ?? false
        }
        XCTAssertTrue(rawDeletedState)
    }

    func testUpdateOrCreateDailyMetric_IsIdempotentForSameId() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_idempotent_\(UUID().uuidString)"
        let date = Date()
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

    func testUpdateOrCreateDailyMetricClearsDeletedFlagWhenServerRecordReturns() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_restore_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 5_000,
            notes: "local",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)
        XCTAssertTrue(await coreData.markDailyMetricDeleted(id: id))

        coreData.updateOrCreateDailyMetric(from: [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "steps": 9_000,
            "notes": "restored",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ])

        let fetched = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.stepCount, 9_000)
    }

    func testUpdateOrCreateDailyMetricMarksDeletedWhenServerPayloadIsDeleted() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_remote_delete_\(UUID().uuidString)"
        let date = Date()
        let formatter = ISO8601DateFormatter()

        coreData.updateOrCreateDailyMetric(from: [
            "id": id,
            "user_id": userId,
            "date": formatter.string(from: date),
            "steps": 4_500,
            "is_deleted": true,
            "notes": "remote-delete",
            "created_at": formatter.string(from: date),
            "updated_at": formatter.string(from: date)
        ])

        let fetched = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertTrue(fetched.isEmpty)

        let rawDeletedState = await coreData.viewContext.perform { () -> Bool in
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            return (try? coreData.viewContext.fetch(request).first?.isMarkedDeleted) ?? false
        }
        XCTAssertTrue(rawDeletedState)
    }

    func testUpdateOrCreateProfileUpdatesExistingProfileById() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_restore_\(UUID().uuidString)"
        let email = "profile@example.com"
        let originalProfile = UserProfile(
            fullName: "Original Name",
            username: "original",
            dateOfBirth: nil,
            height: 70,
            heightUnit: "in",
            gender: "Male",
            activityLevel: "moderate",
            goalWeight: nil,
            goalWeightUnit: nil
        )

        coreData.saveProfile(originalProfile, userId: userId, email: email)

        let dob = Date(timeIntervalSince1970: 946684800) // 2000-01-01T00:00:00Z
        let createdAt = Date(timeIntervalSince1970: 946684800)
        let updatedAt = Date(timeIntervalSince1970: 978307200) // 2001-01-01
        let formatter = ISO8601DateFormatter()
        coreData.updateOrCreateProfile(from: [
            "id": userId,
            "email": "server@example.com",
            "full_name": "Updated Name",
            "username": "updated",
            "height": 72.0,
            "height_unit": "in",
            "gender": "Female",
            "activity_level": "active",
            "goal_weight": 150.0,
            "goal_weight_unit": "lbs",
            "date_of_birth": formatter.string(from: dob),
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: updatedAt)
        ])

        let fetchedProfile = try XCTUnwrap(await coreData.fetchProfile(for: userId))
        XCTAssertEqual(fetchedProfile.email, "server@example.com")
        XCTAssertEqual(fetchedProfile.fullName, "Updated Name")
        XCTAssertEqual(fetchedProfile.username, "updated")
        XCTAssertEqual(fetchedProfile.gender, "Female")
        XCTAssertEqual(fetchedProfile.goalWeight, 150.0, accuracy: 0.001)
        XCTAssertEqual(fetchedProfile.goalWeightUnit, "lbs")
        XCTAssertEqual(fetchedProfile.createdAt?.timeIntervalSince(createdAt) ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(fetchedProfile.updatedAt?.timeIntervalSince(updatedAt) ?? 0, 0, accuracy: 0.001)

        let count = await coreData.viewContext.perform { () -> Int in
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            return (try? coreData.viewContext.count(for: request)) ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testUpdateOrCreateProfileMarksDeletedWhenServerPayloadIsDeleted() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_remote_delete_\(UUID().uuidString)"
        let formatter = ISO8601DateFormatter()
        let now = Date()

        coreData.updateOrCreateProfile(from: [
            "id": userId,
            "email": "deleted@example.com",
            "is_deleted": true,
            "created_at": formatter.string(from: now),
            "updated_at": formatter.string(from: now)
        ])

        let fetchedProfile = await coreData.fetchProfile(for: userId)
        XCTAssertNil(fetchedProfile)

        let rawDeletedState = await coreData.viewContext.perform { () -> Bool in
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            return (try? coreData.viewContext.fetch(request).first?.isMarkedDeleted) ?? false
        }
        XCTAssertTrue(rawDeletedState)
    }

    func testFetchAllBodyMetricsExcludesMarkedDeletedEntries() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_fetch_delete_\(UUID().uuidString)"
        let date = Date()
        let metric = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 81.0,
            weightUnit: "kg",
            bodyFatPercentage: 18.0,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "delete-me",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveBodyMetrics(metric, userId: userId)
        XCTAssertTrue(await coreData.markBodyMetricDeleted(id: id))

        let fetched = await coreData.fetchAllBodyMetrics(for: userId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testMarkDailyMetricDeletedHidesEntryFromDailyFetchAndMarksUnsynced() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_delete_\(UUID().uuidString)"
        let date = Date()

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 7_500,
            notes: "delete-me",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)

        let deleted = await coreData.markDailyMetricDeleted(id: id)
        XCTAssertTrue(deleted)

        let fetched = await coreData.fetchDailyMetrics(for: userId, date: date)
        XCTAssertNil(fetched)

        let unsynced = await coreData.fetchUnsyncedEntries()
        let deletedEntry = try XCTUnwrap(
            unsynced.dailyMetrics.first(where: { $0.id == id })
        )
        XCTAssertTrue(deletedEntry.isMarkedDeleted)
        XCTAssertFalse(deletedEntry.isSynced)
        XCTAssertEqual(deletedEntry.syncStatus, "pending")
    }

    func testFetchAllDailyLogsExcludesMarkedDeletedEntries() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_fetch_delete_\(UUID().uuidString)"
        let date = Date()
        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 8_200,
            notes: "delete-me",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)
        XCTAssertTrue(await coreData.markDailyMetricDeleted(id: id))

        let fetched = await coreData.fetchAllDailyLogs(for: userId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testCleanupOldDataRemovesDeletedDailyMetrics() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_daily_cleanup_\(UUID().uuidString)"
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60)
        let recentDate = Date()

        let oldDeleted = DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: oldDate,
            steps: 4_000,
            notes: "old-deleted",
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let recentDeleted = DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: recentDate,
            steps: 8_000,
            notes: "recent-deleted",
            createdAt: recentDate,
            updatedAt: recentDate
        )

        coreData.saveDailyMetrics(oldDeleted, userId: userId)
        coreData.saveDailyMetrics(recentDeleted, userId: userId)
        XCTAssertTrue(await coreData.markDailyMetricDeleted(id: oldDeleted.id))
        XCTAssertTrue(await coreData.markDailyMetricDeleted(id: recentDeleted.id))

        coreData.cleanupOldData()

        let counts = await coreData.viewContext.perform { () -> (Int, Int) in
            let oldRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            oldRequest.predicate = NSPredicate(format: "id == %@", oldDeleted.id)

            let recentRequest: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            recentRequest.predicate = NSPredicate(format: "id == %@", recentDeleted.id)

            let oldCount = (try? coreData.viewContext.count(for: oldRequest)) ?? 0
            let recentCount = (try? coreData.viewContext.count(for: recentRequest)) ?? 0
            return (oldCount, recentCount)
        }

        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 1)
    }

    func testProcessBatchHealthKitData_RespectsExistingEntriesWithinSameHour() async throws {
        let coreData = CoreDataManager.shared
        let healthKitManager = HealthKitManager.shared

        let userId = "healthkit_test_user_existing_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_existing@example.com",
            name: "HK Existing",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
            bodyFatHistory: bodyFatHistory
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
        let user = LocalUser(
            id: userId,
            email: "hk_batch@example.com",
            name: "HK Batch",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
            bodyFatHistory: bodyFatHistory
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
        let user = LocalUser(
            id: userId,
            email: "hk_bodyfat@example.com",
            name: "HK BodyFat",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        AuthManager.shared.currentUser = user

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
            bodyFatHistory: bodyFatHistory
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

    func testCreateOrUpdateMetrics_PreservesExistingCircumferenceFields() async throws {
        let coreData = CoreDataManager.shared
        let userId = "photo_metadata_preserve_circumference_\(UUID().uuidString)"
        let date = Date()
        let startOfDay = Calendar.current.startOfDay(for: date)

        coreData.saveBodyMetrics(
            BodyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: startOfDay,
                weight: 80.0,
                weightUnit: "kg",
                bodyFatPercentage: 20.0,
                bodyFatMethod: "Manual",
                muscleMass: nil,
                boneMass: nil,
                waistCm: 82.4,
                hipCm: 99.1,
                waistUnit: "cm",
                notes: "existing",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: startOfDay,
                updatedAt: startOfDay
            ),
            userId: userId
        )

        let updated = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: date,
            photoUrl: "https://example.com/progress.jpg",
            weight: nil,
            bodyFatPercentage: nil,
            userId: userId
        )

        XCTAssertEqual(updated.waistCm, 82.4, accuracy: 0.001)
        XCTAssertEqual(updated.hipCm, 99.1, accuracy: 0.001)
        XCTAssertEqual(updated.waistUnit, "cm")

        let savedMetrics = await coreData.fetchAllBodyMetrics(for: userId)
        let savedMetric = try XCTUnwrap(savedMetrics.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
        }))

        XCTAssertEqual(savedMetric.waistCm, 82.4, accuracy: 0.001)
        XCTAssertEqual(savedMetric.hipCm, 99.1, accuracy: 0.001)
        XCTAssertEqual(savedMetric.waistUnit, "cm")
        XCTAssertEqual(savedMetric.photoUrl, "https://example.com/progress.jpg")
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
            dataSource: "HealthKit",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        coreData.saveBodyMetrics(metricModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

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
        XCTAssertEqual(payload["data_source"] as? String, "HealthKit")
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
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.bodyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testLogBodyMetrics_PreservesCircumferenceFieldsForCurrentUser() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager.shared
        let previousUser = authManager.currentUser
        let previousAuth = authManager.isAuthenticated
        defer {
            authManager.currentUser = previousUser
            authManager.isAuthenticated = previousAuth
        }

        let userId = "sync_test_user_log_body_metrics_\(UUID().uuidString)"
        authManager.currentUser = LocalUser(
            id: userId,
            email: "log-body-metrics@example.com",
            name: "Body Metrics",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        authManager.isAuthenticated = false

        let date = Date()
        let metric = BodyMetrics(
            id: UUID().uuidString,
            userId: "ignored-user-id",
            date: date,
            weight: 84.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: 81.5,
            hipCm: 98.2,
            waistUnit: "cm",
            notes: "circumference",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )

        manager.logBodyMetrics(metric)

        let savedMetrics = await coreData.fetchAllBodyMetrics(for: userId)
        let savedMetric = try XCTUnwrap(savedMetrics.first(where: { $0.id == metric.id }))

        XCTAssertEqual(savedMetric.userId, userId)
        XCTAssertEqual(savedMetric.waistCm, 81.5, accuracy: 0.001)
        XCTAssertEqual(savedMetric.hipCm, 98.2, accuracy: 0.001)
        XCTAssertEqual(savedMetric.waistUnit, "cm")
    }

    func testSyncLocalChanges_ScopesUploadsToExplicitUserId() async throws {
        let coreData = CoreDataManager.shared

        let activeUserId = "sync_test_user_scoped_active_\(UUID().uuidString)"
        let otherUserId = "sync_test_user_scoped_other_\(UUID().uuidString)"
        let date = Date()

        coreData.saveBodyMetrics(
            BodyMetrics(
                id: UUID().uuidString,
                userId: activeUserId,
                date: date,
                weight: 81.0,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "active-user",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: date,
                updatedAt: date
            ),
            userId: activeUserId
        )

        coreData.saveBodyMetrics(
            BodyMetrics(
                id: UUID().uuidString,
                userId: otherUserId,
                date: date,
                weight: 92.0,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "other-user",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: date,
                updatedAt: date
            ),
            userId: otherUserId
        )

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token", userId: activeUserId)

        XCTAssertEqual(stubSupabase.bodyMetricsBatches.count, 1)
        let batch = try XCTUnwrap(stubSupabase.bodyMetricsBatches.first)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?["user_id"] as? String, activeUserId)

        let unsynced = await coreData.fetchUnsyncedEntries()
        XCTAssertFalse(unsynced.bodyMetrics.contains(where: { $0.userId == activeUserId }))
        XCTAssertTrue(unsynced.bodyMetrics.contains(where: { $0.userId == otherUserId }))
    }

    func testPendingSyncState_IgnoresUnsyncedEntriesFromOtherUsers() async throws {
        let coreData = CoreDataManager.shared
        let authManager = AuthManager.shared
        let previousUser = authManager.currentUser
        let previousAuth = authManager.isAuthenticated
        defer {
            authManager.currentUser = previousUser
            authManager.isAuthenticated = previousAuth
        }

        let activeUserId = "sync_test_user_pending_active_\(UUID().uuidString)"
        let otherUserId = "sync_test_user_pending_other_\(UUID().uuidString)"
        authManager.currentUser = LocalUser(
            id: activeUserId,
            email: "pending-sync@example.com",
            name: "Pending Sync",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        authManager.isAuthenticated = true

        coreData.saveBodyMetrics(
            BodyMetrics(
                id: UUID().uuidString,
                userId: otherUserId,
                date: Date(),
                weight: 90.0,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "other-user",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: Date(),
                updatedAt: Date()
            ),
            userId: otherUserId
        )

        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: authManager,
            supabaseManager: StubSupabaseManager()
        )

        XCTAssertFalse(await manager.hasPendingSyncOperations())

        manager.updatePendingSyncCount()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(manager.pendingSyncCount, 0)

        coreData.saveBodyMetrics(
            BodyMetrics(
                id: UUID().uuidString,
                userId: activeUserId,
                date: Date(),
                weight: 81.0,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "active-user",
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: Date(),
                updatedAt: Date()
            ),
            userId: activeUserId
        )

        XCTAssertTrue(await manager.hasPendingSyncOperations())

        manager.updatePendingSyncCount()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(manager.pendingSyncCount, 1)
    }

    func testSyncLocalChanges_SendsNullsForMissingBodyMetricValues() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_realtime_sparse_body_\(UUID().uuidString)"
        let date = Date()
        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "sparse",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveBodyMetrics(metricModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        guard let batch = stubSupabase.bodyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No body metrics batch captured")
            return
        }

        XCTAssertTrue(payload["weight"] is NSNull)
        XCTAssertTrue(payload["weight_unit"] is NSNull)
        XCTAssertTrue(payload["waist_circumference"] is NSNull)
        XCTAssertTrue(payload["hip_circumference"] is NSNull)
        XCTAssertTrue(payload["waist_unit"] is NSNull)
        XCTAssertTrue(payload["body_fat_percentage"] is NSNull)
        XCTAssertTrue(payload["muscle_mass"] is NSNull)
        XCTAssertTrue(payload["bone_mass"] is NSNull)
    }

    func testSyncLocalChanges_SendsDeletionFlagForDeletedBodyMetric() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_realtime_deleted_body_\(UUID().uuidString)"
        let date = Date()
        let metricModel = BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: 80.0,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: nil,
            hipCm: nil,
            waistUnit: nil,
            notes: "to-delete",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveBodyMetrics(metricModel, userId: userId)
        XCTAssertTrue(await coreData.markBodyMetricDeleted(id: id))

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.bodyMetricsBatches.first?.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["is_deleted"] as? Bool, true)
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
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

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
        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.dailyMetrics.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChanges_SendsNullForMissingDailySteps() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_realtime_sparse_\(UUID().uuidString)"
        let date = Date()

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: nil,
            notes: "notes-only",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        guard let batch = stubSupabase.dailyMetricsBatches.first,
              let payload = batch.first else {
            XCTFail("No daily metrics batch captured")
            return
        }

        XCTAssertTrue(payload["steps"] is NSNull)
        XCTAssertEqual(payload["notes"] as? String, "notes-only")
    }

    func testSyncLocalChanges_SendsDeletionFlagForDeletedDailyMetric() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_daily_realtime_deleted_\(UUID().uuidString)"
        let date = Date()

        let dailyModel = DailyMetrics(
            id: id,
            userId: userId,
            date: date,
            steps: 5_000,
            notes: "to-delete",
            createdAt: date,
            updatedAt: date
        )

        coreData.saveDailyMetrics(dailyModel, userId: userId)
        XCTAssertTrue(await coreData.markDailyMetricDeleted(id: id))

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.dailyMetricsBatches.first?.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual(payload["is_deleted"] as? Bool, true)
    }

    func testSyncLocalChanges_UsesSupabaseAndSendsProfileGoalWeightFields() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_realtime_\(UUID().uuidString)"
        let profile = UserProfile(
            fullName: "Goal User",
            username: "goaluser",
            dateOfBirth: nil,
            height: 70,
            heightUnit: "in",
            gender: "Female",
            activityLevel: "active",
            goalWeight: 145.0,
            goalWeightUnit: "lbs"
        )

        coreData.saveProfile(profile, userId: userId, email: "goal@example.com")

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertEqual(stubSupabase.profilePayloads.count, 1)
        let payload = try XCTUnwrap(stubSupabase.profilePayloads.first)
        XCTAssertEqual(payload["id"] as? String, userId)
        XCTAssertEqual(payload["goal_weight"] as? Double, 145.0, accuracy: 0.001)
        XCTAssertEqual(payload["goal_weight_unit"] as? String, "lbs")

        let unsynced = await coreData.fetchUnsyncedEntries()
        let unsyncedForUser = unsynced.profiles.filter { $0.id == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
    }

    func testSyncLocalChanges_SendsDeletionFlagForDeletedProfile() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_profile_deleted_\(UUID().uuidString)"
        let profile = UserProfile(
            fullName: "Deleted User",
            username: "deleteduser",
            dateOfBirth: nil,
            height: 70,
            heightUnit: "in",
            gender: "Female",
            activityLevel: "active",
            goalWeight: nil,
            goalWeightUnit: nil
        )

        coreData.saveProfile(profile, userId: userId, email: "deleted@example.com")
        await coreData.viewContext.perform {
            let request: NSFetchRequest<CachedProfile> = CachedProfile.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", userId)
            let cached = try? coreData.viewContext.fetch(request).first
            cached?.isMarkedDeleted = true
            cached?.isSynced = false
            cached?.syncStatus = "pending"
            cached?.lastModified = Date()
            try? coreData.viewContext.save()
        }

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.profilePayloads.first)
        XCTAssertEqual(payload["id"] as? String, userId)
        XCTAssertEqual(payload["is_deleted"] as? Bool, true)
    }

    func testSyncLocalChanges_SendsNullForMissingGlp1DoseAmount() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_glp1_sparse_\(UUID().uuidString)"
        let takenAt = Date()
        let log = Glp1DoseLog(
            id: id,
            userId: userId,
            takenAt: takenAt,
            medicationId: nil,
            doseAmount: nil,
            doseUnit: nil,
            drugClass: "GLP-1",
            brand: nil,
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: "dose pending",
            createdAt: takenAt,
            updatedAt: takenAt
        )

        coreData.saveGlp1DoseLogs([log], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let payload = try XCTUnwrap(stubSupabase.glp1DosePayloads.first)
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertTrue(payload["dose_amount"] is NSNull)
        XCTAssertEqual(payload["notes"] as? String, "dose pending")

        let unsyncedLogs = await coreData.fetchUnsyncedGlp1DoseLogs()
        XCTAssertFalse(unsyncedLogs.contains(where: { $0.id == id }))
    }

    func testSyncLocalChanges_DoesNotEndActiveGlp1MedicationsForHistoricalMedicationSync() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_glp1_historical_\(UUID().uuidString)"
        let startedAt = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let endedAt = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let medication = Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: "Historical Med",
            genericName: "historical",
            drugClass: "GLP-1",
            brand: nil,
            route: "subcutaneous",
            frequency: "weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: "historical",
            createdAt: startedAt,
            updatedAt: endedAt
        )

        coreData.saveGlp1Medications([medication], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        XCTAssertTrue(stubSupabase.endActiveGlp1Calls.isEmpty)
        XCTAssertEqual(stubSupabase.glp1MedicationPayloads.first?["id"] as? String, medication.id)
    }

    func testSyncLocalChanges_EndsActiveGlp1MedicationsAtMedicationStartDate() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_glp1_active_\(UUID().uuidString)"
        let startedAt = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let medication = Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: "Active Med",
            genericName: "active",
            drugClass: "GLP-1",
            brand: nil,
            route: "subcutaneous",
            frequency: "weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: startedAt,
            endedAt: nil,
            notes: "active",
            createdAt: startedAt,
            updatedAt: startedAt
        )

        coreData.saveGlp1Medications([medication], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

        let endCall = try XCTUnwrap(stubSupabase.endActiveGlp1Calls.first)
        XCTAssertEqual(endCall.userId, userId)
        XCTAssertEqual(endCall.endedAt.timeIntervalSince(startedAt), 0, accuracy: 0.001)
        XCTAssertEqual(stubSupabase.glp1MedicationPayloads.first?["id"] as? String, medication.id)
    }

    func testPullSupplementalRemoteDataCachesGlp1AndDexaAsSynced() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_remote_supplemental_\(UUID().uuidString)"
        let now = Date()

        let medication = Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: "Remote Med",
            genericName: "remote",
            drugClass: "GLP-1",
            brand: "RemoteBrand",
            route: "subcutaneous",
            frequency: "weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
            endedAt: nil,
            notes: "remote-med",
            createdAt: now,
            updatedAt: now
        )

        let doseLog = Glp1DoseLog(
            id: UUID().uuidString,
            userId: userId,
            takenAt: now,
            medicationId: medication.id,
            doseAmount: 1.0,
            doseUnit: "mg",
            drugClass: "GLP-1",
            brand: "RemoteBrand",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: "remote-dose",
            createdAt: now,
            updatedAt: now
        )

        let dexaResult = DexaResult(
            id: UUID().uuidString,
            userId: userId,
            bodyMetricsId: nil,
            externalSource: "BodySpec",
            externalResultId: "remote-result",
            externalUpdateTime: now,
            scannerModel: "Scanner",
            locationId: "location",
            locationName: "Remote Location",
            acquireTime: now,
            analyzeTime: now,
            vatMassKg: 1.2,
            vatVolumeCm3: 450,
            resultPdfUrl: "https://example.com/result.pdf",
            resultPdfName: "result.pdf",
            createdAt: now,
            updatedAt: now
        )

        let stubSupabase = StubSupabaseManager()
        stubSupabase.fetchedGlp1Medications = [medication]
        stubSupabase.fetchedGlp1DoseLogs = [doseLog]
        stubSupabase.fetchedDexaResults = [dexaResult]

        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.pullSupplementalRemoteData(userId: userId)

        let fetchedMedications = await coreData.fetchGlp1Medications(for: userId)
        XCTAssertEqual(fetchedMedications.map(\.id), [medication.id])

        let fetchedDoseLogs = await coreData.fetchGlp1DoseLogs(for: userId)
        XCTAssertEqual(fetchedDoseLogs.map(\.id), [doseLog.id])

        let fetchedDexa = await coreData.fetchDexaResults(for: userId, limit: 10)
        XCTAssertEqual(fetchedDexa.map(\.id), [dexaResult.id])

        let unsyncedMeds = await coreData.fetchUnsyncedGlp1Medications()
        XCTAssertFalse(unsyncedMeds.contains(where: { $0.id == medication.id }))

        let unsyncedLogs = await coreData.fetchUnsyncedGlp1DoseLogs()
        XCTAssertFalse(unsyncedLogs.contains(where: { $0.id == doseLog.id }))

        let unsyncedDexa = await coreData.fetchUnsyncedDexaResults()
        XCTAssertFalse(unsyncedDexa.contains(where: { $0.id == dexaResult.id }))
    }

    func testPullSupplementalRemoteDataRefreshesExistingSupplementalCreatedAtValues() async throws {
        let coreData = CoreDataManager.shared

        let userId = "sync_test_user_remote_supplemental_created_at_\(UUID().uuidString)"
        let localDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let remoteDate = Date().addingTimeInterval(-2 * 24 * 60 * 60)

        let medicationId = UUID().uuidString
        let doseLogId = UUID().uuidString
        let dexaId = UUID().uuidString

        coreData.saveGlp1Medications([
            Glp1Medication(
                id: medicationId,
                userId: userId,
                displayName: "Local Med",
                genericName: nil,
                drugClass: "GLP-1",
                brand: nil,
                route: nil,
                frequency: nil,
                doseUnit: nil,
                isCompounded: false,
                hkIdentifier: nil,
                startedAt: localDate,
                endedAt: nil,
                notes: nil,
                createdAt: localDate,
                updatedAt: localDate
            )
        ], userId: userId, markAsSynced: false)

        coreData.saveGlp1DoseLogs([
            Glp1DoseLog(
                id: doseLogId,
                userId: userId,
                takenAt: localDate,
                medicationId: medicationId,
                doseAmount: 0.5,
                doseUnit: "mg",
                drugClass: "GLP-1",
                brand: nil,
                isCompounded: false,
                supplierType: nil,
                supplierName: nil,
                notes: nil,
                createdAt: localDate,
                updatedAt: localDate
            )
        ], userId: userId, markAsSynced: false)

        coreData.saveDexaResults([
            DexaResult(
                id: dexaId,
                userId: userId,
                bodyMetricsId: nil,
                externalSource: "BodySpec",
                externalResultId: "local-result",
                externalUpdateTime: localDate,
                scannerModel: nil,
                locationId: nil,
                locationName: nil,
                acquireTime: localDate,
                analyzeTime: localDate,
                vatMassKg: 1.0,
                vatVolumeCm3: 400,
                resultPdfUrl: nil,
                resultPdfName: nil,
                createdAt: localDate,
                updatedAt: localDate
            )
        ], userId: userId, markAsSynced: false)

        let stubSupabase = StubSupabaseManager()
        stubSupabase.fetchedGlp1Medications = [
            Glp1Medication(
                id: medicationId,
                userId: userId,
                displayName: "Remote Med",
                genericName: nil,
                drugClass: "GLP-1",
                brand: nil,
                route: nil,
                frequency: nil,
                doseUnit: nil,
                isCompounded: false,
                hkIdentifier: nil,
                startedAt: remoteDate,
                endedAt: nil,
                notes: nil,
                createdAt: remoteDate,
                updatedAt: remoteDate
            )
        ]
        stubSupabase.fetchedGlp1DoseLogs = [
            Glp1DoseLog(
                id: doseLogId,
                userId: userId,
                takenAt: remoteDate,
                medicationId: medicationId,
                doseAmount: 1.0,
                doseUnit: "mg",
                drugClass: "GLP-1",
                brand: nil,
                isCompounded: false,
                supplierType: nil,
                supplierName: nil,
                notes: nil,
                createdAt: remoteDate,
                updatedAt: remoteDate
            )
        ]
        stubSupabase.fetchedDexaResults = [
            DexaResult(
                id: dexaId,
                userId: userId,
                bodyMetricsId: nil,
                externalSource: "BodySpec",
                externalResultId: "remote-result",
                externalUpdateTime: remoteDate,
                scannerModel: nil,
                locationId: nil,
                locationName: nil,
                acquireTime: remoteDate,
                analyzeTime: remoteDate,
                vatMassKg: 1.2,
                vatVolumeCm3: 450,
                resultPdfUrl: nil,
                resultPdfName: nil,
                createdAt: remoteDate,
                updatedAt: remoteDate
            )
        ]

        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.pullSupplementalRemoteData(userId: userId)

        let medicationCreatedAt = await coreData.fetchGlp1Medications(for: userId).first?.createdAt
        XCTAssertEqual(medicationCreatedAt?.timeIntervalSince(remoteDate) ?? 0, 0, accuracy: 0.001)

        let doseLogCreatedAt = await coreData.fetchGlp1DoseLogs(for: userId).first?.createdAt
        XCTAssertEqual(doseLogCreatedAt?.timeIntervalSince(remoteDate) ?? 0, 0, accuracy: 0.001)

        let dexaCreatedAt = await coreData.fetchDexaResults(for: userId, limit: 1).first?.createdAt
        XCTAssertEqual(dexaCreatedAt?.timeIntervalSince(remoteDate) ?? 0, 0, accuracy: 0.001)
    }

    func testHasDexaResult_MatchesExternalResultIdAndSourceCaseInsensitively() async throws {
        let coreData = CoreDataManager.shared
        let userId = "sync_test_user_has_dexa_result_\(UUID().uuidString)"
        let resultId = "bodyspec-result-\(UUID().uuidString)"
        let now = Date()

        coreData.saveDexaResults([
            DexaResult(
                id: UUID().uuidString,
                userId: userId,
                bodyMetricsId: nil,
                externalSource: "BodySpec",
                externalResultId: resultId,
                externalUpdateTime: now,
                scannerModel: nil,
                locationId: nil,
                locationName: nil,
                acquireTime: now,
                analyzeTime: now,
                vatMassKg: 1.3,
                vatVolumeCm3: 420,
                resultPdfUrl: nil,
                resultPdfName: nil,
                createdAt: now,
                updatedAt: now
            )
        ], userId: userId, markAsSynced: false)

        XCTAssertTrue(await coreData.hasDexaResult(
            for: userId,
            externalSource: "bodyspec",
            externalResultId: resultId
        ))
        XCTAssertFalse(await coreData.hasDexaResult(
            for: userId,
            externalSource: "bodyspec",
            externalResultId: "missing-\(UUID().uuidString)"
        ))
    }

    func testProfileHeightStorage_ConvertsCentimetersToMatchingStoredUnit() {
        XCTAssertEqual(
            ProfileHeightStorage.storedHeightValue(heightCm: 177.8, preferredUnit: "cm"),
            177.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ProfileHeightStorage.storedHeightValue(heightCm: 177.8, preferredUnit: "in"),
            70.0,
            accuracy: 0.001
        )
    }

    func testProfileHeightStorage_NormalizesStoredHeightBackToCentimeters() {
        XCTAssertEqual(
            ProfileHeightStorage.heightCentimeters(storedHeight: 177.8, preferredUnit: "cm"),
            177.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ProfileHeightStorage.heightCentimeters(storedHeight: 70.0, preferredUnit: "in"),
            177.8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ProfileHeightStorage.heightCentimeters(storedHeight: 177.8, preferredUnit: "in"),
            177.8,
            accuracy: 0.001
        )
    }

    func testOnboardingProfileUpdateBuilder_UsesMatchingImperialHeightValue() {
        var bodyScoreInput = BodyScoreInput()
        bodyScoreInput.sex = .male
        bodyScoreInput.height = HeightMeasurement(value: 177.8, unit: .centimeters)

        let updates = OnboardingProfileUpdateBuilder.buildUpdates(
            bodyScoreInput: bodyScoreInput,
            heightUnit: .inches
        )

        XCTAssertEqual(updates["heightUnit"] as? String, "in")
        let height = try? XCTUnwrap(updates["height"] as? Double)
        XCTAssertEqual(height ?? 0, 70.0, accuracy: 0.001)
    }

    func testNormalizedProfilePayload_ConvertsCamelCaseKeysToSupabaseFields() {
        let dateOfBirth = Date(timeIntervalSince1970: 1_234_567)
        let payload: [String: Any] = [
            "id": "user_123",
            "name": "Taylor User",
            "dateOfBirth": dateOfBirth,
            "height": 70.0,
            "heightUnit": "in",
            "activityLevel": "active",
            "goalWeight": 145.0,
            "goal_weight_unit": "lbs",
            "onboardingCompleted": true
        ]

        let normalized = SupabaseManager.normalizedProfilePayload(payload)

        XCTAssertEqual(normalized["id"] as? String, "user_123")
        XCTAssertEqual(normalized["full_name"] as? String, "Taylor User")
        XCTAssertEqual(normalized["height_unit"] as? String, "in")
        XCTAssertEqual(normalized["activity_level"] as? String, "active")
        XCTAssertEqual(normalized["goal_weight"] as? Double, 145.0, accuracy: 0.001)
        XCTAssertEqual(normalized["goal_weight_unit"] as? String, "lbs")
        XCTAssertEqual(normalized["onboarding_completed"] as? Bool, true)
        XCTAssertEqual(normalized["date_of_birth"] as? Date, dateOfBirth)
        XCTAssertNil(normalized["name"])
        XCTAssertNil(normalized["dateOfBirth"])
        XCTAssertNil(normalized["heightUnit"])
        XCTAssertNil(normalized["activityLevel"])
        XCTAssertNil(normalized["goalWeight"])
        XCTAssertNil(normalized["onboardingCompleted"])
    }

    func testProfileUpdateMerge_UpdatesLocalUserAndPreservesExistingProfileFields() {
        let existingProfile = UserProfile(
            id: "user_123",
            email: "taylor@example.com",
            username: "taylor",
            fullName: "Taylor User",
            dateOfBirth: nil,
            height: 165.0,
            heightUnit: "cm",
            gender: "Female",
            activityLevel: "moderate",
            goalWeight: 140.0,
            goalWeightUnit: "lbs",
            onboardingCompleted: false
        )
        let user = User(
            id: "user_123",
            email: "taylor@example.com",
            name: "Taylor User",
            avatarUrl: nil,
            profile: existingProfile,
            onboardingCompleted: false
        )
        let dateOfBirth = Date(timeIntervalSince1970: 2_345_678)

        let updatedUser = ProfileUpdateMerge.updatedUser(user, updates: [
            "dateOfBirth": dateOfBirth,
            "height": 70.0,
            "heightUnit": "in",
            "onboardingCompleted": true
        ])

        XCTAssertEqual(updatedUser.profile?.fullName, "Taylor User")
        XCTAssertEqual(updatedUser.profile?.dateOfBirth, dateOfBirth)
        XCTAssertEqual(updatedUser.profile?.height, 70.0, accuracy: 0.001)
        XCTAssertEqual(updatedUser.profile?.heightUnit, "in")
        XCTAssertEqual(updatedUser.profile?.goalWeight, 140.0, accuracy: 0.001)
        XCTAssertEqual(updatedUser.profile?.goalWeightUnit, "lbs")
        XCTAssertEqual(updatedUser.profile?.activityLevel, "moderate")
        XCTAssertEqual(updatedUser.profile?.onboardingCompleted, true)
        XCTAssertTrue(updatedUser.onboardingCompleted)
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
        let manager = RealtimeSyncManager(
            coreDataManager: coreData,
            authManager: AuthManager.shared,
            supabaseManager: stubSupabase
        )

        try await manager.syncLocalChanges(token: "test-token")

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
        let unsyncedDexa = await coreData.fetchUnsyncedDexaResults()
        let unsyncedForUser = unsyncedDexa.filter { $0.userId == userId }
        XCTAssertTrue(unsyncedForUser.isEmpty)
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

final class MockHealthSyncCoordinator: HealthSyncCoordinating {
    private(set) var didCallBootstrapIfNeeded = false
    private(set) var lastBootstrapSyncEnabled: Bool?

    private(set) var didCallResetForCurrentUser = false
    private(set) var didCallConfigureWeightOnly = false
    private(set) var didCallConfigureWeightAndSteps = false
    private(set) var didCallWarmUpAfterLogin = false
    private(set) var didCallPerformInitialConnectSync = false
    private(set) var didCallRunDeferredOnboardingWeightSync = false
    private(set) var didCallSyncWeightFromHealthKit = false
    private(set) var didCallSyncStepsFromHealthKit = false
    private(set) var didCallForceFullHealthKitSync = false

    var performInitialConnectSyncError: Error?
    var syncWeightError: Error?
    var syncStepsError: Error?

    func bootstrapIfNeeded(syncEnabled: Bool) {
        didCallBootstrapIfNeeded = true
        lastBootstrapSyncEnabled = syncEnabled
    }

    func resetForCurrentUser() async {
        didCallResetForCurrentUser = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        didCallConfigureWeightOnly = true
    }

    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {
        didCallConfigureWeightAndSteps = true
    }

    func warmUpAfterLoginIfNeeded() async {
        didCallWarmUpAfterLogin = true
    }

    func performInitialConnectSync() async throws {
        didCallPerformInitialConnectSync = true
        if let error = performInitialConnectSyncError {
            throw error
        }
    }

    func runDeferredOnboardingWeightSync() async {
        didCallRunDeferredOnboardingWeightSync = true
    }

    func syncWeightFromHealthKit() async throws {
        didCallSyncWeightFromHealthKit = true
        if let error = syncWeightError {
            throw error
        }
    }

    func syncStepsFromHealthKit() async throws {
        didCallSyncStepsFromHealthKit = true
        if let error = syncStepsError {
            throw error
        }
    }

    func forceFullHealthKitSync() async {
        didCallForceFullHealthKitSync = true
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

final class GlobalTimelineServiceCoverageTests: XCTestCase {
    func testWeeklyBucketsAreNotCappedAtFourWeeks() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let anchorDate = Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let metrics = (0..<6).map { weekOffset in
            Self.makeMetric(
                id: "week-\(weekOffset)",
                date: Self.calendar.date(byAdding: .day, value: -(weekOffset * 7), to: anchorDate)!,
                weight: 180 - Double(weekOffset),
                weightUnit: "lbs"
            )
        }

        let buckets = service.makeBuckets(for: .week, metrics: metrics)

        XCTAssertEqual(buckets.count, 6)
    }

    func testMonthlyBucketsAggregateAcrossMonthsAndNormalizeWeightUnits() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let metrics = [
            Self.makeMetric(
                id: "jan-1",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!,
                weight: 80,
                weightUnit: "kg",
                bodyFatPercentage: 20
            ),
            Self.makeMetric(
                id: "jan-2",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!,
                weight: 82,
                weightUnit: "kg",
                bodyFatPercentage: 19
            ),
            Self.makeMetric(
                id: "feb-1",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!,
                weight: 180,
                weightUnit: "lbs",
                bodyFatPercentage: 18
            ),
            Self.makeMetric(
                id: "mar-photo",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
                photoUrl: "https://example.com/photo.jpg"
            )
        ]

        let buckets = service.makeBuckets(for: .month, metrics: metrics)

        XCTAssertEqual(buckets.map(\.id), ["2026-01", "2026-02", "2026-03"])
        XCTAssertEqual(buckets[0].metrics.weight.presence, .present)
        XCTAssertEqual(buckets[0].metrics.weight.value ?? 0, 178.6, accuracy: 0.2)
        XCTAssertTrue(buckets[2].metrics.hasPhotosInRange)
        XCTAssertEqual(buckets[2].metrics.canonicalPhotoId, "https://example.com/photo.jpg")
    }

    func testYearlyBucketsAggregateAcrossYears() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let metrics = [
            Self.makeMetric(
                id: "2024",
                date: Self.calendar.date(from: DateComponents(year: 2024, month: 6, day: 1))!,
                weight: 78,
                weightUnit: "kg",
                bodyFatPercentage: 18,
                photoUrl: "https://example.com/2024.jpg"
            ),
            Self.makeMetric(
                id: "2025",
                date: Self.calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!,
                weight: 80,
                weightUnit: "kg",
                bodyFatPercentage: 17
            ),
            Self.makeMetric(
                id: "2026",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
                weight: 82,
                weightUnit: "kg",
                bodyFatPercentage: 16
            )
        ]

        let buckets = service.makeBuckets(for: .year, metrics: metrics)

        XCTAssertEqual(buckets.map(\.id), ["2024", "2025", "2026"])
        XCTAssertEqual(buckets[0].metrics.canonicalPhotoId, "https://example.com/2024.jpg")
        XCTAssertEqual(buckets[2].metrics.bodyFat.value ?? 0, 16, accuracy: 0.01)
    }

    func testWeeklyBucketsIncludeStepOnlyWeeks() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let dailyMetrics = [
            Self.makeDailyMetric(
                id: "steps-1",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
                steps: 8_000
            ),
            Self.makeDailyMetric(
                id: "steps-2",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!,
                steps: 10_000
            ),
            Self.makeDailyMetric(
                id: "steps-3",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 11))!,
                steps: 12_000
            )
        ]

        let buckets = service.makeBuckets(
            for: .week,
            input: GlobalTimelineService.BuildInput(
                bodyMetrics: [],
                dailyMetrics: dailyMetrics
            )
        )

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].metrics.steps.value ?? 0, 10_000, accuracy: 0.01)
        XCTAssertEqual(buckets[0].metrics.steps.presence, .estimated)
    }

    func testMonthlyBucketsPopulateFFMIAndBodyScoreFromContext() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let metrics = [
            Self.makeMetric(
                id: "mar-1",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!,
                weight: 180,
                weightUnit: "lbs",
                bodyFatPercentage: 18
            ),
            Self.makeMetric(
                id: "mar-2",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 18))!,
                weight: 178,
                weightUnit: "lbs",
                bodyFatPercentage: 17
            )
        ]

        let buckets = service.makeBuckets(
            for: .month,
            input: GlobalTimelineService.BuildInput(
                bodyMetrics: metrics,
                bodyScoreContext: Self.makeBodyScoreContext()
            )
        )

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].metrics.ffmi.presence, .present)
        XCTAssertNotNil(buckets[0].metrics.ffmi.value)
        XCTAssertNotNil(buckets[0].metrics.bodyScore)
        XCTAssertEqual(buckets[0].metrics.bodyScoreCompleteness, .full)
    }

    func testMixedInputsDoNotAppendTrailingStepOnlyBuckets() {
        let service = GlobalTimelineService(calendar: Self.calendar)
        let metrics = [
            Self.makeMetric(
                id: "body",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!,
                weight: 180,
                weightUnit: "lbs"
            )
        ]
        let dailyMetrics = [
            Self.makeDailyMetric(
                id: "steps-late",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 24))!,
                steps: 10_000
            )
        ]

        let buckets = service.makeBuckets(
            for: .week,
            input: GlobalTimelineService.BuildInput(
                bodyMetrics: metrics,
                dailyMetrics: dailyMetrics
            )
        )

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].id, "2026-W10")
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double? = nil,
        weightUnit: String? = nil,
        bodyFatPercentage: Double? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }

    private static func makeDailyMetric(
        id: String,
        date: Date,
        steps: Int
    ) -> DailyMetrics {
        DailyMetrics(
            id: id,
            userId: "user",
            date: date,
            steps: steps,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private static func makeBodyScoreContext() -> GlobalTimelineService.BodyScoreContext {
        GlobalTimelineService.BodyScoreContext(
            sex: .male,
            birthYear: 1990,
            heightCm: 180,
            measurementPreference: .imperial
        )
    }
}

final class MetricsFormatterTests: XCTestCase {
    func testFormatWeightUsesSingleDecimalPlaceForBothUnits() {
        XCTAssertEqual(MetricsFormatter.formatWeight(value: 80, unit: "kg"), "80.0")
        XCTAssertEqual(MetricsFormatter.formatWeight(value: 180.44, unit: "lbs"), "180.4")
    }

    func testConvertWeightConvertsBetweenKgAndLbs() {
        XCTAssertEqual(
            MetricsFormatter.convertWeight(value: 100, from: "kg", to: "lbs"),
            220.462,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MetricsFormatter.convertWeight(value: 220.462, from: "lbs", to: "kg"),
            100,
            accuracy: 0.001
        )
    }

    func testTrendDirectionTreatsTinyDeltasAsFlat() {
        XCTAssertEqual(MetricsFormatter.trendDirection(delta: 1.0), .up)
        XCTAssertEqual(MetricsFormatter.trendDirection(delta: -1.0), .down)
        XCTAssertEqual(MetricsFormatter.trendDirection(delta: 0.0001), .flat)
    }
}

final class BodyMetricsValidationTests: XCTestCase {
    func testInitializerRejectsInvalidWeightUnitAndOutOfRangeValues() {
        let metrics = Self.makeMetric(
            weight: 220,
            weightUnit: "stone",
            bodyFatPercentage: 80,
            waistCm: -5,
            hipCm: 0
        )

        XCTAssertNil(metrics.weight)
        XCTAssertNil(metrics.weightUnit)
        XCTAssertNil(metrics.bodyFatPercentage)
        XCTAssertNil(metrics.waistCm)
        XCTAssertNil(metrics.hipCm)
    }

    func testInitializerRejectsWeightOverOneThousandPoundsEquivalent() {
        let metrics = Self.makeMetric(weight: 500, weightUnit: "kg")

        XCTAssertNil(metrics.weight)
        XCTAssertEqual(metrics.weightUnit, "kg")
    }

    func testDecodingAppliesValidationRules() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = """
        {
          "id": "decoded",
          "user_id": "user",
          "date": "2026-03-10T00:00:00Z",
          "weight": 200,
          "weight_unit": "stone",
          "body_fat_percentage": 72,
          "waist_circumference": -1,
          "hip_circumference": 40,
          "created_at": "2026-03-10T00:00:00Z",
          "updated_at": "2026-03-10T00:00:00Z"
        }
        """.data(using: .utf8)!

        let metrics = try decoder.decode(BodyMetrics.self, from: data)

        XCTAssertNil(metrics.weight)
        XCTAssertNil(metrics.weightUnit)
        XCTAssertNil(metrics.bodyFatPercentage)
        XCTAssertNil(metrics.waistCm)
        XCTAssertEqual(metrics.hipCm, 40.0)
    }

    private static func makeMetric(
        weight: Double?,
        weightUnit: String?,
        bodyFatPercentage: Double?,
        waistCm: Double?,
        hipCm: Double?
    ) -> BodyMetrics {
        let now = Date()
        return BodyMetrics(
            id: "metric",
            userId: "user",
            date: now,
            weight: weight,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            waistCm: waistCm,
            hipCm: hipCm,
            waistUnit: "cm",
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: now,
            updatedAt: now
        )
    }
}

final class GlobalTimelineHeaderPresentationTests: XCTestCase {
    func testVisibleZonesExcludeEmptyBucketGroups() {
        let weeklyBucket = Self.makeBucket(
            id: "2026-W11",
            scale: .week,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        )

        let visibleZones = GlobalTimelineHeaderPresentation.visibleZones(
            weeklyBuckets: [weeklyBucket],
            monthlyBuckets: [],
            yearlyBuckets: []
        )

        XCTAssertEqual(visibleZones.map(\.scale), [.week])
    }

    func testCurrentLabelUsesSelectedWeekBucketStartDate() {
        let weeklyBucket = Self.makeBucket(
            id: "2026-W11",
            scale: .week,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        )
        let cursor = GlobalTimelineCursor(
            date: weeklyBucket.endDate,
            scale: .week,
            bucketId: weeklyBucket.id
        )

        let label = GlobalTimelineHeaderPresentation.currentLabel(
            cursor: cursor,
            weeklyBuckets: [weeklyBucket],
            monthlyBuckets: [],
            yearlyBuckets: [],
            calendar: Self.calendar
        )

        XCTAssertEqual(label, "Week of Mar 9")
    }

    func testCurrentLabelUsesSelectedMonthBucketStartDate() {
        let monthlyBucket = Self.makeBucket(
            id: "2026-03",
            scale: .month,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        )
        let cursor = GlobalTimelineCursor(
            date: monthlyBucket.endDate,
            scale: .month,
            bucketId: monthlyBucket.id
        )

        let label = GlobalTimelineHeaderPresentation.currentLabel(
            cursor: cursor,
            weeklyBuckets: [],
            monthlyBuckets: [monthlyBucket],
            yearlyBuckets: [],
            calendar: Self.calendar
        )

        XCTAssertEqual(label, "March 2026")
    }

    func testCurrentLabelUsesSelectedYearBucketStartDate() {
        let yearlyBucket = Self.makeBucket(
            id: "2026",
            scale: .year,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        )
        let cursor = GlobalTimelineCursor(
            date: yearlyBucket.endDate,
            scale: .year,
            bucketId: yearlyBucket.id
        )

        let label = GlobalTimelineHeaderPresentation.currentLabel(
            cursor: cursor,
            weeklyBuckets: [],
            monthlyBuckets: [],
            yearlyBuckets: [yearlyBucket],
            calendar: Self.calendar
        )

        XCTAssertEqual(label, "2026")
    }

    func testCurrentLabelShowsEmptyStateCopyWhenNoBucketsExist() {
        let label = GlobalTimelineHeaderPresentation.currentLabel(
            cursor: nil,
            weeklyBuckets: [],
            monthlyBuckets: [],
            yearlyBuckets: [],
            calendar: Self.calendar
        )

        XCTAssertEqual(label, GlobalTimelineHeaderPresentation.emptyTimelineLabel)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeBucket(
        id: String,
        scale: GlobalTimelineScale,
        startDate: Date,
        endDate: Date
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: id,
            scale: scale,
            startDate: startDate,
            endDate: endDate,
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(value: nil, presence: .missing),
                ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }
}

@MainActor
final class GlobalTimelineStoreTests: XCTestCase {
    func testUpdateRecomputesBucketSnapshotsWhenBodyScoreContextChanges() {
        let store = GlobalTimelineStore(service: GlobalTimelineService(calendar: Self.calendar))
        let metrics = [
            Self.makeMetric(
                id: "mar",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!,
                weight: 180,
                weightUnit: "lbs",
                bodyFatPercentage: 18
            )
        ]

        store.update(
            bodyMetrics: metrics,
            dailyMetrics: [],
            bodyScoreContext: nil
        )

        let initialBucket = store.weeklyBuckets.last
        XCTAssertNil(initialBucket?.metrics.bodyScore)
        XCTAssertEqual(initialBucket?.metrics.bodyScoreCompleteness, .none)

        store.update(
            bodyMetrics: metrics,
            dailyMetrics: [],
            bodyScoreContext: Self.makeBodyScoreContext()
        )

        let updatedBucket = store.weeklyBuckets.last
        XCTAssertNotNil(updatedBucket?.metrics.bodyScore)
        XCTAssertEqual(updatedBucket?.metrics.bodyScoreCompleteness, .full)
    }

    func testPreviousBucketReturnsPriorBucketAtSameScale() {
        let store = GlobalTimelineStore(service: GlobalTimelineService(calendar: Self.calendar))
        store.updateMetrics([
            Self.makeMetric(
                id: "jan",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!,
                weight: 80,
                weightUnit: "kg"
            ),
            Self.makeMetric(
                id: "feb",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!,
                weight: 81,
                weightUnit: "kg"
            ),
            Self.makeMetric(
                id: "mar",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!,
                weight: 82,
                weightUnit: "kg"
            )
        ])

        let marchCursor = GlobalTimelineCursor(
            date: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!,
            scale: .month,
            bucketId: "2026-03"
        )

        XCTAssertEqual(store.previousBucket(for: marchCursor)?.id, "2026-02")
    }

    func testPreviousBucketReturnsNilForFirstBucket() {
        let store = GlobalTimelineStore(service: GlobalTimelineService(calendar: Self.calendar))
        store.updateMetrics([
            Self.makeMetric(
                id: "week-a",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!,
                weight: 180,
                weightUnit: "lbs"
            ),
            Self.makeMetric(
                id: "week-b",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 22))!,
                weight: 179,
                weightUnit: "lbs"
            )
        ])

        let firstWeekCursor = GlobalTimelineCursor(
            date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!,
            scale: .week,
            bucketId: "2026-W11"
        )

        XCTAssertNil(store.previousBucket(for: firstWeekCursor))
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double? = nil,
        weightUnit: String? = nil,
        bodyFatPercentage: Double? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage,
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

    private static func makeBodyScoreContext() -> GlobalTimelineService.BodyScoreContext {
        GlobalTimelineService.BodyScoreContext(
            sex: .male,
            birthYear: 1990,
            heightCm: 180,
            measurementPreference: .imperial
        )
    }
}

final class GlobalTimelineSelectionResolverTests: XCTestCase {
    func testCursorPrefersWeeklyBucketForMetricDate() {
        let metricDate = Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let weeklyBucket = Self.makeBucket(
            id: "2026-W11",
            scale: .week,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        )
        let monthlyBucket = Self.makeBucket(
            id: "2026-03",
            scale: .month,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        )

        let cursor = GlobalTimelineSelectionResolver.cursor(
            for: metricDate,
            weeklyBuckets: [weeklyBucket],
            monthlyBuckets: [monthlyBucket],
            yearlyBuckets: []
        )

        XCTAssertEqual(cursor?.scale, .week)
        XCTAssertEqual(cursor?.bucketId, "2026-W11")
    }

    func testMetricIndexPrefersCanonicalPhotoMatchWithinBucket() {
        let cursor = GlobalTimelineCursor(
            date: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!,
            scale: .month,
            bucketId: "2026-03"
        )
        let monthlyBucket = Self.makeBucket(
            id: "2026-03",
            scale: .month,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!,
            canonicalPhotoId: "https://example.com/match.jpg"
        )
        let metrics = [
            Self.makeMetric(
                id: "newest",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 28))!,
                photoUrl: "https://example.com/other.jpg"
            ),
            Self.makeMetric(
                id: "match",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!,
                photoUrl: "https://example.com/match.jpg"
            )
        ]

        let resolvedIndex = GlobalTimelineSelectionResolver.metricIndex(
            for: cursor,
            metrics: metrics,
            weeklyBuckets: [],
            monthlyBuckets: [monthlyBucket],
            yearlyBuckets: []
        )

        XCTAssertEqual(resolvedIndex, 1)
    }

    func testMetricIndexFallsBackToMetricClosestToBucketMidpoint() {
        let cursor = GlobalTimelineCursor(
            date: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!,
            scale: .month,
            bucketId: "2026-03"
        )
        let monthlyBucket = Self.makeBucket(
            id: "2026-03",
            scale: .month,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        )
        let metrics = [
            Self.makeMetric(
                id: "late",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 28))!
            ),
            Self.makeMetric(
                id: "mid",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!
            ),
            Self.makeMetric(
                id: "early",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
            )
        ]

        let resolvedIndex = GlobalTimelineSelectionResolver.metricIndex(
            for: cursor,
            metrics: metrics,
            weeklyBuckets: [],
            monthlyBuckets: [monthlyBucket],
            yearlyBuckets: []
        )

        XCTAssertEqual(resolvedIndex, 1)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeBucket(
        id: String,
        scale: GlobalTimelineScale,
        startDate: Date,
        endDate: Date,
        canonicalPhotoId: String? = nil
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: id,
            scale: scale,
            startDate: startDate,
            endDate: endDate,
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(value: nil, presence: .missing),
                ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: canonicalPhotoId,
                hasPhotosInRange: canonicalPhotoId != nil,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }

    private static func makeMetric(
        id: String,
        date: Date,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

final class GlobalTimelineMetricAdapterTests: XCTestCase {
    func testDisplayWeightValueConvertsFromMostRecentActualWeightUnit() {
        let metrics = [
            Self.makeMetric(
                id: "older",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!,
                weight: 80,
                weightUnit: "kg"
            ),
            Self.makeMetric(
                id: "newer",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
                weight: 180,
                weightUnit: "lbs"
            )
        ]
        let snapshot = GlobalTimelineMetricValue(value: 180, presence: .present)

        let displayValue = GlobalTimelineMetricAdapter.displayWeightValue(
            from: snapshot,
            metrics: metrics,
            preferredUnit: "kg"
        )

        XCTAssertEqual(displayValue ?? 0, 81.6, accuracy: 0.2)
    }

    func testDeltaReturnsDifferenceWhenBothValuesExist() {
        let current = GlobalTimelineMetricValue(value: 180, presence: .present)
        let previous = GlobalTimelineMetricValue(value: 183, presence: .present)

        XCTAssertEqual(
            GlobalTimelineMetricAdapter.delta(current: current, previous: previous),
            -3
        )
    }

    func testDisplayWeightDeltaConvertsToPreferredUnitBeforeSubtracting() {
        let metrics = [
            Self.makeMetric(
                id: "older",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!,
                weight: 180,
                weightUnit: "lbs"
            )
        ]
        let current = GlobalTimelineMetricValue(value: 180, presence: .present)
        let previous = GlobalTimelineMetricValue(value: 176, presence: .present)

        let delta = GlobalTimelineMetricAdapter.displayWeightDelta(
            current: current,
            previous: previous,
            metrics: metrics,
            preferredUnit: "kg"
        )

        XCTAssertEqual(delta ?? 0, 1.8, accuracy: 0.2)
    }

    func testDisplayStepsValueRoundsSnapshotValue() {
        let snapshot = GlobalTimelineMetricValue(value: 10_249.6, presence: .present)

        XCTAssertEqual(
            GlobalTimelineMetricAdapter.displayStepsValue(from: snapshot),
            10_250
        )
    }

    func testComparisonCaptionMatchesBucketScale() {
        XCTAssertEqual(GlobalTimelineMetricAdapter.comparisonCaption(for: .week), "last week")
        XCTAssertEqual(GlobalTimelineMetricAdapter.comparisonCaption(for: .month), "last month")
        XCTAssertEqual(GlobalTimelineMetricAdapter.comparisonCaption(for: .year), "last year")
    }

    func testBucketDateTextMatchesScale() {
        let weekBucket = Self.makeBucket(
            id: "2026-W11",
            scale: .week,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!
        )
        let monthBucket = Self.makeBucket(
            id: "2026-03",
            scale: .month,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        )
        let yearBucket = Self.makeBucket(
            id: "2026",
            scale: .year,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        )

        XCTAssertEqual(GlobalTimelineMetricAdapter.bucketDateText(weekBucket), "Week of Mar 9")
        XCTAssertEqual(GlobalTimelineMetricAdapter.bucketDateText(monthBucket), "March 2026")
        XCTAssertEqual(GlobalTimelineMetricAdapter.bucketDateText(yearBucket), "2026")
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double,
        weightUnit: String
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
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

    private static func makeBucket(
        id: String,
        scale: GlobalTimelineScale,
        startDate: Date,
        endDate: Date
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: id,
            scale: scale,
            startDate: startDate,
            endDate: endDate,
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(value: nil, presence: .missing),
                ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }
}

final class DashboardPhotosPresentationTests: XCTestCase {
    func testStandaloneScrubberHiddenWhenGlobalTimelineEnabled() {
        XCTAssertFalse(
            DashboardPhotosPresentation.showsStandaloneScrubber(isGlobalTimelineEnabled: true)
        )
        XCTAssertTrue(
            DashboardPhotosPresentation.showsStandaloneScrubber(isGlobalTimelineEnabled: false)
        )
    }

    func testEmptyStateMessageShownForPhotoLessSelectedBucket() {
        let bucket = Self.makeBucket(hasPhotosInRange: false)

        let message = DashboardPhotosPresentation.emptyStateMessage(
            isGlobalTimelineEnabled: true,
            selectedTimelineBucket: bucket
        )

        XCTAssertEqual(message, DashboardPhotosPresentation.emptyBucketMessage)
    }

    func testEmptyStateMessageHiddenWhenBucketHasPhotosOrGateDisabled() {
        let photoBucket = Self.makeBucket(hasPhotosInRange: true)
        let emptyBucket = Self.makeBucket(hasPhotosInRange: false)

        XCTAssertNil(
            DashboardPhotosPresentation.emptyStateMessage(
                isGlobalTimelineEnabled: true,
                selectedTimelineBucket: photoBucket
            )
        )
        XCTAssertNil(
            DashboardPhotosPresentation.emptyStateMessage(
                isGlobalTimelineEnabled: false,
                selectedTimelineBucket: emptyBucket
            )
        )
    }

    private static func makeBucket(hasPhotosInRange: Bool) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: "2026-03",
            scale: .month,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 86_400),
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(value: nil, presence: .missing),
                ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: hasPhotosInRange ? "photo" : nil,
                hasPhotosInRange: hasPhotosInRange,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }
}

final class DashboardBodyScorePresentationTests: XCTestCase {
    func testDeltaTextFormatsPositiveAndNegativeComparisons() {
        XCTAssertEqual(
            DashboardBodyScorePresentation.deltaText(
                currentScore: 82,
                previousScore: 79,
                comparison: "last month"
            ),
            "+3 last month"
        )
        XCTAssertEqual(
            DashboardBodyScorePresentation.deltaText(
                currentScore: 75,
                previousScore: 79,
                comparison: "last year"
            ),
            "-4 last year"
        )
    }
}

final class DashboardFFMIPresentationTests: XCTestCase {
    func testValueTextUsesSelectedBucketValueWhenPresent() {
        let bucket = Self.makeBucket(ffmiValue: 20.4)

        XCTAssertEqual(
            DashboardFFMIPresentation.valueText(
                selectedTimelineBucket: bucket,
                fallbackValue: "18.9"
            ),
            "20.4"
        )
    }

    func testValueTextShowsMissingWhenSelectedBucketHasNoFFMI() {
        let bucket = Self.makeBucket(ffmiValue: nil)

        XCTAssertEqual(
            DashboardFFMIPresentation.valueText(
                selectedTimelineBucket: bucket,
                fallbackValue: "18.9"
            ),
            "–"
        )
    }

    func testValueTextFallsBackWhenNoSelectedBucketExists() {
        XCTAssertEqual(
            DashboardFFMIPresentation.valueText(
                selectedTimelineBucket: nil,
                fallbackValue: "18.9"
            ),
            "18.9"
        )
    }

    private static func makeBucket(ffmiValue: Double?) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: "2026-03",
            scale: .month,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 86_400),
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(value: nil, presence: .missing),
                ffmi: GlobalTimelineMetricValue(
                    value: ffmiValue,
                    presence: ffmiValue == nil ? .missing : .present
                ),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }
}

final class BodyCompositionMetricsNormalizationTests: XCTestCase {
    func testWeightValueInKilogramsConvertsPounds() {
        let metric = Self.makeMetric(weight: 180, weightUnit: "lbs")

        XCTAssertEqual(
            BodyCompositionMetricsNormalization.weightValueInKilograms(for: metric) ?? 0,
            81.6,
            accuracy: 0.2
        )
    }

    func testMetricsInKilogramsRewritesPoundEntriesToKilograms() {
        let metrics = [
            Self.makeMetric(weight: 180, weightUnit: "lbs"),
            Self.makeMetric(weight: 82, weightUnit: "kg")
        ]

        let normalized = BodyCompositionMetricsNormalization.metricsInKilograms(metrics)

        XCTAssertEqual(normalized[0].weightUnit, "kg")
        XCTAssertEqual(normalized[0].weight ?? 0, 81.6, accuracy: 0.2)
        XCTAssertEqual(normalized[1].weightUnit, "kg")
        XCTAssertEqual(normalized[1].weight ?? 0, 82, accuracy: 0.01)
    }

    private static func makeMetric(weight: Double, weightUnit: String) -> BodyMetrics {
        let now = Date()
        return BodyMetrics(
            id: UUID().uuidString,
            userId: "user",
            date: now,
            weight: weight,
            weightUnit: weightUnit,
            bodyFatPercentage: 18,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: now,
            updatedAt: now
        )
    }
}

final class DashboardMetricCardTrendPresentationTests: XCTestCase {
    func testWeightTrendUsesBucketComparisonWhenAvailable() {
        let metrics = [
            Self.makeMetric(
                id: "older",
                date: Date(timeIntervalSince1970: 0),
                weight: 180,
                weightUnit: "lbs"
            )
        ]
        let currentBucket = Self.makeBucket(
            scale: .month,
            weightValue: 180,
            bodyFatValue: nil,
            ffmiValue: nil
        )
        let previousBucket = Self.makeBucket(
            scale: .month,
            weightValue: 176,
            bodyFatValue: nil,
            ffmiValue: nil
        )

        let trend = DashboardMetricCardTrendPresentation.weightTrend(
            selectedTimelineBucket: currentBucket,
            previousTimelineBucket: previousBucket,
            metrics: metrics,
            preferredUnit: "kg",
            fallbackTrend: nil
        )

        XCTAssertEqual(trend?.caption, "last month")
        Self.assertDirection(trend?.direction, matches: .up)
        XCTAssertEqual(trend?.valueText, "1.8 kg")
    }

    func testMetricTrendUsesBucketDeltaWhenAvailable() {
        let currentBucket = Self.makeBucket(
            scale: .year,
            weightValue: nil,
            bodyFatValue: 18,
            ffmiValue: 20.4
        )
        let previousBucket = Self.makeBucket(
            scale: .year,
            weightValue: nil,
            bodyFatValue: 19,
            ffmiValue: 19.9
        )

        let bodyFatTrend = DashboardMetricCardTrendPresentation.metricTrend(
            current: currentBucket.metrics.bodyFat,
            previous: previousBucket.metrics.bodyFat,
            selectedTimelineBucket: currentBucket,
            unit: "%",
            fallbackTrend: nil
        )
        let ffmiTrend = DashboardMetricCardTrendPresentation.metricTrend(
            current: currentBucket.metrics.ffmi,
            previous: previousBucket.metrics.ffmi,
            selectedTimelineBucket: currentBucket,
            unit: "",
            fallbackTrend: nil
        )

        XCTAssertEqual(bodyFatTrend?.caption, "last year")
        Self.assertDirection(bodyFatTrend?.direction, matches: .down)
        XCTAssertEqual(bodyFatTrend?.valueText, "1%")
        XCTAssertEqual(ffmiTrend?.caption, "last year")
        Self.assertDirection(ffmiTrend?.direction, matches: .up)
        XCTAssertEqual(ffmiTrend?.valueText, "0.5")
    }

    func testMetricTrendFallsBackWhenBucketComparisonUnavailable() {
        let fallbackTrend = MetricSummaryCard.Trend(
            direction: .flat,
            valueText: "No change",
            caption: "1M"
        )

        let trend = DashboardMetricCardTrendPresentation.metricTrend(
            current: GlobalTimelineMetricValue(value: 18, presence: .present),
            previous: GlobalTimelineMetricValue(value: nil, presence: .missing),
            selectedTimelineBucket: Self.makeBucket(
                scale: .month,
                weightValue: nil,
                bodyFatValue: 18,
                ffmiValue: nil
            ),
            unit: "%",
            fallbackTrend: fallbackTrend
        )

        XCTAssertEqual(trend?.caption, "1M")
        Self.assertDirection(trend?.direction, matches: .flat)
        XCTAssertEqual(trend?.valueText, "No change")
    }

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double,
        weightUnit: String
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
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

    private static func makeBucket(
        scale: GlobalTimelineScale,
        weightValue: Double?,
        bodyFatValue: Double?,
        ffmiValue: Double?
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: "bucket-\(scale)",
            scale: scale,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 86_400),
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(
                    value: weightValue,
                    presence: weightValue == nil ? .missing : .present
                ),
                bodyFat: GlobalTimelineMetricValue(
                    value: bodyFatValue,
                    presence: bodyFatValue == nil ? .missing : .present
                ),
                ffmi: GlobalTimelineMetricValue(
                    value: ffmiValue,
                    presence: ffmiValue == nil ? .missing : .present
                ),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }

    private static func assertDirection(
        _ actual: MetricSummaryCard.Trend.Direction?,
        matches expected: MetricSummaryCard.Trend.Direction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.up?, .up), (.down?, .down), (.flat?, .flat):
            return
        default:
            XCTFail("Unexpected direction", file: file, line: line)
        }
    }
}

final class DashboardMetricSparklinePresentationTests: XCTestCase {
    func testTrailingBucketsEndsAtSelectedBucket() {
        let buckets = (1...9).map { index in
            Self.makeBucket(id: "bucket-\(index)", value: Double(index))
        }

        let trailing = DashboardMetricSparklinePresentation.trailingBuckets(
            buckets: buckets,
            currentBucketId: "bucket-8"
        )

        XCTAssertEqual(trailing.map(\.id), [
            "bucket-2",
            "bucket-3",
            "bucket-4",
            "bucket-5",
            "bucket-6",
            "bucket-7",
            "bucket-8"
        ])
    }

    func testPointsCompactsMissingValuesAndReindexes() {
        let buckets = [
            Self.makeBucket(id: "a", value: 10),
            Self.makeBucket(id: "b", value: nil),
            Self.makeBucket(id: "c", value: 30)
        ]

        let points = DashboardMetricSparklinePresentation.points(buckets: buckets) {
            $0.metrics.bodyFat.value
        }

        XCTAssertEqual(points.map(\.index), [0, 1])
        XCTAssertEqual(points.map(\.value), [10, 30])
    }

    func testChartPointsUseBucketStartDatesAndSkipMissingValues() {
        let firstDate = Date(timeIntervalSince1970: 0)
        let secondDate = Date(timeIntervalSince1970: 86_400)
        let buckets = [
            Self.makeBucket(id: "a", startDate: firstDate, value: 10),
            Self.makeBucket(id: "b", startDate: secondDate, value: nil)
        ]

        let points = DashboardMetricSparklinePresentation.chartPoints(buckets: buckets) {
            $0.metrics.bodyFat.value
        }

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.date, firstDate)
        XCTAssertEqual(points.first?.value, 10)
    }

    private static func makeBucket(
        id: String,
        startDate: Date = Date(timeIntervalSince1970: 0),
        value: Double?
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: id,
            scale: .month,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(86_400),
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(value: nil, presence: .missing),
                bodyFat: GlobalTimelineMetricValue(
                    value: value,
                    presence: value == nil ? .missing : .present
                ),
                ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: nil,
                bodyScoreCompleteness: .none
            )
        )
    }
}

final class DashboardMetricBucketHistoryBuilderTests: XCTestCase {
    func testWeightPayloadBuildsMonthlyTimelineEntriesWithYearGrouping() {
        let buckets = [
            Self.makeBucket(
                id: "2026-02",
                scale: .month,
                startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!,
                endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
                weightValue: 176,
                bodyFatValue: 19,
                ffmiValue: nil,
                bodyScore: nil,
                stepsValue: nil
            ),
            Self.makeBucket(
                id: "2026-03",
                scale: .month,
                startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
                endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!,
                weightValue: 180,
                bodyFatValue: 18,
                ffmiValue: nil,
                bodyScore: nil,
                stepsValue: nil
            )
        ]
        let metrics = [
            Self.makeMetric(
                id: "latest-weight-unit",
                date: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!,
                weight: 180,
                weightUnit: "lbs"
            )
        ]

        let payload = DashboardMetricBucketHistoryBuilder.payload(
            for: .weight,
            buckets: buckets,
            metrics: metrics,
            preferredUnit: "kg"
        )

        let entries = try XCTUnwrap(payload?.entries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.displayDateText, "March 2026")
        XCTAssertEqual(entries.last?.sectionKeyOverride, "timeline-year-2026")
        XCTAssertEqual(entries.last?.sectionTitleOverride, "2026")
        XCTAssertEqual(entries.last?.source, .integration(id: "Timeline"))
        XCTAssertFalse(entries.last?.isDeletable ?? true)
        XCTAssertEqual(entries.last?.primaryValue ?? 0, 81.6, accuracy: 0.2)
        XCTAssertEqual(entries.last?.secondaryValue ?? 0, 18, accuracy: 0.001)
    }

    func testBodyScorePayloadUsesSharedYearlySectionMetadata() {
        let buckets = [
            Self.makeBucket(
                id: "2025",
                scale: .year,
                startDate: Self.calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!,
                endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
                weightValue: nil,
                bodyFatValue: nil,
                ffmiValue: nil,
                bodyScore: 78,
                stepsValue: nil
            ),
            Self.makeBucket(
                id: "2026",
                scale: .year,
                startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
                endDate: Self.calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!,
                weightValue: nil,
                bodyFatValue: nil,
                ffmiValue: nil,
                bodyScore: 82,
                stepsValue: nil
            )
        ]

        let payload = DashboardMetricBucketHistoryBuilder.payload(
            for: .bodyScore,
            buckets: buckets,
            metrics: [],
            preferredUnit: "kg"
        )

        let entries = try XCTUnwrap(payload?.entries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.displayDateText, "2025")
        XCTAssertEqual(entries.first?.sectionKeyOverride, "timeline-years")
        XCTAssertEqual(entries.first?.sectionTitleOverride, "By year")
        XCTAssertFalse(entries.first?.isDeletable ?? true)
    }

    func testMetadataLeavesWeeklyBucketsOnDefaultMonthGrouping() {
        let bucket = Self.makeBucket(
            id: "2026-W11",
            scale: .week,
            startDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!,
            endDate: Self.calendar.date(from: DateComponents(year: 2026, month: 3, day: 16))!,
            weightValue: nil,
            bodyFatValue: nil,
            ffmiValue: nil,
            bodyScore: nil,
            stepsValue: 10_000
        )

        let metadata = DashboardMetricBucketHistoryBuilder.metadata(for: bucket)

        XCTAssertEqual(metadata.displayDateText, "Week of Mar 9")
        XCTAssertNil(metadata.sectionKey)
        XCTAssertNil(metadata.sectionTitle)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double,
        weightUnit: String
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
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

    private static func makeBucket(
        id: String,
        scale: GlobalTimelineScale,
        startDate: Date,
        endDate: Date,
        weightValue: Double?,
        bodyFatValue: Double?,
        ffmiValue: Double?,
        bodyScore: Int?,
        stepsValue: Double?
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: id,
            scale: scale,
            startDate: startDate,
            endDate: endDate,
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(
                    value: weightValue,
                    presence: weightValue == nil ? .missing : .present
                ),
                bodyFat: GlobalTimelineMetricValue(
                    value: bodyFatValue,
                    presence: bodyFatValue == nil ? .missing : .present
                ),
                ffmi: GlobalTimelineMetricValue(
                    value: ffmiValue,
                    presence: ffmiValue == nil ? .missing : .present
                ),
                steps: GlobalTimelineMetricValue(
                    value: stepsValue,
                    presence: stepsValue == nil ? .missing : .present
                ),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: bodyScore,
                bodyScoreCompleteness: bodyScore == nil ? .none : .full
            )
        )
    }
}

final class DetailChartTimelinePresentationTests: XCTestCase {
    func testAvailableTimeRangesTrimForMonthlyAndYearlyBuckets() {
        XCTAssertEqual(
            DetailChartTimelinePresentation.availableTimeRanges(for: .month),
            [.month1, .month3, .month6, .year1, .all]
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.availableTimeRanges(for: .year),
            [.year1, .all]
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.availableTimeRanges(for: .week),
            TimeRange.allCases
        )
    }

    func testFallbackTimeRangeMatchesScale() {
        XCTAssertEqual(DetailChartTimelinePresentation.fallbackTimeRange(for: .month), .month1)
        XCTAssertEqual(DetailChartTimelinePresentation.fallbackTimeRange(for: .year), .year1)
        XCTAssertEqual(DetailChartTimelinePresentation.fallbackTimeRange(for: nil), .month1)
    }

    func testXAxisModeSwitchesBetweenRawAndBucketSemantics() {
        XCTAssertEqual(
            DetailChartTimelinePresentation.xAxisMode(timelineScale: nil, selectedTimeRange: .week1),
            .rawWeek
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.xAxisMode(timelineScale: nil, selectedTimeRange: .month6),
            .rawAuto(desiredCount: 6)
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.xAxisMode(timelineScale: .week, selectedTimeRange: .month1),
            .bucketWeek
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.xAxisMode(timelineScale: .month, selectedTimeRange: .month3),
            .bucketMonth
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.xAxisMode(timelineScale: .year, selectedTimeRange: .all),
            .bucketYear
        )
    }

    func testSmoothingWindowShrinksForBucketScales() {
        XCTAssertEqual(DetailChartTimelinePresentation.smoothingWindowSize(for: nil), 7)
        XCTAssertEqual(DetailChartTimelinePresentation.smoothingWindowSize(for: .week), 4)
        XCTAssertEqual(DetailChartTimelinePresentation.smoothingWindowSize(for: .month), 3)
        XCTAssertEqual(DetailChartTimelinePresentation.smoothingWindowSize(for: .year), 1)
        XCTAssertTrue(DetailChartTimelinePresentation.showsChartModeToggle(for: .month))
        XCTAssertFalse(DetailChartTimelinePresentation.showsChartModeToggle(for: .year))
    }

    func testStatTitlesBecomeBucketSpecific() {
        XCTAssertEqual(
            DetailChartTimelinePresentation.averageTitle(selectedTimeRange: .month3, timelineScale: nil),
            "Avg (3M)"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.averageTitle(selectedTimeRange: .month3, timelineScale: .month),
            "Avg (monthly)"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.averageTitle(selectedTimeRange: .all, timelineScale: .year),
            "Avg (yearly)"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.boundsTitles(for: .week).low,
            "Lowest week"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.boundsTitles(for: .month).high,
            "Highest month"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.boundsTitles(for: nil).high,
            "High"
        )
    }

    func testCalloutContextLabelIdentifiesBucketAggregates() {
        XCTAssertEqual(
            DetailChartTimelinePresentation.calloutContextLabel(for: .week),
            "Weekly summary"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.calloutContextLabel(for: .month),
            "Monthly summary"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.calloutContextLabel(for: .year),
            "Yearly summary"
        )
        XCTAssertNil(DetailChartTimelinePresentation.calloutContextLabel(for: nil))
    }

    func testChangeCaptionTextBecomesBucketAwareForFallbackSeriesDelta() {
        XCTAssertEqual(
            DetailChartTimelinePresentation.changeCaptionText(selectedTimeRange: .month3, timelineScale: nil),
            "Change vs 3 months ago"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.changeCaptionText(selectedTimeRange: .month3, timelineScale: .month),
            "Change across months"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.changeCaptionText(selectedTimeRange: .all, timelineScale: .year),
            "Change across years"
        )
    }

    func testPointDateTextUsesBucketFriendlyFormatting() {
        let formatter = ISO8601DateFormatter()
        let weekDate = formatter.date(from: "2026-03-09T00:00:00Z")!
        let monthDate = formatter.date(from: "2026-03-01T00:00:00Z")!
        let yearDate = formatter.date(from: "2026-01-01T00:00:00Z")!

        XCTAssertEqual(
            DetailChartTimelinePresentation.pointDateText(weekDate, timelineScale: .week),
            "Week of Mar 9"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.pointDateText(monthDate, timelineScale: .month),
            "March 2026"
        )
        XCTAssertEqual(
            DetailChartTimelinePresentation.pointDateText(yearDate, timelineScale: .year),
            "2026"
        )
    }
}

final class DetailChartStatisticsPresentationTests: XCTestCase {
    func testSummarySeriesFollowsSelectedChartMode() {
        let displayed = [
            MetricChartDataPoint(date: Date(timeIntervalSince1970: 0), value: 10),
            MetricChartDataPoint(date: Date(timeIntervalSince1970: 1), value: 20)
        ]
        let smoothed = [
            MetricChartDataPoint(date: Date(timeIntervalSince1970: 0), value: 12),
            MetricChartDataPoint(date: Date(timeIntervalSince1970: 1), value: 18)
        ]

        let rawSummary = DetailChartStatisticsPresentation.summarySeries(
            chartMode: .raw,
            displayedSeries: displayed,
            smoothedSeries: smoothed
        )
        let trendSummary = DetailChartStatisticsPresentation.summarySeries(
            chartMode: .trend,
            displayedSeries: displayed,
            smoothedSeries: smoothed
        )

        XCTAssertEqual(rawSummary.map(\.value), [10, 20])
        XCTAssertEqual(trendSummary.map(\.value), [12, 18])
    }
}

final class DetailHistorySourcePresentationTests: XCTestCase {
    func testTimelineSummaryUsesFirstPartyLabel() {
        XCTAssertEqual(
            DetailHistorySourcePresentation.label(for: .integration(id: "Timeline")),
            "Timeline summary"
        )
        XCTAssertTrue(
            DetailHistorySourcePresentation.isTimelineSummary(.integration(id: "Timeline"))
        )
        XCTAssertFalse(
            DetailHistorySourcePresentation.isTimelineSummary(.integration(id: "Whoop"))
        )
        XCTAssertEqual(
            DetailHistorySourcePresentation.label(for: .integration(id: "Whoop")),
            "Whoop"
        )
    }
}

final class DetailHistoryDeletionTargetTests: XCTestCase {
    func testResolveUsesDailyMetricsForStepsAndBodyMetricsForBodyComposition() {
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .steps), .dailyMetric)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .weight), .bodyMetric)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .bodyFat), .bodyMetric)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .ffmi), .bodyMetric)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .bodyScore), .bodyMetric)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: .glp1), .unsupported)
        XCTAssertEqual(DetailHistoryDeletionTarget.resolve(metricType: nil), .unsupported)
    }
}

final class DetailHistoryValuePresentationTests: XCTestCase {
    func testSecondaryTextFormatsConfiguredSecondaryValue() {
        let entry = MetricHistoryEntry(
            id: "entry",
            date: Date(),
            primaryValue: 180,
            secondaryValue: 18.4,
            source: .manual
        )
        let config = MetricEntriesConfiguration(
            metricType: .weight,
            unitLabel: "lbs",
            secondaryUnitLabel: "%",
            primaryFormatter: MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1),
            secondaryFormatter: MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        )

        XCTAssertEqual(
            DetailHistoryValuePresentation.secondaryText(entry: entry, config: config),
            "18.4 %"
        )
    }

    func testSecondaryTextReturnsNilWhenValueMissing() {
        let entry = MetricHistoryEntry(
            id: "entry",
            date: Date(),
            primaryValue: 180,
            secondaryValue: nil,
            source: .manual
        )
        let config = MetricEntriesConfiguration(
            metricType: .weight,
            unitLabel: "lbs",
            secondaryUnitLabel: "%",
            primaryFormatter: MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1),
            secondaryFormatter: MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        )

        XCTAssertNil(DetailHistoryValuePresentation.secondaryText(entry: entry, config: config))
    }
}

final class DashboardMetricDetailChangePresentationTests: XCTestCase {
    func testWeightChangeUsesBucketScaleCaptionAndConvertedDelta() {
        let metrics = [
            Self.makeMetric(
                id: "metric",
                date: Date(timeIntervalSince1970: 0),
                weight: 180,
                weightUnit: "lbs"
            )
        ]

        let change = DashboardMetricDetailChangePresentation.weightChange(
            selectedTimelineBucket: Self.makeBucket(
                scale: .month,
                weightValue: 180,
                bodyFatValue: nil,
                ffmiValue: nil,
                bodyScore: nil,
                stepsValue: nil
            ),
            previousTimelineBucket: Self.makeBucket(
                scale: .month,
                weightValue: 176,
                bodyFatValue: nil,
                ffmiValue: nil,
                bodyScore: nil,
                stepsValue: nil
            ),
            metrics: metrics,
            preferredUnit: "kg"
        )

        XCTAssertEqual(change?.title, "Change vs last month")
        XCTAssertEqual(change?.delta ?? 0, 1.8, accuracy: 0.2)
    }

    func testMetricChangeUsesBucketMetricDelta() {
        let change = DashboardMetricDetailChangePresentation.metricChange(
            current: GlobalTimelineMetricValue(value: 18, presence: .present),
            previous: GlobalTimelineMetricValue(value: 19.5, presence: .present),
            selectedTimelineBucket: Self.makeBucket(
                scale: .year,
                weightValue: nil,
                bodyFatValue: 18,
                ffmiValue: nil,
                bodyScore: nil,
                stepsValue: nil
            )
        )

        XCTAssertEqual(change?.title, "Change vs last year")
        XCTAssertEqual(change?.delta ?? 0, -1.5, accuracy: 0.001)
    }

    func testBodyScoreChangeUsesIntegerDifference() {
        let change = DashboardMetricDetailChangePresentation.bodyScoreChange(
            currentScore: 82,
            previousScore: 79,
            selectedTimelineBucket: Self.makeBucket(
                scale: .week,
                weightValue: nil,
                bodyFatValue: nil,
                ffmiValue: nil,
                bodyScore: 82,
                stepsValue: nil
            )
        )

        XCTAssertEqual(change?.title, "Change vs last week")
        XCTAssertEqual(change?.delta, 3)
    }

    private static func makeMetric(
        id: String,
        date: Date,
        weight: Double,
        weightUnit: String
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
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

    private static func makeBucket(
        scale: GlobalTimelineScale,
        weightValue: Double?,
        bodyFatValue: Double?,
        ffmiValue: Double?,
        bodyScore: Int?,
        stepsValue: Double?
    ) -> GlobalTimelineBucket {
        GlobalTimelineBucket(
            id: "bucket-\(scale)",
            scale: scale,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 86_400),
            metrics: GlobalTimelineMetricsSnapshot(
                weight: GlobalTimelineMetricValue(
                    value: weightValue,
                    presence: weightValue == nil ? .missing : .present
                ),
                bodyFat: GlobalTimelineMetricValue(
                    value: bodyFatValue,
                    presence: bodyFatValue == nil ? .missing : .present
                ),
                ffmi: GlobalTimelineMetricValue(
                    value: ffmiValue,
                    presence: ffmiValue == nil ? .missing : .present
                ),
                steps: GlobalTimelineMetricValue(
                    value: stepsValue,
                    presence: stepsValue == nil ? .missing : .present
                ),
                canonicalPhotoId: nil,
                hasPhotosInRange: false,
                bodyScore: bodyScore,
                bodyScoreCompleteness: bodyScore == nil ? .none : .full
            )
        )
    }
}

// swiftlint:enable single_test_class
