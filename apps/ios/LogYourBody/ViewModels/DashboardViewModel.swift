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
    private let todayStepCountLoader: (() async throws -> Int)?
    private let dailyStepLoader: @MainActor (String, Date) async -> DailyMetrics?
    private let dailyStepWriter: @MainActor (DailyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void
    private let stepSyncTrigger: (@MainActor () -> Void)?
    private var historicalLoadTask: Task<Void, Never>?

    init(
        healthKitManager: HealthKitManager = .shared,
        healthSyncCoordinator: HealthSyncCoordinating,
        latestMetricLoader: @escaping @MainActor (String) async -> BodyMetrics? = { userId in
            let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: userId)
            return cached?.toBodyMetrics()
        },
        todayStepCountLoader: (() async throws -> Int)? = nil,
        dailyStepLoader: @escaping @MainActor (String, Date) async -> DailyMetrics? = { userId, date in
            await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: date)?.toDailyMetrics()
        },
        dailyStepWriter: @escaping @MainActor (
            DailyMetrics, @escaping CoreDataManager.WriteAdmission
        ) async throws -> Void = { metrics, admission in
            try await CoreDataManager.shared.saveDailyMetricsAndWait(
                metrics, userId: metrics.userId, writeAdmission: admission
            )
        },
        stepSyncTrigger: (@MainActor () -> Void)? = nil
    ) {
        self.healthKitManager = healthKitManager
        self.healthSyncCoordinator = healthSyncCoordinator
        self.latestMetricLoader = latestMetricLoader
        self.todayStepCountLoader = todayStepCountLoader
        self.dailyStepLoader = dailyStepLoader
        self.dailyStepWriter = dailyStepWriter
        self.stepSyncTrigger = stepSyncTrigger
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

    func syncStepsFromHealthKit(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager
    ) async {
        guard let ownership = authManager.captureAccountSession() else { return }
        do {
            let stepCount: Int
            if let todayStepCountLoader {
                stepCount = try await todayStepCountLoader()
            } else {
                stepCount = try await healthKitManager.fetchTodayStepCount()
            }
            try await updateStepCount(
                steps: stepCount,
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager,
                ownership: ownership
            )
        } catch {
            guard !Task.isCancelled, authManager.ownsAccountSession(ownership) else { return }
            let context = ErrorContext(
                feature: "healthKit",
                operation: "syncStepsFromHealthKit",
                screen: "Dashboard",
                userId: ownership.subject
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

    func updateStepCount(
        steps: Int,
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager,
        ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async throws {
        _ = try DailyStepCountPolicy.storedSteps(steps)
        guard let ownership = ownership ?? authManager.captureAccountSession() else {
            throw HealthKitError.notAuthorized
        }
        try requireStepOwnership(ownership, authManager: authManager)
        let today = Date()
        let current = await dailyStepLoader(ownership.subject, today)
        try requireStepOwnership(ownership, authManager: authManager)
        let metrics = DailyMetrics(
            id: current?.id ?? UUID().uuidString,
            userId: ownership.subject,
            date: current?.date ?? today,
            steps: steps,
            notes: current?.notes,
            createdAt: current?.createdAt ?? today,
            updatedAt: Date()
        )
        let cancellation = HealthKitImportCancellation()
        let admission: CoreDataManager.WriteAdmission = {
            guard !cancellation.isCancelled, authManager.ownsAccountSession(ownership) else {
                throw HealthKitError.notAuthorized
            }
        }
        try await withTaskCancellationHandler {
            try await dailyStepWriter(metrics, admission)
        } onCancel: {
            cancellation.cancel()
        }
        try requireStepOwnership(ownership, authManager: authManager)
        dailyMetrics = metrics
        if let stepSyncTrigger { stepSyncTrigger() } else { realtimeSyncManager.syncAll() }
    }

    private func requireStepOwnership(
        _ ownership: AuthManager.ProfileSessionOwnership, authManager: AuthManager
    ) throws {
        try Task.checkCancellation()
        guard authManager.ownsAccountSession(ownership) else { throw HealthKitError.notAuthorized }
    }
}
