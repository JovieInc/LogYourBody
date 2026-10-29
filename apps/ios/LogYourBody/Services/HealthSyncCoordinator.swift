//
// HealthSyncCoordinator.swift
// LogYourBody
//

import Foundation
import HealthKit

enum HealthKitAccountSyncPolicy {
    static let accountIdKey = "healthKitSyncAccountId"

    static func admitsImport(currentUserId: String, boundAccountId: String?) -> Bool {
        guard let boundAccountId, !boundAccountId.isEmpty else { return true }
        return boundAccountId == currentUserId
    }

    static func bindIfUnbound(userId: String?, syncEnabled: Bool, defaults: UserDefaults) {
        guard syncEnabled, let userId, !userId.isEmpty else { return }
        let existing = defaults.string(forKey: accountIdKey)
        guard existing == nil || existing?.isEmpty == true else { return }
        defaults.set(userId, forKey: accountIdKey)
    }

    static func claim(userId: String?, defaults: UserDefaults) {
        guard let userId, !userId.isEmpty else { return }
        defaults.set(userId, forKey: accountIdKey)
    }
}

protocol HealthKitSyncManaging: AnyObject {
    var isHealthKitAvailable: Bool { get }
    var isAuthorized: Bool { get }

    func checkAuthorizationStatus()
    func observeWeightChanges()
    func observeBodyFatChanges()
    func observeStepChanges()
    func setupBackgroundDelivery() async throws
    func setupStepCountBackgroundDelivery() async throws
    func resetForCurrentUser() async
    func suspendAutomaticImportAfterSignOut() async
    func admitsAutomaticImportForCurrentAccount() -> Bool
    func claimAutomaticImportAccount() async
    func syncWeightFromHealthKit() async throws
    func syncStepsFromHealthKit() async throws
    func fetchTodayStepCount() async throws -> Int?
    func forceFullHealthKitSync() async -> Bool
    func refreshSmartScaleSamplesIfEnabled() async -> HealthKitSmartScaleRefreshResult
}

extension HealthKitSyncManaging {
    func suspendAutomaticImportAfterSignOut() async {}
    func admitsAutomaticImportForCurrentAccount() -> Bool { true }
    func claimAutomaticImportAccount() async {}
    func refreshSmartScaleSamplesIfEnabled() async -> HealthKitSmartScaleRefreshResult { .inactive }
}

extension HealthKitManager: HealthKitSyncManaging {}

/// Protocol abstraction for coordinating HealthKit-related sync operations.
/// This enables easier unit testing for components that depend on
/// HealthSyncCoordinator by allowing mock implementations.
@MainActor
protocol HealthSyncCoordinating {
    func bootstrapIfNeeded(syncEnabled: Bool)
    func resetForCurrentUser() async
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async
    func warmUpAfterLoginIfNeeded() async
    func performInitialConnectSync() async throws
    func runDeferredOnboardingWeightSync() async
    func syncWeightFromHealthKit() async throws
    func syncStepsFromHealthKit() async throws
    func forceFullHealthKitSync() async -> Bool
}

/// Central coordinator for HealthKit bootstrap and, over time, HealthKit-related
/// sync decisions. Starts by owning the bootstrapping of observers and
/// background delivery, using HealthKitManager as the underlying adapter.
@MainActor
final class HealthSyncCoordinator: ObservableObject, HealthSyncCoordinating {
    static let shared = HealthSyncCoordinator()

    private let healthKitManager: HealthKitSyncManaging
    private let now: () -> Date
    private var hasBootstrappedObservers = false
    private var refreshID = UUID()

    @Published private(set) var syncStatus = HealthSyncStateReducer()
    var syncState: HealthSyncState { syncStatus.state }
    var lastSuccessfulSync: Date? { syncStatus.lastSuccessfulSync }

    init(healthKitManager: HealthKitSyncManaging = HealthKitManager.shared, now: @escaping () -> Date = Date.init) {
        self.healthKitManager = healthKitManager
        self.now = now
    }

    /// Idempotent bootstrap for HealthKit observers and background delivery.
    /// Mirrors the previous HealthKitManager.bootstrapIfNeeded behavior but is
    /// centralized here so other parts of the app can delegate orchestration
    /// through a single coordinator.
    func bootstrapIfNeeded(syncEnabled: Bool) {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.bootstrapIfNeeded",
            category: "healthKitCoordinator",
            data: [
                "syncEnabled": syncEnabled ? "true" : "false",
                "hasBootstrapped": hasBootstrappedObservers ? "true" : "false"
            ]
        )

