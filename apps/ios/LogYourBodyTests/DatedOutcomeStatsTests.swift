import XCTest
@testable import LogYourBody

final class DatedOutcomeStatsTests: XCTestCase {
    private let projector = DatedTimelineProjector()
    private let now = DatedOutcome.calendarDate("2026-11-01")!
    private let week: TimeInterval = 7 * 86_400

    private var outcome: DatedOutcome {
        .init(outcome: .init(metric: .weightKg, targetValue: 76), outcomeDate: "2026-12-27")
    }

    func testStatsFixtureEditorDraftMatchesEveryProjectedOutcome() throws {
        for state in LaunchJourney.RouteState.allCases {
            let arguments = ["-lybUITestDatedTimelineFixture", "-lybUITestDatedStatsState", state.rawValue]
            var input = LaunchJourney.Input(now: now)
            var metrics: [BodyMetrics] = []
            DatedStatsUITestFixture.apply(owner: "a", input: &input, metrics: &metrics, arguments: arguments)
            let draft = try XCTUnwrap(DatedStatsUITestFixture.editorOutcome(saved: nil, arguments: arguments))
            XCTAssertEqual(draft, input.outcome, state.rawValue)
            XCTAssertEqual(draft.outcomeDate,
                           state == .expiredDate ? "2026-10-01" : state == .impossibleDate ? "2026-11-08" : "2026-12-27")
            XCTAssertEqual(draft.constraints.maintenance.isEmpty, state != .maintenance)
            var saved = outcome
            saved.outcomeDate = "2099-12-28"
            XCTAssertEqual(DatedStatsUITestFixture.editorOutcome(saved: saved, arguments: arguments), saved)
        }
    }

    func testStatsFixtureEditorDraftRequiresBothFlagsAndAValidState() {
        let invalidArguments = [
            [], ["-lybUITestDatedTimelineFixture"], ["-lybUITestDatedStatsState", "expired-date"],
            ["-lybUITestDatedTimelineFixture", "-lybUITestDatedStatsState"],
            ["-lybUITestDatedTimelineFixture", "-lybUITestDatedStatsState", "unknown"]
        ]
        for arguments in invalidArguments {
            XCTAssertNil(DatedStatsUITestFixture.editorOutcome(saved: nil, arguments: arguments))
            XCTAssertEqual(DatedStatsUITestFixture.editorOutcome(saved: outcome, arguments: arguments), outcome)
        }
    }

    // Wiring examples only. The current canonical policy supplies no numeric bounds.
    private func input(_ outcome: DatedOutcome) -> LaunchJourney.Input {
        .init(now: now, outcome: outcome, freshnessWindow: 365 * 86_400,
              thresholds: [.weightKg: .init(minimumTarget: 40, maximumTarget: 250,
                                            minimumWeeklyChange: -1, maximumWeeklyChange: 1)],
              safeWeeklyChangeKg: -1...1)
    }

    private func metric(
        _ id: String = "current", weight: Double? = 78, date: Date? = nil, owner: String = "a",
        bodyFat: Double? = nil, method: String? = nil
    ) -> BodyMetrics {
        .init(id: id, userId: owner, date: date ?? now, weight: weight, weightUnit: "kg",
              bodyFatPercentage: bodyFat, bodyFatMethod: method, muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil,
              dataSource: "manual", createdAt: now, updatedAt: now)
    }

