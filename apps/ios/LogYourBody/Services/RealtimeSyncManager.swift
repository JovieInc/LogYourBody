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
    let networkMonitor: NWPathMonitor

    var syncTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    var syncQueue = DispatchQueue(label: "com.logyourbody.sync", qos: .background)
    var pendingOperations: [SyncOperation] = []
    var isProcessingQueue = false
    var pendingCountTask: Task<Void, Never>?

    // Battery optimization settings
    var syncInterval: TimeInterval = 300 // 5 minutes default
    var lastSyncAttempt: Date?
    var consecutiveFailures = 0
    let maxConsecutiveFailures = 3

    // WebSocket for real-time (when available)
    var webSocketTask: URLSessionWebSocketTask?
    var webSocketPingTimer: Timer?

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
    init() {
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
}

extension PendingBodyMetricSyncItem {
    var shouldSkipBodyMetricUpsert: Bool {
        isEmptyPhotoPlaceholder ||
            (
                CoreDataManager.isPhotoUploadPlaceholderSyncStatus(syncStatus) &&
                    Self.isBlank(photoUrl)
            )
    }

    var isStaleEmptyPhotoPlaceholder: Bool {
        isEmptyPhotoPlaceholder && !CoreDataManager.isPhotoUploadPlaceholderSyncStatus(syncStatus)
    }

    var isEmptyPhotoPlaceholder: Bool {
        BodyMetricSource.normalizedRawValue(dataSource) == BodyMetricSource.photo.rawValue &&
            weight <= 0 &&
            waistCircumference <= 0 &&
            hipCircumference <= 0 &&
            bodyFatPercentage <= 0 &&
            muscleMass <= 0 &&
            boneMass <= 0 &&
            Self.isBlank(photoUrl) &&
            Self.isBlank(notes) &&
            Self.isBlank(sourceMetadataJSON)
    }

    static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
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
        guard size > 0 else {
            return isEmpty ? [] : [self]
        }

        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
