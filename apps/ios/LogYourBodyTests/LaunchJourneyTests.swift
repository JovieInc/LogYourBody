import XCTest
@testable import LogYourBody

final class LaunchJourneyTests: XCTestCase {
    private let now = DatedOutcome.calendarDate("2026-11-01")!
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let bounds = OutcomeFeasibility.Thresholds(
        minimumTarget: 40, maximumTarget: 250, minimumWeeklyChange: -1, maximumWeeklyChange: 1
    )

    func testBaselineDenialAndNoDataRecoverToOneAction() {
        let denied = LaunchJourney.decide(LaunchJourney.Input(now: now, permissionDenied: true))
        XCTAssertEqual(denied.state, .denial)
        XCTAssertEqual(denied.action.title, "Enter one measurement")
        XCTAssertFalse(denied.action.detail.isEmpty)

        let empty = LaunchJourney.decide(LaunchJourney.Input(now: now))
        XCTAssertEqual(empty.state, .noData)
        XCTAssertEqual(empty.action.title, "Set an outcome and a date")
        XCTAssertEqual(empty.action.detail, LaunchJourney.promiseExplanation)
    }

    func testDatedOutcomeSurvivesAndEditRecomputes() {
        let original = outcome(date: "2026-12-27")
        let first = LaunchJourney.decide(readyInput(original, current: 78))
        XCTAssertEqual(first.state, .ready)
        XCTAssertEqual(first.action.title, "Hold the plan")

        var edited = original
        edited.outcomeDate = "2026-11-08"
        edited.outcome.targetValue = 60
        XCTAssertEqual(original.outcomeDate, "2026-12-27")
        let second = LaunchJourney.decide(readyInput(edited, current: 78))
        XCTAssertEqual(second.state, .impossibleDate)
        XCTAssertEqual(second.action.title, "Choose a later date or a closer outcome")
        XCTAssertNotEqual(first.action, second.action)
    }

    func testDateEditRecomputesWithoutExtendingExpired() {
        let expired = outcome(date: "2026-10-01")
        let decision = LaunchJourney.decide(readyInput(expired, current: 78))
        XCTAssertEqual(decision.state, .expiredDate)
        XCTAssertEqual(decision.action.title, "Choose a new date or maintenance")
        XCTAssertTrue(decision.action.detail.contains("not extended"))
        XCTAssertEqual(expired.outcomeDate, "2026-10-01")

        var revised = expired
        revised.outcomeDate = "2026-12-27"
        let replanned = LaunchJourney.decide(readyInput(revised, current: 78))
        XCTAssertEqual(replanned.state, .ready)
        XCTAssertEqual(expired.outcomeDate, "2026-10-01")
    }

    func testOneNextActionForReadyPlan() {
        let decision = LaunchJourney.decide(readyInput(outcome(date: "2026-12-27"), current: 78))
        XCTAssertEqual(decision.state, .ready)
        XCTAssertEqual(decision.action.title, "Hold the plan")
        let surfaces = LaunchJourney.presentations(for: readyInput(outcome(date: "2026-12-27"), current: 78))
        XCTAssertEqual(Set(surfaces.map(\.action.title)), ["Hold the plan"])
        XCTAssertEqual(surfaces.map(\.surface), [.timeline, .stats, .coach])
    }

    func testDriftChangesTheSingleAction() {
        let held = LaunchJourney.decide(readyInput(outcome(date: "2026-12-27"), current: 78))
        let behind = LaunchJourney.decide(readyInput(outcome(date: "2026-12-27"), current: 80))
        XCTAssertEqual(held.action.title, "Hold the plan")
        XCTAssertEqual(behind.state, .ready)
        XCTAssertEqual(behind.action.title, "Review progress")
        XCTAssertNotEqual(held.action.title, behind.action.title)
    }

