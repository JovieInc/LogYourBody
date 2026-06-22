import Foundation
import Combine
import Network
import Clerk
import UIKit

extension RealtimeSyncManager {
// MARK: - Pending Operations
    func loadPendingOperations() {
        if let data = UserDefaults.standard.data(forKey: "pendingSyncOperations"),
           let operations = try? JSONDecoder().decode([SyncOperation].self, from: data) {
            pendingOperations = operations
            updatePendingSyncCount()
        }
    }

func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            UserDefaults.standard.set(data, forKey: "pendingSyncOperations")
        }
    }

nonisolated func processPendingOperations(_ operations: [SyncOperation], token: String) async -> [SyncOperation] {
        guard !operations.isEmpty else { return [] }

        var failedOperations: [SyncOperation] = []

        for operation in operations {
            do {
                switch operation.type {
                case .insert, .update:
                    try await supabaseManager.upsertData(
                        table: operation.tableName,
                        data: operation.data,
                        token: token
                    )
                case .delete:
                    try await supabaseManager.deleteData(
                        table: operation.tableName,
                        id: operation.id,
                        token: token
                    )
                }
            } catch {
                var failedOp = operation
                failedOp.retryCount += 1
                if failedOp.retryCount < 3 {
                    failedOperations.append(failedOp)
                }
            }
        }

        return failedOperations
    }

// MARK: - Helpers
    func updatePendingSyncCount() {
        let userId = authManager.currentUser?.id
        pendingCountTask?.cancel()
        pendingCountTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let userId else {
                await MainActor.run {
                    self.unsyncedBodyCount = 0
                    self.unsyncedDailyCount = 0
                    self.unsyncedProfileCount = 0
                    self.unsyncedGlp1Count = 0
                    self.unsyncedDexaCount = 0
                    self.pendingSyncCount = 0
                }
                return
            }

            let operationsCount = await MainActor.run {
                self.pendingOperations.filter { $0.userId == userId }.count
            }

            let unsynced: PendingLocalSyncCounts
            do {
                unsynced = try await self.coreDataManager.fetchPendingLocalSyncCounts(for: userId)
            } catch {
                await MainActor.run {
                    self.pendingSyncCount = max(self.pendingSyncCount, operationsCount + 1)
                }
                return
            }

            await MainActor.run {
                self.unsyncedBodyCount = unsynced.bodyMetrics
                self.unsyncedDailyCount = unsynced.dailyMetrics
                self.unsyncedProfileCount = unsynced.profiles
                self.unsyncedGlp1Count = unsynced.glp1DoseLogs
                self.unsyncedDexaCount = unsynced.dexaResults
                self.pendingSyncCount = unsynced.total +
                    operationsCount
            }
        }
    }

func hasPendingSyncOperations() async -> Bool {
        guard let userId = authManager.currentUser?.id else {
            return false
        }

        do {
            let unsynced = try await coreDataManager.fetchPendingLocalSyncCounts(for: userId)
            return unsynced.total > 0 ||
                pendingOperations.contains { $0.userId == userId }
        } catch {
            return true
        }
    }

func shouldPullLatestData() -> Bool {
        guard let lastSync = lastSyncDate else { return true }

        // Pull if more than 5 minutes have passed
        return Date().timeIntervalSince(lastSync) > syncInterval
    }

func needsRemoteRefresh(after threshold: TimeInterval = 300) -> Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > threshold
    }

func scheduleBackgroundSync() {
        // This would use BGTaskScheduler for iOS 13+
        // Implementation depends on app capabilities
    }

// MARK: - Public Methods
    @discardableResult
    func deleteBodyMetric(id: String) async -> Bool {
        let success = await coreDataManager.markBodyMetricDeleted(id: id)
        guard success else { return false }

        queueOperation(
            SyncOperation(
                id: id,
                userId: authManager.currentUser?.id,
                type: .delete,
                data: Data(),
                tableName: "body_metrics",
                timestamp: Date()
            )
        )

        if isOnline {
            syncAll()
        }

        return true
    }

func logBodyMetrics(_ metrics: BodyMetrics) {
        guard let userId = authManager.currentUser?.id else { return }

        let metricsWithUserId = BodyMetrics(
            id: metrics.id,
            userId: userId,
            date: metrics.date,
            localDate: metrics.localDate,
            weight: metrics.weight,
            weightUnit: metrics.weightUnit,
            bodyFatPercentage: metrics.bodyFatPercentage,
            bodyFatMethod: metrics.bodyFatMethod,
            muscleMass: metrics.muscleMass,
            boneMass: metrics.boneMass,
            notes: metrics.notes,
            photoUrl: metrics.photoUrl,
            dataSource: metrics.dataSource,
            sourceMetadata: metrics.sourceMetadata,
            createdAt: metrics.createdAt,
            updatedAt: metrics.updatedAt
        )

        coreDataManager.saveBodyMetrics(metricsWithUserId, userId: userId, markAsSynced: false)
        updatePendingSyncCount()
        syncIfNeeded()
    }

func queueOperation(_ operation: SyncOperation) {
        pendingOperations.append(operation)
        savePendingOperations()
        updatePendingSyncCount()

        // Try to sync immediately if online
        if isOnline {
            syncIfNeeded()
        }
    }

func clearError() {
        error = nil
        if syncStatus == .error("") {
            syncStatus = .idle
        }
    }
}
