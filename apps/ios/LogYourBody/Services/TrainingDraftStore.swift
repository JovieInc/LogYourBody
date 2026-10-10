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

    var key: String { "\(exerciseId)-\(setNumber)" }
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
        let version: Int
        let ownerId: String
        let sessionId: String
        var rows: [String: TrainingSetDraft]
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
        let url = journalURL(ownerId: ownerId, sessionId: sessionId)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1, journal.ownerId == ownerId, journal.sessionId == sessionId,
              journal.rows.allSatisfy({ $0.key == $0.value.key && validStoredRow($0.value, sessionId: sessionId) })
        else { throw TrainingDraftError.unavailable }
        return journal.rows
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
        let ownerURL = ownerURL(ownerId)
        try FileManager.default.createDirectory(
            at: ownerURL, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var excludedURL = rootURL
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excludedURL.setResourceValues(resources)
        let data = try JSONEncoder().encode(Journal(version: 1, ownerId: ownerId, sessionId: sessionId, rows: rows))
        try writeData(
            data, journalURL(ownerId: ownerId, sessionId: sessionId),
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func ownerURL(_ ownerId: String) -> URL {
        rootURL.appendingPathComponent(digest(ownerId), isDirectory: true)
    }

    private func validStoredRow(_ row: TrainingSetDraft, sessionId: String) -> Bool {
        guard row.setNumber > 0, (0...6).contains(row.rir) else { return false }
        guard let pending = row.pendingRequest else { return true }
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
