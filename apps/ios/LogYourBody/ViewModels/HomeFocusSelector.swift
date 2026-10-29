import Foundation

/// LYB-173's Home ranking policy. Producers own evidence, safety classification,
/// and workout/plan state (LYB-129); selection never changes a prescription.
/// UI integration and its rollout gate belong to the separate Home card slice.
enum HomeFocusSelector {
    enum Measurement: Hashable, Sendable {
        case weight
        case bodyFat
    }

    enum Level: Equatable, Sendable {
        case low
        case medium
        case high
    }

    struct AskValue: Equatable, Sendable {
        let expectedBenefit: Level
        /// Confidence that this ask will improve the decision, accounting for noise.
        let confidence: Level
        let userBurden: Level

        /// Conservative admission policy, not a physiological score: a clear
        /// benefit, at least medium confidence, and manageable burden are required.
        var isHighValue: Bool {
            expectedBenefit == .high && confidence != .low && userBurden != .high
        }
    }

    enum Kind: Equatable, Sendable {
        case staleMeasurementAsk(Measurement, AskValue)
        case missingPhotoAsk(AskValue)
        case todaysWorkout
        case planRevision(isSafetyRelevant: Bool)
        case earnedWin(isEarned: Bool)
    }

    struct Candidate: Equatable, Identifiable, Sendable {
        /// Stable identity of the existing action/receipt, also used to break ties.
        let id: String
        let kind: Kind
    }

    struct Signal: Equatable, Sendable {
        /// Latest reliable observation time, regardless of manual/import source.
        /// A new import receipt for an old observation does not refresh the signal.
        let observedAt: Date?
        /// Supplied by the caller's signal policy; the inclusive boundary is current.
        let freshnessWindow: TimeInterval

        func needsUpdate(at now: Date) -> Bool {
            guard now.timeIntervalSinceReferenceDate.isFinite,
                  freshnessWindow.isFinite, freshnessWindow >= 0 else { return false }
            guard let observedAt else { return true }
            let age = now.timeIntervalSince(observedAt)
            // Invalid/future observations need source reconciliation, not another ask.
            return age.isFinite && age > freshnessWindow
        }
    }

    struct Context: Equatable, Sendable {
        let now: Date
        /// Omitted measurements have no reliable observation yet.
        let measurements: [Measurement: Signal]
        let photo: Signal
    }

    enum Primary: Equatable, Sendable {
        case candidate(Candidate)
        case nothingToDo
    }

    struct Selection: Equatable, Sendable {
        let primary: Primary
        /// Remaining eligible actions in rank order. Current/low-value asks and
        /// unearned celebrations are suppressed here as well as in the primary.
        let rest: [Candidate]
    }

    /// Always returns one primary. If every input is suppressed, prefer calm
    /// over reintroducing an unnecessary ask just because the input was nonempty.
    static func select(_ candidates: [Candidate], context: Context) -> Selection {
        let ranked = candidates.enumerated().compactMap { index, candidate -> RankedCandidate? in
            guard let priority = priority(for: candidate.kind, context: context) else { return nil }
            return RankedCandidate(candidate: candidate, priority: priority, inputIndex: index)
        }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.candidate.id != $1.candidate.id { return $0.candidate.id < $1.candidate.id }
            return $0.inputIndex < $1.inputIndex
        }
        guard let first = ranked.first else {
            return Selection(primary: .nothingToDo, rest: [])
        }
        return Selection(primary: .candidate(first.candidate), rest: ranked.dropFirst().map(\.candidate))
    }

    private struct RankedCandidate {
        let candidate: Candidate
        let priority: Int
        let inputIndex: Int
    }

    /// Safety > plan decision > today's workout > valuable missing signal > win.
    /// Low-value asks never compete with a genuine win or create busywork alone.
    private static func priority(for kind: Kind, context: Context) -> Int? {
        switch kind {
        case .planRevision(let isSafetyRelevant):
            return isSafetyRelevant ? 4 : 3
        case .todaysWorkout:
            return 2
        case .staleMeasurementAsk(let measurement, let value):
            guard value.isHighValue,
                  context.measurements[measurement]?.needsUpdate(at: context.now) ?? true else { return nil }
            return 1
        case .missingPhotoAsk(let value):
            return value.isHighValue && context.photo.needsUpdate(at: context.now) ? 1 : nil
        case .earnedWin(let isEarned):
            return isEarned ? 0 : nil
        }
    }
}