    func testEveryStatsManifestStateHasOneRecoveryAndPreservesConstraints() async {
        var denied = input(outcome)
        denied.permissionDenied = true
        var offline = input(outcome)
        offline.offline = true
        var stale = input(outcome)
        stale.freshnessWindow = nil
        var unsafe = input(outcome)
        unsafe.safetyAvailable = false
        var impossible = outcome
        impossible.outcome.targetValue = 60
        impossible.outcomeDate = "2026-11-08"
        var expired = outcome
        expired.outcomeDate = "2026-10-01"
        var maintenance = outcome
        maintenance.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        let cases: [(LaunchJourney.RouteState, LaunchJourney.Input, [BodyMetrics])] = [
            (.ready, input(outcome), [metric()]), (.denial, denied, []), (.noData, input(outcome), []),
            (.offline, offline, [metric()]), (.stale, stale, [metric()]),
            (.conflicting, input(outcome), [metric(), metric("conflict", weight: 79)]),
            (.unsafeDate, unsafe, [metric()]), (.impossibleDate, input(impossible), [metric()]),
            (.expiredDate, input(expired), []), (.maintenance, input(maintenance), [metric()])
        ]
        XCTAssertEqual(Set(cases.map { $0.0 }), Set(LaunchJourney.RouteState.allCases))
        for (state, input, metrics) in cases {
            let result = await projector.project(owner: "a", metrics: metrics, input: input,
                                                 savedOutcome: input.outcome.map { .init(revision: UUID(), value: $0) })
            XCTAssertEqual(result.stats.presentation.surface, .stats)
            XCTAssertEqual(result.stats.presentation.state, state)
            XCTAssertEqual(result.coach.presentation.surface, .coach)
            XCTAssertEqual(result.coach.presentation.state, state)
            XCTAssertFalse(result.coach.presentation.action.title.isEmpty)
            if state != .ready {
                XCTAssertNil(result.coach.actionToSave, state.rawValue)
                XCTAssertNil(result.coach.evidence, state.rawValue)
            }
            XCTAssertFalse(result.stats.presentation.action.title.isEmpty)
            XCTAssertEqual(result.outcome, input.outcome)
            XCTAssertEqual(result.stats.deadline, input.outcome?.outcomeDate)
            if state != .ready { XCTAssertNil(result.stats.drift, state.rawValue) }
            for claim in ["safe plan", "reached safely", "guarantee", "physiologically impossible"] {
                XCTAssertFalse(result.stats.presentation.action.detail.lowercased().contains(claim))
            }
        }
    }

