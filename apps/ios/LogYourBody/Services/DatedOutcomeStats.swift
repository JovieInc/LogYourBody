import Foundation

/// Prepared by DatedTimelineProjector, never in a SwiftUI body. This is a view
/// of recorded evidence and the existing planner, not a body-scoring model.
struct DatedOutcomeStats {
    struct Value: Equatable {
        var text: String
        var caption: String
    }

    var presentation: LaunchJourney.Presentation
    var measurement: Value?
    var estimate: Value?
    var target: String?
    var deadline: String?
    var remaining: String?
    var expiresAt: Date?
    var drift: Value?
    var baseline: Value?

    static func project(
        input: LaunchJourney.Input, state: LaunchJourney.RouteState, action: LaunchJourney.Action,
        entries: [String: DatedTimelineProjector.Entry], metrics: [BodyMetrics]
    ) -> Self {
        let matching = input.readings.filter { $0.metric == input.outcome?.outcome.metric }
        let latest = matching.max(by: { $0.date < $1.date })
        let conflicting = latest.map { latest in
            matching.contains { $0.date == latest.date && $0.value != latest.value }
        } ?? false
        let estimateMetric = metrics.filter { entries[$0.id]?.bodyFatIsEstimate == true }
            .max(by: { $0.date < $1.date })
        let estimate = estimateMetric.flatMap { metric in
            entries[metric.id].map { Value(text: $0.bodyFat, caption: "\($0.bodyFatSource) · \(date(metric.date))") }
        }
        let measurement = conflicting ? nil : latest.map {
            Value(text: value($0.value, metric: $0.metric),
                  caption: "\($0.metric == .ffmi ? "Derived from recorded inputs" : "Recorded measurement") · \(date($0.date))")
        }
        let deadline = input.outcome?.outcomeDate
        let expiresAt = deadline.flatMap(DatedOutcome.calendarDate)
        let seconds = expiresAt?.timeIntervalSince(input.now)
        let remaining = seconds.flatMap { seconds -> String? in
            guard seconds.isFinite else { return nil }
            if seconds <= 0 { return "Date passed" }
            let days = ceil(seconds / (24 * 60 * 60))
            return days == 1 ? "1 day remaining" : String(format: "%.0f days remaining", days)
        }
        let plan = admittedPlan(input: input, state: state, readings: matching)
        let action = input.outcome == nil || !input.safetyAvailable ? action : recovery(state, action: action)
        return Self(
            presentation: .init(surface: .stats, state: state, title: title(state), action: action),
            measurement: measurement, estimate: estimate,
            target: input.outcome.map { value($0.outcome.targetValue, metric: $0.outcome.metric) },
            deadline: deadline, remaining: remaining, expiresAt: expiresAt,
            drift: plan.flatMap { plan in
                guard let drift = plan.driftKg, let evaluatedAt = plan.evaluatedAt else { return nil }
                return Value(text: String(format: "%+.1f kg", drift),
                             caption: "Planner difference at \(date(evaluatedAt)) · positive is behind; negative is ahead")
            },
            baseline: plan.flatMap { _ in input.planBaseline }.map {
                Value(text: value($0.value, metric: $0.metric), caption: "Original baseline · \(date($0.date))")
            }
        )
    }

    private static func admittedPlan(
        input: LaunchJourney.Input, state: LaunchJourney.RouteState, readings: [LaunchJourney.Reading]
    ) -> BackwardPlanner.Plan? {
        // Recovery states expose no trajectory, score or extrapolated trend.
        guard state == .ready, input.safetyAvailable, let outcome = input.outcome,
              outcome.outcome.metric == .weightKg else { return nil }
        let plan = LaunchJourney.weightPlanResult(outcome, readings: readings, input: input)
        guard let plan, [.onTrack, .behind, .ahead].contains(plan.status) else { return nil }
        return plan
    }

    private static func recovery(_ state: LaunchJourney.RouteState, action: LaunchJourney.Action) -> LaunchJourney.Action {
        switch state {
        case .unsafeDate:
            return .init(title: "Review your outcome",
                         detail: "This outcome needs constraint review. The target and date have not changed.")
        case .impossibleDate:
            return .init(title: "Choose a later date or a closer outcome",
                         detail: "The required change exceeds the supplied planning bounds. " +
                            "The target and date have not changed.")
        case .noData, .denial:
            return .init(title: action.title, detail: "Add a recorded measurement to review your saved outcome.")
        case .maintenance:
            return .init(title: "Review your outcome", detail: action.detail)
        default: return action
        }
    }

