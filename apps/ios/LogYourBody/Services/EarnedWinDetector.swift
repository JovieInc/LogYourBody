//
// EarnedWinDetector.swift
// LogYourBody
//
import Foundation

/// Machine-readable kind of an earned win. Presentation copy is a separate decision.
enum EarnedWinKind: String, Equatable, Hashable {
    case goalRelativeGain
    case firstEver
    case timeSaved
}

/// One-time milestones. Each is returned at most once, then suppressed.
enum EarnedWinMilestone: String, Equatable, Hashable {
    case firstImport
    case firstPhoto
    case firstWorkout
}

/// Metric a user-selected target is about. Readings and the target share one unit.
enum EarnedWinMetric: String, Equatable, Hashable {
    case weight
    case bodyFat
    case ffmi
}

enum EarnedWinRowKind: String, Equatable, Hashable {
    case reading
    case importEvent
    case photo
    case workout
    case duration
}

enum EarnedWinDurationActivity: String, Equatable, Hashable {
    case workout
    case logging
}

/// One real history row. The detector never invents rows of its own.
struct EarnedWinRow: Equatable, Identifiable, Hashable {
    let id: String
    let kind: EarnedWinRowKind
    let occurredAt: Date
    let metric: EarnedWinMetric?
    let value: Double?
    let durationMinutes: Double?
    let activity: EarnedWinDurationActivity?

    init(
        id: String,
        kind: EarnedWinRowKind,
        occurredAt: Date,
        metric: EarnedWinMetric? = nil,
        value: Double? = nil,
        durationMinutes: Double? = nil,
        activity: EarnedWinDurationActivity? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.metric = metric
        self.value = value
        self.durationMinutes = durationMinutes
        self.activity = activity
    }
}

/// User-selected target. Direction is the direction that gets closer to `target`.
struct EarnedWinGoal: Equatable {
    let metric: EarnedWinMetric
    let target: Double
}

/// Identity of a win that has already been presented.
struct EarnedWinShownToken: Equatable, Hashable {
    let kind: EarnedWinKind
    let milestone: EarnedWinMilestone?
    let evidenceIDs: [String]
}

struct EarnedWinHistory: Equatable {
    let rows: [EarnedWinRow]
    let shown: Set<EarnedWinShownToken>

    init(rows: [EarnedWinRow], shown: Set<EarnedWinShownToken> = []) {
        self.rows = rows
        self.shown = shown
    }

    func markingShown(_ win: EarnedWin) -> EarnedWinHistory {
        EarnedWinHistory(rows: rows, shown: shown.union([win.shownToken]))
    }
}

struct EarnedWin: Equatable {
    let kind: EarnedWinKind
    let milestone: EarnedWinMilestone?
    let metric: EarnedWinMetric?
    let evidence: [EarnedWinRow]

    init(
        kind: EarnedWinKind,
        milestone: EarnedWinMilestone?,
        metric: EarnedWinMetric?,
        evidence: [EarnedWinRow]
    ) {
        precondition(!evidence.isEmpty, "An earned win requires the rows behind it.")
        self.kind = kind
        self.milestone = milestone
        self.metric = metric
        self.evidence = evidence
    }

    var shownToken: EarnedWinShownToken {
        EarnedWinShownToken(
            kind: kind,
            milestone: milestone,
            evidenceIDs: evidence.map(\.id).sorted()
        )
    }
}

/// Returns at most one earned win from real rows.
///
/// A goal-relative gain needs enough distinct days to draw a trend and a move
/// toward the user's target that clears the phase-insight noise band. A first
/// import, photo, or workout is returned once. Time saved is a measured drop in
/// duration, not a count of sessions. Streaks, totals, and empty history are not wins.
enum EarnedWinDetector {
    /// Distinct days with a measured reading. Same-day repeats count once,
    /// matching `HomeV2TrendPolicy.minimumDistinctDays`.
    static let minimumReadings = 7

    /// 0.25% of starting weight per week. Phase insight still calls that maintenance.
    static let weightNoiseFractionPerWeek = 0.0025

    /// Body-fat and FFMI points. Phase insight treats a smaller move as no change.
    static let bodyCompositionNoisePoints = 0.3

    /// Minutes a later block of sessions must beat before it counts as time saved.
    static let durationNoiseMinutes = 5.0

    static func detect(
        history: EarnedWinHistory,
        goal: EarnedWinGoal?,
        calendar: Calendar = .current
    ) -> EarnedWin? {
        if let milestone = firstEver(history: history) {
            return milestone
        }
        if let gain = goalRelativeGain(history: history, goal: goal, calendar: calendar) {
            return gain
        }
        return timeSaved(history: history)
    }

    static func weightNoiseFloor(start: Double, spanDays: Int) -> Double? {
        guard start > 0, spanDays > 0 else { return nil }
        let weeks = Double(spanDays) / 7
        return start * weightNoiseFractionPerWeek * weeks
    }

    // MARK: - First ever

    private static func firstEver(history: EarnedWinHistory) -> EarnedWin? {
        let pairs: [(EarnedWinMilestone, EarnedWinRowKind)] = [
            (.firstImport, .importEvent),
            (.firstPhoto, .photo),
            (.firstWorkout, .workout)
        ]
        var earliest: (milestone: EarnedWinMilestone, row: EarnedWinRow)?
        for (milestone, kind) in pairs where !isMilestoneShown(milestone, history: history) {
            guard let row = history.rows.filter({ $0.kind == kind }).min(by: chronological) else {
                continue
            }
            if let current = earliest {
                if chronological(row, current.row) {
                    earliest = (milestone, row)
                }
            } else {
                earliest = (milestone, row)
            }
        }
        guard let earliest else { return nil }
        return EarnedWin(
            kind: .firstEver,
            milestone: earliest.milestone,
            metric: nil,
            evidence: [earliest.row]
        )
    }

