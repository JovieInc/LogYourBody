import Foundation

/// History is useful without an admitted plan. Only the shared classifier/planner
/// may admit one; this projection supplies no rate, freshness, or target defaults.
actor DatedTimelineProjector {
    struct Snapshot {
        var outcome: DatedOutcome?
        var outcomeText: String?
        var presentation: LaunchJourney.Presentation
        var destination: Destination
        var entries: [String: Entry]
        var baselineTab: Int
        var containsOnlyOwnerRecords: Bool
        var stats: DatedOutcomeStats
        var planBaseline: DatedOutcome.PlanBaseline?
        var coach: DatedCoachReview
    }

    struct Entry {
        var weight: String
        var weightSource: String
        var bodyFat: String
        var bodyFatSource: String
        var provenance: String
        var ffmi: String
        var bodyFatIsEstimate: Bool
    }

    enum Destination: Equatable {
        case editor, measurement, retry, timeline, profile
    }

    func project(
        owner: String, metrics: [BodyMetrics], input original: LaunchJourney.Input, heightCm: Double? = nil,
        savedOutcome: DatedOutcomeSnapshot? = nil
    ) -> Snapshot {
        var input = original
        var metrics = metrics
        #if DEBUG
        DatedStatsUITestFixture.apply(owner: owner, input: &input, metrics: &metrics)
        #endif
        input.usesLatestConflictOnly = true
        var entries: [String: Entry] = [:]
        input.readings = []
        for metric in metrics where metric.userId == owner && !metric.isExcluded && metric.date <= input.now {
            let prepared = prepare(metric, heightCm: heightCm)
            entries[metric.id] = prepared.entry
            input.readings.append(contentsOf: prepared.readings)
        }

        if input.planBaseline == nil, input.outcome?.outcome.metric == .weightKg,
           let first = originalBaseline(input.readings) {
            input.planBaseline = .init(date: first.date, metric: first.metric, value: first.value)
        }
        let decision = decision(for: input)
        let baselineTab = input.outcome?.outcome.metric == .bodyFatPercentage ||
            (input.outcome?.outcome.metric == .ffmi && input.readings.contains { $0.metric == .weightKg }) ? 1 : 0
        let needsHeight = input.outcome?.outcome.metric == .ffmi && !(heightCm.map { $0.isFinite && $0 > 0 } ?? false) &&
            input.readings.contains { $0.metric == .weightKg } &&
            input.readings.contains { $0.metric == .bodyFatPercentage }
        var destination = Self.destination(for: decision.state, hasOutcome: input.outcome != nil)
        if decision.state == .offline && input.outcome != nil && !input.readings.contains(where: {
            $0.metric == input.outcome?.outcome.metric
        }) { destination = .measurement }
        if needsHeight && destination == .measurement { destination = .profile }
        var coach = DatedCoachReview.project(owner: owner, input: input, decision: decision, saved: savedOutcome)
        if decision.state != .ready {
            coach.destination = decision.state == .maintenance ? .editor : destination
        }
        return Snapshot(
            outcome: input.outcome,
            outcomeText: input.outcome.map(Self.outcomeText),
            presentation: .init(surface: .timeline, state: decision.state, title: "Timeline", action: decision.action),
            destination: destination,
            entries: entries,
            baselineTab: baselineTab,
            containsOnlyOwnerRecords: metrics.allSatisfy { $0.userId == owner },
            stats: DatedOutcomeStats.project(
                input: input, state: decision.state, action: decision.action, entries: entries, metrics: metrics),
            planBaseline: input.planBaseline,
            coach: coach
        )
    }

    private func originalBaseline(_ readings: [LaunchJourney.Reading]) -> LaunchJourney.Reading? {
        let groups = Dictionary(grouping: readings.filter { $0.metric == .weightKg }, by: \.date)
        return groups.values.compactMap { group in
            guard let first = group.first, group.allSatisfy({ $0.value == first.value }) else { return nil }
            return first
        }.min(by: { $0.date < $1.date })
    }

    private func prepare(_ metric: BodyMetrics, heightCm: Double?) -> (entry: Entry, readings: [LaunchJourney.Reading]) {
        var readings: [LaunchJourney.Reading] = []
        let weight = recordedWeight(metric)
        let bodyFat = HomeV2EditorialPolicy.bodyFat(in: metric)
        let isEstimated = bodyFat?.caption.localizedCaseInsensitiveContains("estimate") == true
        if let weight {
            readings.append(.init(date: metric.date, metric: .weightKg, value: weight))
        }
        let comparableBodyFat = !isEstimated && bodyFat?.caption != "Source not recorded" &&
            metric.measurementSource(for: .bodyFat) != .photo
        if let bodyFat, comparableBodyFat {
            readings.append(.init(date: metric.date, metric: .bodyFatPercentage, value: bodyFat.percentage))
        }
        let provenance = metric.provenance
        let ffmi = weight.flatMap { weight -> Double? in
            guard let bodyFat, let heightCm, heightCm.isFinite, heightCm > 0 else { return nil }
            return UnitConversion.calculateFFMI(weightKg: weight, bodyFatPercentage: bodyFat.percentage, heightCm: heightCm)
        }
        if let ffmi, ffmi.isFinite, ffmi > 0, comparableBodyFat {
            readings.append(.init(date: metric.date, metric: .ffmi, value: ffmi))
        }
        let entry = Entry(
            weight: weight.map { String(format: "%.1f kg", $0) } ?? "—",
            weightSource: weight == nil ? "No recorded weight" : HomeV2Provenance.detailedLabel(for: metric, field: .weight),
            bodyFat: bodyFat.map { String(format: "%.1f%%", $0.percentage) } ?? "—",
            bodyFatSource: bodyFat?.caption ?? "No recorded body fat",
            provenance: "\(provenance.sourceName) · \(metric.localDate) · " +
                "Imported \(provenance.importedAt.formatted(date: .numeric, time: .shortened))",
            ffmi: ffmi.map { String(format: "%.1f", $0) } ?? "—",
            bodyFatIsEstimate: isEstimated
        )

        return (entry, readings)
    }

    private func decision(for input: LaunchJourney.Input) -> (state: LaunchJourney.RouteState, action: LaunchJourney.Action) {
        // Expiry is never hidden by a connection failure or missing measurement.
        if let outcome = input.outcome {
            if let deadline = DatedOutcome.calendarDate(outcome.outcomeDate), deadline <= input.now {
                var expired = input
                expired.safetyAvailable = true
                expired.offline = false
                expired.permissionDenied = false
                return LaunchJourney.decide(expired)
            }
            do { try outcome.validate() } catch {
                var invalid = input
                invalid.safetyAvailable = false
                return LaunchJourney.decide(invalid)
            }
            if LaunchJourney.maintenanceCovers(outcome, now: input.now) || !input.safetyAvailable {
                return checkedDecision(input)
            }
        } else {
            var initial = input
            initial.permissionDenied = false
            return LaunchJourney.decide(initial)
        }
        let decision = checkedDecision(input)
        if decision.state == .unsafeDate && input.readings.contains(where: { $0.metric == input.outcome?.outcome.metric }) {
            return decision
        }
        return LaunchJourney.measurementRecovery(input) ?? decision
    }

    private func checkedDecision(
        _ input: LaunchJourney.Input
    ) -> (state: LaunchJourney.RouteState, action: LaunchJourney.Action) {
        let decision = LaunchJourney.decide(input)
        guard decision.state == .ready || decision.state == .maintenance,
              let outcome = input.outcome, outcome.outcome.metric == .weightKg else { return decision }
        let rate = OutcomeFeasibility(now: input.now).weightRateCheck(outcome: outcome, history: input.readings.map {
            .init(date: $0.date, metric: $0.metric, value: $0.value)
        })
        switch rate {
        case .withinCeiling: return decision // Never bypasses the checks above.
        case .exceedsCeiling:
            return (.impossibleDate, .init(
                title: "Choose a later date or a closer outcome",
                detail: "This outcome needs constraint review. The target and date have not changed."))
        case .unavailable:
            return (.unsafeDate, .init(
                title: "Review your outcome",
                detail: "Planning checks are unavailable. The target and date have not changed."))
        }
    }

    static func destination(for state: LaunchJourney.RouteState, hasOutcome: Bool) -> Destination {
        switch state {
        case .denial, .noData: return hasOutcome ? .measurement : .editor
        case .offline: return hasOutcome ? .retry : .editor
        case .stale, .conflicting: return .measurement
        case .unsafeDate, .impossibleDate, .expiredDate: return .editor
        case .maintenance, .ready: return .timeline
        }
    }

    private func recordedWeight(_ metric: BodyMetrics) -> Double? {
        guard metric.measurementSource(for: .weight) != .photo,
              let value = metric.weight, value.isFinite, value > 0 else { return nil }
        switch metric.weightUnit?.lowercased() {
        case "kg": return value
        case "lb", "lbs": return UnitConversion.lbsToKg(value)
        default: return nil // Unknown units cannot establish a comparable baseline.
        }
    }

    private static func outcomeText(_ value: DatedOutcome) -> String {
        let unit: String
        switch value.outcome.metric {
        case .weightKg: unit = "kg"
        case .bodyFatPercentage: unit = "% body fat"
        case .ffmi: unit = "FFMI"
        }
        return "Your target: \(value.outcome.targetValue.formatted()) \(unit) · \(value.outcomeDate)"
    }
}

