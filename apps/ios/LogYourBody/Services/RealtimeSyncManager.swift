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
    private var syncTask: Task<Void, Never>?
    private var syncRequestPending = false
    private var syncCompletionHandlers: [() -> Void] = []

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
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState

        switch (batteryState, batteryLevel) {
        case (.charging, _), (.full, _):
            // Aggressive sync when charging
            syncInterval = 60 // 1 minute
        case (_, let level) where level > 0.5:
            // Normal sync above 50% battery
            syncInterval = 300 // 5 minutes
        case (_, let level) where level > 0.2:
            // Conservative sync below 50% battery
            syncInterval = 900 // 15 minutes
        default:
            // Minimal sync below 20% battery
            syncInterval = 1_800 // 30 minutes
        }

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

        // Check if enough time has passed since last sync attempt
        if let lastAttempt = lastSyncAttempt,
           Date().timeIntervalSince(lastAttempt) < 30,
           !isSyncing {
            return // Prevent too frequent syncs when idle
        }

        // Check for pending changes
        updatePendingSyncCount()

        if pendingSyncCount > 0 || shouldPullLatestData() {
            syncAll()
        }
    }

    func syncAll(onCompletion: (() -> Void)? = nil) {
        if let onCompletion {
            syncCompletionHandlers.append(onCompletion)
        }

        syncRequestPending = true

        guard syncTask == nil else { return }

        syncRequestPending = false
        syncTask = Task(priority: .utility) { [weak self] in
            await self?.runSyncCycle()
        }
    }

    func syncAllAwaitingCompletion() async {
        await withCheckedContinuation { continuation in
            self.syncAll {
                continuation.resume()
            }
        }
    }

    private func runSyncCycle() async {
        struct SyncContext {
            let operationsToProcess: [SyncOperation]
            let lastSyncSnapshot: Date?
            let userIdSnapshot: String?
        }

        guard let context = await MainActor.run({ () -> SyncContext? in
            guard self.isOnline else {
                self.syncStatus = .offline
                return nil
            }

            guard self.authManager.isAuthenticated else {
                return nil
            }

            self.lastSyncAttempt = Date()
            self.isSyncing = true
            self.syncStatus = .syncing
            self.error = nil

            let operationsToProcess = self.pendingOperations
            self.pendingOperations.removeAll()
            self.savePendingOperations()

            return SyncContext(
                operationsToProcess: operationsToProcess,
                lastSyncSnapshot: self.lastSyncDate,
                userIdSnapshot: self.authManager.currentUser?.id
            )
        }) else {
            await finalizeSyncCycle(status: isOnline ? .idle : .offline)
            return
        }

        var operationsNeedingRetry = context.operationsToProcess

        do {
            guard let userId = context.userIdSnapshot else {
                throw SyncError.noAuthSession
            }

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

            try await self.syncLocalChanges(token: token)
            try await self.pullLatestData(userId: userId, lastSync: context.lastSyncSnapshot, token: token)
            self.coreDataManager.cleanupOldData()

            await finalizeSyncCycle(
                status: .success,
                operationsNeedingRetry: operationsNeedingRetry,
                shouldUpdateLastSync: true
            )
        } catch {
            if let supabaseError = error as? SupabaseError {
                if case .unauthorized = supabaseError {
                    await self.authManager.handleSupabaseUnauthorized()
                }
            }

            await finalizeSyncCycle(
                status: .error(error.localizedDescription),
                operationsNeedingRetry: operationsNeedingRetry,
                errorDescription: error.localizedDescription
            )
        }
    }

    @MainActor
    private func finalizeSyncCycle(
        status: SyncStatus,
        operationsNeedingRetry: [SyncOperation] = [],
        shouldUpdateLastSync: Bool = false,
        errorDescription: String? = nil
    ) {
        if !operationsNeedingRetry.isEmpty {
            pendingOperations.insert(contentsOf: operationsNeedingRetry, at: 0)
        }

        isSyncing = false
        syncStatus = status
        syncTask = nil

        switch status {
        case .success:
            error = nil
            if shouldUpdateLastSync {
                lastSyncDate = Date()
            }
            consecutiveFailures = 0
        case .error:
            error = errorDescription
            consecutiveFailures += 1

            if consecutiveFailures >= maxConsecutiveFailures {
                syncInterval = min(syncInterval * 2, 3_600)
                startAutoSync()
            }
        default:
            break
        }

        savePendingOperations()
        updatePendingSyncCount()

        let callbacks = syncCompletionHandlers
        syncCompletionHandlers.removeAll()

        let shouldResync = syncRequestPending && isOnline && authManager.isAuthenticated
        syncRequestPending = false

        callbacks.forEach { $0() }

        if shouldResync {
            syncAll()
        }
    }

    nonisolated func syncLocalChanges(token: String) async throws {
        let unsynced = await coreDataManager.fetchUnsyncedEntries()
        let unsyncedGlp1 = await coreDataManager.fetchUnsyncedGlp1DoseLogs()
        let unsyncedMedications = await coreDataManager.fetchUnsyncedGlp1Medications()
        let unsyncedDexa = await coreDataManager.fetchUnsyncedDexaResults()

        // Batch sync for efficiency
        if !unsynced.bodyMetrics.isEmpty {
            try await syncBodyMetricsBatch(unsynced.bodyMetrics, token: token)
        }

        if !unsynced.dailyMetrics.isEmpty {
            try await syncDailyMetricsBatch(unsynced.dailyMetrics, token: token)
        }

        if !unsynced.profiles.isEmpty {
            try await syncProfilesBatch(unsynced.profiles, token: token)
        }

        if !unsyncedGlp1.isEmpty {
            try await syncGlp1DoseLogsBatch(unsyncedGlp1, token: token)
        }

        if !unsyncedMedications.isEmpty {
            try await syncGlp1MedicationsBatch(unsyncedMedications, token: token)
        }

        if !unsyncedDexa.isEmpty {
            try await syncDexaResultsBatch(unsyncedDexa, token: token)
        }
    }

    nonisolated private func syncBodyMetricsBatch(_ metrics: [CachedBodyMetrics], token: String) async throws {
        let batchSize = 50 // Sync in batches to avoid timeouts
        let formatter = ISO8601DateFormatter()

        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.compactMap { metric -> [String: Any]? in
                let id = metric.id ?? UUID().uuidString
                let date = metric.date ?? Date()
                let createdAt = metric.createdAt ?? date
                let updatedAt = metric.updatedAt ?? createdAt

                return [
                    "id": id,
                    "user_id": metric.userId ?? "",
                    "date": formatter.string(from: date),
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
                    "created_at": formatter.string(from: createdAt),
                    "updated_at": formatter.string(from: updatedAt)
                ]
            }

            let response = try await supabaseManager.upsertBodyMetricsBatch(metricsData, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })

            for metric in batch {
                if let id = metric.id, syncedIds.contains(id) {
                    metric.syncStatus = "synced"
                    metric.isSynced = true
                }
            }

            coreDataManager.save()
        }
    }

    nonisolated private func syncDexaResultsBatch(_ results: [CachedDexaResult], token: String) async throws {
        guard !results.isEmpty else { return }

        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in results.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.compactMap { result in
                let id = result.id ?? UUID().uuidString
                let userId = result.userId ?? ""
                let createdAt = result.createdAt ?? Date()
                let updatedAt = result.updatedAt ?? createdAt

                let externalUpdateTimeValue: Any
                if let externalUpdateTime = result.externalUpdateTime {
                    externalUpdateTimeValue = formatter.string(from: externalUpdateTime)
                } else {
                    externalUpdateTimeValue = NSNull()
                }

                let acquireTimeValue: Any
                if let acquireTime = result.acquireTime {
                    acquireTimeValue = formatter.string(from: acquireTime)
                } else {
                    acquireTimeValue = NSNull()
                }

                let analyzeTimeValue: Any
                if let analyzeTime = result.analyzeTime {
                    analyzeTimeValue = formatter.string(from: analyzeTime)
                } else {
                    analyzeTimeValue = NSNull()
                }

                let vatMassValue: Any
                if result.vatMassKg > 0 {
                    vatMassValue = result.vatMassKg
                } else {
                    vatMassValue = NSNull()
                }

                let vatVolumeValue: Any
                if result.vatVolumeCm3 > 0 {
                    vatVolumeValue = result.vatVolumeCm3
                } else {
                    vatVolumeValue = NSNull()
                }

                return [
                    "id": id,
                    "user_id": userId,
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
                    "created_at": formatter.string(from: createdAt),
                    "updated_at": formatter.string(from: updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            try await supabaseManager.upsertData(table: "dexa_results", data: data, token: token)

            for result in batch {
                result.isSynced = true
                result.syncStatus = "synced"
            }

            coreDataManager.save()
        }
    }

    nonisolated private func syncGlp1MedicationsBatch(_ medications: [CachedGlp1Medication], token: String) async throws {
        guard !medications.isEmpty else { return }

        let formatter = ISO8601DateFormatter()
        let batchSize = 50

        let userIds = Set(medications.compactMap { $0.userId })

        for userId in userIds {
            let userMeds = medications.filter { $0.userId == userId }
            let endDate = userMeds.compactMap { $0.endedAt }.max() ?? Date()
            try await supabaseManager.endActiveGlp1Medications(userId: userId, endedAt: endDate)
        }

        for batch in medications.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.compactMap { medication in
                let id = medication.id ?? UUID().uuidString
                let userId = medication.userId ?? ""
                let startedAt = medication.startedAt ?? Date()
                let createdAt = medication.createdAt ?? startedAt
                let updatedAt = medication.updatedAt ?? createdAt

                let endedAtValue: Any
                if let endedAt = medication.endedAt {
                    endedAtValue = formatter.string(from: endedAt)
                } else {
                    endedAtValue = NSNull()
                }

                return [
                    "id": id,
                    "user_id": userId,
                    "display_name": medication.displayName as Any,
                    "generic_name": medication.genericName as Any,
                    "drug_class": medication.drugClass as Any,
                    "brand": medication.brand as Any,
                    "route": medication.route as Any,
                    "frequency": medication.frequency as Any,
                    "dose_unit": medication.doseUnit as Any,
                    "is_compounded": medication.isCompounded,
                    "hk_identifier": medication.hkIdentifier as Any,
                    "started_at": formatter.string(from: startedAt),
                    "ended_at": endedAtValue,
                    "notes": medication.notes as Any,
                    "created_at": formatter.string(from: createdAt),
                    "updated_at": formatter.string(from: updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            try await supabaseManager.upsertData(table: "glp1_medications", data: data, token: token)

            for medication in batch {
                medication.isSynced = true
                medication.syncStatus = "synced"
            }

            coreDataManager.save()
        }
    }

    nonisolated private func syncGlp1DoseLogsBatch(_ logs: [CachedGlp1DoseLog], token: String) async throws {
        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in logs.chunked(into: batchSize) {
            let payload: [[String: Any]] = batch.compactMap { log in
                let id = log.id ?? UUID().uuidString
                let userId = log.userId ?? ""
                let takenAt = log.takenAt ?? Date()
                let createdAt = log.createdAt ?? takenAt
                let updatedAt = log.updatedAt ?? createdAt

                return [
                    "id": id,
                    "user_id": userId,
                    "taken_at": formatter.string(from: takenAt),
                    "medication_id": log.medicationId as Any,
                    "dose_amount": log.doseAmount,
                    "dose_unit": log.doseUnit as Any,
                    "drug_class": log.drugClass as Any,
                    "brand": log.brand as Any,
                    "is_compounded": log.isCompounded,
                    "supplier_type": log.supplierType as Any,
                    "supplier_name": log.supplierName as Any,
                    "notes": log.notes as Any,
                    "created_at": formatter.string(from: createdAt),
                    "updated_at": formatter.string(from: updatedAt)
                ]
            }

            let data = try JSONSerialization.data(withJSONObject: payload)
            try await supabaseManager.upsertData(table: "glp1_dose_logs", data: data, token: token)

            for log in batch {
                log.isSynced = true
                log.syncStatus = "synced"
            }

            coreDataManager.save()
        }
    }

    nonisolated private func syncDailyMetricsBatch(_ metrics: [CachedDailyMetrics], token: String) async throws {
        // Similar batch implementation for daily metrics
        let batchSize = 50
        let formatter = ISO8601DateFormatter()

        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.compactMap { metric -> [String: Any]? in
                let id = metric.id ?? UUID().uuidString
                let date = metric.date ?? Date()
                let createdAt = metric.createdAt ?? date
                let updatedAt = metric.updatedAt ?? createdAt

                return [
                    "id": id,
                    "user_id": metric.userId ?? "",
                    "date": formatter.string(from: date),
                    "steps": metric.steps,
                    "notes": metric.notes as Any,
                    "created_at": formatter.string(from: createdAt),
                    "updated_at": formatter.string(from: updatedAt)
                ]
            }

            let response = try await supabaseManager.upsertDailyMetricsBatch(metricsData, token: token)
            let syncedIds = Set(response.compactMap { $0["id"] as? String })

            for metric in batch {
                if let id = metric.id, syncedIds.contains(id) {
                    metric.syncStatus = "synced"
                    metric.isSynced = true
                }
            }

            coreDataManager.save()
        }
    }

    nonisolated private func syncProfilesBatch(_ profiles: [CachedProfile], token: String) async throws {
        // Profile sync (usually just one per user)
        for profile in profiles {
            let formattedBirthDate: Any
            if let dateOfBirth = profile.dateOfBirth {
                formattedBirthDate = ISO8601DateFormatter().string(from: dateOfBirth)
            } else {
                formattedBirthDate = NSNull()
            }

            let profileData: [String: Any] = [
                "id": profile.id ?? "",
                "full_name": profile.fullName as Any,
                "username": profile.username as Any,
                // "avatar_url": profile.avatarUrl as Any, // Field doesn't exist
                "height": profile.height,
                "height_unit": profile.heightUnit as Any,
                "gender": profile.gender as Any,
                "date_of_birth": formattedBirthDate,
                "activity_level": profile.activityLevel as Any
            ]

            try await supabaseManager.updateProfile(profileData, token: token)

            profile.syncStatus = "synced"
            // profile.lastSyncedAt = Date() // Field doesn't exist
            coreDataManager.save()
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
        pendingCountTask?.cancel()
        pendingCountTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let unsynced = await self.coreDataManager.fetchUnsyncedEntries()
            let unsyncedGlp1 = await self.coreDataManager.fetchUnsyncedGlp1DoseLogs()
            let unsyncedMedications = await self.coreDataManager.fetchUnsyncedGlp1Medications()
            let unsyncedDexa = await self.coreDataManager.fetchUnsyncedDexaResults()
            let operationsCount = await MainActor.run { self.pendingOperations.count }
            await MainActor.run {
                self.unsyncedBodyCount = unsynced.bodyMetrics.count
                self.unsyncedDailyCount = unsynced.dailyMetrics.count
                self.unsyncedProfileCount = unsynced.profiles.count
                self.unsyncedGlp1Count = unsyncedGlp1.count
                self.unsyncedDexaCount = unsyncedDexa.count
                self.pendingSyncCount = unsynced.bodyMetrics.count +
                    unsynced.dailyMetrics.count +
                    unsynced.profiles.count +
                    unsyncedGlp1.count +
                    unsyncedMedications.count +
                    unsyncedDexa.count +
                    operationsCount
            }
        }
    }

    func hasPendingSyncOperations() async -> Bool {
        let unsynced = await coreDataManager.fetchUnsyncedEntries()
        let unsyncedGlp1 = await coreDataManager.fetchUnsyncedGlp1DoseLogs()
        let unsyncedMedications = await coreDataManager.fetchUnsyncedGlp1Medications()
        let unsyncedDexa = await coreDataManager.fetchUnsyncedDexaResults()
        return !unsynced.bodyMetrics.isEmpty ||
            !unsynced.dailyMetrics.isEmpty ||
            !unsynced.profiles.isEmpty ||
            !unsyncedGlp1.isEmpty ||
            !unsyncedMedications.isEmpty ||
            !unsyncedDexa.isEmpty ||
            !pendingOperations.isEmpty
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
    func logBodyMetrics(_ metrics: BodyMetrics) {
        guard let userId = authManager.currentUser?.id else { return }

        let metricsWithUserId = BodyMetrics(
            id: metrics.id,
            userId: userId,
            date: metrics.date,
            weight: metrics.weight,
            weightUnit: metrics.weightUnit,
            bodyFatPercentage: metrics.bodyFatPercentage,
            bodyFatMethod: metrics.bodyFatMethod,
            muscleMass: metrics.muscleMass,
            boneMass: metrics.boneMass,
            notes: metrics.notes,
            photoUrl: metrics.photoUrl,
            dataSource: metrics.dataSource,
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
