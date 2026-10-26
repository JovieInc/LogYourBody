import Foundation

struct MetricSourceCapabilities: Equatable, Sendable {
    var pushEvents = false
    var incrementalPull = false
    var scheduledPoll = false
    var manualUpload = false

    func supports(_ trigger: MetricSourceSyncTrigger) -> Bool {
        switch trigger {
        case .pushEvent: return pushEvents
        case .incrementalPull: return incrementalPull
        case .scheduledPoll: return scheduledPoll
        case .manualUpload: return manualUpload
        }
    }
}

enum MetricSourceSyncTrigger: CaseIterable {
    case pushEvent
    case incrementalPull
    case scheduledPoll
    case manualUpload
}

protocol MetricSourceAdapter {
    associatedtype Report
    associatedtype ReplayResult

    var capabilities: MetricSourceCapabilities { get }
    /// Successful completion time for the current account, never a report's measurement/update date.
    var lastSuccessfulSync: Date? { get async }
    /// Stable within the provider and account. Storage must scope the key to both.
    func idempotencyKey(for report: Report) -> String
    /// A side-effect-free admission hook; implementations may recheck before requests and writes.
    func checkEntitlementAndCost() async throws
    /// Inclusive provider report start date; nil replays all available history. Direct calls must enforce admission too.
    func replay(from startDate: Date?) async throws -> ReplayResult
}

extension MetricSourceAdapter {
    var capabilities: MetricSourceCapabilities { MetricSourceCapabilities() }
}

enum MetricSourceScheduler {
    /// Capabilities select delivery modes. Account, permission, entitlement and cost checks remain admission concerns.
    static func replay<Adapter: MetricSourceAdapter>(
        _ adapter: Adapter, triggeredBy trigger: MetricSourceSyncTrigger, from startDate: Date? = nil
    ) async throws -> Adapter.ReplayResult? {
        guard adapter.capabilities.supports(trigger) else { return nil }
        try Task.checkCancellation()
        try await adapter.checkEntitlementAndCost()
        return try await adapter.replay(from: startDate)
    }
}
