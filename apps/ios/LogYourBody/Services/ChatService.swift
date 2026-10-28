//
// ChatService.swift
// LogYourBody
//

import Foundation

enum ChatAPIContract {
    static let protocolVersion = 1
    static let endpointPath = "/api/auth/mobile/chat/v1"
}

struct ChatConversationMessage: Identifiable, Equatable, Decodable, Sendable {
    enum Role: String, Decodable, Sendable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    let content: String
    let clientMessageId: String?
    let createdAt: String
    struct Turn: Equatable, Decodable, Sendable {
        let status: String
        let retryable: Bool
    }
    let turn: Turn?

    var historyDelivery: ChatHistoryDelivery {
        guard role == .user else { return .complete }
        switch turn?.status {
        case "failed": return .failed
        case "cancelled": return .stopped
        case "pending": return turn?.retryable == true ? .failed : .sending
        default: return .complete
        }
    }
}

enum ChatHistoryDelivery: Equatable {
    case complete
    case sending
    case failed
    case stopped
}

struct ChatHistoryRecovery: Equatable {
    let message: String
    let clientMessageId: String
    let status: String
    let retryable: Bool

    var shouldReload: Bool { status == "pending" && !retryable }

    var errorMessage: String {
        if shouldReload { return "An answer is still in progress. Reload to check it." }
        let explanation: String
        switch status {
        case "cancelled": explanation = "Answer stopped."
        case "pending": explanation = "The answer was interrupted."
        default: explanation = "The answer could not be completed."
        }
        return explanation + (retryable ? " Retry when you’re ready." : "")
    }
}

struct ChatConversationSnapshot: Equatable, Decodable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let expiresAt: String
    let messages: [ChatConversationMessage]

    var historyRecovery: ChatHistoryRecovery? {
        guard let latestUser = messages.last(where: { $0.role == .user }),
              let turn = latestUser.turn,
              ["failed", "cancelled", "pending"].contains(turn.status),
              let clientMessageId = latestUser.clientMessageId,
              !clientMessageId.isEmpty else { return nil }
        return ChatHistoryRecovery(
            message: latestUser.content,
            clientMessageId: clientMessageId,
            status: turn.status,
            retryable: turn.retryable
        )
    }
}

/// Rejects a late history response even when a service does not cooperate with task cancellation.
@MainActor
enum ChatHistoryLoader {
    static func load(
        accessToken: () async -> String?,
        loadHistory: (String) async throws -> ChatConversationSnapshot?,
        isCurrent: () -> Bool
    ) async throws -> ChatConversationSnapshot? {
        func requireCurrent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        try requireCurrent()
        let token = await accessToken()
        try requireCurrent()
        guard let token else { throw ChatServiceError.authenticationExpired }
        do {
            let history = try await loadHistory(token)
            try requireCurrent()
            return history
        } catch {
            try requireCurrent()
            throw error
        }
    }
}

enum ChatStreamEvent: Equatable, Sendable {
    case metadata(conversationId: String, clientMessageId: String, replayed: Bool)
    case delta(String)
    case completed(messageId: String, createdAt: String, replayed: Bool)
    case failure(code: String, message: String, retryable: Bool)
}

enum ChatServiceError: LocalizedError, Equatable {
    case authenticationExpired
    case offline
    case rateLimited(retryAfterSeconds: Int)
    case requestInProgress
    case invalidResponse
    case server(message: String, retryable: Bool)

    var errorDescription: String? {
        switch self {
        case .authenticationExpired:
            return "Your session expired. Sign in again to keep chatting."
        case .offline:
            return "You’re offline. Reconnect, then try again."
        case .rateLimited(let retryAfterSeconds):
            let minutes = max(1, Int(ceil(Double(retryAfterSeconds) / 60)))
            return "You’ve reached the chat limit. Try again in about \(minutes) minute\(minutes == 1 ? "" : "s")."
        case .requestInProgress:
            return "That message is already being answered. Try again in a moment."
        case .invalidResponse:
            return "The answer could not be read. Please try again."
        case .server(let message, _):
            return message
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .requestInProgress, .invalidResponse:
            return true
        case .server(_, let retryable):
            return retryable
        case .authenticationExpired, .rateLimited:
            return false
        }
    }
}

