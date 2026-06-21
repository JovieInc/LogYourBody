//
// RealtimeSyncManager.swift
// LogYourBody
//
import Foundation
import Combine
import Network
import Clerk
import UIKit

/// Optimized sync manager with real-time capabilities and battery efficiency
@MainActor
class RealtimeSyncManager: ObservableObject {
    static let shared = RealtimeSyncManager()

    // MARK: - Published Properties
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var pendingSyncCount = 0
    @Published var unsyncedBodyCount = 0
    @Published var unsyncedDailyCount = 0
    @Published var unsyncedProfileCount = 0
    @Published var unsyncedGlp1Count = 0
    @Published var unsyncedDexaCount = 0
    @Published var isOnline = true
    @Published var realtimeConnected = false
    @Published var error: String?

    // MARK: - Private Properties
    nonisolated let coreDataManager: CoreDataManager
    nonisolated let authManager: AuthManager
    nonisolated let supabaseManager: SupabaseManager
    private let networkMonitor: NWPathMonitor

    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var syncQueue = DispatchQueue(label: "com.logyourbody.sync", qos: .background)
    private var pendingOperations: [SyncOperation] = []
    private var isProcessingQueue = false
    private var pendingCountTask: Task<Void, Never>?

    // Battery optimization settings
    private var syncInterval: TimeInterval = 300 // 5 minutes default
    private var lastSyncAttempt: Date?
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3

