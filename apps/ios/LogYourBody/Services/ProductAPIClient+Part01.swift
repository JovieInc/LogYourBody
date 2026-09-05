import Foundation
import SwiftUI

extension ProductAPIClient {
    func getAccessToken() async throws -> String {
        guard let jwtString = await AuthManager.shared.getAccessToken() else {
            throw ProductAPIError.tokenGenerationFailed
        }
        return jwtString
    }

    func fetchLatestBodyMetricTimestamp(userId: String, token: String) async throws -> Date? {
        _ = userId
        let metrics = try await fetchBodyMetrics(
            userId: userId,
            since: Date(timeIntervalSince1970: 0),
            token: token
        )
        let formatter = ISO8601DateFormatter()
        let timestamps = metrics.compactMap { record -> Date? in
            let value = (record["server_updated_at"] as? String) ?? (record["updated_at"] as? String)
            return value.flatMap(formatter.date(from:))
        }
        return timestamps.max()
    }

    func fetchBodyMetrics(userId: String, since: Date, token: String) async throws -> [[String: Any]] {
        _ = userId
        let sinceString = ISO8601DateFormatter().string(from: since)
        let url = try productAPIURL(
            "/api/auth/mobile/sync/v1/body-metrics",
            query: "since=\(sinceString)"
        )
        let request = authorizedJSONRequest(url: url, method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try records(from: data)
    }

    func fetchDailyMetrics(userId: String, since: Date, token: String) async throws -> [[String: Any]] {
        _ = userId
        let sinceString = ISO8601DateFormatter().string(from: since)
        let url = try productAPIURL(
            "/api/auth/mobile/sync/v1/daily-metrics",
            query: "since=\(sinceString)"
        )
        let request = authorizedJSONRequest(url: url, method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        return try records(from: data)
    }

    func fetchProfile(userId: String, token: String) async throws -> [String: Any]? {
        _ = userId
        let url = try productAPIURL("/api/auth/mobile/profile")
        let request = authorizedJSONRequest(url: url, method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        let object = try jsonObject(from: data)
        return object["profile"] as? [String: Any] ?? object
    }

    func upsertProfilePayload(_ profile: [String: Any], token: String) async throws {
        try await updateProfile(profile, token: token)
    }

    nonisolated static func sanitizedProfilePayload(_ profile: [String: Any]) throws -> [String: Any] {
        try firstPartyProfilePatchBody(profile)
    }

    func fetchProfile(userId: String) async throws -> UserProfile? {
        let jwt = try await getAccessToken()
        guard let data = try await fetchProfile(userId: userId, token: jwt) else { return nil }
        return userProfile(from: data)
    }

    func upsertProfile(_ profile: UserProfile) async throws {
        let jwt = try await getAccessToken()
        var payload: [String: Any] = [:]
        if let fullName = profile.fullName { payload["fullName"] = fullName }
        if let dateOfBirth = profile.dateOfBirth { payload["dateOfBirth"] = dateOfBirth }
        if let height = profile.height { payload["height"] = height }
        if let heightUnit = profile.heightUnit { payload["heightUnit"] = heightUnit }
        if let gender = profile.gender { payload["gender"] = gender }
        if let activityLevel = profile.activityLevel { payload["activityLevel"] = activityLevel }
        if let goalWeight = profile.goalWeight { payload["goalWeight"] = goalWeight }
        if let goalWeightUnit = profile.goalWeightUnit { payload["goalWeightUnit"] = goalWeightUnit }
        if let onboardingCompleted = profile.onboardingCompleted {
            payload["onboardingCompleted"] = onboardingCompleted
        }
        try await updateProfile(payload, token: jwt)
    }

    func fetchGlp1Medications(userId: String) async throws -> [Glp1Medication] {
        try await decodeCollection("glp1-medications", as: Glp1Medication.self, userId: userId)
    }

    func saveGlp1Medication(_ medication: Glp1Medication) async throws {
        try await postEncodable(medication, collection: "glp1-medications")
    }

    func fetchDexaResults(userId: String, limit: Int = 50) async throws -> [DexaResult] {
        try await decodeCollection("dexa-results", as: DexaResult.self, userId: userId, limit: limit)
    }

    func upsertDexaResult(_ result: DexaResult) async throws {
        try await postEncodable(result, collection: "dexa-results")
    }

    func fetchBodyMetrics(userId: String, limit: Int = 30) async throws -> [BodyMetrics] {
        try await decodeCollection("body-metrics", as: BodyMetrics.self, userId: userId, limit: limit)
    }

    func saveBodyMetrics(_ metrics: BodyMetrics) async throws {
        let jwt = try await getAccessToken()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(metrics)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let records = object as? [[String: Any]] ?? [(object as? [String: Any])].compactMap { $0 }
        _ = try await upsertBodyMetricsBatch(records, token: jwt)
    }

    func fetchDailyMetrics(userId: String, from date: Date) async throws -> [DailyMetrics] {
        _ = userId
        let jwt = try await getAccessToken()
        let records = try await fetchDailyMetrics(userId: userId, since: date, token: jwt)
        let data = try JSONSerialization.data(withJSONObject: records)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DailyMetrics].self, from: data)) ?? []
    }