    private static func isMilestoneShown(
        _ milestone: EarnedWinMilestone,
        history: EarnedWinHistory
    ) -> Bool {
        history.shown.contains { $0.kind == .firstEver && $0.milestone == milestone }
    }

    // MARK: - Goal-relative gain

    private static func goalRelativeGain(
        history: EarnedWinHistory,
        goal: EarnedWinGoal?,
        calendar: Calendar
    ) -> EarnedWin? {
        guard let goal, goal.target.isFinite else { return nil }
        let readings = history.rows
            .filter { row in
                guard row.kind == .reading, row.metric == goal.metric, let value = row.value else {
                    return false
                }
                return value.isFinite
            }
            .sorted(by: chronological)
        guard distinctDayCount(readings, calendar: calendar) >= minimumReadings else { return nil }
        guard let earliest = readings.first, let latest = readings.last else { return nil }
        guard let start = earliest.value, let end = latest.value else { return nil }
        let progress = abs(start - goal.target) - abs(end - goal.target)
        guard progress > 0 else { return nil }
        let span = spanDays(from: earliest.occurredAt, to: latest.occurredAt, calendar: calendar)
        guard span > 0, progress >= noiseFloor(metric: goal.metric, start: start, spanDays: span) else {
            return nil
        }
        guard !isEvidenceShown(kind: .goalRelativeGain, evidence: readings, history: history) else {
            return nil
        }
        return EarnedWin(
            kind: .goalRelativeGain,
            milestone: nil,
            metric: goal.metric,
            evidence: readings
        )
    }

    private static func noiseFloor(metric: EarnedWinMetric, start: Double, spanDays: Int) -> Double {
        switch metric {
        case .weight:
            return weightNoiseFloor(start: start, spanDays: spanDays) ?? .infinity
        case .bodyFat, .ffmi:
            return bodyCompositionNoisePoints
        }
    }

    // MARK: - Time saved

    private static func timeSaved(history: EarnedWinHistory) -> EarnedWin? {
        let samples = durationSamples(history.rows)
        let grouped = Dictionary(grouping: samples, by: { $0.activity })
        var best: (activity: EarnedWinDurationActivity, rows: [EarnedWinRow], saved: Double)?
        for (activity, groupedSamples) in grouped {
            let rows = groupedSamples.map { $0.row }.sorted(by: chronological)
            guard rows.count >= minimumReadings, let saved = durationSaved(rows) else { continue }
            guard !isEvidenceShown(kind: .timeSaved, evidence: rows, history: history) else { continue }
            if let current = best {
                let betterSavings = saved > current.saved
                let sameSavingsEarlierActivity = saved == current.saved && activity.rawValue < current.activity.rawValue
                if betterSavings || sameSavingsEarlierActivity {
                    best = (activity, rows, saved)
                }
            } else {
                best = (activity, rows, saved)
            }
        }
        guard let best else { return nil }
        return EarnedWin(kind: .timeSaved, milestone: nil, metric: nil, evidence: best.rows)
    }

    private static func durationSamples(
        _ rows: [EarnedWinRow]
    ) -> [(activity: EarnedWinDurationActivity, row: EarnedWinRow)] {
        rows.compactMap { row in
            guard row.kind == .duration,
                  let minutes = row.durationMinutes,
                  minutes.isFinite,
                  minutes >= 0,
                  let activity = row.activity else {
                return nil
            }
            return (activity: activity, row: row)
        }
    }

    /// How many minutes the later half beat the earlier half, when that drop clears noise.
    private static func durationSaved(_ ordered: [EarnedWinRow]) -> Double? {
        let midpoint = ordered.count / 2
        guard midpoint > 0, midpoint < ordered.count else { return nil }
        let earlier = Array(ordered[..<midpoint])
        let later = Array(ordered[midpoint...])
        let saved = meanDuration(earlier) - meanDuration(later)
        guard saved >= durationNoiseMinutes else { return nil }
        return saved
    }

    private static func meanDuration(_ rows: [EarnedWinRow]) -> Double {
        let total = rows.reduce(0.0) { partial, row in
            partial + (row.durationMinutes ?? 0)
        }
        return total / Double(rows.count)
    }

    // MARK: - Shared

    private static func isEvidenceShown(
        kind: EarnedWinKind,
        evidence: [EarnedWinRow],
        history: EarnedWinHistory
    ) -> Bool {
        let ids = evidence.map(\.id).sorted()
        return history.shown.contains { $0.kind == kind && $0.evidenceIDs == ids }
    }

    private static func distinctDayCount(_ rows: [EarnedWinRow], calendar: Calendar) -> Int {
        Set(rows.map { calendar.startOfDay(for: $0.occurredAt) }).count
    }

    private static func spanDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    private static func chronological(_ lhs: EarnedWinRow, _ rhs: EarnedWinRow) -> Bool {
        if lhs.occurredAt == rhs.occurredAt {
            return lhs.id < rhs.id
        }
        return lhs.occurredAt < rhs.occurredAt
    }
}
