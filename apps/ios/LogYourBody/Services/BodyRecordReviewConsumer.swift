import Combine
import Foundation
import JovieKit

/// LYB supplies completed product actions; JovieKit owns review admission.
/// No measurements, photos, record IDs or receipts leave the device.
@MainActor
final class BodyRecordReviewConsumer: ObservableObject {
    struct Candidate: Equatable {
        let recordID: String
        let ownerID: String
        let completedAt: Date
    }

    static let gateKey = "body_record_app_review_v1"
    @Published private(set) var candidate: Candidate?
    private let coordinator: AppReview.Coordinator
    private let now: () -> Date

    init(coordinator: AppReview.Coordinator, now: @escaping () -> Date = Date.init) {
        self.coordinator = coordinator
        self.now = now
    }

    /// Called by the manual create path around its awaited local persistence.
    /// A thrown save produces no opportunity and never changes the save result.
    /// Cloud sync remains pending; it is not a prerequisite or a claimed outcome.
    func saveNewManualRecord(
        recordID: String,
        ownerID: String,
        save: () async throws -> Void
    ) async throws {
        try await save()
        guard !recordID.isEmpty, !ownerID.isEmpty else { return }
        // A repeated completion cannot refresh the original opportunity's age.
        guard candidate?.recordID != recordID || candidate?.ownerID != ownerID else { return }
        candidate = Candidate(recordID: recordID, ownerID: ownerID, completedAt: now())
    }

    func discardForAccountChange() {
        candidate = nil
    }

    @discardableResult
    func consider(
        currentOwnerID: String?,
        context: AppReview.Context,
        policy: AppReview.Policy,
        assignment: AppReview.Assignment? = nil,
        request: () -> Void
    ) -> AppReview.Decision? {
        guard let candidate else { return nil }
        guard candidate.ownerID == currentOwnerID else {
            self.candidate = nil
            return nil
        }
        let opportunity = AppReview.Opportunity(
            id: candidate.recordID,
            moment: .completedWorkflow,
            achievedAt: candidate.completedAt
        )
        let decision = coordinator.consider(
            opportunity, context: context, policy: policy, assignment: assignment, request: request
        )
        switch decision.reason {
        case .inactive, .interrupted, .offline, .valueNotEstablished, .disabled:
            break // The same local completion may reach a quiet moment later.
        default:
            self.candidate = nil
        }
        return decision
    }
}

/// One stable installation ledger, independent of app and policy revisions.
/// Atomic reservation errors propagate to JovieKit, which fails closed.
struct AppReviewLedgerFile {
    let url: URL

    func load() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
