import Foundation

enum GlobalTimelineScale: String, Codable {
    case week
    case month
    case year
}

enum MetricPresence: String, Codable {
    case present
    case interpolated
    case lastKnown = "last_known"
    case missing

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "present":
            self = .present
        case "interpolated", "estimated":
            self = .interpolated
        case "last_known":
            self = .lastKnown
        case "missing":
            self = .missing
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown metric presence: \(rawValue)"
            )
        }
    }
}

enum GlobalTimelineMetricConfidence: String, Codable {
    case high
    case medium
    case low
}

enum BodyScoreCompleteness: String, Codable {
    case full
    case partial
    case none
}

struct GlobalTimelineMetricValue: Codable, Equatable {
    let value: Double?
    let presence: MetricPresence
    let confidence: GlobalTimelineMetricConfidence?

    init(
        value: Double?,
        presence: MetricPresence,
        confidence: GlobalTimelineMetricConfidence? = nil
    ) {
        self.value = value
        self.presence = presence
        self.confidence = confidence
    }
}

struct GlobalTimelineMetricsSnapshot: Codable, Equatable {
    let weight: GlobalTimelineMetricValue
    let bodyFat: GlobalTimelineMetricValue
    let ffmi: GlobalTimelineMetricValue
    let steps: GlobalTimelineMetricValue

    let canonicalPhotoId: String?
    let canonicalPhotoDate: Date?
    let hasPhotosInRange: Bool
    let photoCount: Int

    let bodyScore: Double?
    let bodyScoreCompleteness: BodyScoreCompleteness
}

struct GlobalTimelineBucket: Identifiable, Codable, Equatable {
    let id: String
    let scale: GlobalTimelineScale
    let startDate: Date
    let endDate: Date
    let metrics: GlobalTimelineMetricsSnapshot
}

struct GlobalTimelineCursor: Codable, Equatable {
    let date: Date
    let scale: GlobalTimelineScale
    let bucketId: String
}
