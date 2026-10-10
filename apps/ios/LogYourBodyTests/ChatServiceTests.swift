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

    @MainActor
    func testTurnRejectsDelayedReplacementTokenBeforeOpeningStream() async throws {
        for interruption in ["owner-B", "same-owner-new-session", "newer-turn", "cancelled"] {
            for token in ["replacement-token", nil] as [String?] {
                let owner = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 1)
                var currentOwner = owner
                let turnId = UUID()
                var currentTurnId = turnId
                var tokenResponse: CheckedContinuation<String?, Never>?
                let started = expectation(description: "Token request held")
                var openedStreams = 0
                var received: [ChatStreamEvent] = []
                let operation = Task { @MainActor in
                    try await ChatTurnExecutor.run(
                        accessToken: {
                            await withCheckedContinuation {
                                tokenResponse = $0
                                started.fulfill()
                            }
                        },
                        makeStream: { _ in
                            openedStreams += 1
                            return AsyncThrowingStream { $0.finish() }
                        },
                        isCurrent: { currentOwner == owner && currentTurnId == turnId },
                        receive: { received.append($0) }
                    )
                }
                await fulfillment(of: [started], timeout: 3)
                switch interruption {
                case "owner-B": currentOwner = .init(subject: "owner-B", generation: 2)
                case "same-owner-new-session": currentOwner = .init(subject: "owner-A", generation: 3)
                case "newer-turn": currentTurnId = UUID()
                default: operation.cancel()
                }
                try XCTUnwrap(tokenResponse).resume(returning: token)
                do {
                    try await operation.value
                    XCTFail("A stale turn must finish silently as cancellation")
                } catch is CancellationError {} catch {
                    XCTFail("Stale token must not publish authentication or stream errors: \(error)")
                }
                XCTAssertEqual(openedStreams, 0, "Do not send old content with a replacement token")
                XCTAssertTrue(received.isEmpty)
            }
        }
    }

    @MainActor
    func testTurnDropsHeldMetadataDeltasCompletionAndFailureAfterReplacement() async throws {
        let events: [ChatStreamEvent] = [
            .metadata(conversationId: "old-conversation", clientMessageId: "old-client", replayed: false),
            .delta("old account answer"),
            .completed(messageId: "old-answer", createdAt: "fixture-date", replayed: false),
            .failure(code: "provider_error", message: "old error", retryable: true)
        ]
        for interruption in ["owner-B", "same-owner-new-session", "newer-turn"] {
            let owner = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 1)
            var currentOwner = owner
            let turnId = UUID()
            var currentTurnId = turnId
            let started = expectation(description: "Stream held")
            var continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation?
            let stream = AsyncThrowingStream<ChatStreamEvent, Error> { continuation = $0 }
            var received: [ChatStreamEvent] = []
            let operation = Task { @MainActor in
                try await ChatTurnExecutor.run(
                    accessToken: { "owner-A-token" },
                    makeStream: { _ in started.fulfill(); return stream },
                    isCurrent: { currentOwner == owner && currentTurnId == turnId },
                    receive: { event in
                        received.append(event)
                        if case .failure(_, let message, let retryable) = event {
                            throw ChatServiceError.server(message: message, retryable: retryable)
                        }
                    }
                )
            }
            await fulfillment(of: [started], timeout: 3)
            switch interruption {
            case "owner-B": currentOwner = .init(subject: "owner-B", generation: 2)
            case "same-owner-new-session": currentOwner = .init(subject: "owner-A", generation: 3)
            default: currentTurnId = UUID()
            }
            let held = try XCTUnwrap(continuation)
            events.forEach { held.yield($0) }
            held.finish()
            do {
                try await operation.value
                XCTFail("Stale stream completion must not become success")
            } catch is CancellationError {} catch { XCTFail("Stale error must be suppressed: \(error)") }
            XCTAssertTrue(received.isEmpty, "No old metadata, answer, spoken completion or Retry error may publish")
        }
    }

    @MainActor
    func testTurnSuppressesDelayedProviderErrorButPreservesCurrentErrors() async throws {
        for replaced in [false, true] {
            var isCurrent = true
            let started = expectation(description: "Provider stream held")
            var continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation?
            let stream = AsyncThrowingStream<ChatStreamEvent, Error> { continuation = $0 }
            let operation = Task { @MainActor in
                try await ChatTurnExecutor.run(
                    accessToken: { "fixture-token" },
                    makeStream: { _ in started.fulfill(); return stream },
                    isCurrent: { isCurrent },
                    receive: { _ in XCTFail("A failed provider emitted no messages") }
                )
            }
            await fulfillment(of: [started], timeout: 3)
            isCurrent = !replaced
            try XCTUnwrap(continuation).finish(throwing: ChatServiceError.offline)
            do {
                try await operation.value
                XCTFail("Expected provider failure or stale cancellation")
            } catch is CancellationError {
                XCTAssertTrue(replaced)
            } catch {
                XCTAssertFalse(replaced, "A delayed error must not restore an old Retry identity")
                XCTAssertEqual(error as? ChatServiceError, .offline)
            }
        }
    }

    @MainActor
    func testCurrentTurnAcceptsRotatedTokenEventsAndRequiresCompletion() async throws {
        let events: [ChatStreamEvent] = [
            .metadata(conversationId: "conversation", clientMessageId: "client", replayed: false),
            .delta("answer"),
            .completed(messageId: "answer", createdAt: "fixture-date", replayed: false)
        ]
        var received: [ChatStreamEvent] = []
        try await ChatTurnExecutor.run(
            accessToken: { "rotated-token-same-session" },
            makeStream: { token in
                XCTAssertEqual(token, "rotated-token-same-session")
                return AsyncThrowingStream { continuation in
                    events.forEach { continuation.yield($0) }
                    continuation.finish()
                }
            },
            isCurrent: { true },
            receive: { received.append($0) }
        )
        XCTAssertEqual(received, events)
        do {
            try await ChatTurnExecutor.run(
                accessToken: { "fixture-token" },
                makeStream: { _ in AsyncThrowingStream { $0.finish() } },
                isCurrent: { true },
                receive: { _ in }
            )
            XCTFail("An empty stream must not be accepted as complete")
        } catch { XCTAssertEqual(error as? ChatServiceError, .invalidResponse) }
    }

    func testTrainingLoadFieldStartsAtTheEngineLoad() {
        XCTAssertEqual(TrainingLoadPrefillPolicy.text(for: 60), "60")
        XCTAssertEqual(TrainingLoadPrefillPolicy.text(for: 62.5), "62.5")
        XCTAssertEqual(TrainingLoadPrefillPolicy.text(for: 22.6796), "22.68")
        XCTAssertEqual(Double(TrainingLoadPrefillPolicy.text(for: 1_002.5)), 1_002.5, "Parses back when the set is logged")
        XCTAssertEqual(TrainingLoadPrefillPolicy.text(for: nil), "", "increase_load keeps the field empty")
        XCTAssertEqual(TrainingLoadPrefillPolicy.text(for: 0), "")
    }

    func testRecoveryPresentationKeepsPendingNeutralWithoutMaskingLaterErrors() throws {
        let pending = try historySnapshot(messages: [historyMessage(status: "pending", retryable: false)])
        var presentation = ChatRecoveryPresentation()
        presentation.restore(pending.historyRecovery)
        XCTAssertEqual(presentation.kind, .pending)
        XCTAssertEqual(presentation.message, pending.historyRecovery?.errorMessage)

        presentation.message = ChatServiceError.offline.localizedDescription
        XCTAssertEqual(presentation.kind, .warning, "A reload error replaces the previous pending status")
        XCTAssertEqual(presentation.message, ChatServiceError.offline.localizedDescription)
        presentation.restore(pending.historyRecovery)
        presentation.message = nil
        XCTAssertNil(presentation.message)
        XCTAssertEqual(presentation.kind, .warning, "Clearing the notice must clear pending presentation too")
    }

    func testRecoveryPresentationPreservesDistinctFailureAndStoppedCopy() throws {
        var presentation = ChatRecoveryPresentation()
        for (status, retryable) in [("failed", true), ("cancelled", true), ("pending", true)] {
            let history = try historySnapshot(messages: [historyMessage(status: status, retryable: retryable)])
            presentation.restore(history.historyRecovery)
            XCTAssertEqual(presentation.kind, .warning)
            XCTAssertEqual(presentation.message, history.historyRecovery?.errorMessage)
        }
        presentation.restore(nil)
        XCTAssertNil(presentation.message)
    }

    func testHistoryRecoveryKeepsServerRetryPermissionAndDistinctFailureStates() throws {
        let cases: [(String, Bool, ChatHistoryDelivery, String)] = [
            ("failed", true, .failed, "The answer could not be completed."),
            ("cancelled", true, .stopped, "Answer stopped."),
            ("pending", true, .failed, "The answer was interrupted."),
            ("pending", false, .sending, "An answer is still in progress.")
        ]
        for (status, retryable, delivery, copy) in cases {
            let history = try historySnapshot(messages: [historyMessage(status: status, retryable: retryable)])
            let recovery = try XCTUnwrap(history.historyRecovery)
            XCTAssertEqual(recovery.clientMessageId, "client-1")
            XCTAssertEqual(recovery.message, "How am I doing?")
            XCTAssertEqual(recovery.retryable, retryable)
            XCTAssertEqual(recovery.shouldReload, status == "pending" && !retryable)
            XCTAssertTrue(recovery.errorMessage.hasPrefix(copy))
            XCTAssertEqual(history.messages[0].historyDelivery, delivery)
        }
    }

    func testHistoryRecoveryDoesNotOfferOldFailuresAfterNewerSuccessOrInferLegacyFailures() throws {
        let oldFailure = historyMessage(status: "failed", retryable: true)
        for status in [nil, "completed", "future-status"] as [String?] {
            var newest = historyMessage(status: status, retryable: false)
            newest["id"] = "new-message"
            newest["clientMessageId"] = "new-client"
            let history = try historySnapshot(messages: [oldFailure, newest])
            XCTAssertNil(history.historyRecovery)
            XCTAssertEqual(history.messages[0].historyDelivery, .failed)
            XCTAssertEqual(history.messages[1].historyDelivery, .complete)
        }
        var missingIdentity = oldFailure
        missingIdentity["clientMessageId"] = NSNull()
        XCTAssertNil(try historySnapshot(messages: [missingIdentity]).historyRecovery)
        XCTAssertNil(try historySnapshot(messages: []).historyRecovery)
    }

    func testLoadedFailureRetriesOriginalConversationAndMessageIdentity() async throws {
        let snapshot = try historySnapshot(messages: [historyMessage(status: "failed", retryable: true)])
        let history = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "conversation": ["id": snapshot.id, "title": snapshot.title, "createdAt": snapshot.createdAt,
                             "updatedAt": snapshot.updatedAt, "expiresAt": snapshot.expiresAt,
                             "messages": [historyMessage(status: "failed", retryable: true)]]
        ])
        ChatURLProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200, ["Content-Type": "application/json"], history) }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: self.requestBody(request)) as? [String: Any])
            XCTAssertEqual(body["conversationId"] as? String, "conversation-1")
            XCTAssertEqual(body["clientMessageId"] as? String, "client-1")
            XCTAssertEqual(body["message"] as? String, "How am I doing?")
            let response = """
            event: done
            data: {"version":1,"messageId":"answer","createdAt":"2026-10-09","replayed":false}

            """
            return (200, ["Content-Type": "text/event-stream"], Data(response.utf8))
        }
        let service = URLSessionChatService(urlSession: makeSession(), baseURL: URL(string: ProductRegistry.Hosts.api)!)
        let loaded = try await service.loadLatest(accessToken: "fixture-token")
        let recovery = try XCTUnwrap(loaded?.historyRecovery)
        var events: [ChatStreamEvent] = []
        for try await event in service.streamMessage(
            accessToken: "fixture-token", conversationId: try XCTUnwrap(loaded?.id),
            clientMessageId: recovery.clientMessageId, message: recovery.message, voiceMode: false
        ) { events.append(event) }
        XCTAssertEqual(events, [.completed(messageId: "answer", createdAt: "2026-10-09", replayed: false)])
    }

    @MainActor
    func testHistoryLoadRejectsDelayedSuccessEmptyAndErrorAfterOwnershipOrLoadChanges() async throws {
        let snapshot = try historySnapshot(messages: [historyMessage(status: "failed", retryable: true)])
        for interruption in ["other-owner", "same-owner-new-session", "newer-load", "cancelled"] {
            for outcome in ["history", "empty", "error"] {
                let owner = AuthManager.ProfileSessionOwnership(subject: "owner-A", generation: 1)
                var currentOwner = owner
                let loadId = UUID()
                var currentLoadId = loadId
                let started = expectation(description: "History request held")
                var response: CheckedContinuation<ChatConversationSnapshot?, Error>?
                let operation = Task { @MainActor in
                    try await ChatHistoryLoader.load(
                        accessToken: { "fixture-token" },
                        loadHistory: { _ in
                            try await withCheckedThrowingContinuation {
                                response = $0
                                started.fulfill()
                            }
                        },
                        isCurrent: { currentOwner == owner && currentLoadId == loadId }
                    )
                }
                await fulfillment(of: [started], timeout: 3)
                switch interruption {
                case "other-owner":
                    currentOwner = .init(subject: "owner-B", generation: 2)
                case "same-owner-new-session":
                    currentOwner = .init(subject: "owner-A", generation: 3)
                case "newer-load": currentLoadId = UUID()
                default: operation.cancel()
                }
                let held = try XCTUnwrap(response)
                if outcome == "error" { held.resume(throwing: ChatServiceError.offline) } else {
                    held.resume(returning: outcome == "history" ? snapshot : nil)
                }
                do {
                    _ = try await operation.value
                    XCTFail("Stale \(outcome) must not replace messages, retry identity or error for \(interruption)")
                } catch is CancellationError {
                    // Cancellation is silent; the newer load owns all visible state.
                } catch { XCTFail("Stale failure must not become a visible error: \(error)") }
            }
        }
    }

    @MainActor
    func testHistoryLoadRejectsTokenFromReplacementSessionBeforeSending() async throws {
        var isCurrent = true
        var sends = 0
        do {
            _ = try await ChatHistoryLoader.load(
                accessToken: {
                    await Task.yield()
                    isCurrent = false
                    return "replacement-token"
                },
                loadHistory: { _ in sends += 1; return nil },
                isCurrent: { isCurrent }
            )
            XCTFail("A replaced session must not use the new token for the old load")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(sends, 0)
    }

    @MainActor
    func testHistoryLoadAcceptsCurrentOwnerAndPreservesCurrentErrors() async throws {
        let snapshot = try historySnapshot(messages: [historyMessage(status: "failed", retryable: true)])
        let loaded = try await ChatHistoryLoader.load(
            accessToken: { "rotated-token-same-session" },
            loadHistory: { token in
                XCTAssertEqual(token, "rotated-token-same-session")
                return snapshot
            },
            isCurrent: { true }
        )
        XCTAssertEqual(loaded, snapshot)
        do {
            _ = try await ChatHistoryLoader.load(
                accessToken: { "fixture-token" },
                loadHistory: { _ in throw ChatServiceError.offline },
                isCurrent: { true }
            )
            XCTFail("Current failures must remain visible")
        } catch { XCTAssertEqual(error as? ChatServiceError, .offline) }
    }

    private func historyMessage(status: String?, retryable: Bool) -> [String: Any] {
        var value: [String: Any] = ["id": "message-1", "role": "user", "content": "How am I doing?",
                                    "clientMessageId": "client-1", "createdAt": "2026-10-09"]
        if let status { value["turn"] = ["status": status, "retryable": retryable] }
        return value
    }

    private func historySnapshot(messages: [[String: Any]]) throws -> ChatConversationSnapshot {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "conversation-1", "title": "How am I doing?", "createdAt": "2026-10-09",
            "updatedAt": "2026-10-09", "expiresAt": "2026-11-09", "messages": messages
        ])
        return try JSONDecoder().decode(ChatConversationSnapshot.self, from: data)
    }

    func testTrainingLoadInputPreservesDecimalOverridesAndRejectsInvalidLoads() throws {
        for text in ["22.5", "22,5", " 22,5 "] {
            XCTAssertEqual(try TrainingLoadInputPolicy.loadKg(from: text), 22.5)
        }
        XCTAssertNil(try TrainingLoadInputPolicy.loadKg(from: "  "))
        XCTAssertEqual(try TrainingLoadInputPolicy.loadKg(from: "0"), 0)
        XCTAssertEqual(try TrainingLoadInputPolicy.loadKg(from: "500"), 500)
        XCTAssertEqual(TrainingLoadInputPolicy.savedText(for: 22.6796), "22.6796")
        XCTAssertEqual(TrainingLoadInputPolicy.savedText(for: 0), "0")
        XCTAssertEqual(TrainingLoadInputPolicy.savedText(for: nil), "")
        for text in ["-1", "501", "abc", "1,000.5", "NaN", "inf", "22,,5"] {
            XCTAssertThrowsError(try TrainingLoadInputPolicy.loadKg(from: text), text)
            XCTAssertFalse(TrainingLoadInputPolicy.isValid(text), text)
        }
    }

    func testTrainingCoachVisibilityRequiresTheStatsigGate() {
        var checkedKey: String?
        XCTAssertFalse(TrainingCoachPolicy.isEnabled { checkedKey = $0; return false })
        XCTAssertEqual(checkedKey, "hypertrophy_coach_v1")
        XCTAssertTrue(TrainingCoachPolicy.isEnabled { $0 == "hypertrophy_coach_v1" })
    }

    func testVoiceCoachVisibilityRequiresItsStatsigGate() {
        var checkedKey: String?
        XCTAssertFalse(VoiceCoachPolicy.isEnabled { checkedKey = $0; return false })
        XCTAssertEqual(checkedKey, "hypertrophy_coach_voice_v1")
        XCTAssertTrue(VoiceCoachPolicy.isEnabled { $0 == "hypertrophy_coach_voice_v1" })
    }

    func testPendingSpokenReplyIsBoundToAndConsumedByOneVoiceReply() {
        var pending = PendingSpokenReply()
        pending.track(clientMessageId: "voice-turn", shouldSpeakReply: true)

        XCTAssertTrue(pending.shouldSpeakReply(for: "voice-turn"))
        XCTAssertFalse(pending.shouldSpeakReply(for: "different-turn"))
        XCTAssertFalse(pending.consumeIfMatching(clientMessageId: "different-turn"))
        XCTAssertEqual(pending.clientMessageId, "voice-turn")
        XCTAssertTrue(pending.consumeIfMatching(clientMessageId: "voice-turn"))
        XCTAssertFalse(pending.consumeIfMatching(clientMessageId: "voice-turn"))
    }

    func testNonSpokenRequestClearsPendingSpokenReply() {
        var pending = PendingSpokenReply()
        pending.track(clientMessageId: "voice-turn", shouldSpeakReply: true)
        pending.track(clientMessageId: "manual-turn", shouldSpeakReply: false)

        XCTAssertNil(pending.clientMessageId)
        XCTAssertFalse(pending.consumeIfMatching(clientMessageId: "voice-turn"))
    }

    func testCancellingPendingSpokenReplyOnlyClearsMatchingTurn() {
        var pending = PendingSpokenReply()
        pending.track(clientMessageId: "voice-turn", shouldSpeakReply: true)

        pending.cancel(clientMessageId: "different-turn")
        XCTAssertEqual(pending.clientMessageId, "voice-turn")

        pending.cancel(clientMessageId: "voice-turn")
        XCTAssertNil(pending.clientMessageId)
    }

    func testVoiceTranscriptFixtureLogsASetOnlyAfterExplicitConfirmation() async throws {
        let response = try JSONDecoder().decode(
            VoiceIntentResponse.self,
            from: Data(
                #"""
                {
                  "version": 1,
                  "kind": "log_set",
                  "requiresConfirmation": true,
                  "missingFields": [],
                  "proposal": {
                    "sessionId": "11111111-1111-4111-8111-111111111111",
                    "exerciseId": "bench_press",
                    "exerciseName": "Bench Press",
                    "setNumber": 1,
                    "reps": 8,
                    "loadKg": 83.91,
                    "rir": 2
                  }
                }
                """#.utf8
            )
        )
        let proposal = try XCTUnwrap(response.proposal)
        var loggedRequests: [TrainingSetLogRequest] = []

        let session = engineTrainingSession()
        try await VoiceSetLogger.commit(
            proposal,
            isConfirmed: false,
            accessToken: "access-token",
            session: session
        ) { _, request in loggedRequests.append(request) }
        XCTAssertTrue(loggedRequests.isEmpty)

        try await VoiceSetLogger.commit(
            proposal,
            isConfirmed: true,
            accessToken: "access-token",
            session: session
        ) { token, request in
            XCTAssertEqual(token, "access-token")
            loggedRequests.append(request)
        }
        XCTAssertEqual(
            loggedRequests,
            [
                TrainingSetLogRequest(
                    sessionId: "11111111-1111-4111-8111-111111111111",
                    exerciseId: "bench_press",
                    setNumber: 1,
                    reps: 8,
                    loadKg: 83.91,
                    rir: 2
                )
            ]
        )
    }

    func testVoiceLogRejectsAProposalOutsideTheEngineSession() {
        let invented = voiceProposal(exerciseId: "invented_curl", exerciseName: "Invented curl")
        let route = VoiceSetAdmission.route(
            proposal: invented,
            heard: nil,
            missingFields: [],
            session: engineTrainingSession()
        )
        XCTAssertEqual(route, .clarify(fields: [], rejected: true))
        XCTAssertTrue(VoiceSetAdmission.rejectedLogMessage.contains("Nothing was logged"))
    }

    func testVoiceLogDoesNotConfirmWhenNoEngineSessionIsLoaded() {
        let route = VoiceSetAdmission.route(
            proposal: voiceProposal(),
            heard: nil,
            missingFields: [],
            session: nil
        )
        XCTAssertEqual(route, .clarify(fields: [], rejected: true))
    }

    func testVoiceLogConfirmsAProposalThatMatchesTheEngineSession() {
        let matching = voiceProposal()
        XCTAssertEqual(
            VoiceSetAdmission.route(
                proposal: matching,
                heard: nil,
                missingFields: [],
                session: engineTrainingSession()
            ),
            .confirm(matching)
        )
    }

    func testVoiceLogRejectsQuantitiesTheEngineSessionDoesNotAllow() {
        let session = engineTrainingSession()
        let rejected = [
            voiceProposal(reps: 80),
            voiceProposal(reps: 0),
            voiceProposal(setNumber: 4),
            voiceProposal(loadKg: 501),
            voiceProposal(rir: 7),
            voiceProposal(sessionId: "other-session"),
            voiceProposal(exerciseName: "Not the engine name")
        ]
        for bad in rejected {
            XCTAssertEqual(
                VoiceSetAdmission.route(proposal: bad, heard: nil, missingFields: [], session: session),
                .clarify(fields: [], rejected: true)
            )
        }
        let bodyweight = voiceProposal(loadKg: nil)
        XCTAssertEqual(
            VoiceSetAdmission.route(proposal: bodyweight, heard: nil, missingFields: [], session: session),
            .confirm(bodyweight)
        )
    }

    func testVoiceLogStillReviewsAHeardSetWhenOnlyExerciseOrSetIsMissing() {
        let heard = VoiceHeardIntent(
            setNumber: nil, reps: 8, loadValue: 80, weightUnit: "kg", loadKg: 80, rir: 2
        )
        XCTAssertEqual(
            VoiceSetAdmission.route(
                proposal: nil,
                heard: heard,
                missingFields: ["exercise"],
                session: engineTrainingSession()
            ),
            .review(heard)
        )
    }

    func testVoiceLogRejectsHeardValuesOutsideTheLoggedSetBounds() {
        let heard = VoiceHeardIntent(
            setNumber: 1, reps: 0, loadValue: nil, weightUnit: nil, loadKg: nil, rir: 2
        )
        XCTAssertEqual(
            VoiceSetAdmission.route(
                proposal: nil,
                heard: heard,
                missingFields: ["set_number"],
                session: engineTrainingSession()
            ),
            .clarify(fields: [], rejected: true)
        )
    }

    func testConfirmedVoiceLogDoesNotWriteASetOutsideTheEngineSession() async throws {
        var logged = 0
        do {
            try await VoiceSetLogger.commit(
                voiceProposal(exerciseId: "invented_curl", exerciseName: "Invented curl"),
                isConfirmed: true,
                accessToken: "access-token",
                session: engineTrainingSession()
            ) { _, _ in logged += 1 }
            XCTFail("An invented exercise must not be logged")
        } catch let error as VoiceSetLogRejection {
            XCTAssertEqual(error, .outsideEngineSession)
            XCTAssertEqual(error.errorDescription, VoiceSetAdmission.rejectedLogMessage)
        }
        XCTAssertEqual(logged, 0)
    }

    func testVoiceLogKeepsClarificationWhenRepsAreMissing() {
        XCTAssertEqual(
            VoiceSetAdmission.route(
                proposal: nil,
                heard: nil,
                missingFields: ["reps"],
                session: engineTrainingSession()
            ),
            .clarify(fields: ["reps"], rejected: false)
        )
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
            return (201, ["Content-Type": "application/json"], Data("""
              {"version":1,"sessionComplete":false,"log":{
                "sessionId":"session-id","exerciseId":"goblet_squat","setNumber":1,"reps":10,"loadKg":15,"rir":3
              }}
            """.utf8))
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

    func testTrainingSetRejectsMissingAcknowledgement() async throws {
        try await assertTrainingAcknowledgementRejected(#"{"version":1,"sessionComplete":false}"#)
    }

    func testTrainingSetRejectsAnotherSetsAcknowledgement() async throws {
        try await assertTrainingAcknowledgementRejected(
            """
            {"version":1,"sessionComplete":false,"log":{
              "sessionId":"another-session","exerciseId":"press","setNumber":1,"reps":10,"loadKg":22.5,"rir":3
            }}
            """
        )
    }

    func testTrainingSetRejectsEveryMismatchedAcknowledgedValue() async throws {
        let matching: [String: Any] = [
            "sessionId": "fixture-session", "exerciseId": "press", "setNumber": 1, "reps": 10, "loadKg": 22.5, "rir": 3
        ]
        for (field, value) in [
            ("exerciseId", "squat" as Any), ("setNumber", 2), ("reps", 11), ("loadKg", 0), ("rir", 4)
        ] {
            var log = matching
            log[field] = value
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "sessionComplete": false, "log": log])
            try await assertTrainingAcknowledgementRejected(try XCTUnwrap(String(data: data, encoding: .utf8)))
        }
    }

    func testTrainingSetRejectsNilLoadAcknowledgementForExplicitZero() async throws {
        ChatURLProtocol.handler = { _ in
            let body = """
            {"version":1,"sessionComplete":true,"log":{
              "sessionId":"fixture-session","exerciseId":"press","setNumber":1,"reps":10,"loadKg":null,"rir":3
            }}
            """
            return (201, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let service = URLSessionTrainingService(urlSession: makeSession(), baseURL: URL(string: "https://localhost")!)
        do {
            try await service.logSet(
                accessToken: "fixture-token",
                request: TrainingSetLogRequest(
                    sessionId: "fixture-session", exerciseId: "press", setNumber: 1, reps: 10, loadKg: 0, rir: 3
                )
            )
            XCTFail("Explicit zero must remain distinct from bodyweight")
        } catch { XCTAssertEqual(error as? TrainingServiceError, .invalidResponse) }
    }

    private func assertTrainingAcknowledgementRejected(_ body: String) async throws {
        ChatURLProtocol.handler = { _ in
            (201, ["Content-Type": "application/json"], Data(body.utf8))
        }
        let service = URLSessionTrainingService(urlSession: makeSession(), baseURL: URL(string: "https://localhost")!)
        do {
            try await service.logSet(
                accessToken: "fixture-token",
                request: TrainingSetLogRequest(
                    sessionId: "fixture-session", exerciseId: "press", setNumber: 1, reps: 10, loadKg: 22.5, rir: 3
                )
            )
            XCTFail("A success status without this exact saved set must not acknowledge the draft")
        } catch let error as TrainingServiceError {
            XCTAssertEqual(error, .invalidResponse)
        }
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
            XCTAssertEqual(json["voiceMode"] as? Bool, true)

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
            message: "How am I doing?",
            voiceMode: true
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
                message: "Retry",
                voiceMode: false
            ) {}
            XCTFail("Expected rate-limit failure")
        } catch let error as ChatServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfterSeconds: 120))
        }
    }

    private func engineTrainingSession() -> TrainingSession {
        TrainingSession(
            id: "11111111-1111-4111-8111-111111111111",
            week: 1,
            slot: 0,
            pattern: "A",
            title: "Full body A",
            exercises: [
                TrainingExercisePrescription(
                    id: "bench_press",
                    name: "Bench Press",
                    primaryMuscle: "chest",
                    muscleContribution: ["chest": 1],
                    sets: 3,
                    repRange: .init(min: 6, max: 10),
                    targetReps: 8,
                    targetRir: 2,
                    targetLoadKg: 80,
                    loadInstruction: nil,
                    progression: "hold",
                    evidenceIds: ["k:81c218db"]
                )
            ],
            safetyStop: false,
            explanation: nil,
            evidenceIds: ["k:81c218db"],
            loggedSets: nil
        )
    }

    private func voiceProposal(
        sessionId: String = "11111111-1111-4111-8111-111111111111",
        exerciseId: String = "bench_press",
        exerciseName: String = "Bench Press",
        setNumber: Int = 1,
        reps: Int = 8,
        loadKg: Double? = 80,
        rir: Int = 2
    ) -> VoiceSetProposal {
        VoiceSetProposal(
            sessionId: sessionId,
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            setNumber: setNumber,
            reps: reps,
            loadKg: loadKg,
            rir: rir
        )
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
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 { throw try XCTUnwrap(stream.streamError) }
            if bytesRead == 0 { break }
            data.append(buffer, count: bytesRead)
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
