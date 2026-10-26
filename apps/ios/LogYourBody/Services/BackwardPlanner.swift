import Foundation

/// Pure dated weight planning. This slice does not prescribe diet or training changes.
struct BackwardPlanner {
    /// Projection for the persisted-outcome slice; all weights are kilograms.
    struct Outcome: Equatable {
        let startDate: Date
        let startingWeightKg: Double
        let targetWeightKg: Double
        let targetDate: Date
    }

    /// Callers supply comparable measurements, rather than mixing measurement methods.
    struct Measurement: Equatable {
        let date: Date
        let weightKg: Double
    }

    enum Status: Equatable {
        case onTrack, behind, ahead, maintenance, expired
        case needsMeasurement, conflictingMeasurements, invalidOutcome, unavailableRates, unsafeRate
    }

    enum NextAction: Equatable {
        case hold, reviewProgress, reviewOutcome, recordMeasurement
    }

    struct Plan: Equatable {
        let status: Status
        /// Mathematical requirement from the original baseline to the deadline, not a prescription.
        /// Nil for invalid/expired outcomes; maintenance is zero.
        let requiredWeeklyChangeKg: Double?
        let expectedWeightKg: Double?
        /// Positive means behind, negative means ahead, for both loss and gain.
        /// Maintenance uses measured minus target weight, since it has no direction.
        let driftKg: Double?
        /// Drift is evaluated at the latest usable measurement, never extrapolated to now.
        let evaluatedAt: Date?
        let nextAction: NextAction
    }

    /// Signed kg/week bounds supplied by the deterministic engine. No physiological
    /// defaults: the v1 Jovie launch fixture defines no rates. Nil fails closed.
    let safeWeeklyChangeKg: ClosedRange<Double>?

    private static let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60

    func plan(outcome: Outcome, history: [Measurement], now: Date) -> Plan {
        guard valid(outcome, now: now) else {
            return result(.invalidOutcome, action: .reviewOutcome)
        }

        let measurements = history.filter {
            $0.date.timeIntervalSinceReferenceDate.isFinite && $0.weightKg.isFinite && $0.weightKg > 0 &&
                $0.date >= outcome.startDate && $0.date <= now
        }
        let latestDate = measurements.map(\.date).max()
        let latest = measurements.filter { $0.date == latestDate }
        let weight = latest.first?.weightKg
        let conflicts = latest.contains { $0.weightKg != weight }
        let change = outcome.targetWeightKg - outcome.startingWeightKg
        let direction = change < 0 ? -1.0 : 1.0
        let expired = outcome.targetDate <= now
        let weeks = outcome.targetDate.timeIntervalSince(outcome.startDate) / Self.secondsPerWeek
        let rate = expired ? nil : change / weeks
        let fraction = latestDate.map {
            min(1, $0.timeIntervalSince(outcome.startDate) / outcome.targetDate.timeIntervalSince(outcome.startDate))
        }
        let expected = fraction.map { outcome.startingWeightKg + change * $0 }
        let drift = conflicts ? nil : weight.flatMap { measured in
            expected.map { expected in
                let difference = change == 0 ? measured - expected : (expected - measured) * direction
                // Absorb floating-point interpolation roundoff, not physiological drift.
                let roundoff = max(measured.ulp, expected.ulp)
                return abs(difference) <= roundoff ? 0 : difference
            }
        }

        func finish(_ status: Status, _ action: NextAction) -> Plan {
            Plan(status: status, requiredWeeklyChangeKg: rate, expectedWeightKg: expected,
                 driftKg: drift, evaluatedAt: latestDate, nextAction: action)
        }

        // A deadline is never silently extended, including when measurements are missing.
        if expired { return finish(.expired, .reviewOutcome) }
        if conflicts { return finish(.conflictingMeasurements, .recordMeasurement) }
        guard let drift, let weight, let latestDate else { return finish(.needsMeasurement, .recordMeasurement) }
        if change == 0 { return finish(.maintenance, drift == 0 ? .hold : .reviewProgress) }
        guard let bounds = safeWeeklyChangeKg,
              bounds.lowerBound.isFinite, bounds.upperBound.isFinite,
              bounds.lowerBound <= 0, bounds.upperBound >= 0 else {
            return finish(.unavailableRates, .reviewOutcome)
        }
        // Never clamp an impossible date into an apparently achievable plan. Also
        // check the remaining requirement against the same bounds after drift.
        let remainingWeeks = outcome.targetDate.timeIntervalSince(latestDate) / Self.secondsPerWeek
        let remainingRate = (outcome.targetWeightKg - weight) / remainingWeeks
        guard let rate, rate.isFinite, remainingRate.isFinite,
              bounds.contains(rate), bounds.contains(remainingRate) else {
            return finish(.unsafeRate, .reviewOutcome)
        }
        if drift > 0 { return finish(.behind, .reviewProgress) }
        if drift < 0 { return finish(.ahead, .hold) }
        return finish(.onTrack, .hold)
    }

    private func valid(_ outcome: Outcome, now: Date) -> Bool {
        now.timeIntervalSinceReferenceDate.isFinite && outcome.startDate.timeIntervalSinceReferenceDate.isFinite &&
            outcome.targetDate.timeIntervalSinceReferenceDate.isFinite &&
            outcome.targetDate.timeIntervalSince(outcome.startDate).isFinite &&
            outcome.targetDate.timeIntervalSince(outcome.startDate) / Self.secondsPerWeek > 0 &&
            outcome.startDate <= now && outcome.targetDate > outcome.startDate &&
            outcome.startingWeightKg.isFinite && outcome.startingWeightKg > 0 &&
            outcome.targetWeightKg.isFinite && outcome.targetWeightKg > 0
    }

    private func result(_ status: Status, action: NextAction) -> Plan {
        Plan(status: status, requiredWeeklyChangeKg: nil, expectedWeightKg: nil,
             driftKg: nil, evaluatedAt: nil, nextAction: action)
    }
}