    func testReadySeparatesRecordedEstimateTargetTimeAndOriginalPlannerDrift() async {
        let baseline = metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week))
        let latest = metric("latest", weight: 79, date: now.addingTimeInterval(-4 * week),
                            bodyFat: 20, method: "visual_estimate")
        let result = await projector.project(owner: "a", metrics: [latest, baseline], input: input(outcome))
        XCTAssertEqual(result.stats.presentation.state, .ready)
        XCTAssertEqual(result.stats.measurement?.text, "79.0 kg")
        XCTAssertTrue(result.stats.measurement?.caption.contains("2026-10-04") == true)
        XCTAssertEqual(result.stats.estimate?.text, "20.0%")
        XCTAssertTrue(result.stats.estimate?.caption.contains("Visual estimate") == true)
        XCTAssertEqual(result.stats.target, "76.0 kg")
        XCTAssertEqual(result.stats.deadline, "2026-12-27")
        XCTAssertEqual(result.stats.remaining, "56 days remaining")
        XCTAssertEqual(result.stats.expiresAt, DatedOutcome.calendarDate("2026-12-27"))
        XCTAssertEqual(result.stats.drift?.text, "+0.0 kg")
        XCTAssertEqual(result.stats.baseline?.text, "80.0 kg")
    }

    func testNoDataConflictsEstimatesAndForeignRecordsCannotInventProgress() async {
        let estimate = metric(weight: nil, bodyFat: 20, method: "visual_estimate")
        let noData = await projector.project(
            owner: "a", metrics: [estimate, metric("foreign", owner: "b")], input: input(outcome))
        XCTAssertEqual(noData.stats.presentation.state, .noData)
        XCTAssertNil(noData.stats.measurement)
        XCTAssertNil(noData.stats.drift)
        XCTAssertNil(noData.stats.baseline)
        XCTAssertNotNil(noData.stats.estimate)
        let conflict = await projector.project(
            owner: "a", metrics: [metric(), metric("other", weight: 79)], input: input(outcome))
        XCTAssertNil(conflict.stats.measurement)
        XCTAssertNil(conflict.stats.drift)
    }

    func testNewAcceptedReadingRecoversLatestConflictWithoutReplacingExistingBaseline() async {
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)),
                       metric("one", weight: 78, date: now.addingTimeInterval(-week)),
                       metric("two", weight: 79, date: now.addingTimeInterval(-week))]
        let conflict = await projector.project(owner: "a", metrics: records, input: input(outcome))
        XCTAssertEqual(conflict.stats.presentation.state, .conflicting)
        var refreshed = input(outcome)
        refreshed.planBaseline = conflict.planBaseline
        let recovered = await projector.project(owner: "a", metrics: records + [metric(weight: 78)], input: refreshed)
        XCTAssertEqual(recovered.stats.presentation.state, .ready)
        XCTAssertEqual(recovered.planBaseline, conflict.planBaseline)
        XCTAssertEqual(recovered.stats.measurement?.text, "78.0 kg")
        XCTAssertNotNil(recovered.stats.drift)
    }

    func testRateBoundaryDoesNotBypassTargetEligibilityOrIncompletePolicy() async {
        let fields: [WritableKeyPath<OutcomeFeasibility.Thresholds, Double?>] = [
            \.minimumTarget, \.maximumTarget, \.minimumWeeklyChange, \.maximumWeeklyChange
        ]
        for target in [90.0, 110] { // LYB-273 examples: exactly 1% of 100 kg over ten weeks.
            var boundary = outcome
            boundary.outcome.targetValue = target
            boundary.outcomeDate = "2027-01-10"
            let accepted = await projector.project(owner: "a", metrics: [metric(weight: 100)], input: input(boundary))
            XCTAssertEqual(accepted.stats.presentation.state, .ready)
            for field in fields {
                var missing = input(boundary)
                missing.thresholds[.weightKg]?[keyPath: field] = nil
                let rejected = await projector.project(owner: "a", metrics: [metric(weight: 100)], input: missing)
                XCTAssertEqual(rejected.stats.presentation.state, .unsafeDate)
                XCTAssertNil(rejected.stats.drift)
                XCTAssertNil(rejected.coach.actionToSave)
                XCTAssertEqual(rejected.outcome, boundary)
            }
            var unavailable = input(boundary)
            unavailable.safetyAvailable = false
            let denied = await projector.project(owner: "a", metrics: [metric(weight: 100)], input: unavailable)
            XCTAssertEqual(denied.stats.presentation.state, .unsafeDate)
            var outside = input(boundary)
            outside.thresholds[.weightKg]?.minimumTarget = 75
            outside.thresholds[.weightKg]?.maximumTarget = 85
            let rejected = await projector.project(owner: "a", metrics: [metric(weight: 100)], input: outside)
            XCTAssertEqual(rejected.stats.presentation.state, .unsafeDate)
            var beyond = boundary
            beyond.outcome.targetValue += target < 100 ? -0.01 : 0.01
            var broad = input(beyond)
            broad.thresholds[.weightKg]?.minimumWeeklyChange = -10
            broad.thresholds[.weightKg]?.maximumWeeklyChange = 10
            broad.safeWeeklyChangeKg = -10...10
            let impossible = await projector.project(owner: "a", metrics: [metric(weight: 100)], input: broad)
            XCTAssertEqual(impossible.stats.presentation.state, .impossibleDate)
            XCTAssertEqual(impossible.outcome, beyond)
        }
    }

    func testAdoptedCeilingUsesCurrentAcceptedWeightAndElapsedTimeWithoutCompounding() async {
        for (target, expected) in [(90.0, true), (110.0, true), (90.01, true), (109.99, true),
                                   (89.99, false), (110.01, false), (100.0, true)] {
            var goal = outcome
            goal.outcome.targetValue = target
            goal.outcomeDate = "2027-01-10"
            let history: [OutcomeFeasibility.Measurement] = [
                .init(date: now.addingTimeInterval(-week), metric: .weightKg, value: 200),
                .init(date: now, metric: .weightKg, value: 100)
            ]
            XCTAssertEqual(OutcomeFeasibility(now: now).weightRateCheck(outcome: goal, history: history),
                           expected ? .withinCeiling : .exceedsCeiling)
            if target == 90 || target == 110 {
                let later = OutcomeFeasibility(now: now.addingTimeInterval(1)).weightRateCheck(outcome: goal, history: history)
                XCTAssertEqual(later, .exceedsCeiling,
                               "Use remaining elapsed weeks at evaluation, never round to the displayed days")
            }
        }
        var nonWeight = outcome
        nonWeight.outcome.metric = .bodyFatPercentage
        XCTAssertEqual(OutcomeFeasibility(now: now).weightRateCheck(outcome: nonWeight, history: []), .unavailable)
        let missing = await projector.project(owner: "a", metrics: [metric(weight: 100)],
                                              input: .init(now: now, outcome: outcome))
        XCTAssertEqual(missing.stats.presentation.state, .unsafeDate,
                       "The adopted outer ceiling is never a complete admission policy")
    }

    func testDateEditsAndNewMeasurementsRetainOriginalBaseline() async {
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)),
                       metric("latest", weight: 78, date: now.addingTimeInterval(-4 * week))]
        let first = await projector.project(owner: "a", metrics: records, input: input(outcome))
        var refreshed = input(outcome)
        refreshed.planBaseline = first.planBaseline
        let changed = await projector.project(owner: "a", metrics: records + [metric(weight: 79)], input: refreshed)
        XCTAssertEqual(changed.planBaseline, first.planBaseline)
        XCTAssertEqual(changed.stats.drift?.text, "+1.0 kg")
        refreshed.outcome?.outcomeDate = "2027-02-21"
        let edited = await projector.project(owner: "a", metrics: records + [metric(weight: 79)], input: refreshed)
        XCTAssertEqual(edited.planBaseline, first.planBaseline)
        XCTAssertNotEqual(edited.stats.drift, changed.stats.drift)
        XCTAssertEqual(first.outcome?.outcomeDate, "2026-12-27")
        let imported = metric("older-import", weight: 85, date: now.addingTimeInterval(-10 * week))
        let backfilled = await projector.project(owner: "a", metrics: records + [imported], input: refreshed)
        let beforeImport = await projector.project(owner: "a", metrics: records, input: refreshed)
        XCTAssertEqual(backfilled.planBaseline, first.planBaseline)
        XCTAssertEqual(backfilled.stats.drift, beforeImport.stats.drift)
        let removed = await projector.project(owner: "a", metrics: [metric()], input: refreshed)
        XCTAssertEqual(removed.stats.presentation.state, .unsafeDate)
        XCTAssertNil(removed.stats.drift, "An excluded/removed baseline cannot silently become a new plan")
    }

    func testExpiryWinsOverDenialOfflineMissingPolicyAndMaintenance() async {
        var expired = outcome
        expired.outcomeDate = "2026-10-01"
        expired.constraints.maintenance = [.init(start: "2026-10-01", end: "2026-12-01")]
        let result = await projector.project(owner: "a", metrics: [], input: .init(
            now: now, outcome: expired, offline: true, permissionDenied: true, safetyAvailable: false))
        XCTAssertEqual(result.stats.presentation.state, .expiredDate)
        XCTAssertEqual(result.stats.remaining, "Date passed")
        XCTAssertEqual(result.destination, .editor)
        XCTAssertEqual(result.outcome, expired)
        XCTAssertNil(result.stats.drift)
    }

    func testUnavailablePolicyMaintenanceAndAccountReplacementNeverAdmitAPlan() async {
        var maintenance = outcome
        maintenance.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        let missing = await projector.project(owner: "a", metrics: [metric()], input: .init(now: now, outcome: maintenance))
        XCTAssertEqual(missing.stats.presentation.state, .unsafeDate)
        XCTAssertNil(missing.stats.drift)
        let replacement = await projector.project(owner: "b", metrics: [metric()], input: .init(now: now))
        XCTAssertNil(replacement.stats.measurement)
        XCTAssertNil(replacement.stats.target)
        XCTAssertNil(replacement.planBaseline)
    }

    func testCoachFirstActionRestoresOriginalEvidenceAndWeeklyReviewOnReturn() async throws {
        let saved = DatedOutcomeSnapshot(revision: UUID(), value: outcome)
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)), metric(weight: 78)]
        var manual = input(outcome)
        manual.permissionDenied = true
        let first = await projector.project(owner: "a", metrics: records, input: manual, savedOutcome: saved)
        let action = try XCTUnwrap(first.coach.actionToSave)
        XCTAssertEqual(action.nextAction, .hold)
        XCTAssertEqual(action.outcome, outcome)
        XCTAssertEqual(action.outcomeRevision, saved.revision)
        XCTAssertEqual(action.nextCheckIn, now.addingTimeInterval(week))
        XCTAssertEqual(action.baseline, first.planBaseline)
        XCTAssertTrue(action.evidence.contains { $0.provenance == .measured && $0.recordedAt == now })
        XCTAssertTrue(action.evidence.contains { $0.provenance == .engineDerived })
        let restored = DatedOutcomeSnapshot(
            revision: saved.revision, value: outcome, planBaseline: action.baseline, coachAction: action)
        let reopenedProjector = DatedTimelineProjector()
        let returned = await reopenedProjector.project(
            owner: "a", metrics: records, input: input(outcome), savedOutcome: restored)
        XCTAssertNil(returned.coach.actionToSave, "Return restores the receipt instead of claiming another review")
        XCTAssertEqual(returned.coach.nextCheckIn, action.nextCheckIn)
        XCTAssertEqual(returned.coach.presentation, first.coach.presentation)
        XCTAssertEqual(returned.coach.uncertainty, LaunchPromiseCopy.framing)
    }

    func testCoachWeeklyOnTrackBehindAndAheadHoldOrReviewWithoutTrainingNumbers() async throws {
        let saved = DatedOutcomeSnapshot(revision: UUID(), value: outcome)
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)), metric(weight: 78)]
        let first = await projector.project(owner: "a", metrics: records, input: input(outcome), savedOutcome: saved)
        let action = try XCTUnwrap(first.coach.actionToSave)
        let restored = DatedOutcomeSnapshot(
            revision: saved.revision, value: outcome, planBaseline: action.baseline, coachAction: action)
        for (weight, nextAction) in [(77.75, BackwardPlanner.NextAction.hold), (79, .reviewProgress), (77, .hold)] {
            var weekly = input(outcome)
            weekly.now = now.addingTimeInterval(week)
            weekly.planBaseline = action.baseline
            let result = await projector.project(
                owner: "a", metrics: records + [metric("weekly", weight: weight, date: weekly.now)],
                input: weekly, savedOutcome: restored)
            let reviewed = try XCTUnwrap(result.coach.actionToSave)
            XCTAssertEqual(reviewed.nextAction, nextAction)
            XCTAssertEqual(reviewed.baseline, action.baseline)
            XCTAssertEqual(reviewed.outcome, action.outcome)
            XCTAssertEqual(reviewed.nextCheckIn, weekly.now.addingTimeInterval(week))
            XCTAssertFalse(result.coach.presentation.action.detail.contains("adjusted"))
            for term in ["sets", "reps", "load", "safe", "guarantee"] {
                XCTAssertFalse(reviewed.rationale.lowercased().contains(term))
            }
        }
    }

    func testCoachWeeklyFreshnessGapDoesNotChangeActionOrPretendToAdjust() async throws {
        let saved = DatedOutcomeSnapshot(revision: UUID(), value: outcome)
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)), metric(weight: 78)]
        let first = await projector.project(owner: "a", metrics: records, input: input(outcome), savedOutcome: saved)
        let action = try XCTUnwrap(first.coach.actionToSave)
        var weekly = input(outcome)
        weekly.now = action.nextCheckIn
        weekly.planBaseline = action.baseline
        let restored = DatedOutcomeSnapshot(
            revision: saved.revision, value: outcome, planBaseline: action.baseline, coachAction: action)
        let result = await projector.project(owner: "a", metrics: records, input: weekly, savedOutcome: restored)
        XCTAssertEqual(result.coach.presentation.state, .stale)
        XCTAssertEqual(result.coach.destination, .measurement)
        XCTAssertNil(result.coach.actionToSave)
        XCTAssertEqual(result.coach.nextCheckIn, action.nextCheckIn)
        XCTAssertEqual(restored.coachAction, action)
        XCTAssertNil(result.coach.evidence)
    }

    func testCoachDateEditRecomputesAndRetryDoesNotReplaceBaseline() async throws {
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)), metric(weight: 78)]
        let first = await projector.project(owner: "a", metrics: records, input: input(outcome), savedOutcome: .init(
            revision: UUID(), value: outcome))
        let action = try XCTUnwrap(first.coach.actionToSave)
        var changed = outcome
        changed.outcomeDate = "2027-01-10"
        var edited = input(changed)
        edited.planBaseline = action.baseline
        let saved = DatedOutcomeSnapshot(revision: UUID(), value: changed, planBaseline: action.baseline)
        edited.offline = true
        let offline = await projector.project(owner: "a", metrics: records, input: edited, savedOutcome: saved)
        XCTAssertNil(offline.coach.actionToSave)
        XCTAssertEqual(offline.coach.destination, .retry)
        edited.offline = false
        let retry = await projector.project(owner: "a", metrics: records, input: edited, savedOutcome: saved)
        let recomputed = try XCTUnwrap(retry.coach.actionToSave)
        XCTAssertEqual(recomputed.outcome, changed)
        XCTAssertEqual(recomputed.baseline, action.baseline)
        XCTAssertNotEqual(recomputed.id, action.id)
        XCTAssertNotEqual(recomputed.outcomeRevision, action.outcomeRevision)
    }

    func testCoachUnavailablePlannerPolicyAndForeignMemoryFailClosed() async throws {
        let records = [metric("baseline", weight: 80, date: now.addingTimeInterval(-8 * week)), metric(weight: 78)]
        let saved = DatedOutcomeSnapshot(revision: UUID(), value: outcome)
        let first = await projector.project(owner: "a", metrics: records, input: input(outcome), savedOutcome: saved)
        let action = try XCTUnwrap(first.coach.actionToSave)
        var missingCheck = input(outcome)
        missingCheck.safetyAvailable = false
        var missingRates = input(outcome)
        missingRates.safeWeeklyChangeKg = nil
        for unavailable in [LaunchJourney.Input(now: now, outcome: outcome), missingCheck, missingRates] {
            let result = await projector.project(owner: "a", metrics: records, input: unavailable, savedOutcome: saved)
            XCTAssertNil(result.coach.actionToSave)
            XCTAssertNil(result.coach.evidence)
        }
        for partition in ["user", "product", "provenance", "claim-user", "claim-product"] {
            var isolated = action
            if partition == "user" { isolated.userId = "b" }
            if partition == "product" { isolated.productId = "other-product" }
            if partition == "provenance" { isolated.evidence[0].provenance = .coachInferred }
            if partition == "claim-user" { isolated.evidence[0].userId = "b" }
            if partition == "claim-product" { isolated.evidence[0].productId = "other-product" }
            let snapshot = DatedOutcomeSnapshot(revision: saved.revision, value: outcome,
                                                planBaseline: action.baseline, coachAction: isolated)
            let result = await projector.project(owner: "a", metrics: records, input: input(outcome), savedOutcome: snapshot)
            XCTAssertEqual(result.coach.presentation.state, .unsafeDate, partition)
            XCTAssertNil(result.coach.evidence, partition)
            XCTAssertNil(result.coach.actionToSave, partition)
        }
        let restored = DatedOutcomeSnapshot(
            revision: saved.revision, value: outcome, planBaseline: action.baseline, coachAction: action)
        let corrected = await projector.project(
            owner: "a", metrics: [records[0], metric(weight: 79)], input: input(outcome), savedOutcome: restored)
        XCTAssertEqual(corrected.coach.presentation.state, .unsafeDate)
        XCTAssertNil(corrected.coach.evidence, "A corrected reading cannot silently retain the old reviewed evidence")
    }
}
