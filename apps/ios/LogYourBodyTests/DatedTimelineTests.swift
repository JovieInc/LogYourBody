import XCTest
@testable import LogYourBody

final class DatedTimelineTests: XCTestCase {
    private let projector = DatedTimelineProjector()
    private let now = DatedOutcome.calendarDate("2026-11-01")!
    private let week: TimeInterval = 7 * 24 * 60 * 60

    private var outcome: DatedOutcome {
        .init(outcome: .init(metric: .weightKg, targetValue: 76), outcomeDate: "2026-12-27")
    }

    /// Synthetic admission policy exercises wiring; these are not production limits.
    private func input(_ value: DatedOutcome? = nil) -> LaunchJourney.Input {
        .init(now: now, outcome: value ?? outcome, freshnessWindow: week,
              thresholds: [.weightKg: .init(minimumTarget: 40, maximumTarget: 250,
                                            minimumWeeklyChange: -1, maximumWeeklyChange: 1)],
              safeWeeklyChangeKg: -1...1)
    }

    private func metric(
        _ id: String = "current", owner: String = "a", date: Date? = nil,
        weight: Double? = 78, unit: String = "kg", bodyFat: Double? = nil,
        method: String? = nil, source: String = "manual", excluded: Bool = false
    ) -> BodyMetrics {
        .init(id: id, userId: owner, date: date ?? now, weight: weight, weightUnit: unit,
              bodyFatPercentage: bodyFat, bodyFatMethod: method, muscleMass: nil, boneMass: nil,
              notes: nil, photoUrl: nil, dataSource: source, isExcluded: excluded,
              createdAt: now.addingTimeInterval(100), updatedAt: now)
    }

    @MainActor
    func testDelayedSheetActionsRejectReplacementAccountAndSessionGeneration() {
        let owner = AuthManager.ProfileSessionOwnership(subject: "a", generation: 1)
        XCTAssertTrue(NativeSheetPresentationPolicy.allowsAction(owner: owner, current: owner))
        XCTAssertFalse(NativeSheetPresentationPolicy.allowsAction(owner: owner, current: nil))
        XCTAssertFalse(NativeSheetPresentationPolicy.allowsAction(
            owner: owner, current: .init(subject: "b", generation: 1)))
        XCTAssertFalse(NativeSheetPresentationPolicy.allowsAction(
            owner: owner, current: .init(subject: "a", generation: 2)))
        XCTAssertTrue(NativeSheetPresentationPolicy.allowsAction(owner: nil, current: nil),
                      "Unbound existing presentations retain their gate-off behavior")
    }

    func testEveryTimelineStatePreservesOutcomeAndHasOneRecoveryDestination() async {
        var denied = input()
        denied.permissionDenied = true
        var offline = input()
        offline.offline = true
        var stale = input()
        stale.freshnessWindow = nil
        var unsafe = input()
        unsafe.thresholds = [:]
        var impossible = outcome
        impossible.outcome.targetValue = 60
        impossible.outcomeDate = "2026-11-08"
        var expired = outcome
        expired.outcomeDate = "2026-10-01"
        var maintenance = outcome
        maintenance.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        let scenarios: [(LaunchJourney.RouteState, LaunchJourney.Input, [BodyMetrics])] = [
            (.ready, input(), [metric()]), (.denial, denied, []), (.noData, input(), []),
            (.offline, offline, [metric()]), (.stale, stale, [metric()]),
            (.conflicting, input(), [metric(), metric("conflict", weight: 79)]),
            (.unsafeDate, unsafe, [metric()]), (.impossibleDate, input(impossible), [metric()]),
            (.expiredDate, input(expired), []), (.maintenance, input(maintenance), [metric()])
        ]
        XCTAssertEqual(Set(scenarios.map { $0.0 }), Set(LaunchJourney.RouteState.allCases))
        for (state, input, metrics) in scenarios {
            let result = await projector.project(owner: "a", metrics: metrics, input: input)
            XCTAssertEqual(result.presentation.state, state)
            XCTAssertEqual(result.outcome, input.outcome, state.rawValue)
            XCTAssertEqual(result.destination, DatedTimelineProjector.destination(for: state, hasOutcome: true))
            XCTAssertFalse(result.presentation.action.title.isEmpty)
        }
    }

    func testDeniedAndInterruptedOptionalInputsAllowManualBaselineWithoutPolicy() async {
        var denied = LaunchJourney.Input(now: now, outcome: outcome, permissionDenied: true)
        let first = await projector.project(owner: "a", metrics: [], input: denied)
        XCTAssertEqual(first.presentation.state, .denial)
        XCTAssertEqual(first.destination, .measurement)
        denied.permissionDenied = false // Cancelled import is not evidence of denial.
        let interrupted = await projector.project(owner: "a", metrics: [], input: denied)
        XCTAssertEqual(interrupted.presentation.state, .noData)
        XCTAssertEqual(interrupted.destination, .measurement)
        denied.offline = true
        let offline = await projector.project(owner: "a", metrics: [], input: denied)
        XCTAssertEqual(offline.presentation.state, .offline)
        XCTAssertEqual(offline.destination, .measurement)
        XCTAssertEqual(offline.outcome, outcome)
    }

