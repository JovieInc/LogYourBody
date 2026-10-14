import Foundation
import JovieKit
import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import LogYourBody

@MainActor
final class BodyRecordReviewConsumerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFailedSaveCannotBecomeAReviewOpportunity() async {
        let memory = ReviewLedgerMemory()
        let consumer = makeConsumer(memory)
        do {
            try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {
                throw ReviewTestError.failed
            }
            XCTFail("The original save error must propagate")
        } catch {
            XCTAssertTrue(error is ReviewTestError)
        }
        XCTAssertNil(consumer.candidate)
        XCTAssertNil(consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {
            XCTFail("Failed save must not invoke StoreKit")
        })
        XCTAssertNil(memory.data)
    }

    func testAwaitedLocalSaveAndQuietSceneAreBothRequired() async throws {
        let memory = ReviewLedgerMemory()
        let consumer = makeConsumer(memory)
        var didSave = false
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {
            XCTAssertNil(consumer.candidate)
            await Task.yield()
            didSave = true
        }
        XCTAssertTrue(didSave)
        XCTAssertEqual(consumer.candidate?.completedAt, now)
        var blocked = context()
        blocked.hasBlockingActivity = true
        var invocations = 0
        XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: blocked, policy: .init()) {
            invocations += 1
        }?.reason, .interrupted)
        XCTAssertNil(memory.data)
        let result = consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {
            XCTAssertNotNil(memory.data, "Durable fatigue reservation precedes native invocation")
            invocations += 1
        }
        XCTAssertEqual(result?.reason, .requested)
        XCTAssertEqual(invocations, 1)
        XCTAssertNil(consumer.candidate)
        XCTAssertEqual(result?.receipt?.display, "unobservable")
        XCTAssertEqual(result?.receipt?.reviewOutcome, "unobservable")
    }

    func testDuplicateCompletionCannotRefreshAgeOrInvokeTwiceAfterRestart() async throws {
        let memory = ReviewLedgerMemory()
        var clock = now
        let consumer = BodyRecordReviewConsumer(coordinator: memory.coordinator(), now: { clock })
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        clock = now.addingTimeInterval(60)
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        XCTAssertEqual(consumer.candidate?.completedAt, now)
        XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {}?.reason, .requested)

        let restarted = makeConsumer(memory)
        try await restarted.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        XCTAssertEqual(restarted.consider(currentOwnerID: "owner", context: context(), policy: .init()) {
            XCTFail("The same persisted record must not spend another request")
        }?.reason, .duplicate)
        XCTAssertNil(restarted.candidate)
    }

    func testFatigueSurvivesRestartAndPolicyRevision() async throws {
        let memory = ReviewLedgerMemory()
        let consumer = makeConsumer(memory)
        try await consumer.saveNewManualRecord(recordID: "first", ownerID: "owner") {}
        _ = consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {}
        let restarted = makeConsumer(memory)
        try await restarted.saveNewManualRecord(recordID: "second", ownerID: "owner") {}
        XCTAssertEqual(restarted.consider(
            currentOwnerID: "owner", context: context(), policy: .init(revision: "new-revision")
        ) { XCTFail("Revision changes must not reset fatigue") }?.reason, .cooldown)
        XCTAssertNil(restarted.candidate)
    }

    func testOfflineCompletionDefersWithoutClaimingCloudCommit() async throws {
        let memory = ReviewLedgerMemory()
        let consumer = makeConsumer(memory)
        try await consumer.saveNewManualRecord(recordID: "offline-record", ownerID: "owner") {}
        var offline = context()
        offline.isOnline = false
        XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: offline, policy: .init()) {
            XCTFail("Offline request")
        }?.reason, .offline)
        XCTAssertNotNil(consumer.candidate)
        XCTAssertNil(memory.data)
        XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {}?.reason, .requested)
    }

    func testUnreadyDisabledAndInactiveContextsKeepOriginalCompletion() async throws {
        let memory = ReviewLedgerMemory()
        let consumer = makeConsumer(memory)
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        let original = consumer.candidate
        for reason in [AppReview.Reason.inactive, .valueNotEstablished, .disabled] {
            var ctx = context()
            ctx.isForegroundActive = reason != .inactive
            ctx.hasExperiencedValue = reason != .valueNotEstablished
            let result = consumer.consider(
                currentOwnerID: "owner", context: ctx, policy: .init(enabled: reason != .disabled)
            ) { XCTFail("Unready context") }
            XCTAssertEqual(result?.reason, reason)
            XCTAssertEqual(consumer.candidate, original)
        }
        XCTAssertNil(memory.data)
    }

    func testAccountChangeCannotCarryAnOpportunityToAnotherUser() async throws {
        let consumer = makeConsumer(ReviewLedgerMemory())
        try await consumer.saveNewManualRecord(recordID: "private-record", ownerID: "owner") {}
        XCTAssertNil(consumer.consider(currentOwnerID: "other", context: context(), policy: .init()) {
            XCTFail("Wrong account")
        })
        XCTAssertNil(consumer.candidate)
        try await consumer.saveNewManualRecord(recordID: "another", ownerID: "owner") {}
        consumer.discardForAccountChange()
        XCTAssertNil(consumer.candidate)
    }

    func testCorruptStateAndFailedReservationCannotInvokeNativeAPI() async throws {
        for failure in 0..<3 {
            let memory = ReviewLedgerMemory()
            memory.data = failure == 0 ? Data("corrupt".utf8) : nil
            memory.failLoad = failure == 1
            memory.failSave = failure == 2
            let consumer = makeConsumer(memory)
            try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
            XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: context(), policy: .init()) {
                XCTFail("Persistence failure must fail closed")
            }?.reason, .persistenceUnavailable)
            XCTAssertNil(consumer.candidate)
        }
    }

    func testMissingChangedAndHoldoutAssignmentsUseCanonicalPolicy() async throws {
        let memory = ReviewLedgerMemory()
        let policy = AppReview.Policy(experiment: "review-experiment")
        let holdout = AppReview.Assignment(experiment: "review-experiment", variant: "control", isHoldout: true)
        let first = makeConsumer(memory)
        try await first.saveNewManualRecord(recordID: "first", ownerID: "owner") {}
        XCTAssertEqual(first.consider(currentOwnerID: "owner", context: context(), policy: policy, assignment: holdout) {
            XCTFail("Holdout must not invoke StoreKit")
        }?.reason, .holdout)
        for assignment in [nil, AppReview.Assignment(experiment: "review-experiment", variant: "treatment", isHoldout: false)] {
            let restarted = makeConsumer(memory)
            try await restarted.saveNewManualRecord(recordID: "next", ownerID: "owner") {}
            XCTAssertEqual(restarted.consider(
                currentOwnerID: "owner", context: context(), policy: policy, assignment: assignment
            ) { XCTFail("Unstable assignment must fail closed") }?.reason, .assignmentChanged)
        }
    }

    func testLocalReceiptHasOnlyCanonicalGenericTelemetry() async throws {
        let consumer = makeConsumer(ReviewLedgerMemory())
        try await consumer.saveNewManualRecord(recordID: "private-record", ownerID: "private-owner") {}
        let result = consumer.consider(currentOwnerID: "private-owner", context: context(), policy: .init()) {}
        let telemetry = try XCTUnwrap(result?.receipt?.telemetry)
        XCTAssertEqual(telemetry, [
            "schema": "app-review/v1", "policy_revision": "review-policy-v1",
            "value_moment": "completedWorkflow", "action": "request_invoked",
            "display": "unobservable", "review_outcome": "unobservable"
        ])
    }

    func testMissingIdentityAndExpiredCompletionNeverRequest() async throws {
        let consumer = makeConsumer(ReviewLedgerMemory())
        for (record, owner) in [("", "owner"), ("record", "")] {
            try await consumer.saveNewManualRecord(recordID: record, ownerID: owner) {}
            XCTAssertNil(consumer.candidate)
        }
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        var late = context()
        late.now = now.addingTimeInterval(24 * 60 * 60 + 1)
        XCTAssertEqual(consumer.consider(currentOwnerID: "owner", context: late, policy: .init()) {
            XCTFail("Stale completion")
        }?.reason, .staleOpportunity)
        XCTAssertNil(consumer.candidate)
    }

    func testAtomicFileLedgerSurvivesRecreationAndPreservesFailures() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        let file = AppReviewLedgerFile(url: url)
        XCTAssertNil(try file.load())
        try file.save(Data("first".utf8))
        XCTAssertEqual(try AppReviewLedgerFile(url: url).load(), Data("first".utf8))
        try file.save(Data("second".utf8))
        XCTAssertEqual(try file.load(), Data("second".utf8))
        let blocked = AppReviewLedgerFile(url: url.appendingPathComponent("child"))
        XCTAssertThrowsError(try blocked.save(Data()))
        XCTAssertThrowsError(try AppReviewLedgerFile(url: directory).load())
    }

    #if canImport(UIKit)
    func testMissingWindowAndSceneCannotQualifyForNativeInvocation() async throws {
        var invocations = 0
        let adapter = AppReviewNativeAdapter(invoke: { _ in invocations += 1 })
        let isAppStoreBuild = await adapter.isAppStoreBuild()
        let context = adapter.context(window: nil, isOnline: true, isAppStoreBuild: isAppStoreBuild, now: now)
        XCTAssertFalse(context.isForegroundActive)
        XCTAssertFalse(context.isQuietMoment)
        XCTAssertTrue(context.hasBlockingActivity)
        XCTAssertFalse(context.isAppStoreBuild, "Unit tests must not consume production review budget")
        let consumer = makeConsumer(ReviewLedgerMemory())
        try await consumer.saveNewManualRecord(recordID: "record", ownerID: "owner") {}
        _ = consumer.consider(currentOwnerID: "owner", context: context, policy: .init()) {
            XCTFail("A missing scene must not invoke StoreKit")
        }
        XCTAssertEqual(invocations, 0)
    }

    func testNativeAdapterPassesTheExactSceneToItsInvocationPort() throws {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            throw XCTSkip("No hosted application window scene in this test environment")
        }
        var received: UIWindowScene?
        let adapter = AppReviewNativeAdapter(invoke: { received = $0 })
        adapter.invoke(scene)
        XCTAssertTrue(received === scene)
    }
    #endif

    private func makeConsumer(_ memory: ReviewLedgerMemory) -> BodyRecordReviewConsumer {
        BodyRecordReviewConsumer(coordinator: memory.coordinator(), now: { self.now })
    }

    private func context() -> AppReview.Context {
        AppReview.Context(now: now, isAppStoreBuild: true, isForegroundActive: true,
                          hasExperiencedValue: true, isQuietMoment: true,
                          isOnline: true, hasBlockingActivity: false)
    }
}

private enum ReviewTestError: Error { case failed }

@MainActor
private final class ReviewLedgerMemory {
    var data: Data?
    var failLoad = false
    var failSave = false

    func coordinator() -> AppReview.Coordinator {
        AppReview.Coordinator(load: {
            if self.failLoad { throw ReviewTestError.failed }
            return self.data
        }, save: {
            if self.failSave { throw ReviewTestError.failed }
            self.data = $0
        })
    }
}
