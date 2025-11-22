import Foundation

enum BodySpecAPIError: Error {
    case notConnected
    case invalidResponse
    case httpError(Int)
}

struct BodySpecUser: Decodable {
    let userId: String
    let email: String
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct BodySpecService: Decodable {
    let name: String
    let description: String
    let serviceId: String?
    let serviceCode: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case serviceId = "service_id"
        case serviceCode = "service_code"
    }
}

struct BodySpecLocation: Decodable {
    let locationId: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case locationId = "location_id"
        case name
    }
}

struct BodySpecResultSummary: Decodable {
    let resultId: String
    let startTime: Date
    let location: BodySpecLocation
    let service: BodySpecService

    enum CodingKeys: String, CodingKey {
        case resultId = "result_id"
        case startTime = "start_time"
        case location
        case service
    }
}

struct BodySpecResultsListResponse: Decodable {
    let results: [BodySpecResultSummary]
}

struct BodySpecDexaScanInfoResponse: Decodable {
    let resultId: String
    let scannerModel: String
    let acquireTime: Date
    let analyzeTime: Date

    enum CodingKeys: String, CodingKey {
        case resultId = "result_id"
        case scannerModel = "scanner_model"
        case acquireTime = "acquire_time"
        case analyzeTime = "analyze_time"
    }
}

struct BodySpecBodyRegion: Decodable {
    let fatMassKg: Double
    let leanMassKg: Double
    let boneMassKg: Double
    let totalMassKg: Double
    let tissueFatPct: Double
    let regionFatPct: Double

    enum CodingKeys: String, CodingKey {
        case fatMassKg = "fat_mass_kg"
        case leanMassKg = "lean_mass_kg"
        case boneMassKg = "bone_mass_kg"
        case totalMassKg = "total_mass_kg"
        case tissueFatPct = "tissue_fat_pct"
        case regionFatPct = "region_fat_pct"
    }
}

struct BodySpecDexaCompositionResponse: Decodable {
    let resultId: String
    let total: BodySpecBodyRegion

    enum CodingKeys: String, CodingKey {
        case resultId = "result_id"
        case total
    }
}

final class BodySpecAPI {
    static let shared = BodySpecAPI()

    private let baseURL: URL
    private let urlSession: URLSession
    private let authManager: BodySpecAuthManager

    init(
        baseURL: URL = URL(string: "https://app.bodyspec.com")!,
        urlSession: URLSession = .shared,
        authManager: BodySpecAuthManager = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.authManager = authManager
    }

    func getUser() async throws -> BodySpecUser {
        let token = try await requireToken()
        let url = baseURL.appendingPathComponent("/api/v1/users/me")
        let request = try makeRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BodySpecUser.self, from: data)
    }

    func listResults(page: Int = 1, pageSize: Int = 20) async throws -> BodySpecResultsListResponse {
        let token = try await requireToken()

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/v1/users/me/results/"),
            resolvingAgainstBaseURL: false
        )

        components?.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]

        guard let url = components?.url else {
            throw BodySpecAPIError.invalidResponse
        }

        let request = try makeRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BodySpecResultsListResponse.self, from: data)
    }

    func getDexaScanInfo(resultId: String) async throws -> BodySpecDexaScanInfoResponse {
        let token = try await requireToken()
        let path = "/api/v1/users/me/results/\(resultId)/dexa/scan-info"
        let url = baseURL.appendingPathComponent(path)
        let request = try makeRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BodySpecDexaScanInfoResponse.self, from: data)
    }

    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse {
        let token = try await requireToken()
        let path = "/api/v1/users/me/results/\(resultId)/dexa/composition"
        let url = baseURL.appendingPathComponent(path)
        let request = try makeRequest(url: url, token: token)
        let (data, response) = try await urlSession.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BodySpecDexaCompositionResponse.self, from: data)
    }

    private func requireToken() async throws -> String {
        guard let token = try await authManager.ensureValidToken() else {
            throw BodySpecAPIError.notConnected
        }

        return token
    }

    private func makeRequest(url: URL, token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BodySpecAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BodySpecAPIError.httpError(httpResponse.statusCode)
        }
    }
}