    func testManualBaselineNeverAdmitsMissingOrIncompletePolicy() async {
        var missing = LaunchJourney.Input(now: now, outcome: outcome, freshnessWindow: week)
        let first = await projector.project(owner: "a", metrics: [metric()], input: missing)
        XCTAssertEqual(first.presentation.state, .unsafeDate)
        XCTAssertEqual(first.destination, .editor)
        missing.thresholds = [.weightKg: .init(minimumTarget: 40, maximumTarget: 250)]
        let incomplete = await projector.project(owner: "a", metrics: [metric()], input: missing)
        XCTAssertEqual(incomplete.presentation.state, .unsafeDate)
        XCTAssertEqual(incomplete.outcome, outcome)
    }

    func testDatedProvenanceDoesNotUseImportTimeAsMeasurementTime() async {
        let old = metric(date: now.addingTimeInterval(-2 * week), weight: 176.3698, unit: "lbs", source: "healthkit")
        let result = await projector.project(owner: "a", metrics: [old], input: input())
        XCTAssertEqual(result.presentation.state, .stale)
        XCTAssertEqual(result.entries[old.id]?.weight, "80.0 kg")
        XCTAssertEqual(result.entries[old.id]?.weightSource, "Apple Health")
        XCTAssertTrue(result.entries[old.id]?.provenance.contains(old.localDate) == true)
        XCTAssertFalse(result.entries[old.id]?.provenance.contains(outcome.outcomeDate) == true)
    }

    func testForeignExcludedFutureAndPhotoEstimatesCannotEstablishBaseline() async {
        let records = [metric("foreign", owner: "b"), metric("excluded", excluded: true),
                       metric("future", date: now.addingTimeInterval(1)),
                       metric("photo", bodyFat: 20, method: "visual_estimate", source: "photo"),
                       metric("unknown-unit", unit: "unknown")]
        let result = await projector.project(owner: "a", metrics: records, input: input())
        XCTAssertEqual(result.presentation.state, .noData)
        XCTAssertNil(result.entries["foreign"])
        XCTAssertNil(result.entries["excluded"])
        XCTAssertNil(result.entries["future"])
        XCTAssertEqual(result.entries["photo"]?.weight, "—")
        XCTAssertEqual(result.entries["photo"]?.bodyFatSource, "Visual estimate")
        XCTAssertEqual(result.entries["unknown-unit"]?.weight, "—")
    }

    func testOptionalDexaAndDisclosureDoNotChangeRecovery() async {
        var optional = input()
        optional.glp1Disclosed = true
        optional.dexaPresent = true
        let ordinary = await projector.project(owner: "a", metrics: [metric()], input: input())
        let disclosed = await projector.project(owner: "a", metrics: [metric()], input: optional)
        XCTAssertEqual(ordinary.presentation, disclosed.presentation)
        XCTAssertEqual(ordinary.destination, disclosed.destination)
    }

    func testExpiredDateWinsOverOfflineDenialAndMissingPolicy() async {
        var expired = outcome
        expired.outcomeDate = "2026-10-01"
        let result = await projector.project(owner: "a", metrics: [], input: .init(
            now: now, outcome: expired, offline: true, permissionDenied: true, safetyAvailable: false))
        XCTAssertEqual(result.presentation.state, .expiredDate)
        XCTAssertEqual(result.destination, .editor)
        XCTAssertEqual(result.outcome?.outcomeDate, "2026-10-01")
    }

    func testSafetyAndMaintenanceWithMissingPolicyRecoverWithoutAdmittingPlan() async {
        var unavailable = input()
        unavailable.safetyAvailable = false
        let safety = await projector.project(owner: "a", metrics: [], input: unavailable)
        XCTAssertEqual(safety.presentation.state, .unsafeDate)
        XCTAssertEqual(safety.destination, .editor)
        var maintenance = outcome
        maintenance.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        let held = await projector.project(owner: "a", metrics: [metric()], input: .init(now: now, outcome: maintenance))
        XCTAssertEqual(held.presentation.state, .unsafeDate)
        XCTAssertEqual(held.outcome, maintenance)
        XCTAssertEqual(held.destination, .editor)
    }

    func testSwitchingAccountsCannotExposePreviousHistoryOrRequireItsAction() async {
        let previous = await projector.project(owner: "a", metrics: [metric()], input: input())
        XCTAssertNotNil(previous.entries["current"])
        let next = await projector.project(owner: "b", metrics: [metric()], input: .init(now: now))
        XCTAssertTrue(next.entries.isEmpty)
        XCTAssertNil(next.outcome)
        XCTAssertEqual(next.destination, .editor)
        XCTAssertFalse(next.containsOnlyOwnerRecords)
    }

    func testManualBodyFatAndFFMIBaselinesUseExistingInputs() async {
        var bodyFat = outcome
        bodyFat.outcome.metric = .bodyFatPercentage
        bodyFat.outcome.targetValue = 20
        let empty = await projector.project(owner: "a", metrics: [], input: input(bodyFat))
        XCTAssertEqual(empty.baselineTab, 1)
        var ffmi = bodyFat
        ffmi.outcome.metric = .ffmi
        let needsHeight = await projector.project(
            owner: "a", metrics: [metric(bodyFat: 20, method: "manual")], input: input(ffmi))
        XCTAssertEqual(needsHeight.destination, .profile)
        let complete = await projector.project(owner: "a", metrics: [metric(bodyFat: 20, method: "manual")],
                                               input: input(ffmi), heightCm: 178)
        XCTAssertEqual(complete.presentation.state, .unsafeDate, "Derived baseline still requires approved policy")
        XCTAssertNotEqual(complete.entries["current"]?.ffmi, "—")
    }
}
