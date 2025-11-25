//
// HealthSyncCoordinator.swift
// LogYourBody
//

import Foundation

/// Protocol abstraction for coordinating HealthKit-related sync operations.
/// This enables easier unit testing for components that depend on
/// HealthSyncCoordinator by allowing mock implementations.
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
    func forceFullHealthKitSync() async
}

/// Central coordinator for HealthKit bootstrap and, over time, HealthKit-related
/// sync decisions. Starts by owning the bootstrapping of observers and
/// background delivery, using HealthKitManager as the underlying adapter.
@MainActor
final class HealthSyncCoordinator: ObservableObject, HealthSyncCoordinating {
    static let shared = HealthSyncCoordinator()

    private let healthKitManager: HealthKitManager
    private var hasBootstrappedObservers = false

    private init(healthKitManager: HealthKitManager = .shared) {
        self.healthKitManager = healthKitManager
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

        if hasBootstrappedObservers {
            return
        }

        healthKitManager.checkAuthorizationStatus()

        guard healthKitManager.isAuthorized else { return }

        hasBootstrappedObservers = true

        healthKitManager.observeWeightChanges()
        healthKitManager.observeStepChanges()

        Task {
            try? await healthKitManager.setupStepCountBackgroundDelivery()
        }
    }

    /// Reset all HealthKit-related state for the current user and clear
    /// coordinator bootstrap state. Used when deleting the account or
    /// signing out completely.
    func resetForCurrentUser() async {
        hasBootstrappedObservers = false
        await healthKitManager.resetForCurrentUser()
    }

    /// Ensure observers and background delivery are configured after the
    /// user has granted authorization, then kick off an initial weight sync
    /// in the background. Intended for settings-based toggles.
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.configurePipeline.weightOnly",
            category: "healthKitCoordinator"
        )

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

        guard healthKitManager.isAuthorized else { return }

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
    func forceFullHealthKitSync() async {
        ErrorTrackingService.shared.addBreadcrumb(
            message: "HealthSyncCoordinator.forceFullHealthKitSync",
            category: "healthKitCoordinator"
        )

        await healthKitManager.forceFullHealthKitSync()
    }
}
