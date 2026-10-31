import Foundation

/// Pure classification of a user-selected target; never supplies a prescription or moves its date.
struct OutcomeFeasibility {
    enum Classification: String, Equatable, Sendable {
        case ok, unsafe, impossible, expired, noData
    }

    /// Values must be comparable measurements in the target metric's canonical units.
    struct Measurement: Equatable, Sendable {
        let date: Date
        let metric: DatedOutcome.Metric
        let value: Double
    }

    /// Supplied only from reviewed contract policy. There are no physiological defaults.
    /// Weekly changes are signed and use the metric's canonical units per elapsed week.
    struct Thresholds: Equatable, Sendable {
        var minimumTarget: Double?
        var maximumTarget: Double?
        var minimumWeeklyChange: Double?
        var maximumWeeklyChange: Double?

        fileprivate var ranges: (target: ClosedRange<Double>, weeklyChange: ClosedRange<Double>)? {
            guard let minimumTarget, let maximumTarget, let minimumWeeklyChange, let maximumWeeklyChange,
                  minimumTarget.isFinite, maximumTarget.isFinite,
                  minimumWeeklyChange.isFinite, maximumWeeklyChange.isFinite,
                  minimumTarget > 0, minimumTarget <= maximumTarget,
                  minimumWeeklyChange <= 0, maximumWeeklyChange >= 0 else { return nil }
            return (minimumTarget...maximumTarget, minimumWeeklyChange...maximumWeeklyChange)
        }
    }

    let now: Date
    // The current Jovie v1 fixture supplies no thresholds. Missing policy fails closed.
    var thresholds: [DatedOutcome.Metric: Thresholds] = [:]

    func classify(outcome: DatedOutcome, history: [Measurement]) -> Classification {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let deadline = DatedOutcome.calendarDate(outcome.outcomeDate) else { return .unsafe }
        // Check before targets, policy, or history: missing/invalid data cannot hide expiry.
        if deadline <= now { return .expired }
        do {
            try outcome.validate()
        } catch { return .unsafe }
        guard let bounds = thresholds[outcome.outcome.metric]?.ranges,
              bounds.target.contains(outcome.outcome.targetValue) else { return .unsafe }
        guard let current = latestMeasurement(in: history, metric: outcome.outcome.metric) else { return .noData }

        let weeksRemaining = deadline.timeIntervalSince(now) / (7 * 24 * 60 * 60)
        let requiredChange = (outcome.outcome.targetValue - current.value) / weeksRemaining
        guard weeksRemaining.isFinite, weeksRemaining > 0, requiredChange.isFinite else { return .unsafe }
        return bounds.weeklyChange.contains(requiredChange) ? .ok : .impossible
    }

    private func latestMeasurement(in history: [Measurement], metric: DatedOutcome.Metric) -> Measurement? {
        let usable = history.filter {
            $0.metric == metric && $0.date.timeIntervalSinceReferenceDate.isFinite && $0.date <= now &&
                $0.value.isFinite && $0.value > 0
        }
        guard let latestDate = usable.map(\.date).max(),
              let latest = usable.first(where: { $0.date == latestDate }),
              !usable.contains(where: { $0.date == latestDate && $0.value != latest.value }) else { return nil }
        return latest
    }
}
