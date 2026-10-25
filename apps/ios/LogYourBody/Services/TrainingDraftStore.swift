import CryptoKit
import Foundation

/// A submission/form journal only. Confirmed training records remain server-owned.
struct TrainingSetDraft: Codable, Equatable {
    let exerciseId: String
    let setNumber: Int
    var repsText: String
    var loadText: String
    var rir: Int
    var revision = UUID()
    var pendingRequest: TrainingSetLogRequest?
    var correctionBase: TrainingSavedSet?
    var pendingCorrection: TrainingSetCorrectionRequest?

    var key: String { "\(exerciseId)-\(setNumber)" }
}

struct TrainingFeedbackDraft: Codable, Equatable {
    let request: TrainingFeedbackRequest
    var response: TrainingFeedbackResponse?
    var readinessHold: TrainingFeedbackResponse?

    var recommendationReceipt: TrainingFeedbackResponse? {
        guard let response else { return readinessHold }
        if response.nextSetRecommendation.action == .symptomSafety ||
            response.nextSetRecommendation.observationIds.contains(response.feedback.id) {
            return response
        }
        // Performance-only feedback may return a decision based on an earlier readiness observation.
        guard let readinessHold,
              response.nextSetRecommendation.observationIds.contains(readinessHold.feedback.id)
        else { return nil }
        return TrainingFeedbackResponse(
            version: response.version, feedback: readinessHold.feedback,
            nextSetRecommendation: response.nextSetRecommendation
        )
    }
}

struct TrainingSetUndoReceipt: Codable, Equatable, Sendable {
    let id: String
    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let expectedRevision: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
    let restoresCorrectionId: String
    let issuedAt: Date
    var submitted: Bool
}

enum TrainingDraftError: LocalizedError {
    case unavailable
    case changed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Training drafts could not be read or saved on this device. Try again."
        case .changed: "This set changed while saving. Reopen the session to review it."
        }
    }
}

@MainActor
final class TrainingDraftStore {
    static let shared = TrainingDraftStore(
        rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrainingDrafts", isDirectory: true)
    )

    private struct Journal: Codable {
        var version: Int
        var ownerId: String
        var sessionId: String
        var rows: [String: TrainingSetDraft]
        var feedback: TrainingFeedbackDraft?
        var undoReceipt: TrainingSetUndoReceipt?

        private enum CodingKeys: String, CodingKey {
            case version, ownerId, sessionId, rows, feedback, undoReceipt
        }

        init(
            version: Int,
            ownerId: String,
            sessionId: String,
            rows: [String: TrainingSetDraft],
            feedback: TrainingFeedbackDraft? = nil,
            undoReceipt: TrainingSetUndoReceipt? = nil
        ) {
            self.version = version
            self.ownerId = ownerId
            self.sessionId = sessionId
            self.rows = rows
            self.feedback = feedback
            self.undoReceipt = undoReceipt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            ownerId = try container.decode(String.self, forKey: .ownerId)
            sessionId = try container.decode(String.self, forKey: .sessionId)
            rows = try container.decode([String: TrainingSetDraft].self, forKey: .rows)
            feedback = try container.decodeIfPresent(TrainingFeedbackDraft.self, forKey: .feedback)
            // A missing or unreadable receipt is dropped. It must not fail the journal.
            undoReceipt = try? container.decode(TrainingSetUndoReceipt.self, forKey: .undoReceipt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(ownerId, forKey: .ownerId)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(rows, forKey: .rows)
            try container.encodeIfPresent(feedback, forKey: .feedback)
            try container.encodeIfPresent(undoReceipt, forKey: .undoReceipt)
        }
    }

    private let rootURL: URL
    private let writeData: (Data, URL, Data.WritingOptions) throws -> Void

    init(rootURL: URL, writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void = { data, url, options in
        try data.write(to: url, options: options)
    }) {
        self.rootURL = rootURL
        self.writeData = writeData
    }

    func load(ownerId: String, sessionId: String) throws -> [String: TrainingSetDraft] {
        try loadJournal(ownerId: ownerId, sessionId: sessionId).rows
    }

    func loadFeedback(ownerId: String, sessionId: String) throws -> TrainingFeedbackDraft? {
        try loadJournal(ownerId: ownerId, sessionId: sessionId).feedback
    }

    func loadUndo(ownerId: String, sessionId: String) throws -> TrainingSetUndoReceipt? {
        try loadJournal(ownerId: ownerId, sessionId: sessionId).undoReceipt
    }

    func replaceUndo(
        _ receipt: TrainingSetUndoReceipt?,
        expecting previous: TrainingSetUndoReceipt?,
        ownerId: String,
        sessionId: String
    ) throws -> Bool {
        var journal = try loadJournal(ownerId: ownerId, sessionId: sessionId)
        guard journal.undoReceipt == previous else { return false }
        journal.undoReceipt = receipt
        try persist(journal)
        return true
    }

    func replaceFeedback(
        _ feedback: TrainingFeedbackDraft,
        expecting previous: TrainingFeedbackDraft?,
        ownerId: String,
        sessionId: String
    ) throws -> Bool {
        var journal = try loadJournal(ownerId: ownerId, sessionId: sessionId)
        guard journal.feedback == previous else { return false }
        journal.feedback = feedback
        try persist(journal)
        return true
    }

