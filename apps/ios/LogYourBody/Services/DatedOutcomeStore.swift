import CoreData
import Foundation

/// One owner-scoped journal: the saved value and each recompute request commit together.
/// Logout removes access, not data. Account deletion uses CoreDataManager.deleteAllData.
@MainActor
final class DatedOutcomeStore {
    static let featureGate = "dated_outcome_v1"
    nonisolated private let context: NSManagedObjectContext
    private let currentOwner: () -> String?
    private let enabled: () -> Bool
    private let didSave: (DatedOutcomeEdit) -> Void
    private var isSyncing = false

    init(
        context: NSManagedObjectContext,
        currentOwner: @escaping () -> String?,
        enabled: @escaping () -> Bool,
        didSave: @escaping (DatedOutcomeEdit) -> Void = { _ in }
    ) {
        self.context = context
        self.currentOwner = currentOwner
        self.enabled = enabled
        self.didSave = didSave
    }

    func load() throws -> DatedOutcomeSnapshot? {
        let owner = try requireOwner()
        return try context.performAndWait {
            try rows(owner: owner).first.map(snapshot)
        }
    }

    /// UI callers suspend while the private context fetches and decodes the journal.
    func loadForPresentation(isCurrent: () -> Bool) async throws -> DatedOutcomeSnapshot? {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        let value = try await context.perform {
            try self.rows(owner: owner).first.map(self.snapshot)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
        return value
    }

    func saveForPresentation(_ value: DatedOutcome, isCurrent: () -> Bool) async throws {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        let edit = try await context.perform {
            try value.validate()
            return try self.saveValue(value, owner: owner)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
        if let edit { didSave(edit) }
    }

    /// Freeze the first comparable baseline in the existing owner-scoped journal.
    /// This metadata emits no sync edit and cannot replace an edited revision.
    func retainPlanBaselineForPresentation(
        _ baseline: DatedOutcome.PlanBaseline, revision: UUID, isCurrent: () -> Bool
    ) async throws {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        try await context.perform {
            try self.retainBaseline(baseline, revision: revision, owner: owner)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
    }

    /// Commit the reviewed action only against the outcome revision that produced it.
    /// No sync request, training mutation or date change is created by a review.
    func retainCoachActionForPresentation(_ action: DatedCoachAction, isCurrent: () -> Bool) async throws {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        guard action.userId == owner, action.productId == LaunchJourney.productId else {
            throw DatedOutcomeError.unauthenticated
        }
        try await context.perform {
            try self.retainCoachAction(action, owner: owner)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
    }

    /// A single Save action emits one durable recompute request even if several fields changed.
    /// A no-op Save emits none. A failed save publishes nothing and restores the context.
    @discardableResult
    func save(_ value: DatedOutcome) throws -> DatedOutcomeEdit? {
        // Local relaunch persistence does not wait for the cloud gate. synchronize() stays gated.
        let owner = try requireOwner()
        try value.validate()
        let edit: DatedOutcomeEdit? = try context.performAndWait {
            try saveValue(value, owner: owner)
        }
        if let edit { didSave(edit) }
        return edit
    }

    func pendingEdits() throws -> [DatedOutcomeEdit] {
        let owner = try requireOwner()
        return try context.performAndWait {
            try rows(owner: owner).reversed().filter { $0.value(forKey: "pending") as? Bool == true }.map(decode)
        }
    }

    func acknowledge(_ edit: DatedOutcomeEdit, receipt: DatedOutcomeSnapshot) throws {
        let owner = try requireOwner()
        guard receipt.revision == edit.requestId, receipt.value == edit.value else {
            throw DatedOutcomeError.invalidReceipt
        }
        try context.performAndWait {
            let owned = try rows(owner: owner)
            guard let row = owned.first(where: { $0.value(forKey: "revision") as? UUID == edit.requestId }),
                  try decode(row) == edit else { throw DatedOutcomeError.invalidReceipt }
            row.setValue(false, forKey: "pending")
            // Retain the current value and unsent edits; only acknowledged history can go.
            for old in owned.dropFirst() where old.value(forKey: "pending") as? Bool == false {
                context.delete(old)
            }
            try commit()
        }
    }

    /// Pull never replaces an unsynced local edit and never creates a new recompute request.
    func applyRemote(_ remote: DatedOutcomeSnapshot) throws {
        let owner = try requireOwner()
        try remote.value.validate()
        try context.performAndWait {
            let owned = try rows(owner: owner)
            guard !owned.contains(where: { $0.value(forKey: "pending") as? Bool == true }) else { return }
            if let latest = owned.first {
                let current = try snapshot(latest)
                if current.revision == remote.revision && current.value == remote.value { return }
            }
            let sequence = (owned.first?.value(forKey: "sequence") as? Int64 ?? 0) + 1
            let edit = DatedOutcomeEdit(requestId: remote.revision, previousRevision: nil, value: remote.value)
            let previous = try owned.first.map(snapshot)
            let baseline = previous?.value.outcome.metric == remote.value.outcome.metric ? previous?.planBaseline : nil
            for row in owned { context.delete(row) }
            try persist(edit, owner: owner, sequence: sequence, pending: false, baseline: baseline)
        }
    }

    func synchronize(
        remote: DatedOutcomeRemote, token: String, isCurrent: () -> Bool
    ) async throws {
        guard enabled(), !isSyncing else { return }
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        isSyncing = true
        defer { isSyncing = false }
        while let edit = try pendingEdits().first {
            guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
            let receipt = try await remote.saveDatedOutcome(edit, token: token)
            guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
            try acknowledge(edit, receipt: receipt)
        }
        let latest = try await remote.fetchDatedOutcome(token: token)
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        if let latest { try applyRemote(latest) }
    }

    private func requireOwner() throws -> String {
        guard let owner = currentOwner(), !owner.isEmpty else { throw DatedOutcomeError.unauthenticated }
        return owner
    }

    nonisolated private func saveValue(_ value: DatedOutcome, owner: String) throws -> DatedOutcomeEdit? {
        let prior = try rows(owner: owner).first
        let previous = try prior.map(snapshot)
        guard previous?.value != value else { return nil }
        let edit = DatedOutcomeEdit(requestId: UUID(), previousRevision: previous?.revision, value: value)
        let baseline = previous?.value.outcome.metric == value.outcome.metric ? previous?.planBaseline : nil
        try persist(edit, owner: owner, sequence: (prior?.value(forKey: "sequence") as? Int64 ?? 0) + 1,
                    pending: true, baseline: baseline)
        return edit
    }

    nonisolated private func retainBaseline(_ baseline: DatedOutcome.PlanBaseline, revision: UUID, owner: String) throws {
        guard let row = try rows(owner: owner).first else { return }
        let current = try snapshot(row)
        guard current.revision == revision, current.planBaseline == nil,
              current.value.outcome.metric == baseline.metric else { return }
        guard baseline.date.timeIntervalSinceReferenceDate.isFinite,
              baseline.value.isFinite, baseline.value > 0 else { throw DatedOutcomeError.invalidValue }
        let payload = try JSONEncoder().encode(LocalPayload(
            edit: decode(row), planBaseline: baseline, coachAction: current.coachAction))
        row.setValue(payload, forKey: "payload")
        try commit()
    }

    nonisolated private func retainCoachAction(_ action: DatedCoachAction, owner: String) throws {
        guard let row = try rows(owner: owner).first else { throw DatedOutcomeError.invalidReceipt }
        let current = try snapshot(row)
        guard current.revision == action.outcomeRevision, current.value == action.outcome,
              current.planBaseline == action.baseline,
              current.coachAction.map({ $0.id == action.id || $0.reviewedAt < action.reviewedAt }) ?? true else {
            throw DatedOutcomeError.invalidReceipt
        }
        let payload = try JSONEncoder().encode(LocalPayload(
            edit: decode(row), planBaseline: current.planBaseline, coachAction: action))
        row.setValue(payload, forKey: "payload")
        try commit()
    }

    nonisolated private func rows(owner: String) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedDatedOutcome")
        request.predicate = NSPredicate(format: "ownerId == %@", owner)
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
        return try context.fetch(request)
    }

    nonisolated private func decode(_ row: NSManagedObject) throws -> DatedOutcomeEdit {
        guard let data = row.value(forKey: "payload") as? Data else { throw DatedOutcomeError.invalidValue }
        return try JSONDecoder().decode(DatedOutcomeEdit.self, from: data)
    }

    nonisolated private func snapshot(_ row: NSManagedObject) throws -> DatedOutcomeSnapshot {
        let edit = try decode(row)
        let data = row.value(forKey: "payload") as? Data ?? Data()
        let metadata = try JSONDecoder().decode(BaselineField.self, from: data)
        return DatedOutcomeSnapshot(revision: edit.requestId, value: edit.value,
                                    planBaseline: metadata.planBaseline, coachAction: metadata.coachAction)
    }

    private struct BaselineField: Decodable {
        var planBaseline: DatedOutcome.PlanBaseline?
        var coachAction: DatedCoachAction?
    }

    private struct LocalPayload: Encodable {
        var edit: DatedOutcomeEdit
        var planBaseline: DatedOutcome.PlanBaseline?
        var coachAction: DatedCoachAction?
        enum CodingKeys: String, CodingKey { case planBaseline, coachAction }
        func encode(to encoder: Encoder) throws {
            try edit.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(planBaseline, forKey: .planBaseline)
            try container.encodeIfPresent(coachAction, forKey: .coachAction)
        }
    }

    nonisolated private func persist(
        _ edit: DatedOutcomeEdit, owner: String, sequence: Int64, pending: Bool,
        baseline: DatedOutcome.PlanBaseline? = nil
    ) throws {
        let payload = try JSONEncoder().encode(LocalPayload(edit: edit, planBaseline: baseline))
        let row = NSEntityDescription.insertNewObject(forEntityName: "CachedDatedOutcome", into: context)
        row.setValue(owner, forKey: "ownerId")
        row.setValue(edit.requestId, forKey: "revision")
        row.setValue(sequence, forKey: "sequence")
        row.setValue(payload, forKey: "payload")
        row.setValue(pending, forKey: "pending")
        try commit()
    }

    nonisolated private func commit() throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
