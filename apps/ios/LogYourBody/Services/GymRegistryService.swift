import Combine
import Foundation

@MainActor
protocol GymRegistrySyncing {
    func list(token: String) async throws -> [Gym]
    func save(_ gym: Gym, token: String) async throws
    func remove(_ id: UUID, token: String) async throws
}

@MainActor
final class GymRegistryService: ObservableObject {
    static let featureGate = "gym_registry_v1"

    @Published private(set) var snapshot = GymRegistrySnapshot()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSyncing = false
    private let ownerId: String
    private let store: GymRegistryStoring
    private let isCurrent: () -> Bool
    private var loaded = false

    init(ownerId: String, store: GymRegistryStoring, isCurrent: @escaping () -> Bool) {
        self.ownerId = ownerId
        self.store = store
        self.isCurrent = isCurrent
        do {
            snapshot = try store.load(ownerId: ownerId)
            loaded = true
        } catch { errorMessage = error.localizedDescription }
    }

    func save(_ gym: Gym) throws {
        let gym = try gym.validated()
        var next = snapshot
        guard !next.removed.contains(gym.id) else { throw GymRegistryError.invalidGym }
        next.gyms.removeAll { $0.id == gym.id }
        next.gyms.append(gym)
        next.pending.insert(gym.id)
        try persist(next)
    }

    func remove(_ id: UUID) throws {
        guard snapshot.gyms.contains(where: { $0.id == id }) else { throw GymRegistryError.invalidGym }
        var next = snapshot
        next.gyms.removeAll { $0.id == id }
        next.pending.remove(id)
        next.removed.insert(id)
        if next.activeGymId == id { next.activeGymId = nil }
        try persist(next)
    }

    func select(_ id: UUID?) throws {
        guard id == nil || snapshot.gyms.contains(where: { $0.id == id }) else { throw GymRegistryError.invalidGym }
        var next = snapshot
        next.activeGymId = id
        try persist(next)
    }

    private func persist(_ next: GymRegistrySnapshot) throws {
        guard isCurrent() else { throw GymRegistryError.accountChanged }
        guard loaded else { throw GymRegistryError.unavailable }
        try store.save(next, ownerId: ownerId)
        snapshot = next
        errorMessage = nil
    }

    /// Replay durable mutations first. Never clear a newer edit on a late acknowledgement.
    func synchronize(api: GymRegistrySyncing, getToken: () async -> String?) async {
        guard !isSyncing, loaded, isCurrent() else { return }
        isSyncing = true
        defer { isSyncing = false }
        let captured = snapshot
        do {
            guard let token = await getToken(), isCurrent(), !Task.isCancelled else {
                throw GymRegistryError.accountChanged
            }
            for gym in captured.gyms where captured.pending.contains(gym.id) {
                try requireCurrent()
                try await api.save(gym, token: token)
            }
            for id in captured.removed {
                try requireCurrent()
                try await api.remove(id, token: token)
            }
            try requireCurrent()
            let remote = try await api.list(token: token)
            try requireCurrent()
            guard Set(remote.map(\.id)).count == remote.count,
                  remote.allSatisfy({ (try? $0.validated()) == $0 })
            else { throw GymRegistryError.unavailable }
            // A concurrent local edit keeps its journal intact for the next retry.
            guard snapshot == captured else { return }
            var next = GymRegistrySnapshot(gyms: remote, activeGymId: captured.activeGymId)
            if next.activeGym == nil { next.activeGymId = nil }
            try persist(next)
        } catch {
            guard isCurrent() else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func requireCurrent() throws {
        guard isCurrent(), !Task.isCancelled else { throw GymRegistryError.accountChanged }
    }

    func withCurrentToken(getToken: () async -> String?, send: (String) async throws -> Void) async throws {
        try requireCurrent()
        guard let token = await getToken() else { throw GymRegistryError.accountChanged }
        try requireCurrent()
        try await send(token)
        try requireCurrent()
    }
}

@MainActor
struct FirstPartyGymRegistryAdapter: GymRegistrySyncing {
    let client: ProductAPIClient
    private let path = "/api/auth/mobile/sync/v1/gyms"

    func exerciseNames(equipment: Set<GymEquipment>?, token: String) async throws -> [String] {
        struct Exercise: Decodable { let name: String }
        struct Response: Decodable { let exercises: [Exercise] }
        let query = equipment.map { "equipment=" + $0.map(\.rawValue).sorted().joined(separator: ",") }
        let request = client.authorizedJSONRequest(
            url: try client.productAPIURL("/api/auth/mobile/training/v1/exercises", query: query),
            method: "GET", token: token
        )
        let (data, response) = try await client.session.data(for: request)
        _ = try client.requireHTTPSuccess(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data).exercises.map(\.name)
    }

    func list(token: String) async throws -> [Gym] {
        struct Response: Decodable { let gyms: [Gym] }
        return try JSONDecoder().decode(Response.self, from: await send(method: "GET", token: token)).gyms
    }

    func save(_ gym: Gym, token: String) async throws {
        struct Response: Decodable { let gym: Gym }
        let data = try await send(method: "POST", token: token, body: JSONEncoder().encode(gym))
        guard try JSONDecoder().decode(Response.self, from: data).gym == gym else {
            throw GymRegistryError.unavailable
        }
    }

    func remove(_ id: UUID, token: String) async throws {
        struct Response: Decodable { let deleted: UUID }
        let data = try await send(method: "DELETE", token: token, body: JSONEncoder().encode(["id": id]))
        guard try JSONDecoder().decode(Response.self, from: data).deleted == id else { throw GymRegistryError.unavailable }
    }

    private func send(method: String, token: String, body: Data? = nil) async throws -> Data {
        let request = client.authorizedJSONRequest(
            url: try client.productAPIURL(path), method: method, token: token, body: body
        )
        let (data, response) = try await client.session.data(for: request)
        _ = try client.requireHTTPSuccess(response, data: data)
        return data
    }
}
