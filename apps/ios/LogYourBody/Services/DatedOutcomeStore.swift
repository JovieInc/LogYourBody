import CoreData
import Foundation

/// One owner-scoped journal: the saved value and each recompute request commit together.
/// Logout removes access, not data. Account deletion uses CoreDataManager.deleteAllData.
@MainActor
final class DatedOutcomeStore {
    static let featureGate = "dated_outcome_v1"
    private let context: NSManagedObjectContext
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

    /// A single Save action emits one durable recompute request even if several fields changed.
    /// A no-op Save emits none. A failed save publishes nothing and restores the context.
    @discardableResult
    func save(_ value: DatedOutcome) throws -> DatedOutcomeEdit? {
        // Local relaunch persistence does not wait for the cloud gate. synchronize() stays gated.
        let owner = try requireOwner()
        try value.validate()
        let edit: DatedOutcomeEdit? = try context.performAndWait {
            let prior = try rows(owner: owner).first
            let previous = try prior.map(snapshot)
            guard previous?.value != value else { return nil }
            let edit = DatedOutcomeEdit(requestId: UUID(), previousRevision: previous?.revision, value: value)
            try persist(edit, owner: owner, sequence: (prior?.value(forKey: "sequence") as? Int64 ?? 0) + 1, pending: true)
            return edit
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
            if let latest = owned.first, try snapshot(latest) == remote { return }
            let sequence = (owned.first?.value(forKey: "sequence") as? Int64 ?? 0) + 1
            let edit = DatedOutcomeEdit(requestId: remote.revision, previousRevision: nil, value: remote.value)
            for row in owned { context.delete(row) }
            try persist(edit, owner: owner, sequence: sequence, pending: false)
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

    private func rows(owner: String) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedDatedOutcome")
        request.predicate = NSPredicate(format: "ownerId == %@", owner)
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
        return try context.fetch(request)
    }

    private func decode(_ row: NSManagedObject) throws -> DatedOutcomeEdit {
        guard let data = row.value(forKey: "payload") as? Data else { throw DatedOutcomeError.invalidValue }
        return try JSONDecoder().decode(DatedOutcomeEdit.self, from: data)
    }

    private func snapshot(_ row: NSManagedObject) throws -> DatedOutcomeSnapshot {
        let edit = try decode(row)
        return DatedOutcomeSnapshot(revision: edit.requestId, value: edit.value)
    }

    private func persist(_ edit: DatedOutcomeEdit, owner: String, sequence: Int64, pending: Bool) throws {
        let payload = try JSONEncoder().encode(edit)
        let row = NSEntityDescription.insertNewObject(forEntityName: "CachedDatedOutcome", into: context)
        row.setValue(owner, forKey: "ownerId")
        row.setValue(edit.requestId, forKey: "revision")
        row.setValue(sequence, forKey: "sequence")
        row.setValue(payload, forKey: "payload")
        row.setValue(pending, forKey: "pending")
        try commit()
    }

    private func commit() throws {
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
