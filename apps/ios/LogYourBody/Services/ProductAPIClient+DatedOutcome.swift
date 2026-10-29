import Foundation

@MainActor
protocol DatedOutcomeRemote {
    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot
    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot?
}

extension ProductAPIClient: DatedOutcomeRemote {
    func saveDatedOutcome(_ edit: DatedOutcomeEdit, token: String) async throws -> DatedOutcomeSnapshot {
        struct Receipt: Decodable { let snapshot: DatedOutcomeSnapshot }
        let request = authorizedJSONRequest(
            url: try productAPIURL("/api/auth/mobile/dated-outcome"), method: "PUT", token: token,
            body: try JSONEncoder().encode(edit)
        )
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try JSONDecoder().decode(Receipt.self, from: data).snapshot
    }

    func fetchDatedOutcome(token: String) async throws -> DatedOutcomeSnapshot? {
        struct Envelope: Decodable { let snapshot: DatedOutcomeSnapshot? }
        let request = authorizedJSONRequest(
            url: try productAPIURL("/api/auth/mobile/dated-outcome"), method: "GET", token: token
        )
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try JSONDecoder().decode(Envelope.self, from: data).snapshot
    }
}
