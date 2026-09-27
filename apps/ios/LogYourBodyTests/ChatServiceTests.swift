import XCTest
@testable import LogYourBody

final class ChatServiceTests: XCTestCase {
    override func tearDown() {
        ChatURLProtocol.handler = nil
        super.tearDown()
    }

    func testSSEParserRequiresVersionedMetadataAndBuildsDeltas() throws {
        var parser = ChatSSEParser()
        XCTAssertNil(try parser.consume(line: "event: meta"))
        XCTAssertNil(
            try parser.consume(
                line: """
                data: {"version":1,"conversationId":"conversation","clientMessageId":"client","replayed":false}
                """
            )
        )
        XCTAssertEqual(
            try parser.consume(line: ""),
            .metadata(conversationId: "conversation", clientMessageId: "client", replayed: false)
        )

        XCTAssertNil(try parser.consume(line: "event: delta"))
        XCTAssertNil(try parser.consume(line: "data: {\"version\":1,\"text\":\"Hello\"}"))
        XCTAssertEqual(try parser.consume(line: ""), .delta("Hello"))
    }

    func testLoadLatestUsesBearerTokenAndDecodesOwnedConversation() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, ChatAPIContract.endpointPath)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let body = """
            {
              "version": 1,
              "conversation": {
                "id": "conversation-1",
                "title": "How am I doing?",
                "createdAt": "2026-08-02T22:00:00.000Z",
                "updatedAt": "2026-08-02T22:01:00.000Z",
                "expiresAt": "2026-09-01T22:01:00.000Z",
                "messages": [{
                  "id": "message-1",
                  "role": "user",
                  "content": "How am I doing?",
                  "clientMessageId": "client-1",
                  "createdAt": "2026-08-02T22:00:00.000Z"
                }]
              }
            }
            """
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }

        let service = URLSessionChatService(
            urlSession: session,
            baseURL: URL(string: ProductRegistry.Hosts.api)!
        )
        let conversation = try await service.loadLatest(accessToken: "access-token")
        XCTAssertEqual(conversation?.id, "conversation-1")
        XCTAssertEqual(conversation?.messages.first?.clientMessageId, "client-1")
    }

    func testTrainingCoachVisibilityRequiresTheStatsigGate() {
        var checkedKey: String?
        XCTAssertFalse(TrainingCoachPolicy.isEnabled { checkedKey = $0; return false })
        XCTAssertEqual(checkedKey, "hypertrophy_coach_v1")
        XCTAssertTrue(TrainingCoachPolicy.isEnabled { $0 == "hypertrophy_coach_v1" })
    }

    func testTrainingNextUsesBearerTokenAndDecodesEngineOutput() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "\(TrainingAPIContract.rootPath)/next")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let body = """
            {
              "version": 1,
              "week": 1,
              "weekCount": 2,
              "weeklyFractionalVolume": {"chest": 4},
              "session": {
                "id": "11111111-1111-4111-8111-111111111111",
                "week": 1,
                "slot": 0,
                "pattern": "A",
                "title": "Full body A",
                "safetyStop": false,
                "explanation": null,
                "evidenceIds": ["k:81c218db"],
                "exercises": [{
                  "id": "goblet_squat",
                  "name": "Goblet squat",
                  "primaryMuscle": "quads",
                  "muscleContribution": {"quads": 1},
                  "sets": 2,
                  "repRange": {"min": 8, "max": 12},
                  "targetReps": 8,
                  "targetRir": 4,
                  "targetLoadKg": null,
                  "loadInstruction": null,
                  "progression": "hold",
                  "evidenceIds": ["k:1795aef0"]
                }]
              }
            }
            """
            return (200, ["Content-Type": "application/json"], Data(body.utf8))
        }

        let service = URLSessionTrainingService(urlSession: session, baseURL: URL(string: ProductRegistry.Hosts.api)!)
        let output = try await service.loadNext(accessToken: "access-token")
        XCTAssertEqual(output.session?.exercises.first?.targetReps, 8)
        XCTAssertEqual(output.session?.exercises.first?.evidenceIds, ["k:1795aef0"])
        XCTAssertNil(output.session?.exercises.first?.targetLoadKg)
    }

    func testTrainingEnrollmentSendsExplicitAdultAndSafetyOptIn() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "\(TrainingAPIContract.rootPath)/enroll")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: self.requestBody(request)) as? [String: Any])
            XCTAssertEqual(body["adultConfirmed"] as? Bool, true)
            XCTAssertEqual(body["safetyConfirmed"] as? Bool, true)
            XCTAssertEqual(body["sessionsPerWeek"] as? Int, 2)
            XCTAssertEqual(body["equipment"] as? String, "dumbbells")
            return (201, ["Content-Type": "application/json"], Data("""
              {"version":1,"program":{
                "id":"setup-id","consentVersion":"hypertrophy-coach-v1",
                "sessionsPerWeek":2,"equipment":"dumbbells"
              }}
            """.utf8))
        }

        let service = URLSessionTrainingService(urlSession: session, baseURL: URL(string: ProductRegistry.Hosts.api)!)
        let output = try await service.enroll(accessToken: "access-token", sessionsPerWeek: 2, equipment: "dumbbells")
        XCTAssertEqual(output.program.consentVersion, TrainingAPIContract.consentVersion)
    }

    func testTrainingSetLogUsesTheEngineSessionRouteAndUserValues() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "\(TrainingAPIContract.rootPath)/log-set")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: self.requestBody(request)) as? [String: Any])
            XCTAssertEqual(body["sessionId"] as? String, "session-id")
            XCTAssertEqual(body["exerciseId"] as? String, "goblet_squat")
            XCTAssertEqual(body["setNumber"] as? Int, 1)
            XCTAssertEqual(body["reps"] as? Int, 10)
            XCTAssertEqual(body["loadKg"] as? Double, 15)
            XCTAssertEqual(body["rir"] as? Int, 3)
            return (201, ["Content-Type": "application/json"], Data("{\"version\":1,\"sessionComplete\":false}".utf8))
        }

        let service = URLSessionTrainingService(urlSession: session, baseURL: URL(string: ProductRegistry.Hosts.api)!)
        try await service.logSet(
            accessToken: "access-token",
            request: TrainingSetLogRequest(
                sessionId: "session-id",
                exerciseId: "goblet_squat",
                setNumber: 1,
                reps: 10,
                loadKg: 15,
                rir: 3
            )
        )
    }

    func testLoadLatestRejectsAnUnsupportedProtocolVersion() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { _ in
            (
                200,
                ["Content-Type": "application/json"],
                Data("{\"version\":2,\"conversation\":null}".utf8)
            )
        }

        let service = URLSessionChatService(
            urlSession: session,
            baseURL: URL(string: ProductRegistry.Hosts.api)!
        )
        do {
            _ = try await service.loadLatest(accessToken: "access-token")
            XCTFail("Expected an unsupported protocol version to fail")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testStreamSendsStableIdempotencyKeyAndParsesVersionedEvents() async throws {
        let session = makeSession()
        ChatURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let json = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: try self.requestBody(request)) as? [String: Any]
            )
            XCTAssertEqual(json["protocolVersion"] as? Int, 1)
            XCTAssertEqual(json["conversationId"] as? String, "conversation-1")
            XCTAssertEqual(json["clientMessageId"] as? String, "client-1")
            XCTAssertEqual(json["message"] as? String, "How am I doing?")

            let body = """
            event: meta
            data: {"version":1,"conversationId":"conversation-1","clientMessageId":"client-1","replayed":false}

            event: delta
            data: {"version":1,"text":"Your trend "}

            event: delta
            data: {"version":1,"text":"is stable."}

            event: done
            data: {"version":1,"messageId":"assistant-1","createdAt":"2026-08-02T22:00:00.000Z","replayed":false}

            """
            return (200, ["Content-Type": "text/event-stream"], Data(body.utf8))
        }

        let service = URLSessionChatService(
            urlSession: session,
            baseURL: URL(string: ProductRegistry.Hosts.api)!
        )
        var events: [ChatStreamEvent] = []
        for try await event in service.streamMessage(
            accessToken: "access-token",
            conversationId: "conversation-1",
            clientMessageId: "client-1",
            message: "How am I doing?"
        ) {
            events.append(event)
        }

        XCTAssertEqual(
            events,
            [
                .metadata(
                    conversationId: "conversation-1",
                    clientMessageId: "client-1",
                    replayed: false
                ),
                .delta("Your trend "),
                .delta("is stable."),
                .completed(
                    messageId: "assistant-1",
                    createdAt: "2026-08-02T22:00:00.000Z",
                    replayed: false
                )
            ]
        )
    }

    func testHTTPFailuresMapToUserVisibleAuthAndRateLimitStates() async throws {
        let session = makeSession()
        let service = URLSessionChatService(
            urlSession: session,
            baseURL: URL(string: ProductRegistry.Hosts.api)!
        )

        ChatURLProtocol.handler = { _ in
            (401, ["Content-Type": "application/json"], Data("{\"error\":\"unauthorized\"}".utf8))
        }
        do {
            _ = try await service.loadLatest(accessToken: "expired-token")
            XCTFail("Expected authentication failure")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .authenticationExpired)
        }

        ChatURLProtocol.handler = { _ in
            (
                429,
                ["Content-Type": "application/json", "Retry-After": "120"],
                Data("{\"error\":\"rate_limited\"}".utf8)
            )
        }
        do {
            for try await _ in service.streamMessage(
                accessToken: "access-token",
                conversationId: "conversation-1",
                clientMessageId: "client-1",
                message: "Retry"
            ) {}
            XCTFail("Expected rate-limit failure")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 120))
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class ChatURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