    private static func title(_ state: LaunchJourney.RouteState) -> String {
        switch state {
        case .ready: return "Goal-relative status"
        case .denial: return "Manual entry available"
        case .noData: return "More evidence needed"
        case .offline: return "Offline"
        case .stale: return "Fresh measurement needed"
        case .conflicting: return "Conflicting measurements"
        case .unsafeDate, .impossibleDate: return "Review constraints"
        case .expiredDate: return "Date passed"
        case .maintenance: return "Maintenance interval"
        }
    }

    private static func value(_ value: Double, metric: DatedOutcome.Metric) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        switch metric {
        case .weightKg: return String(format: "%.1f kg", value)
        case .bodyFatPercentage: return String(format: "%.1f%% body fat", value)
        case .ffmi: return String(format: "%.1f FFMI", value)
        }
    }

    private static func date(_ value: Date) -> String {
        String(value.formatted(.iso8601).prefix(10))
    }
}

/// Runs inside DatedTimelineProjector. It explains only the existing planner's
/// hold/review decision; it never creates or adjusts a numeric training prescription.
struct DatedCoachReview {
    var presentation: LaunchJourney.Presentation
    var destination: DatedTimelineProjector.Destination
    var actionToSave: DatedCoachAction?
    var nextCheckIn: Date?
    var evidence: String?
    var uncertainty: String?
    var note: String?
    var wakeAt: Date?

    static func project(
        owner: String, input: LaunchJourney.Input,
        decision: (state: LaunchJourney.RouteState, action: LaunchJourney.Action), saved: DatedOutcomeSnapshot?
    ) -> Self {
        var result = recovery(input: input, state: decision.state, action: decision.action)
        guard decision.state == .ready else { return result }
        guard input.safetyAvailable, !owner.isEmpty, let saved, saved.value == input.outcome,
              let baseline = input.planBaseline, let outcome = input.outcome,
              outcome.outcome.metric == .weightKg,
              let plan = LaunchJourney.weightPlanResult(outcome, readings: input.readings, input: input),
              [.onTrack, .behind, .ahead].contains(plan.status), let evaluatedAt = plan.evaluatedAt,
              let measurement = input.readings.first(where: { $0.metric == baseline.metric && $0.date == evaluatedAt }) else {
            return unavailable(input)
        }
        if let previous = saved.coachAction {
            guard previous.userId == owner, previous.productId == LaunchJourney.productId else {
                return unavailable(input)
            }
            if previous.outcomeRevision == saved.revision, previous.outcome == outcome, previous.baseline == baseline {
                guard previous.reviewedAt <= input.now, previous.evaluatedAt <= evaluatedAt,
                      previous.nextCheckIn > previous.reviewedAt,
                      authorizedEvidence(previous, safetyAvailable: input.safetyAvailable) else {
                    return unavailable(input)
                }
                if input.now < previous.nextCheckIn {
                    guard input.readings.contains(where: {
                        $0.metric == previous.measurement.metric && $0.date == previous.measurement.date &&
                            $0.value == previous.measurement.value
                    }) else { return unavailable(input) }
                    return presentation(previous, actionToSave: nil)
                }
                if evaluatedAt <= previous.evaluatedAt {
                    result = recovery(input: input, state: .stale, action: .init(
                        title: "Record a fresh measurement",
                        detail: "Your weekly review needs a new reading. The action and date have not changed."))
                    result.nextCheckIn = previous.nextCheckIn
                    result.note = "Weekly review due. " + LaunchPromiseCopy.framing
                    return result
                }
            }
        }
        let rationale: String
        switch plan.status {
        case .behind:
            rationale = "The reviewed measurement is behind the original dated trajectory. " +
                "Review progress before changing the plan."
        case .ahead:
            rationale = "The reviewed measurement is ahead of the original dated trajectory. Hold the plan for this review."
        default:
            rationale = "The reviewed measurement follows the original dated trajectory. Hold the plan for this review."
        }
        let evidence = claims(owner: owner, input: input, baseline: baseline, rationale: rationale, evaluatedAt: evaluatedAt)
        let action = DatedCoachAction(
            id: UUID(), userId: owner, productId: LaunchJourney.productId, outcomeRevision: saved.revision,
            outcome: outcome, baseline: baseline,
            measurement: .init(date: measurement.date, metric: measurement.metric, value: measurement.value),
            nextAction: plan.nextAction, rationale: rationale,
            evidence: evidence, reviewedAt: input.now, evaluatedAt: evaluatedAt,
            nextCheckIn: input.now.addingTimeInterval(7 * 24 * 60 * 60))
        guard authorizedEvidence(action, safetyAvailable: input.safetyAvailable) else { return unavailable(input) }
        return presentation(action, actionToSave: action)
    }

