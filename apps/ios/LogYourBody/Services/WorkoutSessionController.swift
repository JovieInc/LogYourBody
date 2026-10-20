import Foundation

/// A single executable action in a live workout: one set of one exercise.
struct WorkoutNowAction: Equatable {
    let exercise: TrainingExercisePrescription
    let setNumber: Int

    var totalSets: Int { max(1, exercise.sets) }
    var setKey: String { "\(exercise.id)-\(setNumber)" }
}

/// Result of reporting that the equipment for an exercise is occupied right now.
enum WorkoutOccupiedOutcome: Equatable {
    /// The blocked exercise moved behind the remaining work; the intended session is preserved.
    case reordered
    /// Nothing later remains to swap with. The caller must supply an eligible substitute.
    case requiresSubstitution
    /// The exercise has no remaining work in this session; there is nothing to resolve.
    case notActionable
}

/// Decisions a situational report can route to. Pain never mutates the session; it enters
/// the existing safety/check-in path.
enum WorkoutInterruptionRoute: Equatable {
    case safetyReview
}

/// Eligibility for substituting one prescription for another inside a live session.
/// A substitute must preserve the target stimulus and must never invent a working load:
/// only the candidate's own prescribed target load is carried over.
enum WorkoutSubstitutionPolicy {
    static func isEligible(
        candidate: TrainingExercisePrescription,
        replacing exerciseId: String,
        session: TrainingSession
    ) -> Bool {
        guard candidate.id != exerciseId, candidate.sets >= 1 else { return false }
        guard let replaced = session.exercises.first(where: { $0.id == exerciseId }) else { return false }
        guard candidate.primaryMuscle == replaced.primaryMuscle else { return false }
        let sessionIds = Set(session.exercises.map(\.id))
        guard !sessionIds.contains(candidate.id) else { return false }
        return true
    }
}

/// Deterministic Now / Up-next ordering for a live workout session.
///
/// The controller derives the current and next actions from the canonical durable
/// logged-set keys so touch, voice, relaunch and interruption replay all resume at the
/// same place. Situational changes (skips, reorders, trims, substitutions) live only in
/// memory for this session id: they expire on relaunch or on the next session and never
/// mutate durable preference or history.
struct WorkoutSessionController: Equatable {
    /// Rough per-set estimate (work + rest) used only to bound a shortened session.
    static let minutesPerSetEstimate = 4

    let sessionId: String
    private var prescriptions: [String: TrainingExercisePrescription]
    private var substitutions: [String: TrainingExercisePrescription]
    private(set) var order: [String]
    private(set) var skippedToday: Set<String>
    private(set) var exerciseLimit: Int?
    private(set) var loggedKeys: Set<String>

