import CoreData
import Foundation
import Observation

/// One owner-scoped journal: the saved value and each recompute request commit together.
/// Logout removes access, not data. Account deletion uses CoreDataManager.deleteAllData.
@MainActor
@Observable
final class DatedOutcomeStore {
    enum SyncIssue: Equatable { case retry, conflict }
    static let featureGate = "dated_outcome_v1"
    nonisolated private let context: NSManagedObjectContext
    private let currentOwner: () -> String?
    private let enabled: () -> Bool
    private let didSave: (DatedOutcomeEdit) -> Void
    private var isSyncing = false
    private var syncIssues: [String: SyncIssue] = [:]

    var syncIssue: SyncIssue? { currentOwner().flatMap { syncIssues[$0] } }

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

    func saveForPresentation(
        _ value: DatedOutcome, expectedRevision: UUID? = nil, checkingRevision: Bool = false,
        isCurrent: () -> Bool
    ) async throws {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        let edit = try await context.perform {
            try value.validate()
            if checkingRevision, try self.rows(owner: owner).first.map(self.snapshot)?.revision != expectedRevision {
                throw DatedOutcomeError.conflict
            }
            return try self.saveValue(value, owner: owner)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
        if let edit { didSave(edit) }
    }

    func hasPendingForPresentation(isCurrent: () -> Bool) async throws -> Bool {
        try await pendingCountForPresentation(isCurrent: isCurrent) > 0
    }

    func pendingCountForPresentation(isCurrent: () -> Bool) async throws -> Int {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        let pending = try await context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedDatedOutcome")
            request.predicate = NSPredicate(format: "ownerId == %@ AND pending == YES", owner)
            return try self.context.count(for: request)
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
        return pending
    }

    /// Explicit reconciliation only. A pull or retry cannot discard a pending edit.
    func acceptRemoteForPresentation(
        _ remote: DatedOutcomeSnapshot, expectedRevision: UUID?, isCurrent: () -> Bool
    ) async throws {
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        try await context.perform {
            try remote.value.validate()
            let owned = try self.rows(owner: owner)
            guard try owned.first.map(self.snapshot)?.revision == expectedRevision else {
                throw DatedOutcomeError.conflict
            }
            for row in owned { self.context.delete(row) }
            try self.persist(
                .init(requestId: remote.revision, previousRevision: nil, value: remote.value),
                owner: owner, sequence: 1, pending: false
            )
        }
        guard isCurrent(), currentOwner() == owner else { throw DatedOutcomeError.unauthenticated }
        syncIssues[owner] = nil
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
        try context.performAndWait { try acknowledgeValue(edit, receipt: receipt, owner: owner) }
    }

    /// Pull never replaces an unsynced local edit and never creates a new recompute request.
    func applyRemote(_ remote: DatedOutcomeSnapshot) throws {
        let owner = try requireOwner()
        try context.performAndWait { try applyRemoteValue(remote, owner: owner) }
    }

    nonisolated private func acknowledgeValue(
        _ edit: DatedOutcomeEdit, receipt: DatedOutcomeSnapshot, owner: String
    ) throws {
        guard receipt.revision == edit.requestId, receipt.value == edit.value else {
            throw DatedOutcomeError.invalidReceipt
        }
        let owned = try rows(owner: owner)
        guard let row = owned.first(where: { $0.value(forKey: "revision") as? UUID == edit.requestId }),
              try decode(row) == edit else { throw DatedOutcomeError.invalidReceipt }
        row.setValue(false, forKey: "pending")
        for old in owned.dropFirst() where old.value(forKey: "pending") as? Bool == false {
            context.delete(old)
        }
        try commit()
    }

    nonisolated private func applyRemoteValue(_ remote: DatedOutcomeSnapshot, owner: String) throws {
        try remote.value.validate()
        let owned = try rows(owner: owner)
        guard !owned.contains(where: { $0.value(forKey: "pending") as? Bool == true }) else { return }
        if let latest = owned.first, try snapshot(latest) == remote { return }
        let sequence = (owned.first?.value(forKey: "sequence") as? Int64 ?? 0) + 1
        let edit = DatedOutcomeEdit(requestId: remote.revision, previousRevision: nil, value: remote.value)
        for row in owned { context.delete(row) }
        try persist(edit, owner: owner, sequence: sequence, pending: false)
    }

    func synchronize(
        remote: DatedOutcomeRemote, token: String, isCurrent: () -> Bool
    ) async throws {
        guard enabled(), !isSyncing else { return }
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        let owner = try requireOwner()
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await synchronizeJournal(remote: remote, token: token, isCurrent: isCurrent)
            guard currentOwner() == owner, isCurrent() else { throw DatedOutcomeError.unauthenticated }
            syncIssues[owner] = nil
        } catch {
            if currentOwner() == owner, isCurrent() {
                syncIssues[owner] = (error as? ProductAPIError) == .httpError(409) ? .conflict : .retry
            }
            throw error
        }
    }

