import XCTest
@testable import LogYourBody

final class BackwardPlannerTests: XCTestCase {
    private typealias Outcome = BackwardPlanner.Outcome
    private typealias Measurement = BackwardPlanner.Measurement

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let week: TimeInterval = 7 * 24 * 60 * 60
    // Arithmetic test bounds only, NOT approved physiological policy or production defaults.
    private let planner = BackwardPlanner(safeWeeklyChangeKg: -1...1)

    func testPinnedLaunchContractIncludesDriftDeadlineAndSafetyPaths() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "lyb-launch-contract", withExtension: "json"))
        let contract = try JSONDecoder().decode(LaunchContract.self, from: Data(contentsOf: url))
        XCTAssertEqual(contract.schema, "lyb-launch-contract/v1")
        XCTAssertEqual(contract.sourceIssue, "JOV-6013")
        XCTAssertTrue(contract.promise.requiredInputs.contains("outcomeDate"))
        for path in ["launch.drift", "launch.deadline-replan", "launch.return", "launch.safety"] {
            XCTAssertTrue(contract.requiredPaths.contains { $0.id == path }, path)
        }
    }

    func testOnTrackLossReturnsZeroDriftAndHold() {
        let plan = plan(target: 76, current: 78)
        XCTAssertEqual(plan.status, .onTrack)
        XCTAssertEqual(plan.requiredWeeklyChangeKg, -0.5)
        XCTAssertEqual(plan.expectedWeightKg, 78)
        XCTAssertEqual(plan.driftKg, 0)
        XCTAssertEqual(plan.nextAction, .hold)
        XCTAssertEqual(plan.evaluatedAt, date(weeks: 4))
    }

    func testBehindLossReturnsPositiveDriftAndOneReviewAction() {
        let plan = plan(target: 76, current: 79)
        XCTAssertEqual(plan.status, .behind)
        XCTAssertEqual(plan.driftKg, 1)
        XCTAssertEqual(plan.nextAction, .reviewProgress)
    }

    func testAheadLossReturnsNegativeDriftAndHold() {
        let plan = plan(target: 76, current: 77)
        XCTAssertEqual(plan.status, .ahead)
        XCTAssertEqual(plan.driftKg, -1)
        XCTAssertEqual(plan.nextAction, .hold)
    }

    func testGainUsesTheSameDriftSignsAndActions() {
        let onTrack = plan(target: 84, current: 82)
        XCTAssertEqual(onTrack.status, .onTrack)
        XCTAssertEqual(onTrack.requiredWeeklyChangeKg, 0.5)
        XCTAssertEqual(onTrack.driftKg, 0)
        XCTAssertEqual(onTrack.nextAction, .hold)

        let behind = plan(target: 84, current: 81)
        XCTAssertEqual(behind.status, .behind)
        XCTAssertEqual(behind.driftKg, 1)
        XCTAssertEqual(behind.nextAction, .reviewProgress)

        let ahead = plan(target: 84, current: 83)
        XCTAssertEqual(ahead.status, .ahead)
        XCTAssertEqual(ahead.driftKg, -1)
        XCTAssertEqual(ahead.nextAction, .hold)
    }

    func testMaintenanceNeedsNoRatePolicyAndNeverInventsADirection() {
        let planner = BackwardPlanner(safeWeeklyChangeKg: nil)
        for current in [79.0, 80, 81] {
            let result = planner.plan(outcome: outcome(target: 80), history: [measurement(4, current)], now: date(weeks: 4))
            XCTAssertEqual(result.status, .maintenance)
            XCTAssertEqual(result.requiredWeeklyChangeKg, 0)
            XCTAssertEqual(result.expectedWeightKg, 80)
            XCTAssertEqual(result.driftKg, current - 80)
            XCTAssertEqual(result.nextAction, current == 80 ? .hold : .reviewProgress)
        }
    }

    func testDeadlineAndExpiredDatesReturnReviewWithoutExtendingTheDate() {
        for weeks in [8.0, 9] {
            let result = planner.plan(outcome: outcome(), history: [measurement(8, 76)], now: date(weeks: weeks))
            XCTAssertEqual(result.status, .expired)
            XCTAssertNil(result.requiredWeeklyChangeKg)
            XCTAssertEqual(result.expectedWeightKg, 76)
            XCTAssertEqual(result.driftKg, 0)
            XCTAssertEqual(result.nextAction, .reviewOutcome)
        }
    }

    func testExpiredOutcomeWithoutHistoryStillOffersReview() {
        let result = planner.plan(outcome: outcome(), history: [], now: date(weeks: 9))
        XCTAssertEqual(result.status, .expired)
        XCTAssertNil(result.driftKg)
        XCTAssertEqual(result.nextAction, .reviewOutcome)
    }

    func testChangingTheDeadlineRecomputesTheTrajectoryAndDrift() {
        let history = [measurement(4, 78)]
        let original = planner.plan(outcome: outcome(), history: history, now: date(weeks: 4))
        let revised = planner.plan(outcome: outcome(deadlineWeeks: 16), history: history, now: date(weeks: 4))
        XCTAssertEqual(original.requiredWeeklyChangeKg, -0.5)
        XCTAssertEqual(revised.requiredWeeklyChangeKg, -0.25)
        XCTAssertEqual(revised.expectedWeightKg, 79)
        XCTAssertEqual(revised.driftKg, -1)
        XCTAssertEqual(revised.nextAction, .hold)
    }

    func testImpossibleLossAndGainDeadlinesAskToReviewInsteadOfClampingTheRate() {
        for target in [60.0, 100] {
            let result = plan(target: target, current: 80)
            XCTAssertEqual(result.status, .unsafeRate)
            XCTAssertEqual(abs(result.requiredWeeklyChangeKg ?? 0), 2.5)
            XCTAssertEqual(result.nextAction, .reviewOutcome)
        }
    }

    func testRemainingRequirementCannotExceedEngineBoundsEvenWhenOriginalRateWasSafe() {
        let result = planner.plan(outcome: outcome(), history: [measurement(7, 80)], now: date(weeks: 7))
        XCTAssertEqual(result.requiredWeeklyChangeKg, -0.5)
        XCTAssertEqual(result.driftKg, 3.5)
        XCTAssertEqual(result.status, .unsafeRate)
        XCTAssertEqual(result.nextAction, .reviewOutcome)
    }

    func testUsesTheSuppliedBoundsIncludingTheirEndpoints() {
        let history = [measurement(0, 80)]
        for limit in [0.49, 0.5] {
            let result = BackwardPlanner(safeWeeklyChangeKg: -limit...limit)
                .plan(outcome: outcome(), history: history, now: start)
            XCTAssertEqual(result.status, limit == 0.5 ? .onTrack : .unsafeRate)
            XCTAssertEqual(result.nextAction, limit == 0.5 ? .hold : .reviewOutcome)
        }
    }

    func testMissingOrUnboundedRatePolicyFailsClosed() {
        let policies: [ClosedRange<Double>?] = [nil, -Double.infinity...1, -1...Double.infinity, 1...2]
        for policy in policies {
            let result = BackwardPlanner(safeWeeklyChangeKg: policy)
                .plan(outcome: outcome(), history: [measurement(4, 78)], now: date(weeks: 4))
            XCTAssertEqual(result.status, .unavailableRates)
            XCTAssertEqual(result.nextAction, .reviewOutcome)
        }
    }

    func testMissingOrInvalidMeasurementsAskForOneMeasurement() {
        let histories: [[Measurement]] = [
            [],
            [measurement(4, .nan), measurement(4, .infinity), measurement(4, 0),
             measurement(4, -80), measurement(-1, 80), measurement(5, 78),
             Measurement(date: Date(timeIntervalSince1970: .nan), weightKg: 78)]
        ]
        for history in histories {
            let result = planner.plan(outcome: outcome(), history: history, now: date(weeks: 4))
            XCTAssertEqual(result.status, .needsMeasurement)
            XCTAssertNil(result.driftKg)
            XCTAssertEqual(result.nextAction, .recordMeasurement)
        }
    }

    func testHistoryOrderDuplicatesAndFutureMeasurementsDoNotChangeThePlan() {
        let history = [measurement(0, 80), measurement(2, 79), measurement(4, 78)]
        let expected = planner.plan(outcome: outcome(), history: history, now: date(weeks: 4))
        let reordered = [history[2], history[0], history[1], history[2], measurement(5, 100)]
        for _ in 0..<10 {
            XCTAssertEqual(planner.plan(outcome: outcome(), history: reordered, now: date(weeks: 4)), expected)
        }
        XCTAssertEqual(history, [measurement(0, 80), measurement(2, 79), measurement(4, 78)])
    }

    func testConflictingLatestMeasurementsNeverChooseAnArbitraryWeight() {
        let history = [measurement(0, 80), measurement(4, 78), measurement(4, 79)]
        let result = planner.plan(outcome: outcome(), history: history, now: date(weeks: 4))
        XCTAssertEqual(result.status, .conflictingMeasurements)
        XCTAssertNil(result.driftKg)
        XCTAssertEqual(result.nextAction, .recordMeasurement)
        XCTAssertEqual(planner.plan(outcome: outcome(), history: Array(history.reversed()), now: date(weeks: 4)), result)
    }

    func testOldMeasurementIsComparedAtItsOwnDateWithoutExtrapolatingProgress() {
        let result = planner.plan(outcome: outcome(), history: [measurement(2, 79)], now: date(weeks: 4))
        XCTAssertEqual(result.expectedWeightKg, 79)
        XCTAssertEqual(result.driftKg, 0)
        XCTAssertEqual(result.evaluatedAt, date(weeks: 2))
    }

    func testFractionalWeeksUseElapsedTimeAndIgnoreInterpolationRoundoff() {
        let result = planner.plan(outcome: outcome(), history: [measurement(0.5, 79.75)], now: date(weeks: 0.5))
        XCTAssertEqual(result.requiredWeeklyChangeKg, -0.5)
        XCTAssertEqual(result.expectedWeightKg, 79.75)
        XCTAssertEqual(result.status, .onTrack)
        let roundoff = planner.plan(outcome: outcome(), history: [measurement(4, 78.0.nextUp)], now: date(weeks: 4))
        XCTAssertEqual(roundoff.driftKg, 0)
        XCTAssertEqual(roundoff.nextAction, .hold)
    }

    func testInvalidOutcomesAndClockValuesReturnDefinedResults() {
        let invalid = [
            outcome(deadlineWeeks: 0), outcome(deadlineWeeks: -1), outcome(target: .nan),
            outcome(target: .infinity), outcome(target: 0),
            Outcome(startDate: start, startingWeightKg: -80, targetWeightKg: 76, targetDate: date(weeks: 8)),
            Outcome(startDate: date(weeks: 5), startingWeightKg: 80, targetWeightKg: 76, targetDate: date(weeks: 8)),
            Outcome(startDate: start, startingWeightKg: 80, targetWeightKg: 76,
                    targetDate: Date(timeIntervalSince1970: .infinity))
        ]
        for outcome in invalid {
            let result = planner.plan(outcome: outcome, history: [], now: date(weeks: 4))
            XCTAssertEqual(result.status, .invalidOutcome)
            XCTAssertNil(result.requiredWeeklyChangeKg)
            XCTAssertNil(result.driftKg)
            XCTAssertEqual(result.nextAction, .reviewOutcome)
        }
        XCTAssertEqual(planner.plan(outcome: outcome(), history: [], now: Date(timeIntervalSince1970: .nan)).status,
                       .invalidOutcome)
    }

    private func plan(target: Double, current: Double) -> BackwardPlanner.Plan {
        planner.plan(outcome: outcome(target: target), history: [measurement(0, 80), measurement(4, current)],
                     now: date(weeks: 4))
    }

    private func outcome(target: Double = 76, deadlineWeeks: Double = 8) -> Outcome {
        Outcome(startDate: start, startingWeightKg: 80, targetWeightKg: target, targetDate: date(weeks: deadlineWeeks))
    }

    private func measurement(_ weeks: Double, _ weightKg: Double) -> Measurement {
        Measurement(date: date(weeks: weeks), weightKg: weightKg)
    }

    private func date(weeks: Double) -> Date {
        start.addingTimeInterval(weeks * week)
    }
}

private struct LaunchContract: Decodable {
    let schema: String
    let sourceIssue: String
    let promise: Promise
    let requiredPaths: [RequiredPath]

    struct Promise: Decodable {
        let requiredInputs: [String]
    }

    struct RequiredPath: Decodable {
        let id: String
    }
}
