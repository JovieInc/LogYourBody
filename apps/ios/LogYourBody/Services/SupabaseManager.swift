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

    let supabaseURL = Constants.supabaseURL
    let supabaseAnonKey = Constants.supabaseAnonKey

    // Custom URLSession with timeout configuration
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0 // 30 seconds per request
        configuration.timeoutIntervalForResource = 60.0 // 60 seconds total
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    init() {}


    // MARK: - Batch Operations

    func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = try SupabaseURLBuilder.restURL(table: "body_metrics", baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let jsonData = try JSONSerialization.data(withJSONObject: metrics)
        request.httpBody = jsonData

        // print("📤 Sending \(metrics.count) body metrics to Supabase")
        if String(data: jsonData, encoding: .utf8) != nil {
            // print("📄 Request body preview: \(String(jsonString.prefix(500)))")
        }

        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.requestFailed
        }

        // print("📡 Supabase body_metrics response: Status \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            if String(data: data, encoding: .utf8) != nil {
                // print("❌ Supabase body_metrics error: \(errorData)")
            }
            throw SupabaseError.requestFailed
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        // print("✅ Supabase returned \(result.count) body metrics")
        return result
    }

    func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        let url = try SupabaseURLBuilder.restURL(table: "daily_metrics", baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let jsonData = try JSONSerialization.data(withJSONObject: metrics)
        request.httpBody = jsonData

        // Debug: Print exactly what we're sending
        if String(data: jsonData, encoding: .utf8) != nil {
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


    func updateProfile(_ profile: [String: Any], token: String) async throws {
        guard let userId = profile["id"] as? String else { throw SupabaseError.invalidData }

        let sanitizedProfile = try Self.sanitizedProfilePayload(profile)
        guard sanitizedProfile["id"] as? String == userId else {
            throw SupabaseError.invalidData
        }

        let url = try SupabaseURLBuilder.restURL(table: "profiles", query: "id=eq.\(userId)&select=id", baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        guard JSONSerialization.isValidJSONObject(sanitizedProfile) else {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "Invalid profile payload for JSON serialization",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "updateProfile",
                    "userId": userId
                ]
            )
            throw SupabaseError.invalidData
        }

        let jsonData = try JSONSerialization.data(withJSONObject: sanitizedProfile)
        request.httpBody = jsonData

        let (responseData, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let rows = if responseData.isEmpty {
            [[String: Any]]()
        } else {
            try JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] ?? []
        }
        if rows.isEmpty {
            try await upsertProfilePayload(sanitizedProfile, token: token)
        }
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

    @discardableResult
    func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        let url = try SupabaseURLBuilder.restURL(table: table, baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = data

        let (responseData, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        return try JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] ?? []
    }

    func deleteData(table: String, id: String, token: String) async throws {
        let url = try SupabaseURLBuilder.restURL(table: table, query: "id=eq.\(id)", baseURL: supabaseURL)
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


    func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        let jwt = try await getSupabaseJWT()

        // Only affects GLP-1 medications; future non-GLP-1 medication tables are untouched.
        let url = try SupabaseURLBuilder.restURL(table: "glp1_medications", query: "user_id=eq.\(userId)&ended_at=is.null", baseURL: supabaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = ["ended_at": formatter.string(from: endedAt)]
        let data = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = data

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }
}