    func saveDailyMetrics(_ metrics: DailyMetrics) async throws {
        try await postEncodable(metrics, collection: "daily-metrics")
    }

    func fetchGlp1DoseLogs(userId: String, limit: Int = 100) async throws -> [Glp1DoseLog] {
        try await decodeCollection("glp1-dose-logs", as: Glp1DoseLog.self, userId: userId, limit: limit)
    }

    func saveGlp1DoseLog(_ log: Glp1DoseLog) async throws {
        try await postEncodable(log, collection: "glp1-dose-logs")
    }

    private func decodeCollection<T: Decodable>(
        _ collection: String,
        as type: T.Type,
        userId: String,
        limit: Int? = nil
    ) async throws -> [T] {
        _ = userId
        let jwt = try await getAccessToken()
        var query = "since=1970-01-01T00:00:00.000Z"
        if let limit {
            query += "&limit=\(limit)"
        }
        let url = try productAPIURL("/api/auth/mobile/sync/v1/\(collection)", query: query)
        let request = authorizedJSONRequest(url: url, method: "GET", token: jwt)
        let (data, response) = try await session.data(for: request)
        _ = try requireHTTPSuccess(response, data: data)
        let records = try records(from: data)
        let recordsData = try JSONSerialization.data(withJSONObject: records)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([T].self, from: recordsData)) ?? []
    }

    private func postEncodable<T: Encodable>(_ value: T, collection: String) async throws {
        let jwt = try await getAccessToken()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let payload: Any = object as? [Any] ?? [object]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await upsertData(
            table: collection.replacingOccurrences(of: "-", with: "_"),
            data: body,
            token: jwt
        )
    }

    private func userProfile(from data: [String: Any]) -> UserProfile {
        let formatter = ISO8601DateFormatter()
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = data["date_of_birth"] as? String
        let dateOfBirth = dateString.flatMap { formatter.date(from: $0) ?? dayFormatter.date(from: $0) }
        return UserProfile(
            id: data["id"] as? String,
            email: data["email"] as? String,
            username: data["username"] as? String,
            fullName: data["full_name"] as? String,
            dateOfBirth: dateOfBirth,
            height: data["height"] as? Double,
            heightUnit: data["height_unit"] as? String,
            gender: data["gender"] as? String,
            activityLevel: data["activity_level"] as? String,
            goalWeight: data["goal_weight"] as? Double,
            goalWeightUnit: data["goal_weight_unit"] as? String,
            onboardingCompleted: data["onboarding_completed"] as? Bool
        )
    }
}
