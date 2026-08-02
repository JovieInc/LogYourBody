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
}

struct ChatConversationSnapshot: Equatable, Decodable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let expiresAt: String
    let messages: [ChatConversationMessage]
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
        message: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func deleteConversation(accessToken: String, conversationId: String) async throws
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
        message: String
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
                            message: message
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
private struct FixtureChatService: ChatServicing {
    enum Mode: Equatable {
        case success
        case providerError
        case offline
        case slow
    }

    let mode: Mode

    func loadLatest(accessToken: String) async throws -> ChatConversationSnapshot? {
        if mode == .offline { throw ChatServiceError.offline }
        return nil
    }

    func streamMessage(
        accessToken: String,
        conversationId: String,
        clientMessageId: String,
        message: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(
                    .metadata(
                        conversationId: conversationId,
                        clientMessageId: clientMessageId,
                        replayed: false
                    )
                )

                switch mode {
                case .success:
                    continuation.yield(.delta("Your fixture trend is stable. "))
                    continuation.yield(.delta("Open Timeline to inspect the selected day."))
                case .providerError:
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
                case .slow:
                    continuation.yield(.delta("Reviewing your authorized trend…"))
                    do {
                        // Keep the fixture deterministically in-flight until the
                        // UI test exercises cancellation. A short delay races
                        // simulator startup and accessibility snapshot latency.
                        try await Task.sleep(nanoseconds: 30_000_000_000)
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func deleteConversation(accessToken: String, conversationId: String) async throws {}
}
#endif

@MainActor
extension AppServicePorts {
    static var chatService: ChatServicing {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lybUITestChatFirstFixture") {
            let mode: FixtureChatService.Mode
            if arguments.contains("-lybUITestChatErrorFixture") {
                mode = .providerError
            } else if arguments.contains("-lybUITestChatOfflineFixture") {
                mode = .offline
            } else if arguments.contains("-lybUITestChatSlowFixture") {
                mode = .slow
            } else {
                mode = .success
            }
            return FixtureChatService(mode: mode)
        }
        #endif
        return URLSessionChatService()
    }
}