    func testHealthMemoryIsolationFailClosed() {
        var store = HealthMemoryStore()
        let recorded = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(store.remember(HealthMemoryClaim(
            userId: "", productId: "lyb", text: "80 kg", provenance: .measured, recordedAt: recorded
        )))
        XCTAssertFalse(store.remember(HealthMemoryClaim(
            userId: "user-a", productId: "other", text: "80 kg", provenance: .measured, recordedAt: recorded
        )))
        XCTAssertTrue(store.remember(HealthMemoryClaim(
            userId: "user-a", productId: "lyb", text: "80 kg", provenance: .userDeclared, recordedAt: recorded
        )))
        XCTAssertTrue(store.remember(HealthMemoryClaim(
            userId: "user-b", productId: "lyb", text: "secret", provenance: .measured, recordedAt: recorded
        )))
        XCTAssertEqual(store.retrieve(userId: "user-a", productId: "lyb", safetyAvailable: false), .safetyUnavailable)
        XCTAssertEqual(store.retrieve(userId: "", productId: "lyb", safetyAvailable: true), .isolated)
        XCTAssertEqual(store.retrieve(userId: "user-a", productId: "other", safetyAvailable: true), .isolated)
        guard case let .records(records) = store.retrieve(userId: "user-a", productId: "lyb", safetyAvailable: true) else {
            return XCTFail("Expected the caller's records")
        }
        XCTAssertEqual(records.map(\.text), ["80 kg"])
        XCTAssertEqual(records.map(\.provenance), [.userDeclared])
        store.clearUser("user-a")
        XCTAssertEqual(store.retrieve(userId: "user-a", productId: "lyb", safetyAvailable: true), .records([]))
        guard case let .records(remaining) = store.retrieve(userId: "user-b", productId: "lyb", safetyAvailable: true) else {
            return XCTFail("Expected the other user to keep their record")
        }
        XCTAssertEqual(remaining.map(\.text), ["secret"])
    }

    func testHiddenSurfaceRecoveryHasAnExit() {
        XCTAssertFalse(LaunchJourney.hiddenSurfaceMessage.isEmpty)
        XCTAssertEqual(LaunchJourney.hiddenSurfaceAction, "Back to coach")
    }

    func testPromiseCopyStatesTheDate() {
        XCTAssertTrue(LaunchJourney.promiseHeadline.contains("date"))
        XCTAssertTrue(LaunchJourney.promiseExplanation.contains("date"))
        XCTAssertTrue(LaunchJourney.promiseExplanation.contains("one next action"))
        XCTAssertTrue(LaunchJourney.promiseFraming.contains("do not guarantee"))
    }

