//
// SupabaseManager.swift
// LogYourBody
//
import Foundation
import SwiftUI


@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let supabaseURL = Constants.supabaseURL
    let supabaseAnonKey = Constants.supabaseAnonKey

    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    init() {}

    var productAPIBaseURL: String {
        Configuration.apiBaseURL
    }

    func productAPIURL(_ path: String, query: String? = nil) throws -> URL {
        var string = productAPIBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        string += path.hasPrefix("/") ? path : "/\(path)"
        if let query, !query.isEmpty {
            string += "?\(query)"
        }
        guard let url = URL(string: string) else {
            throw SupabaseError.invalidConfiguration
        }
        return url
    }

    func nativeCollectionPath(_ table: String) -> String {
        table.replacingOccurrences(of: "_", with: "-")
    }

    func authorizedJSONRequest(url: URL, method: String, token: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = body
        return request
    }

    func requireHTTPSuccess(_ response: URLResponse, data: Data = Data()) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }
        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            _ = data
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
        return httpResponse
    }

    func records(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let dict = object as? [String: Any], let records = dict["records"] as? [[String: Any]] {
            return records
        }
        if let array = object as? [[String: Any]] {
            return array
        }
        return []
    }

    func jsonObject(from data: Data) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - Batch Operations

    func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = try productAPIURL("/api/auth/mobile/sync/v1/body-metrics")
        let body = try JSONSerialization.data(withJSONObject: ["records": metrics])
        let request = authorizedJSONRequest(url: url, method: "POST", token: token, body: body)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try records(from: data)
    }

    func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = try productAPIURL("/api/auth/mobile/sync/v1/daily-metrics")
        let body = try JSONSerialization.data(withJSONObject: metrics)
        let request = authorizedJSONRequest(url: url, method: "POST", token: token, body: body)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try records(from: data)
    }

    func updateProfile(_ profile: [String: Any], token: String) async throws {
        let url = try productAPIURL("/api/auth/mobile/profile")
        let body = try JSONSerialization.data(withJSONObject: Self.firstPartyProfilePatchBody(profile))
        let request = authorizedJSONRequest(url: url, method: "PATCH", token: token, body: body)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
    }

    nonisolated static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    nonisolated static func profileColumnName(for key: String) -> String {
        switch key {
        case "fullName":
            return "full_name"
        case "dateOfBirth":
            return "date_of_birth"
        case "heightUnit":
            return "height_unit"
        case "activityLevel":
            return "activity_level"
        case "goalWeight":
            return "goal_weight"
        case "goalWeightUnit":
            return "goal_weight_unit"
        case "onboardingCompleted":
            return "onboarding_completed"
        case "avatarUrl":
            return "avatar_url"
        case "firstName":
            return "first_name"
        case "lastName":
            return "last_name"
        default:
            return key
        }
    }

    nonisolated static func firstPartyProfilePatchBody(_ profile: [String: Any]) throws -> [String: Any] {
        var body: [String: Any] = [:]

        func stringValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = unwrapOptional(profile[key] as Any) as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        if let fullName = stringValue(["fullName", "full_name"]) {
            body["fullName"] = fullName
        }
        if let dateOfBirth = stringValue(["dateOfBirth", "date_of_birth"]) {
            body["dateOfBirth"] = String(dateOfBirth.prefix(10))
        } else if let date = unwrapOptional(profile["dateOfBirth"] as Any) as? Date
                    ?? unwrapOptional(profile["date_of_birth"] as Any) as? Date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            body["dateOfBirth"] = formatter.string(from: date)
        }
        if let height = unwrapOptional(profile["height"] as Any) as? Double {
            body["height"] = height
        }
        if let heightUnit = stringValue(["heightUnit", "height_unit"]) {
            body["heightUnit"] = heightUnit
        }
        if let gender = stringValue(["gender"]) {
            body["gender"] = gender
        }
        if let activityLevel = stringValue(["activityLevel", "activity_level"]) {
            body["activityLevel"] = activityLevel
        }
        if let goalWeight = unwrapOptional(profile["goalWeight"] as Any) as? Double
            ?? unwrapOptional(profile["goal_weight"] as Any) as? Double {
            body["goalWeight"] = goalWeight
        }
        if let goalWeightUnit = stringValue(["goalWeightUnit", "goal_weight_unit"]) {
            body["goalWeightUnit"] = goalWeightUnit
        }
        if let onboardingCompleted = unwrapOptional(profile["onboardingCompleted"] as Any) as? Bool
            ?? unwrapOptional(profile["onboarding_completed"] as Any) as? Bool {
            body["onboardingCompleted"] = onboardingCompleted
        }

        guard JSONSerialization.isValidJSONObject(body) else {
            throw SupabaseError.invalidData
        }
        return body
    }

    @discardableResult
    func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        let path = nativeCollectionPath(table)
        let url = try productAPIURL("/api/auth/mobile/sync/v1/\(path)")
        var body = data
        if table == "body_metrics" {
            let object = try JSONSerialization.jsonObject(with: data)
            let records = object as? [[String: Any]] ?? [(object as? [String: Any])].compactMap { $0 }
            body = try JSONSerialization.data(withJSONObject: ["records": records])
        }
        let request = authorizedJSONRequest(url: url, method: "POST", token: token, body: body)
        let (responseData, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: responseData)
        return try records(from: responseData)
    }

    func deleteData(table: String, id: String, token: String) async throws {
        let path = nativeCollectionPath(table == "body_metrics" ? "body_metrics" : table)
        let collection = table == "body_metrics" ? "body-metrics" : path
        let url = try productAPIURL("/api/auth/mobile/sync/v1/\(collection)")
        let body = try JSONSerialization.data(withJSONObject: ["ids": [id]])
        let request = authorizedJSONRequest(url: url, method: "DELETE", token: token, body: body)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
    }

    func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        _ = userId
        let jwt = try await getSupabaseJWT()
        let url = try productAPIURL("/api/auth/mobile/sync/v1/glp1-medications")
        let formatter = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: [
            "ended_at": formatter.string(from: endedAt)
        ])
        let request = authorizedJSONRequest(url: url, method: "POST", token: jwt, body: body)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
    }
}
