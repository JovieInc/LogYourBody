import Foundation

/// Sync status only. Reducing an event never prompts for access or schedules work.
enum HealthSyncState: Equatable, CaseIterable {
    case checking
    case updated
    case unavailable
    case permissionNeeded
    case offline

    var isNagWorthy: Bool {
        switch self {
        case .unavailable, .offline: return true
        case .checking, .updated, .permissionNeeded: return false
        }
    }

    enum Event: Equatable {
        case refreshStarted
        case refreshFinished(at: Date)
        /// A completed, successful read with no new samples; never evidence of denial.
        case noNewData(at: Date)
        case refreshFailed
        case authorizationDenied
        case authorizationRevoked
        case authorizationGranted
        case noNetwork
    }
}

struct HealthSyncStateReducer: Equatable {
    private(set) var state: HealthSyncState = .unavailable
    private(set) var lastSuccessfulSync: Date?

    mutating func reduce(_ event: HealthSyncState.Event) {
        switch event {
        case .authorizationDenied, .authorizationRevoked:
            state = .permissionNeeded
        case .authorizationGranted:
            if state == .permissionNeeded { state = .unavailable }
        default:
            // Late results and automatic refresh attempts cannot undo a permission decision.
            guard state != .permissionNeeded else { return }
            reduceRefresh(event)
        }
    }

    private mutating func reduceRefresh(_ event: HealthSyncState.Event) {
        switch event {
        case .refreshStarted:
            state = .checking
        case .refreshFinished(let date), .noNewData(let date):
            guard state == .checking else { return }
            state = .updated
            lastSuccessfulSync = max(lastSuccessfulSync ?? date, date)
        case .refreshFailed:
            state = .unavailable
        case .noNetwork:
            state = .offline
        case .authorizationDenied, .authorizationRevoked, .authorizationGranted:
            break
        }
    }
}
