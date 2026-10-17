import Foundation
import Combine
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
    private let todayStepCountLoader: (() async throws -> Int?)?
    private let dailyStepLoader: @MainActor (String, Date) async -> DailyMetrics?
    private let dailyStepWriter: @MainActor (DailyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void
    private let stepSyncTrigger: (@MainActor () -> Void)?
    private var historicalLoadTask: Task<Void, Never>?
    private var historicalLoadID: UUID?
    private var requestRevision: UInt64 = 0
    private var activeOwnership: AuthManager.ProfileSessionOwnership?
    private(set) var publicationOwnership: AuthManager.ProfileSessionOwnership?
    private weak var observedAuthManager: AuthManager?
    private var accountObservation: AnyCancellable?
    #if DEBUG
    /// Actual observer completion event only; no admission or lifecycle behavior can be changed through this hook.
    var onAccountObservationForTests: (@MainActor () -> Void)?
    #endif

    private struct LoadRequest {
        let revision: UInt64
        let ownership: AuthManager.ProfileSessionOwnership
    }

    /// Reads remain unavailable to consumers when their original account lifetime changes.
    func hasCurrentPublication(for authManager: AuthManager) -> Bool {
        guard let publicationOwnership else { return false }
        return authManager.ownsAccountSession(publicationOwnership)
    }

    func hasCurrentActivity(for authManager: AuthManager) -> Bool {
        guard let activeOwnership else { return false }
        return authManager.ownsAccountSession(activeOwnership)
    }

    private func observeAccountChanges(_ authManager: AuthManager) {
        guard observedAuthManager !== authManager else { return }
        observedAuthManager = authManager
        accountObservation = authManager.$authSession.combineLatest(authManager.$currentUser)
            .dropFirst().sink { [weak self, weak authManager] _, _ in
                // Published emits before AuthManager.didSet increments its generation.
                Task { @MainActor [weak self, weak authManager] in
                    guard let self, let authManager,
                          self.observedAuthManager === authManager else { return }
                    if self.activeOwnership != authManager.captureAccountSession() {
                        self.invalidatePublishedData(signedOut: authManager.captureAccountSession() == nil)
                    }
                    #if DEBUG
                    self.onAccountObservationForTests?()
                    #endif
                }
            }
    }

    private func invalidatePublishedData(signedOut: Bool) {
        requestRevision &+= 1
        historicalLoadTask?.cancel()
        historicalLoadTask = nil
        historicalLoadID = nil
        activeOwnership = nil
        publicationOwnership = nil
        bodyMetrics = []
        sortedBodyMetricsAscending = []
        dailyMetrics = nil
        recentDailyMetrics = []
        hasLoadedInitialData = signedOut
        lastRefreshDate = nil
        isSyncingData = false
    }

    private func beginRequest(
        authManager: AuthManager, expectedOwnership: AuthManager.ProfileSessionOwnership?
    ) -> LoadRequest? {
        observeAccountChanges(authManager)
        guard !Task.isCancelled else { return nil }
        guard let ownership = expectedOwnership ?? authManager.captureAccountSession(),
              authManager.ownsAccountSession(ownership) else {
            // A stale explicit caller must not invalidate a newer owner's request.
            if expectedOwnership == nil, authManager.captureAccountSession() == nil {
                invalidatePublishedData(signedOut: true)
            }
            return nil
        }
        if activeOwnership != ownership { invalidatePublishedData(signedOut: false) }
        requestRevision &+= 1
        historicalLoadTask?.cancel()
        historicalLoadTask = nil
        historicalLoadID = nil
        activeOwnership = ownership
        isSyncingData = false
        return LoadRequest(revision: requestRevision, ownership: ownership)
    }

    private func isCurrent(_ request: LoadRequest, authManager: AuthManager) -> Bool {
        !Task.isCancelled && request.revision == requestRevision &&
            activeOwnership == request.ownership && authManager.ownsAccountSession(request.ownership)
    }

    private func finishRefresh(_ request: LoadRequest) {
        // Cancellation may clear its own spinner, never a newer request's terminal state.
        if request.revision == requestRevision, activeOwnership == request.ownership {
            isSyncingData = false
        }
    }

    #if DEBUG
    /// Read-only handle to the actual task; tests capture it before cancellation clears storage.
    func pendingHistoricalLoadForTests() -> Task<Void, Never>? { historicalLoadTask }
    #endif

    init(
        healthKitManager: HealthKitManager = .shared,
        healthSyncCoordinator: HealthSyncCoordinating,
        latestMetricLoader: @escaping @MainActor (String) async -> BodyMetrics? = { userId in
            let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: userId)
            return cached?.toBodyMetrics()
        },
        todayStepCountLoader: (() async throws -> Int?)? = nil,
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

    /// A queued caller's nil is an explicit captured lifetime, not permission to recapture a future owner.
    func loadDataForCapturedSession(
        _ ownership: AuthManager.ProfileSessionOwnership?, authManager: AuthManager,
        loadOnlyNewest: Bool = false, selectedIndex: Int
    ) async {
        guard !Task.isCancelled, ownership == authManager.captureAccountSession() else { return }
        guard let ownership else {
            observeAccountChanges(authManager)
            invalidatePublishedData(signedOut: true)
            return
        }
        await loadData(
            authManager: authManager, loadOnlyNewest: loadOnlyNewest,
            selectedIndex: selectedIndex, expectedOwnership: ownership
        )
    }

    /// Startup retains its original admitted revision through local paint and successor refresh.
    func loadInitialDataAndRefresh(
        for ownership: AuthManager.ProfileSessionOwnership?, authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager, loadOnlyNewest: Bool, selectedIndex: Int
    ) async {
        guard !Task.isCancelled, ownership == authManager.captureAccountSession() else { return }
        guard let ownership else {
            await loadDataForCapturedSession(
                nil, authManager: authManager, loadOnlyNewest: loadOnlyNewest, selectedIndex: selectedIndex
            )
            return
        }
        guard let initial = beginRequest(authManager: authManager, expectedOwnership: ownership) else { return }
        if !hasLoadedInitialData || !hasCurrentPublication(for: authManager) {
            guard await loadData(
                authManager: authManager, loadOnlyNewest: loadOnlyNewest,
                selectedIndex: selectedIndex, request: initial
            ) else { return }
        }
        // No await separates original-revision admission from successor creation.
        // A superseded same-owner startup cannot rebase onto, or cancel, newer work.
        guard isCurrent(initial, authManager: authManager),
              let refresh = beginRequest(
                authManager: authManager, expectedOwnership: initial.ownership
              ) else { return }
        await refreshData(authManager: authManager, realtimeSyncManager: realtimeSyncManager, request: refresh)
    }

    func loadData(
        authManager: AuthManager,
        loadOnlyNewest: Bool = false,
        selectedIndex: Int,
        expectedOwnership: AuthManager.ProfileSessionOwnership? = nil
    ) async {
        guard let request = beginRequest(authManager: authManager, expectedOwnership: expectedOwnership) else { return }
        _ = await loadData(authManager: authManager, loadOnlyNewest: loadOnlyNewest,
                           selectedIndex: selectedIndex, request: request)
    }

    private func loadData(
        authManager: AuthManager, loadOnlyNewest: Bool, selectedIndex: Int, request: LoadRequest
    ) async -> Bool {
        guard isCurrent(request, authManager: authManager) else { return false }
        let userId = request.ownership.subject
        let todayCached = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        guard isCurrent(request, authManager: authManager) else { return false }
        let today = todayCached?.toDailyMetrics()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentCached = await CoreDataManager.shared.fetchDailyMetrics(for: userId, from: thirtyDaysAgo, to: nil)
        guard isCurrent(request, authManager: authManager) else { return false }
        let recent = recentCached.map { $0.toDailyMetrics() }
        let firstPaint = loadOnlyNewest && !hasLoadedInitialData
        let staged: [BodyMetrics]
        if firstPaint {
            let newest = await latestMetricLoader(userId)
            guard isCurrent(request, authManager: authManager) else { return false }
            staged = newest.map { [$0] } ?? []
        } else {
            let fetched = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
            guard isCurrent(request, authManager: authManager) else { return false }
            staged = await CachedBodyMetrics.bodyMetricsInBatches(from: fetched).sorted { $0.date > $1.date }
            guard isCurrent(request, authManager: authManager) else { return false }
        }
        // No await separates these admitted publications; the first paint still uses the latest-only reader.
        publicationOwnership = request.ownership
        bodyMetrics = staged.filter { $0.userId == userId }
        sortedBodyMetricsAscending = bodyMetrics.sorted { $0.date < $1.date }
        dailyMetrics = today?.userId == userId ? today : nil
        recentDailyMetrics = recent.filter { $0.userId == userId }
        hasLoadedInitialData = true
        _ = selectedIndex
        if firstPaint, !bodyMetrics.isEmpty {
            scheduleHistoricalLoadIfNeeded(request: request, authManager: authManager)
        }
        return true
    }

    private func scheduleHistoricalLoadIfNeeded(request: LoadRequest, authManager: AuthManager) {
        guard historicalLoadTask == nil else { return }
        let taskID = UUID()
        historicalLoadID = taskID
        historicalLoadTask = Task(priority: .background) {
            defer {
                if self.historicalLoadID == taskID {
                    self.historicalLoadTask = nil
                    self.historicalLoadID = nil
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.isCurrent(request, authManager: authManager) else { return }
            let fetched = await CoreDataManager.shared.fetchBodyMetrics(for: request.ownership.subject)
            let allMetrics = await CachedBodyMetrics.bodyMetricsInBatches(from: fetched)
                .filter { $0.userId == request.ownership.subject }.sorted { $0.date > $1.date }
            guard self.isCurrent(request, authManager: authManager),
                  self.bodyMetrics.count <= 1,
                  self.bodyMetrics.first?.userId == request.ownership.subject else { return }
            self.publicationOwnership = request.ownership
            self.bodyMetrics = allMetrics
            self.sortedBodyMetricsAscending = allMetrics.sorted { $0.date < $1.date }
        }
    }

    func refreshData(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager,
        expectedOwnership: AuthManager.ProfileSessionOwnership? = nil
    ) async {
        guard let request = beginRequest(authManager: authManager, expectedOwnership: expectedOwnership) else { return }
        await refreshData(authManager: authManager, realtimeSyncManager: realtimeSyncManager, request: request)
    }

    private func refreshData(
        authManager: AuthManager, realtimeSyncManager: RealtimeSyncManager, request: LoadRequest
    ) async {
        guard isCurrent(request, authManager: authManager) else { return }
        defer { finishRefresh(request) }
        if let lastRefresh = lastRefreshDate, Date().timeIntervalSince(lastRefresh) < 180 {
            _ = await loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0, request: request)
            return
        }
        isSyncingData = true
        var hasErrors = false
        if healthKitManager.isAuthorized {
            do {
                try await healthSyncCoordinator.syncWeightFromHealthKit()
                guard isCurrent(request, authManager: authManager) else { return }
                await syncStepsFromHealthKit(
                    authManager: authManager, realtimeSyncManager: realtimeSyncManager,
                    publicationAdmission: { self.isCurrent(request, authManager: authManager) }
                )
            } catch {
                guard isCurrent(request, authManager: authManager) else { return }
                hasErrors = true
            }
        }
        guard isCurrent(request, authManager: authManager) else { return }
        realtimeSyncManager.syncIfNeeded()
        do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
        guard isCurrent(request, authManager: authManager),
              await loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0, request: request),
              isCurrent(request, authManager: authManager) else { return }
        lastRefreshDate = Date()
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(hasErrors ? .warning : .success)
    }

    func syncStepsFromHealthKit(
        authManager: AuthManager,
        realtimeSyncManager: RealtimeSyncManager,
        publicationAdmission: (@MainActor () -> Bool)? = nil
    ) async {
        guard publicationAdmission?() != false,
              let ownership = authManager.captureAccountSession() else { return }
        do {
            let stepCount: Int?
            if let todayStepCountLoader {
                stepCount = try await todayStepCountLoader()
            } else {
                stepCount = try await healthKitManager.fetchTodayStepCount()
            }
            guard let stepCount else { return }
            try await updateStepCount(
                steps: stepCount,
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager,
                ownership: ownership,
                publicationAdmission: publicationAdmission
            )
        } catch {
            guard !Task.isCancelled, publicationAdmission?() != false,
                  authManager.ownsAccountSession(ownership) else { return }
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
        ownership: AuthManager.ProfileSessionOwnership? = nil,
        publicationAdmission: (@MainActor () -> Bool)? = nil
    ) async throws {
        _ = try DailyStepCountPolicy.storedSteps(steps)
        guard let ownership = ownership ?? authManager.captureAccountSession() else {
            throw HealthKitError.notAuthorized
        }
        try requireStepOwnership(ownership, authManager: authManager, publicationAdmission: publicationAdmission)
        let today = Date()
        let current = await dailyStepLoader(ownership.subject, today)
        try requireStepOwnership(ownership, authManager: authManager, publicationAdmission: publicationAdmission)
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
            guard !cancellation.isCancelled, publicationAdmission?() != false,
                  authManager.ownsAccountSession(ownership) else {
                throw HealthKitError.notAuthorized
            }
        }
        try await withTaskCancellationHandler {
            try await dailyStepWriter(metrics, admission)
        } onCancel: {
            cancellation.cancel()
        }
        try requireStepOwnership(ownership, authManager: authManager, publicationAdmission: publicationAdmission)
        if publicationOwnership != ownership {
            // Empty emissions must not borrow either the old or new publication receipt.
            publicationOwnership = nil
            bodyMetrics = []
            sortedBodyMetricsAscending = []
            recentDailyMetrics = []
            hasLoadedInitialData = false
            lastRefreshDate = nil
        }
        publicationOwnership = ownership
        dailyMetrics = metrics
        if let stepSyncTrigger { stepSyncTrigger() } else { realtimeSyncManager.syncAll() }
    }

    private func requireStepOwnership(
        _ ownership: AuthManager.ProfileSessionOwnership, authManager: AuthManager,
        publicationAdmission: (@MainActor () -> Bool)? = nil
    ) throws {
        try Task.checkCancellation()
        guard publicationAdmission?() != false, authManager.ownsAccountSession(ownership) else {
            throw HealthKitError.notAuthorized
        }
    }
}
