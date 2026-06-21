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

    init() {}

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

    func fetchLatestBodyMetricTimestamp(userId: String, token: String) async throws -> Date? {
        let url = URL(string: "\(supabaseURL)/rest/v1/body_metrics?user_id=eq.\(userId)&order=updated_at.desc&limit=1")!
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
              let dateString = first["updated_at"] as? String else {
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
        let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=*")!
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

        let sanitizedProfile = try Self.sanitizedProfilePayload(profile)
        guard sanitizedProfile["id"] as? String == userId else {
            throw SupabaseError.invalidData
        }

        let url = URL(string: "\(supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=id")!
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

    private func upsertProfilePayload(_ profile: [String: Any], token: String) async throws {
        guard profile["id"] is String else { throw SupabaseError.invalidData }

        let url = URL(string: "\(supabaseURL)/rest/v1/profiles")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        guard JSONSerialization.isValidJSONObject(profile) else {
            throw SupabaseError.invalidData
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: profile)

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
        guard !rows.isEmpty else { throw SupabaseError.requestFailed }
    }

    nonisolated static func sanitizedProfilePayload(_ profile: [String: Any]) throws -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        let sanitizedProfile = profile.reduce(into: [String: Any]()) { result, element in
            let (key, value) = element
            guard let unwrappedValue = unwrapOptional(value) else { return }

            let columnName = profileColumnName(for: key)
            if let dateValue = unwrappedValue as? Date {
                result[columnName] = isoFormatter.string(from: dateValue)
            } else {
                result[columnName] = unwrappedValue
            }
        }

        guard JSONSerialization.isValidJSONObject(sanitizedProfile) else {
            throw SupabaseError.invalidData
        }

        return sanitizedProfile
    }

    nonisolated private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    nonisolated private static func profileColumnName(for key: String) -> String {
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
        let url = URL(string: "\(supabaseURL)/rest/v1/\(table)")!
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
            ErrorTrackingService.shared.addBreadcrumb(
                message: "Profile fetch unauthorized",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "fetchProfile",
                    "userId": userId
                ]
            )
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "Profile fetch HTTP error",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "fetchProfile",
                    "userId": userId,
                    "statusCode": String(httpResponse.statusCode)
                ]
            )
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

    func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        let jwt = try await getSupabaseJWT()

        // Only affects GLP-1 medications; future non-GLP-1 medication tables are untouched.
        let url = URL(string: "\(supabaseURL)/rest/v1/glp1_medications?user_id=eq.\(userId)&ended_at=is.null")!
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

    // MARK: - GLP-1 Medications Operations

    func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication] {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/glp1_medications?user_id=eq.\(userId)&order=started_at.asc")!
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
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 dose logs fetch unauthorized",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "fetchGlp1DoseLogs",
                    "userId": userId
                ]
            )
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 dose logs fetch HTTP error",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "fetchGlp1DoseLogs",
                    "userId": userId,
                    "statusCode": String(httpResponse.statusCode)
                ]
            )
            throw SupabaseError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Glp1Medication].self, from: data)
    }

    func saveGlp1Medication(_ medication: Glp1Medication) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/glp1_medications")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(medication)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 medication save unauthorized",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "saveGlp1Medication",
                    "userId": medication.userId
                ]
            )
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 && httpResponse.statusCode != 204 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 medication save HTTP error",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "saveGlp1Medication",
                    "userId": medication.userId,
                    "statusCode": String(httpResponse.statusCode)
                ]
            )
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }

    func fetchDexaResults(userId: String, limit: Int = 50) async throws -> [DexaResult] {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/dexa_results?user_id=eq.\(userId)&order=acquire_time.desc&limit=\(limit)")!
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
        return try decoder.decode([DexaResult].self, from: data)
    }

    // MARK: - Dexa Results Operations

    func upsertDexaResult(_ result: DexaResult) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/dexa_results")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(result)

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

    // MARK: - GLP-1 Dose Logs Operations

    func fetchGlp1DoseLogs(userId: String, limit: Int = 100) async throws -> [Glp1DoseLog] {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/glp1_dose_logs?user_id=eq.\(userId)&order=taken_at.desc&limit=\(limit)")!
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
        return try decoder.decode([Glp1DoseLog].self, from: data)
    }

    func saveGlp1DoseLog(_ log: Glp1DoseLog) async throws {
        let jwt = try await getSupabaseJWT()

        let url = URL(string: "\(supabaseURL)/rest/v1/glp1_dose_logs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(log)

        let (_, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.networkError
        }

        if httpResponse.statusCode == 401 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 dose log save unauthorized",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "saveGlp1DoseLog",
                    "userId": log.userId
                ]
            )
            throw SupabaseError.unauthorized
        }

        if httpResponse.statusCode != 201 && httpResponse.statusCode != 204 {
            ErrorTrackingService.shared.addBreadcrumb(
                message: "GLP-1 dose log save HTTP error",
                category: "supabase",
                level: .error,
                data: [
                    "operation": "saveGlp1DoseLog",
                    "userId": log.userId,
                    "statusCode": String(httpResponse.statusCode)
                ]
            )
            throw SupabaseError.httpError(httpResponse.statusCode)
        }
    }
}