    // WebSocket for real-time (when available)
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketPingTimer: Timer?

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
        case offline
    }

    struct SyncOperation: Codable {
        let id: String
        let userId: String?
        let type: OperationType
        let data: Data
        let tableName: String
        let timestamp: Date
        var retryCount: Int = 0

        enum OperationType: String, Codable {
            case insert, update, delete
        }
    }

    // MARK: - Initialization
    private init() {
        coreDataManager = CoreDataManager.shared
        authManager = AuthManager.shared
        supabaseManager = SupabaseManager.shared
        networkMonitor = NWPathMonitor()

        setupNetworkMonitoring()
        setupAuthListener()
        observeAppLifecycle()
        loadPendingOperations()
    }

    init(
        coreDataManager: CoreDataManager,
        authManager: AuthManager,
        supabaseManager: SupabaseManager,
        networkMonitor: NWPathMonitor = NWPathMonitor()
    ) {
        self.coreDataManager = coreDataManager
        self.authManager = authManager
        self.supabaseManager = supabaseManager
        self.networkMonitor = networkMonitor
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        let queue = DispatchQueue.global(qos: .background)
        networkMonitor.start(queue: queue)

        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied

                if self.isOnline {
                    self.syncStatus = .idle
                    if wasOffline {
                        // Coming back online - sync immediately
                        self.syncAll()
                    }
                } else {
                    self.syncStatus = .offline
                    self.disconnectRealtime()
                }
            }
        }
    }

    // MARK: - Auth Listener
    private func setupAuthListener() {
        authManager.$currentUser
            .sink { [weak self] user in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    if user != nil {
                        self.startAutoSync()
                        self.connectRealtime()
                    } else {
                        self.stopAutoSync()
                        self.disconnectRealtime()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - App Lifecycle
    private func observeAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppBecameActive()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppEnteredBackground()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func handleAppBecameActive() {
        // Resume real-time connection if authenticated
        if authManager.isAuthenticated {
            connectRealtime()
            syncIfNeeded()
        }

        // Adjust sync interval based on battery level
        adjustSyncIntervalForBattery()
    }

    private func handleAppEnteredBackground() {
        // Disconnect real-time to save battery
        disconnectRealtime()

        // Save pending operations
        savePendingOperations()

        // Schedule background sync if needed
        if pendingSyncCount > 0 {
            scheduleBackgroundSync()
        }
    }

    // MARK: - Battery Optimization
    private func adjustSyncIntervalForBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        syncInterval = BatterySyncIntervalPolicy.interval(
            state: UIDevice.current.batteryState,
            level: UIDevice.current.batteryLevel
        )

        // Restart timer with new interval
        startAutoSync()
    }

    // MARK: - Auto Sync
    private func startAutoSync() {
        stopAutoSync()

        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncIfNeeded()
            }
        }
    }

    private func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync Logic
    func syncIfNeeded() {
        guard isOnline else { return }
        guard authManager.isAuthenticated else { return }
        guard !isSyncing else { return }

        // Check if enough time has passed since last sync attempt
        if let lastAttempt = lastSyncAttempt,
           Date().timeIntervalSince(lastAttempt) < 30 {
            return // Prevent too frequent syncs
        }

        // Check for pending changes
        updatePendingSyncCount()

        if pendingSyncCount > 0 || shouldPullLatestData() {
            syncAll()
        }
    }

    func syncAll(onCompletion: (() -> Void)? = nil) {
        guard !isSyncing else {
            onCompletion?()
            return
        }
        guard isOnline else {
            syncStatus = .offline
            onCompletion?()
            return
        }
        guard authManager.isAuthenticated else {
            onCompletion?()
            return
        }
        guard let userIdSnapshot = authManager.currentUser?.id else {
            onCompletion?()
            return
        }

        lastSyncAttempt = Date()
        isSyncing = true
        syncStatus = .syncing
        error = nil

        let operationsToProcess = pendingOperations.filter { $0.userId == userIdSnapshot }
        pendingOperations.removeAll { $0.userId == userIdSnapshot || $0.userId == nil }
        savePendingOperations()

        let lastSyncSnapshot = lastSyncDate

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var operationsNeedingRetry = operationsToProcess

            do {
                let session = await MainActor.run { self.authManager.clerkSession }
                guard let session else {
                    throw SyncError.noAuthSession
                }

                let tokenResource = try await session.getToken()
                guard let token = tokenResource?.jwt else {
                    throw SyncError.tokenGenerationFailed
                }

                if !operationsNeedingRetry.isEmpty {
                    let failedOperations = await self.processPendingOperations(operationsNeedingRetry, token: token)
                    if failedOperations.isEmpty {
                        operationsNeedingRetry.removeAll()
                    } else {
                        operationsNeedingRetry = failedOperations
                        throw PendingSyncError.failedOperations
                    }
                }

                try await self.syncLocalChanges(for: userIdSnapshot, token: token)
                try await self.pullLatestData(userId: userIdSnapshot, lastSync: lastSyncSnapshot, token: token)
                await self.coreDataManager.cleanupOldData()

                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatus = .success
                    self.lastSyncDate = Date()
                    self.consecutiveFailures = 0
                    self.updatePendingSyncCount()
                    self.savePendingOperations()
                    onCompletion?()
                }
            } catch {
                if let supabaseError = error as? SupabaseError {
                    if case .unauthorized = supabaseError {
                        await self.authManager.handleSupabaseUnauthorized()
                    }
                }

                await MainActor.run {
                    if !operationsNeedingRetry.isEmpty {
                        self.pendingOperations.insert(contentsOf: operationsNeedingRetry, at: 0)
                    }
                    self.isSyncing = false
                    self.syncStatus = .error(error.localizedDescription)
                    self.error = error.localizedDescription
                    self.consecutiveFailures += 1

                    if self.consecutiveFailures >= self.maxConsecutiveFailures {
                        self.syncInterval = min(self.syncInterval * 2, 3_600)
                        self.startAutoSync()
                    }

                    self.savePendingOperations()
                    self.updatePendingSyncCount()
                    AnalyticsService.shared.track(
                        event: "sync_failed",
                        properties: [
                            "pending_count": String(self.pendingSyncCount)
                        ]
                    )
                    onCompletion?()
                }
            }
        }
    }

    func syncAllAwaitingCompletion() async {
        await withCheckedContinuation { continuation in
            self.syncAll {
                continuation.resume()
            }
        }
    }

    nonisolated func syncLocalChanges(token: String) async throws {
        try await syncLocalChanges(for: nil, token: token)
    }

    nonisolated func syncLocalChanges(for userId: String?, token: String) async throws {
        let unsynced = try await coreDataManager.fetchPendingLocalSyncSnapshot(for: userId)
        let deletedBodyMetrics = unsynced.bodyMetrics.filter(\.isMarkedDeleted)
        let bodyMetricsToUpsert = unsynced.bodyMetrics.filter { !$0.isMarkedDeleted }
        let deletedGlp1DoseLogs = unsynced.glp1DoseLogs.filter(\.isMarkedDeleted)
        let glp1DoseLogsToUpsert = unsynced.glp1DoseLogs.filter { !$0.isMarkedDeleted }

        if !deletedBodyMetrics.isEmpty {
            try await syncDeletedBodyMetricsBatch(deletedBodyMetrics, token: token)
        }

        if !bodyMetricsToUpsert.isEmpty {
            try await syncBodyMetricsBatch(bodyMetricsToUpsert, token: token)
        }

        if !unsynced.dailyMetrics.isEmpty {
            try await syncDailyMetricsBatch(unsynced.dailyMetrics, token: token)
        }

        if !unsynced.profiles.isEmpty {
            try await syncProfilesBatch(unsynced.profiles, token: token)
        }

        if !deletedGlp1DoseLogs.isEmpty {
            try await syncDeletedGlp1DoseLogsBatch(deletedGlp1DoseLogs, token: token)
        }

        if !glp1DoseLogsToUpsert.isEmpty {
            try await syncGlp1DoseLogsBatch(glp1DoseLogsToUpsert, token: token)
        }

        if !unsynced.glp1Medications.isEmpty {
            try await syncGlp1MedicationsBatch(unsynced.glp1Medications, token: token)
        }

        if !unsynced.dexaResults.isEmpty {
            try await syncDexaResultsBatch(unsynced.dexaResults, token: token)
        }
    }

    nonisolated private func syncDeletedBodyMetricsBatch(
        _ metrics: [PendingBodyMetricSyncItem],
        token: String
    ) async throws {
        var syncedIds = Set<String>()

        do {
            for metric in metrics {
                try await supabaseManager.deleteData(table: "body_metrics", id: metric.id, token: token)
                syncedIds.insert(metric.id)
            }
        } catch {
            await coreDataManager.markAsSynced(entityName: "CachedBodyMetrics", ids: syncedIds)
            throw error
        }

        await coreDataManager.markAsSynced(entityName: "CachedBodyMetrics", ids: syncedIds)
    }

    nonisolated private func syncDeletedGlp1DoseLogsBatch(
        _ logs: [PendingGlp1DoseLogSyncItem],
        token: String
    ) async throws {
        var syncedIds = Set<String>()

        do {
            for log in logs {
                try await supabaseManager.deleteData(table: "glp1_dose_logs", id: log.id, token: token)
                syncedIds.insert(log.id)
            }
        } catch {
            await coreDataManager.markAsSynced(entityName: "CachedGlp1DoseLog", ids: syncedIds)
            throw error
        }

        await coreDataManager.markAsSynced(entityName: "CachedGlp1DoseLog", ids: syncedIds)
    }

    nonisolated private func syncBodyMetricsBatch(_ metrics: [PendingBodyMetricSyncItem], token: String) async throws {
        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.map { metric -> [String: Any] in
                [
                    "id": metric.id,
                    "user_id": metric.userId,
                    "date": formatter.string(from: metric.date),
                    "local_date": BodyMetricLocalDate.normalized(metric.localDate, fallback: metric.date),
                    "weight": metric.weight,
                    "weight_unit": metric.weightUnit ?? "kg",
                    "waist_circumference": metric.waistCircumference as Any,
                    "hip_circumference": metric.hipCircumference as Any,
                    "waist_unit": metric.waistUnit ?? "cm",
                    "body_fat_percentage": metric.bodyFatPercentage as Any,
                    "body_fat_method": metric.bodyFatMethod as Any,
                    "muscle_mass": metric.muscleMass as Any,
                    "bone_mass": metric.boneMass as Any,
                    "photo_url": metric.photoUrl as Any,
                    "notes": metric.notes as Any,
                    "data_source": BodyMetricSource.normalizedRawValue(metric.dataSource),
                    "source_metadata": BodyMetricSourceMetadata(jsonString: metric.sourceMetadataJSON)?.jsonObject ?? [:],
                    "created_at": formatter.string(from: metric.createdAt),
                    "updated_at": formatter.string(from: metric.updatedAt)
                ]
            }

            let response = try await supabaseManager.upsertBodyMetricsBatch(metricsData, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })
            await coreDataManager.markAsSynced(entityName: "CachedBodyMetrics", ids: syncedIds)
        }
    }

    nonisolated private func syncDexaResultsBatch(_ results: [PendingDexaResultSyncItem], token: String) async throws {
        guard !results.isEmpty else { return }

        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in results.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.map { result in
                let externalUpdateTimeValue: Any = if let externalUpdateTime = result.externalUpdateTime {
                    formatter.string(from: externalUpdateTime)
                } else {
                    NSNull()
                }
                let acquireTimeValue: Any = if let acquireTime = result.acquireTime {
                    formatter.string(from: acquireTime)
                } else {
                    NSNull()
                }
                let analyzeTimeValue: Any = if let analyzeTime = result.analyzeTime {
                    formatter.string(from: analyzeTime)
                } else {
                    NSNull()
                }
                let vatMassValue: Any = result.vatMassKg > 0 ? result.vatMassKg : NSNull()
                let vatVolumeValue: Any = result.vatVolumeCm3 > 0 ? result.vatVolumeCm3 : NSNull()

                return [
                    "id": result.id,
                    "user_id": result.userId,
                    "body_metrics_id": result.bodyMetricsId as Any,
                    "external_source": result.externalSource as Any,
                    "external_result_id": result.externalResultId as Any,
                    "external_update_time": externalUpdateTimeValue,
                    "scanner_model": result.scannerModel as Any,
                    "location_id": result.locationId as Any,
                    "location_name": result.locationName as Any,
                    "acquire_time": acquireTimeValue,
                    "analyze_time": analyzeTimeValue,
                    "vat_mass_kg": vatMassValue,
                    "vat_volume_cm3": vatVolumeValue,
                    "result_pdf_url": result.resultPdfUrl as Any,
                    "result_pdf_name": result.resultPdfName as Any,
                    "created_at": formatter.string(from: result.createdAt),
                    "updated_at": formatter.string(from: result.updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = try await supabaseManager.upsertData(table: "dexa_results", data: data, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })
            await coreDataManager.markAsSynced(entityName: "CachedDexaResult", ids: syncedIds)
        }
    }

    nonisolated private func syncGlp1MedicationsBatch(
        _ medications: [PendingGlp1MedicationSyncItem],
        token: String
    ) async throws {
        guard !medications.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        let batchSize = 50

        for userId in Set(medications.map(\.userId)) {
            let userMeds = medications.filter { $0.userId == userId }
            let endDate = userMeds.compactMap { $0.endedAt }.max() ?? Date()
            try await supabaseManager.endActiveGlp1Medications(userId: userId, endedAt: endDate)
        }

        for batch in medications.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.map { medication in
                let endedAtValue: Any = if let endedAt = medication.endedAt {
                    formatter.string(from: endedAt)
                } else {
                    NSNull()
                }

                return [
                    "id": medication.id,
                    "user_id": medication.userId,
                    "display_name": medication.displayName as Any,
                    "generic_name": medication.genericName as Any,
                    "drug_class": medication.drugClass as Any,
                    "brand": medication.brand as Any,
                    "route": medication.route as Any,
                    "frequency": medication.frequency as Any,
                    "dose_unit": medication.doseUnit as Any,
                    "is_compounded": medication.isCompounded,
                    "hk_identifier": medication.hkIdentifier as Any,
                    "started_at": formatter.string(from: medication.startedAt),
                    "ended_at": endedAtValue,
                    "notes": medication.notes as Any,
                    "created_at": formatter.string(from: medication.createdAt),
                    "updated_at": formatter.string(from: medication.updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = try await supabaseManager.upsertData(table: "glp1_medications", data: data, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })
            await coreDataManager.markAsSynced(entityName: "CachedGlp1Medication", ids: syncedIds)
        }
    }

    nonisolated private func syncGlp1DoseLogsBatch(_ logs: [PendingGlp1DoseLogSyncItem], token: String) async throws {
        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in logs.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.map { log in
                [
                    "id": log.id,
                    "user_id": log.userId,
                    "taken_at": formatter.string(from: log.takenAt),
                    "medication_id": log.medicationId as Any,
                    "dose_amount": log.doseAmount,
                    "dose_unit": log.doseUnit as Any,
                    "drug_class": log.drugClass as Any,
                    "brand": log.brand as Any,
                    "is_compounded": log.isCompounded,
                    "supplier_type": log.supplierType as Any,
                    "supplier_name": log.supplierName as Any,
                    "notes": log.notes as Any,
                    "created_at": formatter.string(from: log.createdAt),
                    "updated_at": formatter.string(from: log.updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = try await supabaseManager.upsertData(table: "glp1_dose_logs", data: data, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })
            await coreDataManager.markAsSynced(entityName: "CachedGlp1DoseLog", ids: syncedIds)
        }
    }

    nonisolated private func syncDailyMetricsBatch(_ metrics: [PendingDailyMetricSyncItem], token: String) async throws {
        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.map { metric -> [String: Any] in
                [
                    "id": metric.id,
                    "user_id": metric.userId,
                    "date": formatter.string(from: metric.date),
                    "steps": Int(metric.steps),
                    "notes": metric.notes as Any,
                    "created_at": formatter.string(from: metric.createdAt),
                    "updated_at": formatter.string(from: metric.updatedAt)
                ]
            }

            let response = try await supabaseManager.upsertDailyMetricsBatch(metricsData, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })
            await coreDataManager.markAsSynced(entityName: "CachedDailyMetrics", ids: syncedIds)
        }
    }

    nonisolated private func syncProfilesBatch(_ profiles: [PendingProfileSyncItem], token: String) async throws {
        let formatter = ISO8601DateFormatter()

        for profile in profiles {
            let formattedBirthDate: Any = if let dateOfBirth = profile.dateOfBirth {
                formatter.string(from: dateOfBirth)
            } else {
                NSNull()
            }

            let profileData: [String: Any] = [
                "id": profile.id,
                "full_name": profile.fullName as Any,
                "username": profile.username as Any,
                "height": profile.height,
                "height_unit": profile.heightUnit as Any,
                "gender": profile.gender as Any,
                "date_of_birth": formattedBirthDate,
                "activity_level": profile.activityLevel as Any
            ]

            try await supabaseManager.updateProfile(profileData, token: token)
            await coreDataManager.markAsSynced(entityName: "CachedProfile", ids: [profile.id])
        }
    }

    nonisolated private func pullLatestData(userId: String, lastSync: Date?, token: String) async throws {
        // Get last sync date for incremental sync
        let lastSync = lastSync ?? Date().addingTimeInterval(-7 * 24 * 60 * 60) // Default to 1 week ago

        // Pull latest body metrics
        let bodyMetrics = try await supabaseManager.fetchBodyMetrics(
            userId: userId,
            since: lastSync,
            token: token
        )

        for metricData in bodyMetrics {
            coreDataManager.updateOrCreateBodyMetric(from: metricData)
        }

        // Pull latest daily metrics
        let dailyMetrics = try await supabaseManager.fetchDailyMetrics(
            userId: userId,
            since: lastSync,
            token: token
        )

        for metricData in dailyMetrics {
            coreDataManager.updateOrCreateDailyMetric(from: metricData)
        }

        // Pull profile updates
        if let profileData = try await supabaseManager.fetchProfile(userId: userId, token: token) {
            coreDataManager.updateOrCreateProfile(from: profileData)
        }

        // Pull latest body metric timestamp
        if let remoteLatest = try? await supabaseManager.fetchLatestBodyMetricTimestamp(
            userId: userId,
            token: token
        ) {
            // Use remoteLatest as needed (currently no-op)
            _ = remoteLatest
        }

        let isStillAuthenticated = await MainActor.run {
            self.authManager.isAuthenticated
        }
        let stillOnline = await MainActor.run {
            self.isOnline
        }

        guard isStillAuthenticated else { return }
        guard stillOnline else { return }

        // For now, we'll use polling instead of WebSocket to simplify
        // WebSocket implementation can be added later for true real-time
        await MainActor.run {
            self.realtimeConnected = false
        }
    }

    private func connectRealtime() {
        realtimeConnected = false
    }

    private func disconnectRealtime() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        webSocketPingTimer?.invalidate()
        webSocketPingTimer = nil
        realtimeConnected = false
    }

    // MARK: - Pending Operations
    private func loadPendingOperations() {
        if let data = UserDefaults.standard.data(forKey: "pendingSyncOperations"),
           let operations = try? JSONDecoder().decode([SyncOperation].self, from: data) {
            pendingOperations = operations
            updatePendingSyncCount()
        }
    }

    private func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            UserDefaults.standard.set(data, forKey: "pendingSyncOperations")
        }
    }

    nonisolated private func processPendingOperations(_ operations: [SyncOperation], token: String) async -> [SyncOperation] {
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
    private func shouldPullLatestData() -> Bool {
        guard let lastSync = lastSyncDate else { return true }

        // Pull if more than 5 minutes have passed
        return Date().timeIntervalSince(lastSync) > syncInterval
    }

    func needsRemoteRefresh(after threshold: TimeInterval = 300) -> Bool {
        guard let lastSync = lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > threshold
    }

    private func scheduleBackgroundSync() {
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

enum PendingSyncError: LocalizedError {
    case failedOperations

    var errorDescription: String? {
        switch self {
        case .failedOperations:
            return "Some operations need to be retried"
        }
    }
}

// MARK: - Errors
enum SyncError: LocalizedError {
    case noAuthSession
    case networkError
    case serverError(String)
    case tokenGenerationFailed

    var errorDescription: String? {
        switch self {
        case .noAuthSession:
            return "No active session"
        case .networkError:
            return "Network connection error"
        case .serverError(let message):
            return message
        case .tokenGenerationFailed:
            return "Failed to generate authentication token"
        }
    }
}

// MARK: - Array Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