protocol ChatServicing {
    func loadLatest(accessToken: String) async throws -> ChatConversationSnapshot?
    func streamMessage(
        accessToken: String,
        conversationId: String,
        clientMessageId: String,
        message: String,
        voiceMode: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func deleteConversation(accessToken: String, conversationId: String) async throws
}

/// Checks account and turn ownership at every suspension before publishing stream state.
@MainActor
enum ChatTurnExecutor {
    static func run(
        accessToken: () async -> String?,
        makeStream: (String) -> AsyncThrowingStream<ChatStreamEvent, Error>,
        isCurrent: () -> Bool,
        receive: (ChatStreamEvent) throws -> Void
    ) async throws {
        func requireCurrent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        try requireCurrent()
        let token = await accessToken()
        try requireCurrent()
        guard let token else { throw ChatServiceError.authenticationExpired }
        do {
            var completed = false
            for try await event in makeStream(token) {
                try requireCurrent()
                try receive(event)
                if case .completed = event { completed = true }
            }
            try requireCurrent()
            guard completed else { throw ChatServiceError.invalidResponse }
        } catch {
            try requireCurrent()
            throw error
        }
    }
}

struct ChatSSEParser {
    private var eventName = ""
    private var dataLines: [String] = []

    mutating func consume(line: String) throws -> ChatStreamEvent? {
        if line.hasPrefix("event:") {
            let pendingEvent = try finish()
            eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            return pendingEvent
        }
        if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            return nil
        }
        guard line.isEmpty else { return nil }
        return try finish()
    }

    mutating func finish() throws -> ChatStreamEvent? {
        guard !eventName.isEmpty else { return nil }

        let name = eventName
        let data = dataLines.joined(separator: "\n")
        eventName = ""
        dataLines = []
        guard let payload = data.data(using: .utf8) else { throw ChatServiceError.invalidResponse }
        let decoder = JSONDecoder()

        switch name {
        case "meta":
            let value = try decoder.decode(MetadataPayload.self, from: payload)
            guard value.version == ChatAPIContract.protocolVersion else {
                throw ChatServiceError.invalidResponse
            }
            return .metadata(
                conversationId: value.conversationId,
                clientMessageId: value.clientMessageId,
                replayed: value.replayed
            )
        case "delta":
            let value = try decoder.decode(DeltaPayload.self, from: payload)
            guard value.version == ChatAPIContract.protocolVersion else {
                throw ChatServiceError.invalidResponse
            }
            return .delta(value.text)
        case "done":
            let value = try decoder.decode(DonePayload.self, from: payload)
            guard value.version == ChatAPIContract.protocolVersion else {
                throw ChatServiceError.invalidResponse
            }
            return .completed(
                messageId: value.messageId,
                createdAt: value.createdAt,
                replayed: value.replayed
            )
        case "error":
            let value = try decoder.decode(ErrorEventPayload.self, from: payload)
            guard value.version == ChatAPIContract.protocolVersion else {
                throw ChatServiceError.invalidResponse
            }
            return .failure(code: value.code, message: value.message, retryable: value.retryable)
        default:
            return nil
        }
    }
}

final class URLSessionChatService: ChatServicing {
    private let urlSession: URLSession
    private let baseURL: URL

    init(
        urlSession: URLSession = .shared,
        baseURL: URL? = URL(string: Configuration.apiBaseURL)
    ) {
        self.urlSession = urlSession
        self.baseURL = baseURL ?? URL(string: ProductRegistry.Hosts.api)!
    }

