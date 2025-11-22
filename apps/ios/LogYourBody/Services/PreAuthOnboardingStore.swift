import Foundation

final class PreAuthOnboardingStore {
    static let shared = PreAuthOnboardingStore()

    private let userDefaults: UserDefaults
    private let storageKey = "preAuthOnboarding.bodyScore"
    private let queue = DispatchQueue(label: "com.logyourbody.onboarding.preAuthStore", qos: .utility)

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(input: BodyScoreInput, result: BodyScoreResult) {
        let snapshot = Snapshot(
            input: input,
            result: PreAuthBodyScoreResultCodable(result: result),
            lastUpdated: Date()
        )

        queue.async { [weak self] in
            guard let self else { return }
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(snapshot) {
                self.userDefaults.set(data, forKey: self.storageKey)
            }
        }
    }

    func load() -> (BodyScoreInput, BodyScoreResult)? {
        queue.sync {
            guard let data = userDefaults.data(forKey: storageKey) else { return nil }
            let decoder = JSONDecoder()
            guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
            return (snapshot.input, snapshot.result.result)
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    private struct Snapshot: Codable {
        let input: BodyScoreInput
        let result: PreAuthBodyScoreResultCodable
        let lastUpdated: Date
    }
}

private struct PreAuthBodyScoreResultCodable: Codable {
    let score: Int
    let ffmi: Double
    let leanPercentile: Double
    let ffmiStatus: String
    let targetLower: Double
    let targetUpper: Double
    let targetLabel: String
    let statusTagline: String

    init(result: BodyScoreResult) {
        score = result.score
        ffmi = result.ffmi
        leanPercentile = result.leanPercentile
        ffmiStatus = result.ffmiStatus
        targetLower = result.targetBodyFat.lowerBound
        targetUpper = result.targetBodyFat.upperBound
        targetLabel = result.targetBodyFat.label
        statusTagline = result.statusTagline
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
