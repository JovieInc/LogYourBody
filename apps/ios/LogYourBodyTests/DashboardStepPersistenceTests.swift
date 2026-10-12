import XCTest
@testable import LogYourBody

@MainActor
final class DashboardStepPersistenceTests: XCTestCase {
    func testExistingDailyStepsRemainAfterDashboardRefresh() async throws {
        let userId = "synthetic-dashboard-steps-\(UUID().uuidString)"
        let metricId = "synthetic-dashboard-steps-row-\(UUID().uuidString)"
        let auth = isolatedAuth(userId: userId)
        let seeded = DailyMetrics(
            id: metricId,
            userId: userId,
            date: Date(),
            steps: 111,
            notes: "seed-steps",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await CoreDataManager.shared.saveDailyMetricsAndWait(seeded, userId: userId)
        let context = CoreDataManager.shared.viewContext
        let fetched = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let saved = try XCTUnwrap(fetched)
        try await context.perform {
            saved.isSynced = true
            saved.syncStatus = "synced"
            if context.hasChanges {
                try context.save()
            }
        }
        await context.perform {
            context.reset()
        }

        let viewModel = dashboard()
        try await viewModel.updateStepCount(
            steps: 4_321,
            authManager: auth,
            realtimeSyncManager: offlineSync(auth: auth)
        )
        await context.perform {
            context.reset()
        }

        let reloaded = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let stored = try XCTUnwrap(reloaded)
        XCTAssertEqual(stored.steps, 4_321, "dashboard refresh must persist today's steps")
        XCTAssertFalse(stored.isSynced, "updated steps must stay pending for sync")
        XCTAssertEqual(stored.userId, userId)
        XCTAssertEqual(stored.notes, "seed-steps")
        XCTAssertEqual(stored.id, metricId)
    }

    func testMissingDailyRowSavesStepsFromDashboardRefresh() async throws {
        let userId = "synthetic-dashboard-steps-new-\(UUID().uuidString)"
        let auth = isolatedAuth(userId: userId)
        let context = CoreDataManager.shared.viewContext
        let viewModel = dashboard()
        try await viewModel.updateStepCount(
            steps: 900,
            authManager: auth,
            realtimeSyncManager: offlineSync(auth: auth)
        )
        await context.perform {
            context.reset()
        }

        let created = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let stored = try XCTUnwrap(created)
        XCTAssertEqual(stored.steps, 900)
        XCTAssertFalse(stored.isSynced)
        XCTAssertEqual(stored.userId, userId)
    }

    private func dashboard() -> DashboardViewModel {
        DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )
    }

    private func offlineSync(auth: AuthManager) -> RealtimeSyncManager {
        let sync = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: auth,
            productAPIClient: ProductAPIClient()
        )
        sync.isOnline = false
        return sync
    }

    private func isolatedAuth(userId: String) -> AuthManager {
        let defaults = UserDefaults(suiteName: "lyb.dashboard.step.\(userId)") ?? .standard
        let auth = AuthManager(userDefaults: defaults)
        auth.currentUser = LocalUser(
            id: userId,
            email: "steps@example.invalid",
            name: "Step Fixture",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        return auth
    }
}