    func loadLatest(accessToken: String) async throws -> ChatConversationSnapshot? {
        var request = URLRequest(url: try endpointURL())
        request.httpMethod = "GET"
        authorize(&request, accessToken: accessToken)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)
        let envelope = try JSONDecoder().decode(ConversationEnvelope.self, from: data)
        guard envelope.version == ChatAPIContract.protocolVersion else {
            throw ChatServiceError.invalidResponse
        }
        return envelope.conversation
    }

    func streamMessage(
        accessToken: String,
        conversationId: String,
        clientMessageId: String,
        message: String,
        voiceMode: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: try endpointURL())
                    request.httpMethod = "POST"
                    authorize(&request, accessToken: accessToken)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        SendMessagePayload(
                            protocolVersion: ChatAPIContract.protocolVersion,
                            conversationId: conversationId,
                            clientMessageId: clientMessageId,
                            message: message,
                            voiceMode: voiceMode
                        )
                    )

                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ChatServiceError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        let data = try await limitedData(from: bytes)
                        throw serviceError(statusCode: http.statusCode, headers: http, data: data)
                    }

                    var parser = ChatSSEParser()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if let event = try parser.consume(line: line) {
                            continuation.yield(event)
                        }
                    }
                    try Task.checkCancellation()
                    if let event = try parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .notConnectedToInternet {
                    continuation.finish(throwing: ChatServiceError.offline)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func deleteConversation(accessToken: String, conversationId: String) async throws {
        guard var components = URLComponents(url: try endpointURL(), resolvingAgainstBaseURL: false) else {
            throw ChatServiceError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "conversationId", value: conversationId)]
        guard let url = components.url else { throw ChatServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        authorize(&request, accessToken: accessToken)
        let (data, response) = try await data(for: request)
        try validate(response: response, data: data, allowedStatusCodes: [204])
    }

    private func endpointURL() throws -> URL {
        guard let url = URL(string: ChatAPIContract.endpointPath, relativeTo: baseURL)?.absoluteURL else {
            throw ChatServiceError.invalidResponse
        }
        return url
    }

    private func authorize(_ request: inout URLRequest, accessToken: String) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ChatServiceError.offline
        }
    }

    private func validate(
        response: URLResponse,
        data: Data,
        allowedStatusCodes: Set<Int> = Set(200...299)
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ChatServiceError.invalidResponse
        }
        guard allowedStatusCodes.contains(http.statusCode) else {
            throw serviceError(statusCode: http.statusCode, headers: http, data: data)
        }
    }

    private func serviceError(
        statusCode: Int,
        headers: HTTPURLResponse,
        data: Data
    ) -> ChatServiceError {
        if statusCode == 401 { return .authenticationExpired }
        if statusCode == 429 {
            return .rateLimited(retryAfterSeconds: Int(headers.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        if statusCode == 409 { return .requestInProgress }
        let payload = try? JSONDecoder().decode(HTTPErrorPayload.self, from: data)
        return .server(
            message: payload?.error == "conversation_not_found"
                ? "That conversation is no longer available. Start a new chat."
                : "Chat is temporarily unavailable. Please try again.",
            retryable: statusCode >= 500
        )
    }

    private func limitedData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            if data.count >= 16_384 { break }
            data.append(byte)
        }
        return data
    }
}

private struct ConversationEnvelope: Decodable {
    let version: Int
    let conversation: ChatConversationSnapshot?
}

private struct SendMessagePayload: Encodable {
    let protocolVersion: Int
    let conversationId: String
    let clientMessageId: String
    let message: String
    let voiceMode: Bool
}

private struct MetadataPayload: Decodable {
    let version: Int
    let conversationId: String
    let clientMessageId: String
    let replayed: Bool
}

private struct DeltaPayload: Decodable {
    let version: Int
    let text: String
}

private struct DonePayload: Decodable {
    let version: Int
    let messageId: String
    let createdAt: String
    let replayed: Bool
}

private struct ErrorEventPayload: Decodable {
    let version: Int
    let code: String
    let message: String
    let retryable: Bool
}

private struct HTTPErrorPayload: Decodable {
    let version: Int?
    let error: String
}

#if DEBUG
/// A synchronous cancellation fence: termination closes admission before scheduling cleanup.
/// DEBUG fixtures use it to reject even noncooperative late provider callbacks.
final class ChatFixtureAttemptGate: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var active = true

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        active = false
    }

    func whileActive(_ operation: () throws -> Bool) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return false }
        return try operation()
    }
}

