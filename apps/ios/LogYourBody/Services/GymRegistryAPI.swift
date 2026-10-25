import Foundation

/// First-party transport adapter; the native client never talks to a database.
final class GymRegistryAPI: GymRegistryRemote {
    private let session: URLSession
    private let baseURL: URL
    private let rootPath = "/api/auth/mobile/gyms/v1"

    init(session: URLSession = .shared, baseURL: URL? = URL(string: Configuration.apiBaseURL)) {
        self.session = session
        self.baseURL = baseURL ?? URL(string: ProductRegistry.Hosts.api)!
    }

    func sync(changes: [GymRecord], accessToken: String) async throws -> [GymRecord] {
        let body = changes.isEmpty ? nil : try JSONEncoder().encode(Changes(changes: changes))
        let response: Snapshot = try await send(path: rootPath, body: body, accessToken: accessToken)
        guard response.version == 1 else { throw GymRegistryError.invalidResponse }
        return response.gyms
    }

    func exercises(equipment: Set<GymEquipment>?, accessToken: String) async throws -> [GymLibraryExercise] {
        var components = URLComponents()
        components.path = rootPath + "/exercises"
        if let equipment {
            components.queryItems = equipment.isEmpty ? [URLQueryItem(name: "equipment", value: "")] :
                equipment.map { URLQueryItem(name: "equipment", value: $0.rawValue) }
                    .sorted { ($0.value ?? "") < ($1.value ?? "") }
        }
        guard let path = components.string else { throw GymRegistryError.invalidResponse }
        let response: Library = try await send(path: path, body: nil, accessToken: accessToken)
        guard response.version == 1 else { throw GymRegistryError.invalidResponse }
        return response.exercises
    }

    private func send<Response: Decodable>(path: String, body: Data?, accessToken: String) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw GymRegistryError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GymRegistryError.invalidResponse }
        if response.statusCode == 401 { throw GymRegistryError.accountChanged }
        guard (200...299).contains(response.statusCode) else { throw GymRegistryError.unavailable }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct Changes: Encodable { let changes: [GymRecord] }
    private struct Snapshot: Decodable { let version: Int; let gyms: [GymRecord] }
    private struct Library: Decodable { let version: Int; let exercises: [GymLibraryExercise] }
}
