import Foundation

enum GlobalTimelineScale: String, Codable {
    case week
    case month
    case year
}

enum MetricPresence: String, Codable {
    case present
    case estimated
    case missing
}

enum BodyScoreCompleteness: String, Codable {
    case full
    case partial
    case none
}

struct GlobalTimelineMetricValue: Codable, Equatable {
    let value: Double?
    let presence: MetricPresence
}

struct GlobalTimelineMetricsSnapshot: Codable, Equatable {
    let weight: GlobalTimelineMetricValue
    let bodyFat: GlobalTimelineMetricValue
    let ffmi: GlobalTimelineMetricValue
    let steps: GlobalTimelineMetricValue

    let canonicalPhotoId: String?
    let hasPhotosInRange: Bool

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