    func testOfflineStaleAndConflictRecover() {
        let offline = LaunchJourney.decide(LaunchJourney.Input(now: now, outcome: outcome(date: "2026-12-27"), offline: true))
        XCTAssertEqual(offline.state, .offline)
        XCTAssertEqual(offline.action.title, "Retry sync")
        XCTAssertTrue(offline.action.detail.contains("2026-12-27"))

        let stale = LaunchJourney.decide(readyInput(outcome(date: "2026-12-27"), current: 78, window: nil))
        XCTAssertEqual(stale.state, .stale)
        XCTAssertEqual(stale.action.title, "Record a fresh measurement")

        var conflicted = readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week)
        conflicted.readings.append(LaunchJourney.Reading(date: now.addingTimeInterval(-4 * week), metric: .weightKg, value: 79))
        let conflict = LaunchJourney.decide(conflicted)
        XCTAssertEqual(conflict.state, .conflicting)
        XCTAssertEqual(conflict.action.title, "Record one new measurement")
    }

    func testExpiredAndMaintenanceDoNotExtendTheDate() {
        let expired = LaunchJourney.decide(readyInput(outcome(date: "2026-10-01"), current: 78))
        XCTAssertEqual(expired.state, .expiredDate)
        XCTAssertFalse(expired.action.detail.contains("2026-12-27"))

        var maintained = outcome(date: "2026-12-27")
        maintained.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        let decision = LaunchJourney.decide(readyInput(maintained, current: 78, window: 365 * week))
        XCTAssertEqual(decision.state, .maintenance)
        XCTAssertEqual(decision.action.title, "Hold this maintenance interval")
        XCTAssertEqual(maintained.outcomeDate, "2026-12-27")
    }

    func testUnavailableSafetyAndUnsafeDatesFailClosed() {
        let closed = LaunchJourney.decide(LaunchJourney.Input(
            now: now, outcome: outcome(date: "2026-12-27"), safetyAvailable: false
        ))
        XCTAssertEqual(closed.state, .unsafeDate)
        XCTAssertEqual(closed.action.title, "Review your outcome")
        XCTAssertFalse(closed.action.detail.contains("kg"))

        var withoutPolicy = readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week)
        withoutPolicy.thresholds = [:]
        withoutPolicy.safeWeeklyChangeKg = nil
        let unsafe = LaunchJourney.decide(withoutPolicy)
        XCTAssertEqual(unsafe.state, .unsafeDate)
        XCTAssertEqual(unsafe.action.title, "Revise the outcome")

        let withGlp1 = readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week)
        var flagged = withGlp1
        flagged.glp1Disclosed = true
        flagged.dexaPresent = true
        XCTAssertEqual(LaunchJourney.decide(withGlp1).action, LaunchJourney.decide(flagged).action)
        XCTAssertFalse(LaunchJourney.decide(flagged).action.detail.localizedCaseInsensitiveContains("glp"))
        XCTAssertFalse(LaunchJourney.decide(flagged).action.detail.localizedCaseInsensitiveContains("dose"))
    }

    func testStatsSurfaceProjectsEveryState() {
        assertEveryState(on: .stats)
    }

    func testTimelineSurfaceProjectsEveryState() {
        assertEveryState(on: .timeline)
    }

    private func assertEveryState(on surface: LaunchJourney.Surface) {
        let states = Set(sampleInputs().flatMap { input in
            LaunchJourney.presentations(for: input).filter { $0.surface == surface }.map(\.state)
        })
        XCTAssertEqual(states, Set(LaunchJourney.RouteState.allCases))
        for input in sampleInputs() {
            let presentation = LaunchJourney.presentations(for: input).first { $0.surface == surface }
            XCTAssertFalse(presentation?.action.title.isEmpty ?? true)
            XCTAssertFalse(presentation?.action.detail.isEmpty ?? true)
        }
    }

    private func sampleInputs() -> [LaunchJourney.Input] {
        var maintenance = outcome(date: "2026-12-27")
        maintenance.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        var hold = outcome(target: 80, date: "2026-12-27")
        var conflict = readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week)
        conflict.readings.append(LaunchJourney.Reading(date: now.addingTimeInterval(-8 * week), metric: .weightKg, value: 81))
        return [
            readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week),
            LaunchJourney.Input(now: now, permissionDenied: true),
            LaunchJourney.Input(now: now),
            LaunchJourney.Input(now: now, offline: true),
            readyInput(outcome(date: "2026-12-27"), current: 78, window: nil),
            conflict,
            unsafeWithoutPolicy(),
            readyInput(outcome(target: 60, date: "2026-11-08"), current: 78, window: 365 * week),
            readyInput(outcome(date: "2026-10-01"), current: 78),
            readyInput(maintenance, current: 78, window: 365 * week),
            readyInput(hold, current: 80, window: 365 * week)
        ]
    }

    private func unsafeWithoutPolicy() -> LaunchJourney.Input {
        var input = readyInput(outcome(date: "2026-12-27"), current: 78, window: 365 * week)
        input.thresholds = [:]
        input.safeWeeklyChangeKg = nil
        return input
    }

    private func outcome(target: Double = 76, date: String) -> DatedOutcome {
        DatedOutcome(outcome: .init(metric: .weightKg, targetValue: target), outcomeDate: date)
    }

    private func readyInput(
        _ outcome: DatedOutcome, current: Double, window: TimeInterval? = 365 * 24 * 60 * 60
    ) -> LaunchJourney.Input {
        LaunchJourney.Input(
            now: now,
            outcome: outcome,
            readings: [
                .init(date: now.addingTimeInterval(-8 * week), metric: .weightKg, value: 80),
                .init(date: now.addingTimeInterval(-4 * week), metric: .weightKg, value: current)
            ],
            freshnessWindow: window,
            thresholds: [.weightKg: bounds],
            safeWeeklyChangeKg: -1...1
        )
    }
}
