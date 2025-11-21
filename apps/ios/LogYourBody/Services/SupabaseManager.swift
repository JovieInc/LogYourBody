//
// SupabaseManager.swift
// LogYourBody
//
import Foundation
import SwiftUI
import Clerk


@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    private let supabaseURL = Constants.supabaseURL
    private let supabaseAnonKey = Constants.supabaseAnonKey

    // Custom URLSession with timeout configuration
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0 // 30 seconds per request
        configuration.timeoutIntervalForResource = 60.0 // 60 seconds total
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private init() {}

    // MARK: - JWT Token Management

    private func getSupabaseJWT() async throws -> String {
        guard let session = Clerk.shared.session else {
            throw SupabaseError.notAuthenticated
        }

        // Get JWT token from Clerk using the new native integration pattern
        // No template parameter needed - Supabase will validate the Clerk session token directly
        let tokenResource = try await session.getToken()

        guard let jwtString = tokenResource?.jwt else {
            throw SupabaseError.tokenGenerationFailed
        }

        return jwtString
    }

    // MARK: - Batch Operations

    func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let jsonData = try JSONSerialization.data(withJSONObject: metrics)
        request.httpBody = jsonData

        // print("📤 Sending \(metrics.count) body metrics to Supabase")
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            // print("📄 Request body preview: \(String(jsonString.prefix(500)))")
        }

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.requestFailed
        }

        // print("📡 Supabase body_metrics response: Status \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            if let errorData = String(data: data, encoding: .utf8) {
                // print("❌ Supabase body_metrics error: \(errorData)")
            }
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        // print("✅ Supabase returned \(result.count) body metrics")
        return result
    }

    func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = URL(string: "\(supabaseURL)/rest/v1/daily_metrics")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let jsonData = try JSONSerialization.data(withJSONObject: metrics)
        request.httpBody = jsonData

        // Debug: Print exactly what we're sending
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            // print("📤 Sending to Supabase body_metrics:")
            // print("   URL: \(url)")
            // print("   Method: POST")
            // print("   Headers: apikey=***, Authorization=Bearer ***, Content-Type=application/json")
            // print("   Prefer: \(request.value(forHTTPHeaderField: "Prefer") ?? "none")")
            // print("   Body: \(jsonString)")
        }

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return result
    }

    func fetchLatestBodyMetricTimestamp(userId: String, token: String) async throws -> Date? {
        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics?user_id=eq.\(userId)&order=logged_at.desc&limit=1")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let first = result.first,
              let dateString = first["logged_at"] as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }

    func fetchBodyMetrics(userId: String, since: Date, token: String) async throws -> [[String: Any]] {
        let dateFormatter = ISO8601DateFormatter()
        let sinceString = dateFormatter.string(from: since)

        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics?user_id=eq.\(userId)&updated_at=gte.\(sinceString)&order=created_at.desc")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return result
    }

    func fetchDailyMetrics(userId: String, since: Date, token: String) async throws -> [[String: Any]] {
        let dateFormatter = ISO8601DateFormatter()
        let sinceString = dateFormatter.string(from: since)

        let url = URL(string: "\(supabaseURL)/rest/v1/daily_metrics?user_id=eq.\(userId)&updated_at=gte.\(sinceString)&order=date.desc")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return result
    }

    func fetchProfile(userId: String, token: String) async throws -> [String: Any]? {
        let url = URL(string: "\(supabaseURL)/rest/v1/user_profiles?id=eq.\(userId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return result.first
    }

    func updateProfile(_ profile: [String: Any], token: String) async throws {
        guard let userId = profile["id"] as? String else { throw SupabaseError.invalidData }

        let url = URL(string: "\(supabaseURL)/rest/v1/user_profiles?id=eq.\(userId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData = try JSONSerialization.data(withJSONObject: profile)
        request.httpBody = jsonData

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }

    func upsertData(table: String, data: Data, token: String) async throws {
        let url = URL(string: "\(supabaseURL)/rest/v1/\(table)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = data

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }

    func deleteData(table: String, id: String, token: String) async throws {
        let url = URL(string: "\(supabaseURL)/rest/v1/\(table)?id=eq.\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }

    // MARK: - Profile Operations

    func fetchProfile(userId: String) async throws -> UserProfile? {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=*")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profiles = try decoder.decode([UserProfile].self, from: data)

        return profiles.first
    }

    func upsertProfile(_ profile: UserProfile) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/profiles")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(profile)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 && httpResponse.statusCode != 204 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Weight Operations

    func fetchWeights(userId: String, limit: Int = 30) async throws -> [WeightEntry] {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/weight_logs?user_id=eq.\(userId)&order=logged_at.desc&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Decode from Supabase format
        let weightLogs = try decoder.decode([WeightLog].self, from: data)

        // Convert to WeightEntry format
        return weightLogs.map { log in
            WeightEntry(
                id: log.id,
                userId: log.userId,
                weight: log.weight,
                weightUnit: log.weightUnit,
                notes: log.notes,
                loggedAt: log.loggedAt
            )
        }
    }

    func saveWeight(_ entry: WeightEntry) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/weight_logs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        // Convert to Supabase format
        let weightLog = WeightLog(
            id: entry.id,
            userId: entry.userId,
            weight: entry.weight,
            weightUnit: entry.weightUnit,
            notes: entry.notes,
            loggedAt: entry.loggedAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(weightLog)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Body Metrics Operations

    func fetchBodyMetrics(userId: String, limit: Int = 30) async throws -> [BodyMetrics] {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics?user_id=eq.\(userId)&order=date.desc&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([BodyMetrics].self, from: data)
    }

    func saveBodyMetrics(_ metrics: BodyMetrics) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(metrics)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 && httpResponse.statusCode != 204 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Daily Metrics Operations

    func fetchDailyMetrics(userId: String, from date: Date) async throws -> [DailyMetrics] {
        let jwt = try await getSupabaseJWT()

        let dateFormatter = ISO8601DateFormatter()
        let fromDateString = dateFormatter.string(from: date)

        let url = URL(string: "\(supabaseURL)/rest/v1/daily_metrics?user_id=eq.\(userId)&date=gte.\(fromDateString)&order=date.desc")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([DailyMetrics].self, from: data)
    }

    func saveDailyMetrics(_ metrics: DailyMetrics) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/daily_metrics")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(metrics)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 && httpResponse.statusCode != 204 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Supabase Models

private struct WeightLog: Codable {
    let id: String
    let userId: String
    let weight: Double
    let weightUnit: String
    let notes: String?
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weight
        case weightUnit = "weight_unit"
        case notes
        case loggedAt = "logged_at"
    }
}