extension LaunchJourney {
    /// Optional connections never block recording history. These are recovery
    /// actions, not an admission decision or a claim that a plan exists.
    static func measurementRecovery(_ input: Input) -> (state: RouteState, action: Action)? {
        let readings = input.readings.filter {
            $0.date <= input.now && $0.value.isFinite && $0.value > 0 &&
                $0.metric == input.outcome?.outcome.metric
        }
        guard let outcome = input.outcome else { return input.offline ? decideOffline(input) : nil }
        if readings.isEmpty {
            if input.permissionDenied {
                return (.denial, Action(
                    title: "Enter one measurement",
                    detail: "Apple Health is unavailable. One measurement keeps the date."
                ))
            }
            return (input.offline ? .offline : .noData, Action(
                title: "Add one measurement", detail: "One measurement starts the plan for \(outcome.outcomeDate)."
            ))
        }
        if input.offline { return decideOffline(input) }
        if conflicts(readings, latestOnly: input.usesLatestConflictOnly) {
            return (.conflicting, Action(
                title: "Record one new measurement",
                detail: "Two values share a time. Record one measurement for \(outcome.outcomeDate)."
            ))
        }
        if stale(readings, now: input.now, window: input.freshnessWindow) {
            return (.stale, Action(
                title: "Record a fresh measurement",
                detail: "The latest measurement is too old to steer \(outcome.outcomeDate)."
            ))
        }
        return nil
    }

    private static func decideOffline(_ input: Input) -> (state: RouteState, action: Action) {
        var offline = input
        offline.safetyAvailable = true
        offline.permissionDenied = false
        return decide(offline)
    }
}
