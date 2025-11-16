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
    @Published var isOnline = true
    @Published var realtimeConnected = false
    @Published var error: String?
    
    // MARK: - Private Properties
    private let coreDataManager = CoreDataManager.shared
    private let authManager = AuthManager.shared
    private let supabaseManager = SupabaseManager.shared
    private let networkMonitor = NWPathMonitor()
    
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var syncQueue = DispatchQueue(label: "com.logyourbody.sync", qos: .background)
    private var pendingOperations: [SyncOperation] = []
    private var isProcessingQueue = false
    
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
        setupNetworkMonitoring()
        setupAuthListener()
        observeAppLifecycle()
        loadPendingOperations()
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
    
    func syncAll() {
        guard !isSyncing else { return }
        guard isOnline else {
            syncStatus = .offline
            return
        }
        guard authManager.isAuthenticated else { return }
        
        lastSyncAttempt = Date()
        isSyncing = true
        syncStatus = .syncing
        error = nil
        
        Task {
            do {
                // Get auth token
                guard let session = authManager.clerkSession else {
                    throw SyncError.noAuthSession
                }
                
                let tokenResource = try await session.getToken()
                guard let token = tokenResource?.jwt else {
                    throw SyncError.tokenGenerationFailed
                }
                
                // Process pending operations first
                if !pendingOperations.isEmpty {
                    try await processPendingOperations(token: token)
                }
                
                // Sync unsynced local data
                try await syncLocalChanges(token: token)
                
                // Pull latest data from server
                try await pullLatestData(token: token)
                
                // Clean up old data
                coreDataManager.cleanupOldData()
                
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatus = .success
                    self.lastSyncDate = Date()
                    self.consecutiveFailures = 0
                    self.updatePendingSyncCount()
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatus = .error(error.localizedDescription)
                    self.error = error.localizedDescription
                    self.consecutiveFailures += 1
                    
                    // Back off if too many failures
                    if self.consecutiveFailures >= self.maxConsecutiveFailures {
                        self.syncInterval = min(self.syncInterval * 2, 3_600) // Max 1 hour
                        self.startAutoSync()
                    }
                }
            }
        }
    }
    
    private func syncLocalChanges(token: String) async throws {
        let unsynced = await coreDataManager.fetchUnsyncedEntries()

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
    }
    
    private func syncBodyMetricsBatch(_ metrics: [CachedBodyMetrics], token: String) async throws {
        let batchSize = 50 // Sync in batches to avoid timeouts
        
        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.compactMap { metric -> [String: Any]? in
                return [
                    "id": metric.id ?? UUID().uuidString,
                    "user_id": metric.userId ?? "",
                    "weight": metric.weight,
                    "body_fat_percentage": metric.bodyFatPercentage as Any,
                    // "muscle_mass_percentage": metric.muscleMassPercentage as Any, // Field doesn't exist
                    "logged_at": ISO8601DateFormatter().string(from: metric.date ?? Date()),
                    "notes": metric.notes as Any
                    // "source": metric.source as Any // Field doesn't exist
                ]
            }
            
            let response = try await supabaseManager.upsertBodyMetricsBatch(metricsData, token: token)
            
            // Mark as synced
            for (index, metric) in batch.enumerated() {
                if index < response.count {
                    metric.syncStatus = "synced"
                    // metric.lastSyncedAt = Date() // Field doesn't exist
                }
            }
            
            coreDataManager.save()
        }
    }
    
    private func syncDailyMetricsBatch(_ metrics: [CachedDailyMetrics], token: String) async throws {
        // Similar batch implementation for daily metrics
        let batchSize = 50
        
        for batch in metrics.chunked(into: batchSize) {
            let metricsData = batch.compactMap { metric -> [String: Any]? in
                return [
                    "id": metric.id ?? UUID().uuidString,
                    "user_id": metric.userId ?? "",
                    "date": ISO8601DateFormatter().string(from: metric.date ?? Date()),
                    "steps": metric.steps,
                    "notes": metric.notes as Any
                ]
            }
            
            let response = try await supabaseManager.upsertDailyMetricsBatch(metricsData, token: token)
            
            for (index, metric) in batch.enumerated() {
                if index < response.count {
                    metric.syncStatus = "synced"
                    // metric.lastSyncedAt = Date() // Field doesn't exist
                }
            }
            
            coreDataManager.save()
        }
    }
    
    private func syncProfilesBatch(_ profiles: [CachedProfile], token: String) async throws {
        // Profile sync (usually just one per user)
        for profile in profiles {
            let profileData: [String: Any] = [
                "id": profile.id ?? "",
                "full_name": profile.fullName as Any,
                "username": profile.username as Any,
                // "avatar_url": profile.avatarUrl as Any, // Field doesn't exist
                "height": profile.height,
                "height_unit": profile.heightUnit as Any,
                "gender": profile.gender as Any,
                "date_of_birth": profile.dateOfBirth != nil ? ISO8601DateFormatter().string(from: profile.dateOfBirth!) : NSNull(),
                "activity_level": profile.activityLevel as Any,
                "onboarding_completed": profile.onboardingCompleted
            ]

            try await supabaseManager.updateProfile(profileData, token: token)
            
            profile.syncStatus = "synced"
            // profile.lastSyncedAt = Date() // Field doesn't exist
            coreDataManager.save()
        }
    }
    
    private func pullLatestData(token: String) async throws {
        guard let userId = authManager.currentUser?.id else { return }
        
        // Get last sync date for incremental sync
        let lastSync = lastSyncDate ?? Date().addingTimeInterval(-7 * 24 * 60 * 60) // Default to 1 week ago
        
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
    }
    
    // MARK: - Real-time Connection
    private func connectRealtime() {
        guard authManager.isAuthenticated else { return }
        guard isOnline else { return }
        
        // For now, we'll use polling instead of WebSocket to simplify
        // WebSocket implementation can be added later for true real-time
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
    
    private func processPendingOperations(token: String) async throws {
        let operations = pendingOperations
        pendingOperations.removeAll()
        
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
                // Re-add to queue if failed
                var failedOp = operation
                failedOp.retryCount += 1
                if failedOp.retryCount < 3 {
                    pendingOperations.append(failedOp)
                }
            }
        }
        
        savePendingOperations()
    }
    
    // MARK: - Helpers
    func updatePendingSyncCount() {
        Task {
            let unsynced = await coreDataManager.fetchUnsyncedEntries()
            await MainActor.run {
                pendingSyncCount = unsynced.bodyMetrics.count +
                                  unsynced.dailyMetrics.count +
                                  unsynced.profiles.count +
                                  pendingOperations.count
            }
        }
    }
    
    private func shouldPullLatestData() -> Bool {
        guard let lastSync = lastSyncDate else { return true }
        
        // Pull if more than 5 minutes have passed
        return Date().timeIntervalSince(lastSync) > syncInterval
    }
    
    private func scheduleBackgroundSync() {
        // This would use BGTaskScheduler for iOS 13+
        // Implementation depends on app capabilities
    }
    
    // MARK: - Public Methods
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
