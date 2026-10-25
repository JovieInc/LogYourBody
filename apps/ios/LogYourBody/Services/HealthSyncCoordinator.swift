//
// HealthSyncCoordinator.swift
// LogYourBody
//

import Foundation
import UIKit

enum HealthKitForegroundRefreshPolicy {
    static let gateKey = "healthkit_foreground_refresh_v1"

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }
}

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
    func refreshSmartScaleSamplesIfEnabled() async
    @MainActor func performSmartScaleRefresh() async -> HealthKitSmartScaleRefreshResult
}

extension HealthKitSyncManaging {
    func suspendAutomaticImportAfterSignOut() async {}
    func admitsAutomaticImportForCurrentAccount() -> Bool { true }
    func claimAutomaticImportAccount() async {}
    func refreshSmartScaleSamplesIfEnabled() async {}
    @MainActor func performSmartScaleRefresh() async -> HealthKitSmartScaleRefreshResult { .inactive }
}

extension HealthKitManager: HealthKitSyncManaging {}

/// Protocol abstraction for coordinating HealthKit-related sync operations.
/// This enables easier unit testing for components that depend on
/// HealthSyncCoordinator by allowing mock implementations.
@MainActor
protocol HealthSyncCoordinating {
    func bootstrapIfNeeded(syncEnabled: Bool)
    func requestForegroundRefresh(syncEnabled: Bool)
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
    private var hasBootstrappedObservers = false
    private var foregroundRefreshTask: Task<Void, Never>?
    private var foregroundRefreshID: UUID?
    private var lastForegroundRefresh: Date?
    private let foregroundRefreshEnabled: @MainActor () -> Bool
    private let syncEnabled: @MainActor () -> Bool
    private let minimumInterval: @MainActor () -> TimeInterval
    private let now: @MainActor () -> Date
    private let sleep: @MainActor (TimeInterval) async throws -> Void

    init(
        healthKitManager: HealthKitSyncManaging = HealthKitManager.shared,
        foregroundRefreshEnabled: @escaping @MainActor () -> Bool = { HealthKitForegroundRefreshPolicy.isEnabled() },
        syncEnabled: @escaping @MainActor () -> Bool = {
            UserDefaults.standard.object(forKey: Constants.healthKitSyncEnabledKey) as? Bool ?? true
        },
        minimumInterval: @escaping @MainActor () -> TimeInterval = {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return BatterySyncIntervalPolicy.interval(
                state: UIDevice.current.batteryState, level: UIDevice.current.batteryLevel
            )
        },
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.healthKitManager = healthKitManager
        self.foregroundRefreshEnabled = foregroundRefreshEnabled
        self.syncEnabled = syncEnabled
        self.minimumInterval = minimumInterval
        self.now = now
        self.sleep = sleep
    }

    /// Scene activation and view appearance share this pending task and cooldown.
    /// Returning immediately lets cached data paint before any HealthKit work.
    func requestForegroundRefresh(syncEnabled: Bool) {
        guard syncEnabled, foregroundRefreshTask == nil, canRefreshInForeground() else { return }
        guard foregroundRefreshIsDue() else { return }

        let requestID = UUID()
        foregroundRefreshID = requestID
        foregroundRefreshTask = Task(priority: .utility) { [weak self, sleep] in
            defer {
                if self?.foregroundRefreshID == requestID {
                    self?.foregroundRefreshTask = nil
                    self?.foregroundRefreshID = nil
                }
            }
            do { try await sleep(BatterySyncIntervalPolicy.debounceInterval) } catch { return }
            guard let self, !Task.isCancelled else { return }
            guard self.canRefreshInForeground(), self.foregroundRefreshIsDue() else { return }
            self.lastForegroundRefresh = self.now()
            let anchored = await self.healthKitManager.performSmartScaleRefresh()
            guard !Task.isCancelled, anchored.outcome != .denied, self.canRefreshInForeground() else { return }
            if anchored.outcome == .inactive {
                try? await self.syncWeightFromHealthKit()
            }
            guard !Task.isCancelled, self.canRefreshInForeground() else { return }
            try? await self.syncStepsFromHealthKit()
        }
    }

    private func canRefreshInForeground() -> Bool {
        guard foregroundRefreshEnabled(), syncEnabled(), healthKitManager.isHealthKitAvailable,
              healthKitManager.admitsAutomaticImportForCurrentAccount() else { return false }
        healthKitManager.checkAuthorizationStatus()
        return healthKitManager.isAuthorized
    }

