import Foundation
import CoreData
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var dailyMetrics: DailyMetrics?
    @Published var bodyMetrics: [BodyMetrics] = []
    @Published var sortedBodyMetricsAscending: [BodyMetrics] = []
    @Published var recentDailyMetrics: [DailyMetrics] = []
    @Published var hasLoadedInitialData = false
    @Published var lastRefreshDate: Date?
    @Published var isSyncingData = false

    private let healthKitManager: HealthKitManager
    private let healthSyncCoordinator: HealthSyncCoordinating
    private let latestMetricLoader: @MainActor (String) async -> BodyMetrics?
    private var historicalLoadTask: Task<Void, Never>?

    init(
        healthKitManager: HealthKitManager = .shared,
        healthSyncCoordinator: HealthSyncCoordinating,
        latestMetricLoader: @escaping @MainActor (String) async -> BodyMetrics? = { userId in
            let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: userId)
            return cached?.toBodyMetrics()
        }
    ) {
        self.healthKitManager = healthKitManager
        self.healthSyncCoordinator = healthSyncCoordinator
        self.latestMetricLoader = latestMetricLoader
    }

    convenience init(healthKitManager: HealthKitManager = .shared) {
        self.init(
            healthKitManager: healthKitManager,
            healthSyncCoordinator: HealthSyncCoordinator.shared
        )
    }

    func loadData(
        authManager: AuthManager,
        loadOnlyNewest: Bool = false,
        selectedIndex: Int
    ) async {
        guard let userId = authManager.currentUser?.id else {
            hasLoadedInitialData = true
            return
        }

        let todayMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentDailyCached = await CoreDataManager.shared.fetchDailyMetrics(
            for: userId,
            from: thirtyDaysAgo,
            to: nil
        )
        let recentDaily = recentDailyCached.map { $0.toDailyMetrics() }

        // Only the first paint may use a single measurement. Later refreshes
        // must retain complete history and reconcile updates and deletions.
        if loadOnlyNewest && !hasLoadedInitialData {
            let newest = await latestMetricLoader(userId)
            // Another load may have completed while the first-paint fetch was
            // suspended. Never replace that newer result with this singleton.
            if !hasLoadedInitialData {
                bodyMetrics = newest.map { [$0] } ?? []
                sortedBodyMetricsAscending = bodyMetrics
                hasLoadedInitialData = true
                if newest != nil {
                    scheduleHistoricalLoadIfNeeded(for: userId)
                }
            }
        } else {
            historicalLoadTask?.cancel()
            historicalLoadTask = nil
            let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
            let allMetrics = fetchedMetrics
                .compactMap { $0.toBodyMetrics() }
                .sorted { $0.date > $1.date }

            bodyMetrics = allMetrics
            sortedBodyMetricsAscending = allMetrics.sorted { $0.date < $1.date }
            if !bodyMetrics.isEmpty {
                // DashboardViewLiquid will handle updating its own animated values
                _ = selectedIndex
            }
            hasLoadedInitialData = true
        }

        if let todayMetrics {
            dailyMetrics = todayMetrics.toDailyMetrics()
        }

        recentDailyMetrics = recentDaily
    }

    private func scheduleHistoricalLoadIfNeeded(for userId: String) {
        if historicalLoadTask != nil {
            return
        }

        historicalLoadTask = Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
            let allMetrics = fetchedMetrics
                .compactMap { $0.toBodyMetrics() }
                .sorted { $0.date > $1.date }

            guard !Task.isCancelled else { return }
            self.historicalLoadTask = nil
            guard self.bodyMetrics.count <= 1,
                  self.bodyMetrics.first?.userId == userId else { return }

            self.bodyMetrics = allMetrics
            self.sortedBodyMetricsAscending = allMetrics.sorted {
                $0.date < $1.date
            }
        }
    }

    func refreshData(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager
    ) async {
        // Debouncing: Skip refresh if last refresh was within 3 minutes
        if let lastRefresh = lastRefreshDate {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < 180 {
                await loadData(
                    authManager: authManager,
                    loadOnlyNewest: true,
                    selectedIndex: 0
                )
                return
            }
        }

        isSyncingData = true

        var hasErrors = false

        // Sync from HealthKit if authorized
        if healthKitManager.isAuthorized {
            do {
                try await healthSyncCoordinator.syncWeightFromHealthKit()
                await syncStepsFromHealthKit(authManager: authManager, realtimeSyncManager: realtimeSyncManager)
            } catch {
                hasErrors = true
            }
        }

        realtimeSyncManager.syncIfNeeded()

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        isSyncingData = false

        await loadData(
            authManager: authManager,
            loadOnlyNewest: true,
            selectedIndex: 0
        )

        lastRefreshDate = Date()

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        if hasErrors {
            generator.notificationOccurred(.warning)
        } else {
            generator.notificationOccurred(.success)
        }
    }

    private func syncStepsFromHealthKit(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager
    ) async {
        do {
            let stepCount = try await healthKitManager.fetchTodayStepCount()
            await updateStepCount(
                steps: stepCount,
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager
            )
        } catch {
            let context = ErrorContext(
                feature: "healthKit",
                operation: "fetchTodayStepCount",
                screen: "Dashboard",
                userId: authManager.currentUser?.id
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

    private func updateStepCount(
        steps: Int,
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager
    ) async {
        guard let userId = authManager.currentUser?.id else { return }

        let today = Date()

        if let existingMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today) {
            existingMetrics.steps = Int32(steps)
            existingMetrics.updatedAt = Date()

            let metrics = existingMetrics.toDailyMetrics()
            dailyMetrics = metrics
        } else {
            let newMetrics = DailyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: today,
                steps: steps,
                notes: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            CoreDataManager.shared.saveDailyMetrics(newMetrics, userId: userId)

            dailyMetrics = newMetrics
        }

        realtimeSyncManager.syncAll()
    }
}
