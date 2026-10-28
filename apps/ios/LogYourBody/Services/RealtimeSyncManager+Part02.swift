import Foundation
import Combine
import Network
import UIKit

extension RealtimeSyncManager {
// MARK: - Pending Operations
    func loadPendingOperations() {
        if let data = userDefaults.data(forKey: Constants.pendingSyncOperationsKey),
           var operations = try? JSONDecoder().decode([SyncOperation].self, from: data) {
            var identifiers = Set<UUID>()
            for index in operations.indices {
                if let identifier = operations[index].queueID, identifiers.insert(identifier).inserted { continue }
                let identifier = UUID()
                operations[index].queueID = identifier
                identifiers.insert(identifier)
            }
            pendingOperations = operations
            savePendingOperations()
            updatePendingSyncCount()
        }
    }

func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            userDefaults.set(data, forKey: Constants.pendingSyncOperationsKey)
        }
    }

nonisolated func processPendingOperations(
        _ operations: [SyncOperation], token: String,
        ownership: AuthManager.RequestSessionOwnership? = nil
    ) async -> [SyncOperation] {
        guard !operations.isEmpty else { return [] }

        var failedOperations: [SyncOperation] = []

        for (index, operation) in operations.enumerated() {
            if let ownership {
                let isCurrent = await authManager.ownsRequestSession(ownership)
                guard isCurrent, operation.userId == ownership.subject else {
                    failedOperations.append(contentsOf: operations[index...])
                    break
                }
            }
            do {
                switch operation.type {
                case .insert, .update:
                    let response = try await productAPIClient.upsertData(
                        table: operation.tableName,
                        data: operation.data,
                        token: token
                    )
                    guard response.contains(where: { $0["id"] as? String == operation.id }) else {
                        throw ProductAPIError.invalidResponse
                    }
                case .delete:
                    try await productAPIClient.deleteData(
                        table: operation.tableName,
                        id: operation.id,
                        token: token
                    )
                }
                await acknowledgePendingOperation(operation)
            } catch {
                var failedOp = operation
                if failedOp.retryCount < Int.max { failedOp.retryCount += 1 }
                failedOperations.append(failedOp)
                await retainFailedPendingOperation(failedOp)
            }
        }

        return failedOperations
    }

    func acknowledgePendingOperation(_ operation: SyncOperation) {
        guard let index = pendingOperations.firstIndex(where: { $0.matchesQueuedChange(operation) }) else { return }
        pendingOperations.remove(at: index)
        savePendingOperations()
    }

    func retainFailedPendingOperation(_ operation: SyncOperation) {
        guard let index = pendingOperations.firstIndex(where: { $0.matchesQueuedChange(operation) }) else { return }
        pendingOperations[index].retryCount = operation.retryCount
        savePendingOperations()
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
        guard let userId = authManager.currentUser?.id else { return false }

        let success = await coreDataManager.markBodyMetricDeleted(id: id, userId: userId)
        guard success else { return false }

        queueOperation(
            SyncOperation(
                id: id,
                userId: userId,
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
        var queued = operation
        queued.queueID = UUID()
        pendingOperations.append(queued)
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
