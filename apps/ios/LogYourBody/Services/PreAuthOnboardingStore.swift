import Foundation

final class PreAuthOnboardingStore {
    static let shared = PreAuthOnboardingStore()

    private let userDefaults: UserDefaults
    private let storageKey = "preAuthOnboarding.bodyScore"
    private let queue = DispatchQueue(label: "com.logyourbody.onboarding.preAuthStore", qos: .utility)

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    struct StoredSnapshot: Equatable {
        let input: BodyScoreInput
        let result: BodyScoreResult
        let defaultHomeMode: DefaultHomeMode
    }

    func save(
        input: BodyScoreInput,
        result: BodyScoreResult,
        defaultHomeMode: DefaultHomeMode = .default
    ) {
        let snapshot = Snapshot(
            input: input,
            result: PreAuthBodyScoreResultCodable(result: result),
            defaultHomeMode: defaultHomeMode,
            lastUpdated: Date()
        )

        queue.sync {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(snapshot) {
                userDefaults.set(data, forKey: storageKey)
            }
        }
    }

    func load() -> StoredSnapshot? {
        queue.sync {
            guard let data = userDefaults.data(forKey: storageKey) else { return nil }
            let decoder = JSONDecoder()
            guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
            return StoredSnapshot(
                input: snapshot.input,
                result: snapshot.result.result,
                defaultHomeMode: snapshot.defaultHomeMode
            )
        }
    }

    func clear() {
        queue.sync {
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    private struct Snapshot: Codable {
        let input: BodyScoreInput
        let result: PreAuthBodyScoreResultCodable
        let defaultHomeMode: DefaultHomeMode
        let lastUpdated: Date

        private enum CodingKeys: String, CodingKey {
            case input
            case result
            case defaultHomeMode
            case lastUpdated
        }

        init(
            input: BodyScoreInput,
            result: PreAuthBodyScoreResultCodable,
            defaultHomeMode: DefaultHomeMode,
            lastUpdated: Date
        ) {
            self.input = input
            self.result = result
            self.defaultHomeMode = defaultHomeMode
            self.lastUpdated = lastUpdated
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try container.decode(BodyScoreInput.self, forKey: .input)
            result = try container.decode(PreAuthBodyScoreResultCodable.self, forKey: .result)
            defaultHomeMode = try container.decodeIfPresent(DefaultHomeMode.self, forKey: .defaultHomeMode) ?? .default
            lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        }
    }
}

private struct PreAuthBodyScoreResultCodable: Codable {
    let score: Int
    let ffmi: Double
    let leanPercentile: Double
    let ffmiStatus: String
    let referenceLower: Double
    let referenceUpper: Double
    let referenceLabel: String
    let statusTagline: String

    private enum CodingKeys: String, CodingKey {
        case score
        case ffmi
        case leanPercentile
        case ffmiStatus
        case referenceLower = "targetLower"
        case referenceUpper = "targetUpper"
        case referenceLabel = "targetLabel"
        case statusTagline
    }

    init(result: BodyScoreResult) {
        score = result.score
        ffmi = result.ffmi
        leanPercentile = result.leanPercentile
        ffmiStatus = result.ffmiStatus
        referenceLower = result.bodyFatReferenceRange.lowerBound
        referenceUpper = result.bodyFatReferenceRange.upperBound
        referenceLabel = result.bodyFatReferenceRange.label
        statusTagline = result.statusTagline
    }

    var result: BodyScoreResult {
        BodyScoreResult(
            score: score,
            ffmi: ffmi,
            leanPercentile: leanPercentile,
            ffmiStatus: ffmiStatus,
            bodyFatReferenceRange: .init(
                lowerBound: referenceLower,
                upperBound: referenceUpper,
                label: referenceLabel
            ),
            statusTagline: statusTagline
        )
    }
}

extension Notification.Name {
    static let preAuthOnboardingCompleted = Notification.Name("preAuthOnboardingCompleted")
}
