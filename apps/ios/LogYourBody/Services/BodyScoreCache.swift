import Foundation

/// Simple in-memory + UserDefaults cache for storing the latest body score result per user.
/// Persisting to UserDefaults lets the dashboard hero hydrate immediately on launch.
final class BodyScoreCache {
    static let shared = BodyScoreCache()

    private let userDefaults: UserDefaults
    private let storageKey = "bodyScoreCache.latestResults"
    private var cache: [String: BodyScoreResult] = [:]

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDisk()
    }

    func latestResult(for userId: String?) -> BodyScoreResult? {
        guard let userId else { return nil }
        return cache[userId]
    }

    func store(_ result: BodyScoreResult, for userId: String?) {
        guard let userId else { return }
        cache[userId] = result
        persistToDisk()
    }

    private func loadFromDisk() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: BodyScoreResultCodable].self, from: data) {
            cache = decoded.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = entry.value.result
            }
        }
    }

    private func persistToDisk() {
        let codable = cache.reduce(into: [String: BodyScoreResultCodable]()) { partialResult, entry in
            partialResult[entry.key] = BodyScoreResultCodable(result: entry.value)
        }

        if let data = try? JSONEncoder().encode(codable) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}

/// Codable wrapper because BodyScoreResult contains non-codable nested structs.
private struct BodyScoreResultCodable: Codable {
    let score: Int
    let ffmi: Double
    let leanPercentile: Double
    let ffmiStatus: String
    let targetLower: Double
    let targetUpper: Double
    let targetLabel: String
    let statusTagline: String

    init(result: BodyScoreResult) {
        self.score = result.score
        self.ffmi = result.ffmi
        self.leanPercentile = result.leanPercentile
        self.ffmiStatus = result.ffmiStatus
        self.targetLower = result.targetBodyFat.lowerBound
        self.targetUpper = result.targetBodyFat.upperBound
        self.targetLabel = result.targetBodyFat.label
        self.statusTagline = result.statusTagline
    }

    var result: BodyScoreResult {
        BodyScoreResult(
            score: score,
            ffmi: ffmi,
            leanPercentile: leanPercentile,
            ffmiStatus: ffmiStatus,
            targetBodyFat: .init(lowerBound: targetLower, upperBound: targetUpper, label: targetLabel),
            statusTagline: statusTagline
        )
    }
}
