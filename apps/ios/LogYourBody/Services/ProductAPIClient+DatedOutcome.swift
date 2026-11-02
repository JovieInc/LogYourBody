import Foundation

@MainActor
protocol DatedOutcomeRemote {
    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot
    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot?
}

extension ProductAPIClient: DatedOutcomeRemote {
    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot {
        struct Receipt: Decodable, Sendable { let snapshot: DatedOutcomeSnapshot }
        let body = try await Task.detached { try JSONEncoder().encode(edit) }.value
        let request = authorizedJSONRequest(
            url: try productAPIURL("/api/auth/mobile/dated-outcome"), method: "PUT", token: token,
            body: body
        )
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try await Task.detached { try JSONDecoder().decode(Receipt.self, from: data).snapshot }.value
    }

    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot? {
        struct Envelope: Decodable, Sendable { let snapshot: DatedOutcomeSnapshot? }
        let request = authorizedJSONRequest(
            url: try productAPIURL("/api/auth/mobile/dated-outcome"), method: "GET", token: token
        )
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try await Task.detached { try JSONDecoder().decode(Envelope.self, from: data).snapshot }.value
    }
}
