//
// LogYourBodyTests.swift
// LogYourBody
//
import XCTest
@testable import LogYourBody

// swiftlint:disable single_test_class

final class LaunchSurfacePolicyTests: XCTestCase {
    func testMVPDefaultSkipsBodyCompositionOnboardingAndProfileGate() {
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: false,
                fullDashboardEnabled: false
            )
        )
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: false,
                fullDashboardEnabled: false
            )
        )
    }

    func testFullDashboardGateRestoresBodyCompositionRequirements() {
        XCTAssertTrue(
            LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: false,
                fullDashboardEnabled: true
            )
        )
        XCTAssertTrue(
            LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: false,
                fullDashboardEnabled: true
            )
        )
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: true,
                fullDashboardEnabled: true
            )
        )
        XCTAssertFalse(
            LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: true,
                fullDashboardEnabled: true
            )
        )
    }

    func testFullDashboardPolicyMirrorsFeatureGate() {
        XCTAssertTrue(LaunchSurfacePolicy.shouldShowFullBodyCompositionDashboard(gateEnabled: true))
        XCTAssertFalse(LaunchSurfacePolicy.shouldShowFullBodyCompositionDashboard(gateEnabled: false))
    }
}

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
            XCTAssertEqual(height, 180.0, accuracy: 0.01)
        }

        XCTAssertEqual(updates["heightUnit"] as? String, "cm")
        XCTAssertEqual(updates["onboardingCompleted"] as? Bool, true)
    }

    func testBuildOnboardingProfileUpdatesRespectsImperialHeightUnit() {
        let viewModel = OnboardingFlowViewModel()
        viewModel.bodyScoreInput.height = HeightValue(value: 72, unit: .inches)
        viewModel.setHeightUnit(.inches)

        let updates = viewModel.buildOnboardingProfileUpdates()

        let height = updates["height"] as? Double
        XCTAssertNotNil(height)
        if let height {
            XCTAssertEqual(height, 72 * 2.54, accuracy: 0.01)
        }

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

    func testUpdateLocalUserUsesExternalAccountEmailWhenPrimaryEmailsMissing() {
        let manager = AuthManager()

        struct FakeExternalAccount {
            let provider: String
            let emailAddress: String
        }

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [String]
            let externalAccounts: [FakeExternalAccount]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_apple_123",
            emailAddresses: [],
            externalAccounts: [
                FakeExternalAccount(
                    provider: "oauth_apple",
                    emailAddress: "private@example.com"
                )
            ],
            firstName: "Apple",
            lastName: "User",
            username: nil,
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "private@example.com")
    }

    func testUpdateLocalUserSynthesizesEmailWhenClerkEmailMissing() {
        let manager = AuthManager()

        struct FakeClerkUser {
            let id: String
            let emailAddresses: [String]
            let externalAccounts: [String]
            let firstName: String?
            let lastName: String?
            let username: String?
            let imageUrl: String?
        }

        let fakeUser = FakeClerkUser(
            id: "user_apple_123",
            emailAddresses: [],
            externalAccounts: [],
            firstName: nil,
            lastName: nil,
            username: nil,
            imageUrl: nil
        )

        manager.updateLocalUser(clerkUser: fakeUser)

        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertEqual(manager.currentUser?.email, "user_apple_123@apple.local.logyourbody")
    }

    func testSyntheticAuthEmailSanitizesClerkUserId() {
        XCTAssertEqual(
            AuthManager.syntheticAuthEmail(userId: " user:abc/123 "),
            "user-abc-123@apple.local.logyourbody"
        )
    }

    func testNormalizedAuthEmailRejectsNonEmailIdentifier() {
        XCTAssertNil(AuthManager.normalizedAuthEmailCandidate("user_apple_123"))
        XCTAssertEqual(
            AuthManager.normalizedAuthEmailCandidate(" private@example.com "),
            "private@example.com"
        )
    }
}