        guard syncEnabled else { return }
        guard healthKitManager.isHealthKitAvailable else {
            syncStatus.reduce(.refreshFailed)
            return
        }
        guard healthKitManager.admitsAutomaticImportForCurrentAccount() else { return }

        if hasBootstrappedObservers {
            healthKitManager.checkAuthorizationStatus()
            if healthKitManager.isAuthorized {
                if syncState != .permissionNeeded { scheduleSmartScaleForegroundRefresh() }
            } else {
                recordPermissionLoss()
            }
            return
        }

        healthKitManager.checkAuthorizationStatus()

        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }
        guard syncState != .permissionNeeded else { return }

        hasBootstrappedObservers = true

        healthKitManager.observeWeightChanges()
        healthKitManager.observeBodyFatChanges()
        healthKitManager.observeStepChanges()

        Task {
            guard healthKitManager.isAuthorized, syncState != .permissionNeeded else { return }
            do {
                try await healthKitManager.setupBackgroundDelivery()
                try await healthKitManager.setupStepCountBackgroundDelivery()
            } catch {
                let event = failureEvent(for: error)
                if event == .authorizationDenied || event == .authorizationRevoked { recordPermissionLoss() }
            }
        }
        scheduleSmartScaleForegroundRefresh()
    }

    /// Foreground entry. The manager no-ops while `healthkit_smart_scale_sync_v1` is off.
    private func scheduleSmartScaleForegroundRefresh() {
        let attempt = refreshID
        Task {
            guard healthKitManager.isAuthorized, syncState != .permissionNeeded else { return }
            let result = await healthKitManager.refreshSmartScaleSamplesIfEnabled()
            guard refreshID == attempt else { return }
            guard healthKitManager.isAuthorized else {
                recordPermissionLoss()
                return
            }
            switch result.outcome {
            case .refreshed:
                syncStatus.reduce(.refreshStarted)
                syncStatus.reduce(result.imported == 0 ? .noNewData(at: now()) : .refreshFinished(at: now()))
            case .denied:
                recordPermissionLoss()
            case .unavailable, .failed:
                syncStatus.reduce(.refreshFailed)
            case .inactive, .busy:
                break
            }
        }
    }

    /// Reset all HealthKit-related state for the current user and clear
    /// coordinator bootstrap state. Used when deleting the account or
    /// signing out completely.
    func resetForCurrentUser() async {
        hasBootstrappedObservers = false
        resetSyncState()
        await healthKitManager.resetForCurrentUser()
    }

    /// Stop observers after sign-out without erasing the account that owns
    /// automatic import. The same account can bootstrap again. Another
    /// account cannot inherit this device's HealthKit sync.
    func suspendAutomaticImportAfterSignOut() async {
        hasBootstrappedObservers = false
        resetSyncState()
        await healthKitManager.suspendAutomaticImportAfterSignOut()
    }

    /// Ensure observers and background delivery are configured after the
    /// user has granted authorization, then kick off an initial weight sync
    /// in the background. Intended for settings-based toggles.
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.configurePipeline.weightOnly",
            category: "healthKitCoordinator"
        )

        await healthKitManager.claimAutomaticImportAccount()
        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }
        syncStatus.reduce(.authorizationGranted)

        bootstrapIfNeeded(syncEnabled: true)

        Task(priority: .background) {
            try? await self.syncWeightFromHealthKit()
        }
    }

    /// Similar to `configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync`,
    /// but also performs an initial step history sync. Intended for the
    /// Integrations screen where the user explicitly enables full HealthKit
    /// syncing.
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.configurePipeline.weightAndSteps",
            category: "healthKitCoordinator"
        )

        await healthKitManager.claimAutomaticImportAccount()
        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }
        syncStatus.reduce(.authorizationGranted)

        bootstrapIfNeeded(syncEnabled: true)

        Task(priority: .background) {
            do {
                try await self.syncWeightFromHealthKit()
                try await self.syncStepsFromHealthKit()
            } catch {
                // Best-effort initial sync; errors are intentionally swallowed here.
            }
        }
    }

    /// Lightweight HealthKit warm-up used after login/on startup to ensure
    /// the latest step count is fetched without triggering a full sync.
    func warmUpAfterLoginIfNeeded() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.warmUpAfterLoginIfNeeded",
            category: "healthKitCoordinator"
        )

        healthKitManager.checkAuthorizationStatus()

        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }

        Task {
            try? await self.refresh {
                try await self.healthKitManager.fetchTodayStepCount() != nil
            }
        }
    }

    /// Used by the HealthKit connect prompt to perform the initial
    /// background delivery configuration and a first sync of weight and
    /// steps after the user authorizes access.
    func performInitialConnectSync() async throws {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.performInitialConnectSync",
            category: "healthKitCoordinator"
        )

        await healthKitManager.claimAutomaticImportAccount()
        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }
        syncStatus.reduce(.authorizationGranted)
        bootstrapIfNeeded(syncEnabled: true)
        try await refresh {
            try await self.healthKitManager.setupBackgroundDelivery()
            try await self.healthKitManager.setupStepCountBackgroundDelivery()
            try await self.healthKitManager.syncWeightFromHealthKit()
            _ = try await self.healthKitManager.fetchTodayStepCount()
            return true
        }
    }

    /// Run a deferred onboarding weight sync in the background if HealthKit
    /// is authorized. Errors are swallowed so that onboarding completion
    /// cannot fail because of HealthKit.
    func runDeferredOnboardingWeightSync() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.runDeferredOnboardingWeightSync",
            category: "healthKitCoordinator",
            data: [
                "isAuthorized": healthKitManager.isAuthorized ? "true" : "false"
            ]
        )

        await healthKitManager.claimAutomaticImportAccount()
        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }

        bootstrapIfNeeded(syncEnabled: true)

        do {
            try await syncWeightFromHealthKit()
        } catch {
            // Intentionally swallow errors; user can sync later from settings.
        }
    }

    /// Thin wrapper around the full weight sync, used by dashboard refresh
    /// and other user-initiated flows that want error propagation.
    func syncWeightFromHealthKit() async throws {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.syncWeightFromHealthKit",
            category: "healthKitCoordinator"
        )

        try await refresh {
            try await self.healthKitManager.syncWeightFromHealthKit()
            return true
        }
    }

    /// Full step history sync. Permission failures remain silent; other errors reach callers.
    func syncStepsFromHealthKit() async throws {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.syncStepsFromHealthKit",
            category: "healthKitCoordinator"
        )

        try await refresh {
            try await self.healthKitManager.syncStepsFromHealthKit()
            return true
        }
    }

    /// Trigger a full historical HealthKit import. This is used by manual
    /// "Sync All Historical Data" actions and the dashboard sync details
    /// sheet.
    func forceFullHealthKitSync() async -> Bool {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.forceFullHealthKitSync",
            category: "healthKitCoordinator"
        )

        var succeeded = false
        try? await refresh {
            succeeded = await self.healthKitManager.forceFullHealthKitSync()
            guard succeeded else { throw HealthKitError.syncFailed }
            return true
        }
        return succeeded
    }

    /// One attempt only. Permission failures are silent and never cause a retry or an access request.
    private func refresh(_ operation: () async throws -> Bool) async throws {
        guard healthKitManager.isHealthKitAvailable else {
            syncStatus.reduce(.refreshFailed)
            return
        }
        guard healthKitManager.isAuthorized else {
            recordPermissionLoss()
            return
        }
        guard syncState != .permissionNeeded else { return }

        let attempt = UUID()
        refreshID = attempt
        syncStatus.reduce(.refreshStarted)
        do {
            let hasNewData = try await operation()
            guard refreshID == attempt else { return }
            guard healthKitManager.isAuthorized else {
                recordPermissionLoss()
                return
            }
            syncStatus.reduce(hasNewData ? .refreshFinished(at: now()) : .noNewData(at: now()))
        } catch {
            let event = failureEvent(for: error)
            if refreshID == attempt { syncStatus.reduce(event) }
            if event == .authorizationDenied || event == .authorizationRevoked { return }
            throw error
        }
    }

    private func failureEvent(for error: Error) -> HealthSyncState.Event {
        let nsError = error as NSError
        let permissionError: Bool
        switch error {
        case HealthKitError.notAuthorized:
            permissionError = true
        default:
            permissionError = nsError.domain == HKErrorDomain &&
                (nsError.code == HKError.Code.errorAuthorizationDenied.rawValue ||
                    nsError.code == HKError.Code.errorAuthorizationNotDetermined.rawValue)
        }
        if permissionError || !healthKitManager.isAuthorized {
            return lastSuccessfulSync == nil ? .authorizationDenied : .authorizationRevoked
        }
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.notConnectedToInternet.rawValue || nsError.code == URLError.networkConnectionLost.rawValue {
            return .noNetwork
        }
        return .refreshFailed
    }

    private func recordPermissionLoss() {
        refreshID = UUID()
        syncStatus.reduce(lastSuccessfulSync == nil ? .authorizationDenied : .authorizationRevoked)
    }

    private func resetSyncState() {
        refreshID = UUID()
        syncStatus = HealthSyncStateReducer()
    }
}