    private func foregroundRefreshIsDue() -> Bool {
        BatterySyncIntervalPolicy.permitsRefresh(
            lastRefresh: lastForegroundRefresh, now: now(), minimumInterval: minimumInterval()
        )
    }

    private func cancelForegroundRefresh() {
        foregroundRefreshTask?.cancel()
        foregroundRefreshTask = nil
        foregroundRefreshID = nil
        lastForegroundRefresh = nil
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
        guard healthKitManager.isHealthKitAvailable else { return }
        guard healthKitManager.admitsAutomaticImportForCurrentAccount() else { return }

        if hasBootstrappedObservers {
            healthKitManager.checkAuthorizationStatus()
            if healthKitManager.isAuthorized {
                scheduleSmartScaleForegroundRefresh()
            }
            return
        }

        healthKitManager.checkAuthorizationStatus()

        guard healthKitManager.isAuthorized else { return }

        hasBootstrappedObservers = true

        healthKitManager.observeWeightChanges()
        healthKitManager.observeBodyFatChanges()
        healthKitManager.observeStepChanges()

        Task {
            try? await healthKitManager.setupBackgroundDelivery()
            try? await healthKitManager.setupStepCountBackgroundDelivery()
        }
        scheduleSmartScaleForegroundRefresh()
    }

    /// Foreground entry. The manager no-ops while `healthkit_smart_scale_sync_v1` is off.
    private func scheduleSmartScaleForegroundRefresh() {
        if foregroundRefreshEnabled() {
            requestForegroundRefresh(syncEnabled: true)
            return
        }
        Task { await healthKitManager.refreshSmartScaleSamplesIfEnabled() }
    }

    /// Reset all HealthKit-related state for the current user and clear
    /// coordinator bootstrap state. Used when deleting the account or
    /// signing out completely.
    func resetForCurrentUser() async {
        cancelForegroundRefresh()
        hasBootstrappedObservers = false
        await healthKitManager.resetForCurrentUser()
    }

    /// Stop observers after sign-out without erasing the account that owns
    /// automatic import. The same account can bootstrap again. Another
    /// account cannot inherit this device's HealthKit sync.
    func suspendAutomaticImportAfterSignOut() async {
        cancelForegroundRefresh()
        hasBootstrappedObservers = false
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
        guard healthKitManager.isAuthorized else { return }

        bootstrapIfNeeded(syncEnabled: true)

        Task.detached(priority: .background) { [healthKitManager] in
            try? await healthKitManager.syncWeightFromHealthKit()
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
        guard healthKitManager.isAuthorized else { return }

        bootstrapIfNeeded(syncEnabled: true)

        Task.detached(priority: .background) { [healthKitManager] in
            do {
                try await healthKitManager.syncWeightFromHealthKit()
                try await healthKitManager.syncStepsFromHealthKit()
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

        guard healthKitManager.isAuthorized else { return }

        let manager = healthKitManager
        Task.detached {
            try? await manager.fetchTodayStepCount()
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
        bootstrapIfNeeded(syncEnabled: true)
        try await healthKitManager.setupBackgroundDelivery()
        try await healthKitManager.setupStepCountBackgroundDelivery()
        try await healthKitManager.syncWeightFromHealthKit()
        _ = try await healthKitManager.fetchTodayStepCount()
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
        guard healthKitManager.isAuthorized else { return }

        bootstrapIfNeeded(syncEnabled: true)

        do {
            try await healthKitManager.syncWeightFromHealthKit()
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

        try await healthKitManager.syncWeightFromHealthKit()
    }

    /// Thin wrapper around the full step history sync. Callers are
    /// responsible for checking authorization and handling errors.
    func syncStepsFromHealthKit() async throws {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.syncStepsFromHealthKit",
            category: "healthKitCoordinator"
        )

        try await healthKitManager.syncStepsFromHealthKit()
    }

    /// Trigger a full historical HealthKit import. This is used by manual
    /// "Sync All Historical Data" actions and the dashboard sync details
    /// sheet.
    func forceFullHealthKitSync() async -> Bool {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.forceFullHealthKitSync",
            category: "healthKitCoordinator"
        )

        return await healthKitManager.forceFullHealthKitSync()
    }
}