    private static func authorizedEvidence(_ action: DatedCoachAction, safetyAvailable: Bool) -> Bool {
        var memory = HealthMemoryStore()
        for claim in action.evidence {
            guard claim.userId == action.userId, claim.productId == action.productId,
                  claim.provenance != .coachInferred,
                  memory.remember(claim, safetyAvailable: safetyAvailable) else { return false }
        }
        guard case .records(let records) = memory.retrieve(
            userId: action.userId, productId: LaunchJourney.productId, safetyAvailable: safetyAvailable
        ) else { return false }
        return records.contains { $0.provenance == .measured && $0.recordedAt == action.evaluatedAt } &&
            records.contains { $0.provenance == .engineDerived && $0.text == action.rationale }
    }

    private static func claims(
        owner: String, input: LaunchJourney.Input, baseline: DatedOutcome.PlanBaseline,
        rationale: String, evaluatedAt: Date
    ) -> [HealthMemoryClaim] {
        var claims = input.readings.filter { $0.metric == baseline.metric && $0.date == evaluatedAt }.map {
            HealthMemoryClaim(userId: owner, productId: LaunchJourney.productId,
                              text: "Recorded \($0.value.formatted()) kg", provenance: .measured, recordedAt: $0.date)
        }
        claims.append(.init(userId: owner, productId: LaunchJourney.productId,
                            text: "Original baseline: \(baseline.value.formatted()) kg",
                            provenance: .measured, recordedAt: baseline.date))
        claims.append(.init(userId: owner, productId: LaunchJourney.productId,
                            text: rationale, provenance: .engineDerived, recordedAt: input.now))
        return claims
    }

    private static func presentation(_ action: DatedCoachAction, actionToSave: DatedCoachAction?) -> Self {
        let title = action.nextAction == .hold ? "Hold the plan" : "Review progress"
        let measuredDate = String(action.evaluatedAt.formatted(.iso8601).prefix(10))
        let baselineDate = String(action.baseline.date.formatted(.iso8601).prefix(10))
        let evidence = "Recorded \(action.measurement.value.formatted()) kg · \(measuredDate). " +
            "Original baseline \(action.baseline.value.formatted()) kg · \(baselineDate). " +
            "Target date · \(action.outcome.outcomeDate)."
        let checkIn = "Next review · " + String(action.nextCheckIn.formatted(.iso8601).prefix(10))
        let deadline = DatedOutcome.calendarDate(action.outcome.outcomeDate) ?? action.nextCheckIn
        return Self(
            presentation: .init(surface: .coach, state: .ready, title: "Your next action",
                                action: .init(title: title, detail: action.rationale)),
            destination: .timeline, actionToSave: actionToSave, nextCheckIn: action.nextCheckIn,
            evidence: evidence, uncertainty: LaunchPromiseCopy.framing,
            note: evidence + " " + checkIn + ". " + LaunchPromiseCopy.framing,
            wakeAt: min(deadline, action.nextCheckIn))
    }

    private static func unavailable(_ input: LaunchJourney.Input) -> Self {
        recovery(input: input, state: .unsafeDate, action: .init(
            title: "Review your outcome",
            detail: "Planning checks are unavailable. The target and date have not changed."))
    }

    private static func recovery(
        input: LaunchJourney.Input, state: LaunchJourney.RouteState, action: LaunchJourney.Action
    ) -> Self {
        // Reuse the canonical claim-limited presentation, including maintenance.
        let stats = DatedOutcomeStats.project(input: input, state: state, action: action, entries: [:], metrics: [])
        var presentation = stats.presentation
        presentation.surface = .coach
        let needsManualBaseline = state == .offline && input.outcome != nil && !input.readings.contains {
            $0.metric == input.outcome?.outcome.metric
        }
        return Self(presentation: presentation,
                    destination: needsManualBaseline ? .measurement :
                        (state == .maintenance ? .editor : DatedTimelineProjector.destination(
                            for: state, hasOutcome: input.outcome != nil)))
    }
}