    init(session: TrainingSession, loggedSetKeys: Set<String>) {
        sessionId = session.id
        prescriptions = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.id, $0) })
        substitutions = [:]
        order = session.exercises.map(\.id)
        skippedToday = []
        exerciseLimit = nil
        loggedKeys = loggedSetKeys
    }

    /// Re-derive actions after a durable set save, sync replay or relaunch.
    mutating func refresh(loggedSetKeys: Set<String>) {
        loggedKeys = loggedSetKeys
    }

    /// The effective prescription at a queue position, after any substitution.
    func exercise(for exerciseId: String) -> TrainingExercisePrescription? {
        if let replacement = substitutions[exerciseId] { return replacement }
        return prescriptions[exerciseId]
    }

    func isSkipped(_ exerciseId: String) -> Bool {
        skippedToday.contains(exerciseId)
    }

    func remainingSetNumbers(for exerciseId: String) -> [Int] {
        guard let exercise = exercise(for: exerciseId) else { return [] }
        return (1...max(1, exercise.sets)).filter { !loggedKeys.contains("\(exercise.id)-\($0)") }
    }

    /// Ordered queue positions that still have work: not skipped, inside the shortened
    /// bound, and with at least one unlogged set.
    var actionableIds: [String] {
        let active = order.filter { !skippedToday.contains($0) }
        let bounded = exerciseLimit.map { Array(active.prefix($0)) } ?? active
        return bounded.filter { !remainingSetNumbers(for: $0).isEmpty }
    }

    /// The dominant current action: the first unlogged set of the first actionable exercise.
    var now: WorkoutNowAction? {
        guard let exerciseId = actionableIds.first,
              let exercise = exercise(for: exerciseId),
              let setNumber = remainingSetNumbers(for: exerciseId).first else { return nil }
        return WorkoutNowAction(exercise: exercise, setNumber: setNumber)
    }

    /// The next action after `now`: the following set of the same exercise, or the first
    /// set of the next actionable exercise.
    var upNext: WorkoutNowAction? {
        guard let current = now else { return nil }
        let remaining = remainingSetNumbers(for: positionId(of: current.exercise))
        if let next = remaining.first(where: { $0 > current.setNumber }) {
            return WorkoutNowAction(exercise: current.exercise, setNumber: next)
        }
        let ids = actionableIds
        guard let index = ids.firstIndex(of: positionId(of: current.exercise)),
              let nextId = ids.dropFirst(index + 1).first,
              let exercise = exercise(for: nextId),
              let setNumber = remainingSetNumbers(for: nextId).first else { return nil }
        return WorkoutNowAction(exercise: exercise, setNumber: setNumber)
    }

    /// Remaining queue entries behind `now`, for the secondary plan list.
    var upcomingExercises: [TrainingExercisePrescription] {
        let ids = actionableIds
        guard let current = now, let index = ids.firstIndex(of: positionId(of: current.exercise)) else { return [] }
        return ids.dropFirst(index + 1).compactMap { exercise(for: $0) }
    }

    var isComplete: Bool {
        now == nil
    }

    /// "The bench is taken": prefer reordering behind the remaining work, since that keeps
    /// every prescribed set executable today. Only when nothing later remains does the
    /// report require a substitution.
    @discardableResult
    mutating func markOccupied(exerciseId: String) -> WorkoutOccupiedOutcome {
        guard actionableIds.contains(exerciseId) else { return .notActionable }
        let ids = actionableIds
        guard ids.count > 1, ids.last != exerciseId else { return .requiresSubstitution }
        order.removeAll { $0 == exerciseId }
        order.append(exerciseId)
        return .reordered
    }

    /// Swap a blocked exercise for an eligible equivalent. Returns false when the
    /// candidate fails eligibility so an invalid substitution can never enter the queue.
    @discardableResult
    mutating func substitute(
        exerciseId: String,
        with candidate: TrainingExercisePrescription,
        session: TrainingSession
    ) -> Bool {
        guard WorkoutSubstitutionPolicy.isEligible(candidate: candidate, replacing: exerciseId, session: session) else {
            return false
        }
        substitutions[exerciseId] = candidate
        return true
    }

    /// "Skip this today": a situational choice scoped to this session only.
    mutating func skipForToday(exerciseId: String) {
        skippedToday.insert(exerciseId)
    }

    mutating func undoSkip(exerciseId: String) {
        skippedToday.remove(exerciseId)
    }

    /// "I only have N minutes": keep the earliest (highest-priority) exercises whose
    /// remaining sets fit the estimate, always keeping at least one. Returns the
    /// number of exercises kept.
    @discardableResult
    mutating func shortenSession(remainingMinutes: Int) -> Int {
        let budget = max(1, remainingMinutes / Self.minutesPerSetEstimate)
        let active = order.filter { !skippedToday.contains($0) }
        var kept = 0
        var sets = 0
        for exerciseId in active {
            let remaining = remainingSetNumbers(for: exerciseId).count
            guard remaining > 0 else { continue }
            if kept >= 1, sets + remaining > budget { break }
            kept += 1
            sets += remaining
        }
        exerciseLimit = kept
        return kept
    }

    mutating func restoreFullSession() {
        exerciseLimit = nil
    }

    /// Pain reports route to the safety/check-in path and never mutate the queue.
    func routePainReport(exerciseId _: String) -> WorkoutInterruptionRoute {
        .safetyReview
    }

    private func positionId(of exercise: TrainingExercisePrescription) -> String {
        for (positionId, replacement) in substitutions where replacement.id == exercise.id {
            return positionId
        }
        return exercise.id
    }
}
