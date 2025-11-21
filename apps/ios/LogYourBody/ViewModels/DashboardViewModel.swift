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

    init(healthKitManager: HealthKitManager = .shared) {
        self.healthKitManager = healthKitManager
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

        let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let allMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        let todayMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentDailyCached = await CoreDataManager.shared.fetchDailyMetrics(
            for: userId,
            from: thirtyDaysAgo,
            to: nil
        )
        let recentDaily = recentDailyCached.map { $0.toDailyMetrics() }

        if loadOnlyNewest {
            if let newest = allMetrics.first {
                bodyMetrics = [newest]
                sortedBodyMetricsAscending = [newest]
                hasLoadedInitialData = true

                // Defer full list assignment to a follow-up task so the UI can show something quickly
                Task { @MainActor [allMetrics] in
                    if self.bodyMetrics.count == 1 {
                        self.bodyMetrics = allMetrics
                        self.sortedBodyMetricsAscending = allMetrics.sorted {
                            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
                        }
                    }
                }
            }
        } else {
            bodyMetrics = allMetrics
            sortedBodyMetricsAscending = allMetrics.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
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

    func refreshData(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager
    ) async {
        // Debouncing: Skip refresh if last refresh was within 3 minutes
        if let lastRefresh = lastRefreshDate {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < 180 {
                await loadData(authManager: authManager, selectedIndex: 0)
                return
            }
        }

        isSyncingData = true

        var hasErrors = false

        // Sync from HealthKit if authorized
        if healthKitManager.isAuthorized {
            do {
                try await healthKitManager.syncWeightFromHealthKit()
                await syncStepsFromHealthKit(authManager: authManager, realtimeSyncManager: realtimeSyncManager)
            } catch {
                hasErrors = true
            }
        }

        realtimeSyncManager.syncAll()

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        isSyncingData = false

        await loadData(authManager: authManager, selectedIndex: 0)

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
            // Silently fail - HealthKit sync is optional
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
