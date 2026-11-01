import Foundation

/// Dated launch decision for timeline, body score, and Jovi. Optional GLP-1 and
/// DEXA inputs never change the plan or add medication commentary. Missing
/// safety policy fails closed. A date is never extended.
enum LaunchJourney {
    static let promiseHeadline = "Your body-composition goal, planned around your next date."
    static let promiseExplanation =
        "Set an outcome and a date. LogYourBody follows your photos and measurements, spots drift, and gives you one next action."
    static let promiseFraming = "Dates guide the plan. They do not guarantee a result."
    static let productId = "lyb"
    static let hiddenSurfaceMessage = "This step isn't part of your dated plan."
    static let hiddenSurfaceAction = "Back to coach"

    enum Surface: String, Equatable, CaseIterable {
        case timeline, stats, coach
    }

    enum RouteState: String, Equatable, CaseIterable {
        case ready
        case denial
        case noData = "no-data"
        case offline
        case stale
        case conflicting
        case unsafeDate = "unsafe-date"
        case impossibleDate = "impossible-date"
        case expiredDate = "expired-date"
        case maintenance
    }

    struct Action: Equatable {
        var title: String
        var detail: String
    }

    struct Presentation: Equatable {
        var surface: Surface
        var state: RouteState
        var title: String
        var action: Action
    }

    struct Reading: Equatable {
        var date: Date
        var metric: DatedOutcome.Metric
        var value: Double
    }

    struct Input: Equatable {
        var now: Date
        var outcome: DatedOutcome?
        var readings: [Reading] = []
        var offline = false
        var permissionDenied = false
        var safetyAvailable = true
        /// Nil means no approved freshness window. An existing reading is then stale.
        var freshnessWindow: TimeInterval?
        var thresholds: [DatedOutcome.Metric: OutcomeFeasibility.Thresholds] = [:]
        /// Nil means no approved kilogram rate. The weight planner then fails closed.
        var safeWeeklyChangeKg: ClosedRange<Double>?
        var glp1Disclosed = false
        var dexaPresent = false
    }

    static func presentations(for input: Input) -> [Presentation] {
        let decision = decide(input)
        return Surface.allCases.map { surface in
            Presentation(
                surface: surface,
                state: decision.state,
                title: title(for: surface),
                action: decision.action
            )
        }
    }

    static func decide(_ input: Input) -> (state: RouteState, action: Action) {
        // The optional wedge is recorded and then ignored.
        _ = input.glp1Disclosed || input.dexaPresent
        if !input.safetyAvailable {
            return (.unsafeDate, Action(
                title: "Review your outcome",
                detail: "Safety checks are unavailable, so this date has no plan."
            ))
        }
        let usable = input.readings.filter { $0.date <= input.now && $0.value.isFinite && $0.value > 0 }
        if input.permissionDenied && usable.isEmpty {
            return (.denial, Action(
                title: "Enter one measurement",
                detail: "Apple Health is unavailable. One measurement keeps the date."
            ))
        }
        if input.offline {
            if let outcome = input.outcome {
                return (.offline, Action(
                    title: "Retry sync",
                    detail: "Saved goal: \(label(outcome)). You're offline, and the date stays \(outcome.outcomeDate)."
                ))
            }
            return (.offline, Action(
                title: "Set an outcome and a date",
                detail: "You're offline. The date can be saved on this device."
            ))
        }
        guard let outcome = input.outcome else {
            return (.noData, Action(title: "Set an outcome and a date", detail: promiseExplanation))
        }
        let metricReadings = usable.filter { $0.metric == outcome.outcome.metric }
        let feasibility = OutcomeFeasibility(now: input.now, thresholds: input.thresholds)
            .classify(outcome: outcome, history: metricReadings.map {
                OutcomeFeasibility.Measurement(date: $0.date, metric: $0.metric, value: $0.value)
            })
        switch feasibility {
        case .expired:
            return (.expiredDate, Action(
                title: "Choose a new date or maintenance",
                detail: "\(outcome.outcomeDate) has passed. The date was not extended."
            ))
        case .unsafe:
            return unsafe(outcome)
        case .impossible:
            return (.impossibleDate, Action(
                title: "Choose a later date or a closer outcome",
                detail: "This date cannot be reached safely. \(outcome.outcomeDate) was not moved."
            ))
        case .noData, .ok:
            if conflicts(metricReadings) {
                return (.conflicting, Action(
                    title: "Record one new measurement",
                    detail: "Two values share a time. Record one measurement for \(outcome.outcomeDate)."
                ))
            }
            if feasibility == .noData {
                return (.noData, Action(
                    title: "Add one measurement",
                    detail: "One measurement starts the plan for \(outcome.outcomeDate)."
                ))
            }
            if stale(metricReadings, now: input.now, window: input.freshnessWindow) {
                return (.stale, Action(
                    title: "Record a fresh measurement",
                    detail: "The latest measurement is too old to steer \(outcome.outcomeDate)."
                ))
            }
            if maintenanceCovers(outcome, now: input.now) {
                return (.maintenance, Action(
                    title: "Hold this maintenance interval",
                    detail: "Maintenance holds the plan. The date stays \(outcome.outcomeDate)."
                ))
            }
            if outcome.outcome.metric == .weightKg {
                return weightPlan(outcome, readings: metricReadings, input: input)
            }
            return (.ready, Action(
                title: "Hold the plan",
                detail: "The date stays \(outcome.outcomeDate)."
            ))
        }
    }

