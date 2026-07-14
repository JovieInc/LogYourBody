//
// SupabaseDataClient.swift
// LogYourBody
//
import Foundation
class SupabaseClient {
    static let shared = SupabaseClient()

    private let supabaseURL = Constants.supabaseURL
    private let supabaseAnonKey = Constants.supabaseAnonKey

    private init() {}

    // MARK: - Database Operations

    func query<T: Decodable>(
        table: String,
        accessToken: String,
        select: String? = nil,
        filter: String? = nil,
        order: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        var urlString = "\(supabaseURL)/rest/v1/\(table)"
        var queryItems: [String] = []

        if let select = select {
            queryItems.append("select=\(select)")
        }
        if let filter = filter {
            queryItems.append(filter)
        }
        if let order = order {
            queryItems.append("order=\(order)")
        }
        if let limit = limit {
            queryItems.append("limit=\(limit)")
        }

        if !queryItems.isEmpty {
            urlString += "?" + queryItems.joined(separator: "&")
        }

        let url = try SupabaseURLBuilder.url(from: urlString)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode != 200 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([T].self, from: data)
    }

    func insert<T: Encodable>(
        table: String,
        data: T,
        accessToken: String
    ) async throws {
        let url = try SupabaseURLBuilder.restURL(table: table, baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(data)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode != 201 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }

    func update<T: Encodable>(
        table: String,
        data: T,
        filter: String,
        accessToken: String
    ) async throws {
        let url = try SupabaseURLBuilder.restURL(table: table, query: filter, baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(data)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode != 204 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Error Types

enum SupabaseError: LocalizedError, Equatable {
    case notAuthenticated
    case tokenGenerationFailed
    case invalidResponse
    case networkError
    case unauthorized
    case httpError(Int)
    case requestFailed
    case invalidData
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .tokenGenerationFailed:
            return "Failed to generate authentication token"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network connection error"
        case .unauthorized:
            return "Unauthorized access"
        case .httpError(let code):
            return "Server error: \(code)"
        case .requestFailed:
            return "Request failed"
        case .invalidData:
            return "Invalid data"
        case .invalidConfiguration:
            return "Invalid server configuration"
        }
    }
}

enum SupabaseURLBuilder {
    static func restURL(table: String, query: String? = nil, baseURL: String = Constants.supabaseURL) throws -> URL {
        let normalizedBase = try normalizedBaseURL(baseURL)
        let suffix = query.map { "/rest/v1/\(table)?\($0)" } ?? "/rest/v1/\(table)"
        return try url(from: normalizedBase + suffix)
    }

    static func storageURL(bucket: String, path: String, baseURL: String = Constants.supabaseURL) throws -> URL {
        let normalizedBase = try normalizedBaseURL(baseURL)
        return try url(from: normalizedBase + "/storage/v1/object/\(bucket)/\(path)")
    }

    static func functionURL(_ functionName: String, baseURL: String = Constants.supabaseURL) throws -> URL {
        let normalizedBase = try normalizedBaseURL(baseURL)
        return try url(from: normalizedBase + "/functions/v1/\(functionName)")
    }

    static func isValidServiceHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard
            !normalized.isEmpty,
            !normalized.contains("*"),
            normalized.contains("."),
            normalized.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return false
        }

        return true
    }

    static func normalizedBaseURL(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !Configuration.isPlaceholder(trimmed) else {
            throw SupabaseError.invalidConfiguration
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = url.host,
           isValidServiceHost(host) {
            return "\(scheme)://\(host)"
        }

        let candidate = "https://\(trimmed)"
        if let url = URL(string: candidate),
           url.scheme?.lowercased() == "https",
           let host = url.host,
           isValidServiceHost(host) {
            return candidate
        }

        throw SupabaseError.invalidConfiguration
    }

    static func url(from absoluteString: String) throws -> URL {
        guard
            let url = URL(string: absoluteString),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = url.host,
            isValidServiceHost(host)
        else {
            throw SupabaseError.invalidConfiguration
        }

        return url
    }
}

// MARK: - Database Models

struct Profile: Codable {
    let id: String
    let email: String
    let username: String?
    let fullName: String?
    let dateOfBirth: Date?
    let height: Double?
    let heightUnit: String?
    let gender: String?
    let activityLevel: String?
    let goalWeight: Double?
    let goalWeightUnit: String?
    let avatarUrl: String?
    let createdAt: Date?
    let updatedAt: Date?
    let onboardingCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email, username
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case height
        case heightUnit = "height_unit"
        case gender
        case activityLevel = "activity_level"
        case goalWeight = "goal_weight"
        case goalWeightUnit = "goal_weight_unit"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case onboardingCompleted = "onboarding_completed"
    }
}