    private func loadJournal(ownerId: String, sessionId: String) throws -> Journal {
        let url = journalURL(ownerId: ownerId, sessionId: sessionId)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Journal(version: 1, ownerId: ownerId, sessionId: sessionId, rows: [:])
        }
        var journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1, journal.ownerId == ownerId, journal.sessionId == sessionId,
              journal.rows.allSatisfy({ $0.key == $0.value.key && validStoredRow($0.value, sessionId: sessionId) })
        else { throw TrainingDraftError.unavailable }
        if let receipt = journal.undoReceipt, !Self.validUndoReceipt(receipt, sessionId: sessionId) {
            journal.undoReceipt = nil
        }
        if let feedback = journal.feedback {
            guard feedback.request.sessionId == sessionId, feedback.request.sourceObservationId != nil,
                  feedback.response.map({ $0.matches(feedback.request) }) ?? true,
                  feedback.readinessHold.map({
                      $0.feedback.observation.sessionId == sessionId &&
                          $0.matches($0.feedback.observation) && $0.nextSetRecommendation.action != .proceed
                  }) ?? true
            else { throw TrainingDraftError.unavailable }
        }
        return journal
    }

    func put(_ row: TrainingSetDraft, ownerId: String, sessionId: String) throws {
        var rows = try load(ownerId: ownerId, sessionId: sessionId)
        rows[row.key] = row
        try persist(rows, ownerId: ownerId, sessionId: sessionId)
    }

    /// MainActor keeps the read/compare/atomic-write indivisible between app controllers.
    func replace(
        _ row: TrainingSetDraft,
        expecting previous: TrainingSetDraft?,
        ownerId: String,
        sessionId: String
    ) throws -> Bool {
        var rows = try load(ownerId: ownerId, sessionId: sessionId)
        guard rows[row.key] == previous else { return false }
        rows[row.key] = row
        try persist(rows, ownerId: ownerId, sessionId: sessionId)
        return true
    }

    @discardableResult
    func remove(_ row: TrainingSetDraft, ownerId: String, sessionId: String) throws -> Bool {
        var rows = try load(ownerId: ownerId, sessionId: sessionId)
        guard rows[row.key] == row else { return false }
        rows.removeValue(forKey: row.key)
        try persist(rows, ownerId: ownerId, sessionId: sessionId)
        return true
    }

    func purge(ownerId: String) throws {
        do {
            try FileManager.default.removeItem(at: ownerURL(ownerId))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func persist(_ rows: [String: TrainingSetDraft], ownerId: String, sessionId: String) throws {
        var journal = try loadJournal(ownerId: ownerId, sessionId: sessionId)
        journal.rows = rows
        try persist(journal)
    }

    private func persist(_ journal: Journal) throws {
        let ownerId = journal.ownerId
        let sessionId = journal.sessionId
        let ownerURL = ownerURL(ownerId)
        try FileManager.default.createDirectory(
            at: ownerURL, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var excludedURL = rootURL
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excludedURL.setResourceValues(resources)
        let data = try JSONEncoder().encode(journal)
        try writeData(
            data, journalURL(ownerId: ownerId, sessionId: sessionId),
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func ownerURL(_ ownerId: String) -> URL {
        rootURL.appendingPathComponent(digest(ownerId), isDirectory: true)
    }

    private static func validUndoReceipt(_ receipt: TrainingSetUndoReceipt, sessionId: String) -> Bool {
        guard receipt.sessionId == sessionId,
              UUID(uuidString: receipt.id) != nil,
              !receipt.restoresCorrectionId.isEmpty,
              !receipt.exerciseId.isEmpty,
              receipt.setNumber > 0,
              receipt.expectedRevision >= 0,
              (1...50).contains(receipt.reps),
              (0...6).contains(receipt.rir),
              receipt.loadKg.map({ $0.isFinite && (0...500).contains($0) }) ?? true
        else { return false }
        return true
    }

    private func validStoredRow(_ row: TrainingSetDraft, sessionId: String) -> Bool {
        guard row.setNumber > 0, (0...6).contains(row.rir) else { return false }
        guard !(row.pendingRequest != nil && row.pendingCorrection != nil) else { return false }
        if let correction = row.pendingCorrection {
            guard let base = row.correctionBase,
                  base.sessionId == sessionId,
                  base.exerciseId == row.exerciseId,
                  base.setNumber == row.setNumber,
                  let reps = Int(row.repsText),
                  (1...50).contains(reps)
            else { return false }
            do {
                return correction == TrainingSetCorrectionRequest(
                    sessionId: sessionId,
                    exerciseId: row.exerciseId,
                    setNumber: row.setNumber,
                    reps: reps,
                    loadKg: try TrainingLoadInputPolicy.loadKg(from: row.loadText),
                    rir: row.rir,
                    correctionId: correction.correctionId,
                    expectedRevision: base.revision ?? 0
                )
            } catch {
                return false
            }
        }
        guard let pending = row.pendingRequest else { return row.correctionBase != nil || row.pendingCorrection == nil }
        guard let reps = Int(row.repsText), (1...50).contains(reps) else { return false }
        do {
            return pending == TrainingSetLogRequest(
                sessionId: sessionId, exerciseId: row.exerciseId, setNumber: row.setNumber,
                reps: reps, loadKg: try TrainingLoadInputPolicy.loadKg(from: row.loadText), rir: row.rir
            )
        } catch {
            return false
        }
    }

    private func journalURL(ownerId: String, sessionId: String) -> URL {
        ownerURL(ownerId).appendingPathComponent(digest(sessionId) + ".json")
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Fence token lookup, transport and acknowledgement with the originating account lifetime.
@MainActor
enum TrainingOwnedRequest {
    static func perform(
        isCurrent: () -> Bool,
        getToken: () async -> String?,
        send: (String) async throws -> Void
    ) async throws {
        guard isCurrent(), let token = await getToken(), isCurrent() else {
            throw TrainingServiceError.authenticationExpired
        }
        try await send(token)
        guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
    }
}
