import Combine
import Foundation

struct GymRegistryState: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var record: GymRecord
        var pendingChange: UUID?
    }
    var version = 1
    var entries: [Entry] = []
    var activeGymID: UUID?
}

@MainActor
protocol GymRegistryPersisting {
    func load(ownerID: String) throws -> GymRegistryState
    func save(_ state: GymRegistryState, ownerID: String) throws
}

protocol GymRegistryRemote {
    func sync(changes: [GymRecord], accessToken: String) async throws -> [GymRecord]
    func exercises(equipment: Set<GymEquipment>?, accessToken: String) async throws -> [GymLibraryExercise]
}

/// Local commits precede transport. Acknowledgements only clear the exact sent
/// mutation, so edits or manual switches made during an await remain authoritative.
@MainActor
final class GymRegistry: ObservableObject {
    @Published private var state: GymRegistryState
    @Published private(set) var isSyncing = false
    let ownerID: String
    private let persistence: GymRegistryPersisting
    private let remote: GymRegistryRemote

    init(ownerID: String, persistence: GymRegistryPersisting, remote: GymRegistryRemote) throws {
        guard !ownerID.isEmpty else { throw GymRegistryError.accountChanged }
        self.ownerID = ownerID
        self.persistence = persistence
        self.remote = remote
        state = try persistence.load(ownerID: ownerID)
        guard state.version == 1,
              Set(state.entries.map { $0.record.gym.id }).count == state.entries.count
        else { throw GymRegistryError.invalidResponse }
        for entry in state.entries { _ = try entry.record.gym.validated() }
    }

    var gyms: [Gym] {
        state.entries.filter { !$0.record.deleted }.map(\.record.gym)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var activeGym: Gym? { gyms.first { $0.id == state.activeGymID } }
    /// nil means no filter. An explicitly empty set allows no equipment.
    var equipmentFilter: Set<GymEquipment>? { activeGym?.equipment }
    var hasPendingChanges: Bool { state.entries.contains { $0.pendingChange != nil } }

    @discardableResult
    func create(name: String, coarseRegion: String?, equipment: Set<GymEquipment>, preferredMachines: [String]) throws -> Gym {
        let gym = try Gym(
            id: UUID(), name: name, coarseRegion: coarseRegion,
            equipment: equipment, preferredMachines: preferredMachines
        ).validated()
        var next = state
        next.entries.append(.init(record: GymRecord(gym: gym, deleted: false), pendingChange: UUID()))
        try commit(next)
        return gym
    }

    func update(_ gym: Gym) throws {
        guard let index = state.entries.firstIndex(where: { $0.record.gym.id == gym.id && !$0.record.deleted })
        else { throw GymRegistryError.invalidGym }
        var next = state
        next.entries[index] = .init(record: GymRecord(gym: try gym.validated(), deleted: false), pendingChange: UUID())
        try commit(next)
    }

    func delete(_ id: UUID) throws {
        guard let index = state.entries.firstIndex(where: { $0.record.gym.id == id && !$0.record.deleted })
        else { throw GymRegistryError.invalidGym }
        var next = state
        next.entries[index].record.deleted = true
        next.entries[index].pendingChange = UUID()
        if next.activeGymID == id { next.activeGymID = nil }
        try commit(next)
    }

    func select(_ id: UUID?) throws {
        guard id == nil || gyms.contains(where: { $0.id == id }) else { throw GymRegistryError.invalidGym }
        var next = state
        next.activeGymID = id
        try commit(next)
    }

    func sync(accessToken: String, isCurrent: () -> Bool) async throws {
        guard !isSyncing else { return }
        guard isCurrent() else { throw GymRegistryError.accountChanged }
        isSyncing = true
        defer { isSyncing = false }
        // Bound each batch; retain newer pending edits for the next sync.
        let pending = state.entries.filter { $0.pendingChange != nil }
        let batches = stride(from: 0, to: max(pending.count, 1), by: 100)
        for offset in batches {
            guard isCurrent() else { throw GymRegistryError.accountChanged }
            let sent = Array(pending.dropFirst(offset).prefix(100))
            let received = try await remote.sync(changes: sent.map(\.record), accessToken: accessToken)
            guard isCurrent(), !Task.isCancelled else { throw GymRegistryError.accountChanged }
            try merge(received, acknowledging: sent)
        }
    }

    func exercises(accessToken: String, isCurrent: () -> Bool) async throws -> [GymLibraryExercise] {
        guard isCurrent() else { throw GymRegistryError.accountChanged }
        let result = try await remote.exercises(equipment: equipmentFilter, accessToken: accessToken)
        guard isCurrent(), !Task.isCancelled else { throw GymRegistryError.accountChanged }
        return result
    }

    private func merge(_ records: [GymRecord], acknowledging sent: [GymRegistryState.Entry]) throws {
        let ids = Set(records.map { $0.gym.id })
        guard ids.count == records.count, sent.allSatisfy({ ids.contains($0.record.gym.id) })
        else { throw GymRegistryError.invalidResponse }
        for record in records { _ = try record.gym.validated() }
        var next = state
        for record in records {
            if let index = next.entries.firstIndex(where: { $0.record.gym.id == record.gym.id }) {
                let local = next.entries[index]
                let acknowledged = sent.contains { $0.record.gym.id == record.gym.id && $0.pendingChange == local.pendingChange }
                if local.pendingChange == nil || acknowledged {
                    next.entries[index] = .init(record: record)
                }
            } else {
                next.entries.append(.init(record: record))
            }
        }
        if let selected = next.activeGymID,
           !next.entries.contains(where: { $0.record.gym.id == selected && !$0.record.deleted }) {
            next.activeGymID = nil
        }
        try commit(next)
    }

    private func commit(_ next: GymRegistryState) throws {
        try persistence.save(next, ownerID: ownerID)
        state = next
    }
}