    private func synchronizeJournal(remote: DatedOutcomeRemote, token: String, isCurrent: () -> Bool) async throws {
        let owner = try requireOwner()
        while let edit = try await context.perform({
            try self.rows(owner: owner).reversed().first { $0.value(forKey: "pending") as? Bool == true }
                .map(self.decode)
        }) {
            guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
            let receipt = try await remote.saveDatedOutcome(edit, token: token)
            guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
            try await context.perform { try self.acknowledgeValue(edit, receipt: receipt, owner: owner) }
        }
        let latest = try await remote.fetchDatedOutcome(token: token)
        guard isCurrent() else { throw DatedOutcomeError.unauthenticated }
        if let latest { try await context.perform { try self.applyRemoteValue(latest, owner: owner) } }
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
        try persist(edit, owner: owner, sequence: (prior?.value(forKey: "sequence") as? Int64 ?? 0) + 1, pending: true)
        return edit
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
        return DatedOutcomeSnapshot(revision: edit.requestId, value: edit.value)
    }

    nonisolated private func persist(_ edit: DatedOutcomeEdit, owner: String, sequence: Int64, pending: Bool) throws {
        let payload = try JSONEncoder().encode(edit)
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

/// The editor holds its opening revision. Background refreshes never replace the draft.
@MainActor
@Observable
final class DatedOutcomeEditorModel {
    let store: DatedOutcomeStore
    private let isCurrent: () -> Bool
    private(set) var snapshot: DatedOutcomeSnapshot?
    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var errorText: String?
    private(set) var accountValue: DatedOutcomeSnapshot?
    private(set) var hasPending = false
    private(set) var hasLocalConflict = false
    var isPresentationCurrent: Bool { isCurrent() }

    init(store: DatedOutcomeStore, isCurrent: @escaping () -> Bool) {
        self.store = store
        self.isCurrent = isCurrent
    }

    func load(refresh: Bool = false) async {
        guard isCurrent(), !isLoaded || refresh else { return }
        do {
            let saved = try await store.loadForPresentation(isCurrent: isCurrent)
            let pending = try await store.hasPendingForPresentation(isCurrent: isCurrent)
            guard isCurrent() else { return }
            snapshot = saved
            hasPending = pending
            isLoaded = true
            errorText = nil
        } catch {
            guard isCurrent() else { return }
            errorText = "The saved outcome could not be loaded. Retry to keep your existing outcome."
        }
    }

    func save(_ value: DatedOutcome) async -> Bool {
        guard isLoaded, !isSaving, isCurrent() else { return false }
        guard !hasLocalConflict, store.syncIssue != .conflict else {
            errorText = "Review the saved outcome to reconcile this edit. Your input is kept here."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.saveForPresentation(
                value, expectedRevision: snapshot?.revision, checkingRevision: true, isCurrent: isCurrent
            )
            guard isCurrent() else { return false }
            errorText = nil
            return true
        } catch {
            guard isCurrent() else { return false }
            if case DatedOutcomeError.conflict = error {
                hasLocalConflict = true
                errorText = "The saved outcome changed. Your input is kept here. Review the saved outcome before trying again."
            } else if case DatedOutcomeError.invalidValue = error {
                errorText = "Enter a valid target, date and constraints. Your input has not been changed."
            } else {
                errorText = "This edit could not be saved. Your input is kept here. Retry Save."
            }
            return false
        }
    }

    func reviewAccountValue(fetch: () async throws -> DatedOutcomeSnapshot?) async {
        guard isCurrent(), !isSaving else { return }
        do {
            let remote: DatedOutcomeSnapshot?
            if hasLocalConflict {
                remote = try await store.loadForPresentation(isCurrent: isCurrent)
            } else {
                remote = try await fetch()
            }
            guard isCurrent() else { return }
            accountValue = remote
            if remote == nil { errorText = "No account outcome is available to compare. Your input is kept here." }
        } catch {
            guard isCurrent() else { return }
            errorText = "The account outcome could not be loaded. Your input is kept here. Retry when connected."
        }
    }

    func useAccountValue() async -> Bool {
        guard let accountValue, isCurrent(), !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if hasLocalConflict {
                // Discard only this unsaved draft. Keep the newer durable value and
                // its original pending request, rather than falsely acknowledging it.
                let current = try await store.loadForPresentation(isCurrent: isCurrent)
                return current == accountValue && isCurrent()
            }
            try await store.acceptRemoteForPresentation(
                accountValue, expectedRevision: snapshot?.revision, isCurrent: isCurrent
            )
            return isCurrent()
        } catch {
            guard isCurrent() else { return false }
            errorText = "Reconciliation could not be saved. Your input is kept here."
            return false
        }
    }
}
