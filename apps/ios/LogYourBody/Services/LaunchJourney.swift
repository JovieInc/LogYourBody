import Foundation

/// Native copy table (LYB-286). Legacy strings: JovieInc/Jovie#21838
/// at 197a96ff21c53cb4ccd8f6c1e3d733058b8c1cf7.
enum LaunchPromiseCopy {
    // LYB-273 adopted decision, 2026-10-30. The older contract copy remains for gate-off users.
    static let datedOutcomePromise = "Pick a date. We build the plan backward from it and adjust every week."
    static let headline = "Your body-composition goal, planned around your next date."
    static let explanation =
        "Set an outcome and a date. LogYourBody follows your photos and measurements, spots drift, and gives you one next action."
    static let framing = "Dates guide the plan. They do not guarantee a result."

    @MainActor
    static var nativeHeadline: String { DatedOutcomeEntry.isEnabled() ? datedOutcomePromise : headline }
}

enum DatedOutcomeEntry {
    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        checkGate: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains("-lybUITestDatedOutcomeEntryFixture") { return true }
        #endif
        return (checkGate ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) })(DatedOutcomeStore.featureGate)
    }
}

/// Dated launch decision for timeline, body score, and Jovi. Optional GLP-1 and
/// DEXA inputs never change the plan or add medication commentary. Missing
/// safety policy fails closed. A date is never extended.
enum LaunchJourney {
    static let gateKey = "deadline_launch_journey"
    static let fixtureArgument = "-lybUITestLaunchJourneyFixture"

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument) { return true }
        #endif
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }

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
        var planBaseline: DatedOutcome.PlanBaseline?
        var usesLatestConflictOnly = false
        var glp1Disclosed = false
        var dexaPresent = false
        /// Gate-on admission also requires positively established eligibility.
        var enforcesDatedOutcomeDecision = false
        var isEligible: Bool?
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
            return (.noData, Action(title: "Set an outcome and a date", detail: LaunchPromiseCopy.explanation))
        }
        let metricReadings = usable.filter { $0.metric == outcome.outcome.metric }
        let feasibility = classify(outcome, input: input, readings: metricReadings)
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
                detail: input.enforcesDatedOutcomeDecision
                    ? "No plan is available for this date and target. \(outcome.outcomeDate) was not moved."
                    : "This date cannot be reached safely. \(outcome.outcomeDate) was not moved."
            ))
        case .noData, .ok:
            if conflicts(metricReadings, latestOnly: input.usesLatestConflictOnly) {
                return (.conflicting, Action(
                    title: "Record one new measurement",
                    detail: "Two values share a time. Record one measurement for \(outcome.outcomeDate)."
                ))
            }
            if feasibility == .noData {
                return (.noData, Action(
                    title: "Add one measurement",
                    detail: input.enforcesDatedOutcomeDecision
                    ? "One measurement starts tracking for \(outcome.outcomeDate)."
                    : "One measurement starts the plan for \(outcome.outcomeDate)."
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

    /// Integration of LYB-273's rejection ceiling, never a replacement for the
    /// classifier's complete reviewed policy. Callers prepare readings off-main.
    static func classify(_ outcome: DatedOutcome, input: Input, readings: [Reading]) -> OutcomeFeasibility.Classification {
        let result = OutcomeFeasibility(now: input.now, thresholds: input.thresholds)
            .classify(outcome: outcome, history: readings.map {
                .init(date: $0.date, metric: $0.metric, value: $0.value)
            })
        guard input.enforcesDatedOutcomeDecision, result != .expired else { return result }
        guard input.isEligible == true, input.safetyAvailable else { return .unsafe }
        guard result == .ok, outcome.outcome.metric == .weightKg else { return result }
        guard let latest = readings.filter({
            $0.metric == .weightKg && $0.date <= input.now && $0.value.isFinite && $0.value > 0
        }).max(by: { $0.date < $1.date }),
              let deadline = DatedOutcome.calendarDate(outcome.outcomeDate) else { return .unsafe }
        let weeks = deadline.timeIntervalSince(input.now) / 604_800
        let percentPerWeek = 100 * abs(outcome.outcome.targetValue - latest.value) / (latest.value * weeks)
        guard percentPerWeek.isFinite else { return .unsafe }
        return percentPerWeek > 1 ? .impossible : .ok
    }

    private static func weightPlan(
        _ outcome: DatedOutcome, readings: [Reading], input: Input
    ) -> (state: RouteState, action: Action) {
        guard let plan = weightPlanResult(outcome, readings: readings, input: input) else { return unsafe(outcome) }
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
                detail: input.enforcesDatedOutcomeDecision
                    ? "One measurement starts tracking for \(outcome.outcomeDate)."
                    : "One measurement starts the plan for \(outcome.outcomeDate)."
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

    /// Shared original-baseline projection for the directive and goal-relative stats.
    /// A new check-in never becomes a replacement baseline.
    static func weightPlanResult(_ outcome: DatedOutcome, readings: [Reading], input: Input) -> BackwardPlanner.Plan? {
        let baseline = input.planBaseline.map { Reading(date: $0.date, metric: $0.metric, value: $0.value) }
        guard let start = baseline ?? readings.min(by: { $0.date < $1.date }),
              start.metric == outcome.outcome.metric, readings.contains(start),
              !readings.contains(where: { $0.date == start.date && $0.value != start.value }),
              let deadline = DatedOutcome.calendarDate(outcome.outcomeDate) else { return nil }
        return BackwardPlanner(safeWeeklyChangeKg: input.safeWeeklyChangeKg).plan(
            outcome: .init(
                startDate: start.date,
                startingWeightKg: start.value,
                targetWeightKg: outcome.outcome.targetValue,
                targetDate: deadline
            ),
            history: readings.map { .init(date: $0.date, weightKg: $0.value) },
            now: input.now
        )
    }

    private static func unsafe(_ outcome: DatedOutcome) -> (state: RouteState, action: Action) {
        (.unsafeDate, Action(
            title: "Revise the outcome",
            detail: "No safe plan is available for \(outcome.outcomeDate)."
        ))
    }

    static func conflicts(_ readings: [Reading], latestOnly: Bool = false) -> Bool {
        let latest = latestOnly ? readings.map(\.date).max() : nil
        var seen: [Date: Double] = [:]
        for reading in readings where latest == nil || reading.date == latest {
            if let prior = seen[reading.date], prior != reading.value { return true }
            seen[reading.date] = reading.value
        }
        return false
    }

    static func stale(_ readings: [Reading], now: Date, window: TimeInterval?) -> Bool {
        guard let latest = readings.map(\.date).max() else { return false }
        guard let window else { return true }
        return SignalFreshness(measuredAt: latest, now: now, window: window, isUsable: true) != .fresh
    }

    static func maintenanceCovers(_ outcome: DatedOutcome, now: Date) -> Bool {
        let today = day(now)
        return outcome.constraints.maintenance.contains { $0.start <= today && today <= $0.end }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
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

struct HealthMemoryClaim: Codable, Equatable, Sendable {
    enum Provenance: String, Codable, Equatable, Sendable {
        case measured, engineDerived, userDeclared, coachInferred
    }

    var userId: String
    var productId: String
    var text: String
    var provenance: Provenance
    var recordedAt: Date
}

struct HealthMemoryStore {
    /// Partition fields. A read matches every field, so dropping one allows a cross read.
    static let isolationKeyFields = ["userId", "productId"]
    /// Result code when the safety check cannot run. That result has no memory payload.
    static let failClosedCode = "safetyUnavailable"

    private(set) var claims: [HealthMemoryClaim] = []

    enum Retrieval: Equatable {
        case records([HealthMemoryClaim])
        case safetyUnavailable
        case isolated

        var code: String {
            switch self {
            case .records: return "records"
            case .safetyUnavailable: return HealthMemoryStore.failClosedCode
            case .isolated: return "isolated"
            }
        }
    }

    @discardableResult
    mutating func remember(_ claim: HealthMemoryClaim, safetyAvailable: Bool) -> Bool {
        guard safetyAvailable else { return false }
        let text = claim.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.complete(userId: claim.userId, productId: claim.productId), !text.isEmpty else { return false }
        claims.append(HealthMemoryClaim(
            userId: claim.userId, productId: claim.productId, text: text,
            provenance: claim.provenance, recordedAt: claim.recordedAt
        ))
        return true
    }

    func retrieve(userId: String, productId: String, safetyAvailable: Bool) -> Retrieval {
        guard safetyAvailable else { return .safetyUnavailable }
        guard Self.complete(userId: userId, productId: productId) else { return .isolated }
        return .records(claims.filter { Self.matches($0, userId: userId, productId: productId) })
    }

    mutating func clearUser(_ userId: String) {
        claims.removeAll { $0.userId == userId }
    }

    private static func fields(userId: String, productId: String) -> [String: String] {
        ["userId": userId, "productId": productId]
    }

    private static func complete(userId: String, productId: String) -> Bool {
        let values = fields(userId: userId, productId: productId)
        return isolationKeyFields.allSatisfy { !(values[$0] ?? "").isEmpty }
    }

    private static func matches(_ claim: HealthMemoryClaim, userId: String, productId: String) -> Bool {
        let stored = fields(userId: claim.userId, productId: claim.productId)
        let requested = fields(userId: userId, productId: productId)
        return isolationKeyFields.allSatisfy { field in
            guard let left = stored[field], let right = requested[field] else { return false }
            return left == right
        }
    }
}
