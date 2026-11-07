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