final class AuthConfigurationValidationTests: XCTestCase {
    func testProductionRejectsDevelopmentAuthAndTelemetryConfig() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .production,
            clerkPublishableKey: "pk_test_123",
            supabaseURL: "https://dev-project.supabase.co",
            supabaseExpectedHost: "prod-project.supabase.co",
            apiBaseURL: "ht" + "tp://localhost:3000",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "replace_with_prod_revenuecat_public_key",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Production builds cannot use Clerk test publishable keys."))
        XCTAssertTrue(result.messages.contains("Supabase URL host must match SUPABASE_EXPECTED_HOST for this environment."))
        XCTAssertTrue(result.messages.contains("Production API base URL must use HTTPS."))
        XCTAssertTrue(result.messages.contains("Production RevenueCat API key must be configured."))
        XCTAssertTrue(result.messages.contains("Production Sentry environment must be production."))
        XCTAssertTrue(result.messages.contains("Production Statsig tier must be production."))
    }

    func testProductionRequiresExplicitSupabaseExpectedHost() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .production,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://prod-project.supabase.co",
            supabaseExpectedHost: "",
            apiBaseURL: "https://www.logyourbody.com",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "appl_123",
            sentryEnvironment: "production",
            statsigEnvironmentTier: "production",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.messages.contains("Supabase expected host must be configured for production."))
    }

    func testDevelopmentRejectsProductionClerkKeyByDefault() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .development,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://dev-project.supabase.co",
            supabaseExpectedHost: "dev-project.supabase.co",
            apiBaseURL: "ht" + "tp://localhost:3000",
            apiExpectedHost: "localhost",
            revenueCatAPIKey: "",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: false
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(
            result.messages.contains("Development builds cannot use Clerk live publishable keys unless explicitly allowed.")
        )
    }

    func testDevelopmentAllowsProductionServicesWhenExplicitlyAllowed() {
        let snapshot = Configuration.AuthEnvironmentSnapshot(
            environment: .development,
            clerkPublishableKey: "pk_live_123",
            supabaseURL: "https://prod-project.supabase.co",
            supabaseExpectedHost: "prod-project.supabase.co",
            apiBaseURL: "https://www.logyourbody.com",
            apiExpectedHost: "www.logyourbody.com",
            revenueCatAPIKey: "appl_123",
            sentryEnvironment: "development",
            statsigEnvironmentTier: "development",
            allowProductionServicesInDevelopment: true
        )

        let result = Configuration.validateAuthEnvironment(snapshot)

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.messages.isEmpty)
    }
}

final class AuthLegacyStorageMigrationTests: XCTestCase {
    func testMigrateLegacyAuthStorageRemovesSensitiveDefaultsOnly() {
        let suiteName = "auth-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("legacy-access", forKey: Constants.authTokenKey)
        defaults.set("legacy-refresh", forKey: "refreshToken")
        defaults.set("legacy-session", forKey: "clerkSession")
        defaults.set("legacy-user-json", forKey: Constants.currentUserKey)
        defaults.set(true, forKey: Constants.hasCompletedOnboardingKey)

        let removedKeys = AuthManager.migrateLegacyAuthStorage(in: defaults)

        XCTAssertTrue(removedKeys.contains(Constants.authTokenKey))
        XCTAssertTrue(removedKeys.contains("refreshToken"))
        XCTAssertTrue(removedKeys.contains("clerkSession"))
        XCTAssertTrue(removedKeys.contains(Constants.currentUserKey))
        XCTAssertNil(defaults.object(forKey: Constants.authTokenKey))
        XCTAssertNil(defaults.object(forKey: "refreshToken"))
        XCTAssertNil(defaults.object(forKey: "clerkSession"))
        XCTAssertNil(defaults.object(forKey: Constants.currentUserKey))
        XCTAssertEqual(defaults.bool(forKey: Constants.hasCompletedOnboardingKey), true)
    }
}

final class StubSupabaseManager: SupabaseManager {
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

@MainActor
final class SyncIntegrationTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
    }

    override func tearDown() async throws {
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    private func wholeSecondDate(_ offset: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_735_000_000 + offset)
    }

    func testUpdateOrCreateBodyMetric_MapsSupabasePayload() async throws {
        let coreData = CoreDataManager.shared

        let id = UUID().uuidString
        let userId = "sync_test_user_body_\(UUID().uuidString)"
        let date = wholeSecondDate()
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
        let date = wholeSecondDate(1_000)
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
        let date = wholeSecondDate(2_000)
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
        let date = wholeSecondDate(3_000)
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
        let existingDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 45), to: day) ?? day

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

        try await coreData.saveBodyMetricsAndWait(existingMetric, userId: userId)

        let sameHourDate = calendar.date(byAdding: DateComponents(hour: 10, minute: 15), to: day) ?? day
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

        try await coreData.saveBodyMetricsAndWait(metricModel, userId: userId)

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

        try await coreData.saveDailyMetricsAndWait(dailyModel, userId: userId)

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

// swiftlint:enable single_test_class
