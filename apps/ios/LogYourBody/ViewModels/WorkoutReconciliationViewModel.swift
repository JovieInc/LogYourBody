import Combine
import Foundation

@MainActor
final class WorkoutReconciliationViewModel: ObservableObject {
    struct Prompt: Equatable, Identifiable {
        let id: UUID
        let ownerId: String
        let day: String
        let gymName: String

        var question: String {
            "Looks like you trained at \(gymName). Was that today's session?"
        }
    }

    @Published private(set) var prompt: Prompt?

    private let store: WorkoutReconciliationStoring
    private let context: @MainActor () -> WorkoutReconciliationPolicy.Context?
    private let checkGate: @MainActor (String) -> Bool
    private let now: () -> Date
    private let calendar: () -> Calendar

    /// Call refresh when attendance, logs, permission, account, gates or the local day change.
    /// The context provider must read live permission/account state, including when answering.
    init(
        store: WorkoutReconciliationStoring,
        context: @escaping @MainActor () -> WorkoutReconciliationPolicy.Context?,
        checkGate: @escaping @MainActor (String) -> Bool = { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) },
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.store = store
        self.context = context
        self.checkGate = checkGate
        self.now = now
        self.calendar = calendar
    }

    func refresh() throws {
        guard let context = eligibleContext() else {
            prompt = nil
            return
        }
        let day = WorkoutReconciliationPolicy.dayKey(for: now(), calendar: calendar())
        do {
            if let record = try store.load(ownerId: context.ownerId, day: day) {
                // Retain the visible question without publishing another presentation event.
                if let existing = prompt, existing.ownerId == context.ownerId, existing.day == day,
                   existing.gymName == context.gymName, existing.id == record.promptId, record.response == nil {
                    return
                }
                prompt = nil
                return
            }
            prompt = nil
            let offered = Prompt(id: UUID(), ownerId: context.ownerId, day: day, gymName: context.gymName)
            // Persist suppression before publication, including for ignored questions and app restarts.
            // This marker asserts neither attendance nor a response and stores no gym or timestamps.
            try store.save(WorkoutReconciliationDay(promptId: offered.id), ownerId: context.ownerId, day: day)
            prompt = offered
        } catch {
            prompt = nil
            throw error
        }
    }

    @discardableResult
    func confirm(userConfirmedStart: Date? = nil, userConfirmedEnd: Date? = nil) throws -> ReconciledWorkoutSession? {
        guard let offered = validPrompt() else { return nil }
        guard var record = try unansweredRecord(for: offered) else { return nil }
        try WorkoutReconciliationPolicy.validate(start: userConfirmedStart, end: userConfirmedEnd)
        let session = ReconciledWorkoutSession(
            id: offered.id, gymName: offered.gymName, confirmedAt: now(),
            userConfirmedStart: userConfirmedStart, userConfirmedEnd: userConfirmedEnd
        )
        record.response = .confirmed
        record.session = session
        try store.save(record, ownerId: offered.ownerId, day: offered.day)
        prompt = nil
        return session
    }

    func deny() throws {
        guard let offered = validPrompt(), var record = try unansweredRecord(for: offered) else { return }
        record.response = .denied
        try store.save(record, ownerId: offered.ownerId, day: offered.day)
        prompt = nil
    }

    func ignore() {
        // No response, session, timestamps or volume is written.
        prompt = nil
    }

    private func eligibleContext() -> WorkoutReconciliationPolicy.Context? {
        guard let current = context(),
              WorkoutReconciliationPolicy.isEligible(
                current, enabled: checkGate(WorkoutReconciliationPolicy.featureGate)
              ) else { return nil }
        return current
    }

    private func validPrompt() -> Prompt? {
        guard let offered = prompt, let current = eligibleContext(),
              offered.ownerId == current.ownerId, offered.gymName == current.gymName,
              offered.day == WorkoutReconciliationPolicy.dayKey(for: now(), calendar: calendar()) else {
            prompt = nil
            return nil
        }
        return offered
    }

    private func unansweredRecord(for offered: Prompt) throws -> WorkoutReconciliationDay? {
        guard let record = try store.load(ownerId: offered.ownerId, day: offered.day),
              record.promptId == offered.id, record.response == nil else {
            prompt = nil
            return nil
        }
        return record
    }
}