    private static func weightPlan(
        _ outcome: DatedOutcome, readings: [Reading], input: Input
    ) -> (state: RouteState, action: Action) {
        guard let start = readings.min(by: { $0.date < $1.date }),
              let deadline = DatedOutcome.calendarDate(outcome.outcomeDate) else {
            return unsafe(outcome)
        }
        let plan = BackwardPlanner(safeWeeklyChangeKg: input.safeWeeklyChangeKg).plan(
            outcome: .init(
                startDate: start.date,
                startingWeightKg: start.value,
                targetWeightKg: outcome.outcome.targetValue,
                targetDate: deadline
            ),
            history: readings.map { .init(date: $0.date, weightKg: $0.value) },
            now: input.now
        )
        switch plan.status {
        case .onTrack, .ahead:
            return (.ready, Action(title: "Hold the plan", detail: "The date stays \(outcome.outcomeDate)."))
        case .behind:
            return (.ready, Action(
                title: "Review progress",
                detail: "You're behind \(outcome.outcomeDate). Review progress before changing the date."
            ))
        case .maintenance:
            return (.maintenance, Action(
                title: plan.nextAction == .hold ? "Hold the plan" : "Review progress",
                detail: "Maintenance holds the plan. The date stays \(outcome.outcomeDate)."
            ))
        case .expired:
            return (.expiredDate, Action(
                title: "Choose a new date or maintenance",
                detail: "\(outcome.outcomeDate) has passed. The date was not extended."
            ))
        case .needsMeasurement:
            return (.noData, Action(
                title: "Add one measurement",
                detail: "One measurement starts the plan for \(outcome.outcomeDate)."
            ))
        case .conflictingMeasurements:
            return (.conflicting, Action(
                title: "Record one new measurement",
                detail: "Two values share a time. Record one measurement for \(outcome.outcomeDate)."
            ))
        case .invalidOutcome, .unavailableRates, .unsafeRate:
            return unsafe(outcome)
        }
    }

    private static func unsafe(_ outcome: DatedOutcome) -> (state: RouteState, action: Action) {
        (.unsafeDate, Action(
            title: "Revise the outcome",
            detail: "No safe plan is available for \(outcome.outcomeDate)."
        ))
    }

    private static func conflicts(_ readings: [Reading]) -> Bool {
        var seen: [Date: Double] = [:]
        for reading in readings {
            if let prior = seen[reading.date], prior != reading.value { return true }
            seen[reading.date] = reading.value
        }
        return false
    }

    private static func stale(_ readings: [Reading], now: Date, window: TimeInterval?) -> Bool {
        guard let latest = readings.map(\.date).max() else { return false }
        guard let window else { return true }
        return SignalFreshness(measuredAt: latest, now: now, window: window, isUsable: true) != .fresh
    }

    private static func maintenanceCovers(_ outcome: DatedOutcome, now: Date) -> Bool {
        let today = day(now)
        return outcome.constraints.maintenance.contains { $0.start <= today && today <= $0.end }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func label(_ outcome: DatedOutcome) -> String {
        "\(outcome.outcome.metric.rawValue) \(outcome.outcome.targetValue) by \(outcome.outcomeDate)"
    }

    private static func title(for surface: Surface) -> String {
        switch surface {
        case .timeline: return "Timeline"
        case .stats: return "Body score"
        case .coach: return "Jovi"
        }
    }
}

struct HealthMemoryClaim: Equatable {
    enum Provenance: String, Equatable {
        case measured, engineDerived, userDeclared, coachInferred
    }

    var userId: String
    var productId: String
    var text: String
    var provenance: Provenance
    var recordedAt: Date
}

struct HealthMemoryStore {
    private(set) var claims: [HealthMemoryClaim] = []

    enum Retrieval: Equatable {
        case records([HealthMemoryClaim])
        case safetyUnavailable
        case isolated
    }

    @discardableResult
    mutating func remember(_ claim: HealthMemoryClaim) -> Bool {
        let text = claim.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claim.userId.isEmpty, claim.productId == LaunchJourney.productId, !text.isEmpty else { return false }
        claims.append(HealthMemoryClaim(
            userId: claim.userId, productId: claim.productId, text: text,
            provenance: claim.provenance, recordedAt: claim.recordedAt
        ))
        return true
    }

    func retrieve(userId: String, productId: String, safetyAvailable: Bool) -> Retrieval {
        guard safetyAvailable else { return .safetyUnavailable }
        guard !userId.isEmpty, productId == LaunchJourney.productId else { return .isolated }
        return .records(claims.filter { $0.userId == userId && $0.productId == productId })
    }

    mutating func clearUser(_ userId: String) {
        claims.removeAll { $0.userId == userId }
    }
}
