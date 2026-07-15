import Foundation
import SwiftUI

extension SupabaseManager {
// MARK: - JWT Token Management

    func getSupabaseJWT() async throws -> String {
        guard let jwtString = await AuthManager.shared.getSupabaseToken() else {
            throw SupabaseError.tokenGenerationFailed
        }

        return jwtString
    }

func fetchLatestBodyMetricTimestamp(userId: String, token: String) async throws -> Date? {
        let url = try SupabaseURLBuilder.restURL(
            table: "body_metrics",
            query: "user_id=eq.\(userId)&order=updated_at.desc&limit=1",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(
            table: "body_metrics",
            query: "user_id=eq.\(userId)&updated_at=gte.\(sinceString)&order=created_at.desc",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(
            table: "daily_metrics",
            query: "user_id=eq.\(userId)&updated_at=gte.\(sinceString)&order=date.desc",
            baseURL: supabaseURL
        )
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
        let url = try SupabaseURLBuilder.restURL(
            table: "profiles",
            query: "id=eq.\(userId)&select=*",
            baseURL: supabaseURL
        )
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

func upsertProfilePayload(_ profile: [String: Any], token: String) async throws {
        guard profile["id"] is String else { throw SupabaseError.invalidData }

        let url = try SupabaseURLBuilder.restURL(table: "profiles", baseURL: supabaseURL)
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

// MARK: - Profile Operations

    func fetchProfile(userId: String) async throws -> UserProfile? {
        let jwt = try await getSupabaseJWT()

        let url = try SupabaseURLBuilder.restURL(
            table: "profiles",
            query: "id=eq.\(userId)&select=*",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "profiles", baseURL: supabaseURL)
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

// MARK: - GLP-1 Medications Operations

    func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication] {
        let jwt = try await getSupabaseJWT()

        let url = try SupabaseURLBuilder.restURL(
            table: "glp1_medications",
            query: "user_id=eq.\(userId)&order=started_at.asc",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "glp1_medications", baseURL: supabaseURL)
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

        let url = try SupabaseURLBuilder.restURL(
            table: "dexa_results",
            query: "user_id=eq.\(userId)&order=acquire_time.desc&limit=\(limit)",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "dexa_results", baseURL: supabaseURL)
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

        let url = try SupabaseURLBuilder.restURL(
            table: "body_metrics",
            query: "user_id=eq.\(userId)&order=date.desc&limit=\(limit)",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "body_metrics", baseURL: supabaseURL)
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

        let url = try SupabaseURLBuilder.restURL(
            table: "daily_metrics",
            query: "user_id=eq.\(userId)&date=gte.\(fromDateString)&order=date.desc",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "daily_metrics", baseURL: supabaseURL)
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

        let url = try SupabaseURLBuilder.restURL(
            table: "glp1_dose_logs",
            query: "user_id=eq.\(userId)&order=taken_at.desc&limit=\(limit)",
            baseURL: supabaseURL
        )
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

        let url = try SupabaseURLBuilder.restURL(table: "glp1_dose_logs", baseURL: supabaseURL)
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