/// Synthetic fixture history only. Production transcript persistence remains server-owned.
/// Atomic writes follow TrainingDraftStore's isolated fixture pattern.
@MainActor
final class ChatFixtureReplayStore {
    static let question = "Synthetic full-turn question"
    static let answer = "Your fixture trend is stable. Open Timeline to inspect the selected day."
    struct Journal: Codable {
        let nonce: UUID
        let conversationId: String
        let clientMessageId: String
        var attemptId: UUID
        var attempts: Int
        var status: String
    }
    // The computed app port recreates this store for each call. Keep only live synthetic
    // attempts in the existing nonce/file scope until matching terminal cleanup.
    private static var activeAttempts: [URL: ChatFixtureAttemptGate] = [:]
    private let nonce: UUID
    private let url: URL
    private let writeData: (Data, URL, Data.WritingOptions) throws -> Void

    init(rootURL: URL, nonce: UUID,
         writeData: @escaping (Data, URL, Data.WritingOptions) throws -> Void = { try $0.write(to: $1, options: $2) }) {
        self.nonce = nonce
        url = rootURL.appendingPathComponent(nonce.uuidString + ".json")
        self.writeData = writeData
    }

    func read() throws -> Journal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let row = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
        guard row.nonce == nonce, UUID(uuidString: row.conversationId) != nil,
              UUID(uuidString: row.clientMessageId) != nil,
              ["pending", "failed", "cancelled", "completed"].contains(row.status) else {
            throw ChatServiceError.invalidResponse
        }
        return row
    }

    private func persist(_ row: Journal) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeData(JSONEncoder().encode(row), url, .atomic)
    }

    /// Returns the attempt count; completed same-ID submissions replay without another write.
    func begin(conversationId: String, clientMessageId: String, message: String,
               gate: ChatFixtureAttemptGate) throws -> Journal {
        guard message == Self.question, UUID(uuidString: conversationId) != nil,
              UUID(uuidString: clientMessageId) != nil else { throw ChatServiceError.invalidResponse }
        var result: Journal?
        let admitted = try gate.whileActive {
            let existing = try read()
            if let existing {
                guard existing.conversationId == conversationId, existing.clientMessageId == clientMessageId else {
                    throw ChatServiceError.invalidResponse
                }
                if existing.status == "completed" { result = existing; return true }
                if existing.status == "pending" {
                    guard let previous = Self.activeAttempts[url], previous.id == existing.attemptId, previous.id != gate.id,
                          !previous.whileActive({ true }) else { throw ChatServiceError.requestInProgress }
                }
            }
            let row = Journal(nonce: nonce, conversationId: conversationId, clientMessageId: clientMessageId,
                              attemptId: gate.id, attempts: (existing?.attempts ?? 0) + 1, status: "pending")
            try persist(row)
            Self.activeAttempts[url] = gate
            result = row
            return true
        }
        guard admitted, let result else { throw CancellationError() }
        return result
    }

    @discardableResult
    func finish(_ status: String, gate: ChatFixtureAttemptGate) throws -> Bool {
        try gate.whileActive {
            guard var row = try read(), row.attemptId == gate.id, row.status == "pending" else { return false }
            guard status == "completed" || status == "failed" else { throw ChatServiceError.invalidResponse }
            row.status = status
            try persist(row)
            if Self.activeAttempts[url]?.id == gate.id { Self.activeAttempts.removeValue(forKey: url) }
            return true
        }
    }

    func cancel(gate: ChatFixtureAttemptGate) throws {
        gate.cancel()
        guard var row = try read(), row.attemptId == gate.id, row.status == "pending" else { return }
        row.status = "cancelled"
        try persist(row)
        if Self.activeAttempts[url]?.id == gate.id { Self.activeAttempts.removeValue(forKey: url) }
    }

    func snapshot() throws -> ChatConversationSnapshot? {
        guard let row = try read() else { return nil }
        let date = "2026-10-14T00:00:00.000Z"
        var messages: [[String: Any]] = [[
            "id": row.clientMessageId, "role": "user", "content": Self.question,
            "clientMessageId": row.clientMessageId, "createdAt": date,
            "turn": ["status": row.status, "retryable": row.status == "failed" || row.status == "cancelled"]
        ]]
        if row.status == "completed" {
            messages.append(["id": "fixture-assistant-message", "role": "assistant",
                             "content": Self.answer, "createdAt": date])
        }
        let body: [String: Any] = [
            "id": row.conversationId, "title": Self.question, "createdAt": date,
            "updatedAt": date, "expiresAt": "2026-11-14", "messages": messages
        ]
        return try JSONDecoder().decode(ChatConversationSnapshot.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func delete(conversationId: String) throws {
        guard let row = try read(), row.conversationId == conversationId else { return }
        try FileManager.default.removeItem(at: url)
    }
}

struct FixtureChatService: ChatServicing {
    enum Mode: Equatable {
        case success
        case providerError
        case offline
        case slow
        case historyFailed
        case historyPending
        case invalidScope
    }

    let mode: Mode
    let replayStore: ChatFixtureReplayStore?
    private let slowTick: @MainActor () async throws -> Void

    init(mode: Mode, replayStore: ChatFixtureReplayStore? = nil,
         slowTick: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(nanoseconds: 1_000_000_000)
         }) {
        self.mode = mode
        self.replayStore = replayStore
        self.slowTick = slowTick
    }

    func loadLatest(accessToken: String) async throws -> ChatConversationSnapshot? {
        if mode == .invalidScope { throw ChatServiceError.invalidResponse }
        if let replayStore {
            guard accessToken == "ui-test-bearer-token" else { throw ChatServiceError.authenticationExpired }
            return try await replayStore.snapshot()
        }
        if mode == .offline { throw ChatServiceError.offline }
        if mode == .historyFailed || mode == .historyPending {
            let body = """
            {"id":"history-conversation","title":"How am I doing?","createdAt":"2026-10-09",
             "updatedAt":"2026-10-09","expiresAt":"2026-11-09","messages":[
              {"id":"history-user","role":"user","content":"How am I doing?",
               "clientMessageId":"history-client","createdAt":"2026-10-09",
               "turn":{"status":"\(mode == .historyFailed ? "failed" : "pending")",
                       "retryable":\(mode == .historyFailed)}}]}
            """
            return try JSONDecoder().decode(ChatConversationSnapshot.self, from: Data(body.utf8))
        }
        return nil
    }

    func streamMessage(
        accessToken: String,
        conversationId: String,
        clientMessageId: String,
        message: String,
        voiceMode: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let gate = ChatFixtureAttemptGate()
            let task = Task { @MainActor in
                if let replayStore {
                    await replayMessage(accessToken: accessToken, identity: (conversationId, clientMessageId, message),
                                        store: replayStore, gate: gate, continuation: continuation)
                    return
                }
                if mode == .historyFailed &&
                    (conversationId != "history-conversation" || clientMessageId != "history-client" ||
                     message != "How am I doing?") {
                    continuation.finish(throwing: ChatServiceError.invalidResponse)
                    return
                }
                continuation.yield(
                    .metadata(
                        conversationId: conversationId,
                        clientMessageId: clientMessageId,
                        replayed: false
                    )
                )

                switch mode {
                case .success, .historyFailed:
                    continuation.yield(.delta("Your fixture trend is stable. "))
                    continuation.yield(.delta("Open Timeline to inspect the selected day."))
                case .providerError, .historyPending:
                    continuation.yield(
                        .failure(
                            code: "provider_error",
                            message: "The answer could not be completed.",
                            retryable: true
                        )
                    )
                    continuation.finish()
                    return
                case .offline:
                    continuation.finish(throwing: ChatServiceError.offline)
                    return
                case .invalidScope:
                    continuation.finish(throwing: ChatServiceError.invalidResponse)
                    return
                case .slow:
                    continuation.yield(.delta("Reviewing your authorized trend…"))
                    do {
                        try await waitForCancellation()
                    } catch {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                }

                continuation.yield(
                    .completed(
                        messageId: "fixture-assistant-message",
                        createdAt: "2026-08-02T22:00:00.000Z",
                        replayed: false
                    )
                )
                continuation.finish()
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination {
                    // Close admission synchronously, before either actor cleanup or a late callback.
                    gate.cancel()
                    if let replayStore { Task { @MainActor in try? replayStore.cancel(gate: gate) } }
                }
                task.cancel()
            }
        }
    }

    @MainActor
    private func replayMessage(accessToken: String, identity: (conversationId: String, clientMessageId: String, message: String),
                               store: ChatFixtureReplayStore, gate: ChatFixtureAttemptGate,
                               continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation) async {
        let (conversationId, clientMessageId, message) = identity
        do {
            guard accessToken == "ui-test-bearer-token" else { throw ChatServiceError.authenticationExpired }
            let row = try store.begin(conversationId: conversationId, clientMessageId: clientMessageId,
                                      message: message, gate: gate)
            let replayed = row.status == "completed"
            continuation.yield(.metadata(conversationId: conversationId, clientMessageId: clientMessageId, replayed: replayed))
            if mode == .providerError && row.attempts == 1 && !replayed {
                // Deliberate transport-red control: correct full text without terminal completion.
                continuation.yield(.delta(ChatFixtureReplayStore.answer))
                guard try store.finish("failed", gate: gate) else { throw CancellationError() }
                continuation.finish()
                return
            }
            if mode == .slow && row.attempts == 1 && !replayed {
                continuation.yield(.delta("Reviewing your authorized trend…"))
                try await waitForCancellation()
            }
            try Task.checkCancellation()
            continuation.yield(.delta(ChatFixtureReplayStore.answer))
            if !replayed {
                guard try store.finish("completed", gate: gate) else { throw CancellationError() }
            }
            continuation.yield(.completed(messageId: "fixture-assistant-message", createdAt: "2026-10-14", replayed: replayed))
            continuation.finish()
        } catch is CancellationError {
            try? store.cancel(gate: gate)
            continuation.finish(throwing: CancellationError())
        } catch {
            _ = try? store.finish("failed", gate: gate)
            continuation.finish(throwing: error)
        }
    }

    @MainActor
    private func waitForCancellation() async throws {
        // XCTest can wait 60s for animations after Send. Elapsed time must
        // never complete the slow fixture before the test can press Stop.
        while true {
            try Task.checkCancellation()
            try await slowTick()
        }
    }

    func deleteConversation(accessToken: String, conversationId: String) async throws {
        guard let replayStore else { return }
        guard accessToken == "ui-test-bearer-token" else { throw ChatServiceError.authenticationExpired }
        try await replayStore.delete(conversationId: conversationId)
    }
}
#endif

@MainActor
extension AppServicePorts {
    static var chatService: ChatServicing {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lybUITestChatFirstFixture") {
            let mode: FixtureChatService.Mode
            if arguments.contains("-lybUITestChatHistoryFailedFixture") {
                mode = .historyFailed
            } else if arguments.contains("-lybUITestChatHistoryPendingFixture") {
                mode = .historyPending
            } else if arguments.contains("-lybUITestChatErrorFixture") {
                mode = .providerError
            } else if arguments.contains("-lybUITestChatOfflineFixture") {
                mode = .offline
            } else if arguments.contains("-lybUITestChatSlowFixture") {
                mode = .slow
            } else {
                mode = .success
            }
            if arguments.contains("-lybUITestChatReplayFixture") {
                guard let value = ProcessInfo.processInfo.environment["LYB_UI_TEST_CHAT_REPLAY_ID"],
                      let nonce = UUID(uuidString: value) else { return FixtureChatService(mode: .invalidScope) }
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("Chat-UIFixture", isDirectory: true)
                return FixtureChatService(mode: mode, replayStore: ChatFixtureReplayStore(rootURL: root, nonce: nonce))
            }
            return FixtureChatService(mode: mode)
        }
        #endif
        return URLSessionChatService()
    }
}
