import Foundation

enum GlobalTimelineScale: String, Codable {
    case week
    case month
    case year
}

enum MetricPresence: String, Codable, CaseIterable {
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

enum PhaseInsightKind: String, Codable, Equatable {
    case cutting
    case maintaining
    case gaining
    case insufficientData = "insufficient_data"
}

struct PhaseInsight: Equatable {
    let kind: PhaseInsightKind
    let title: String
    let message: String
    let detail: String?
    let weightDeltaPercentPerWeek: Double?
    let bodyFatDeltaPercentagePoints: Double?
    let isLongRunning: Bool
}

enum PhaseInsightPolicy {
    static let defaultShowsPhaseInsight = true

    private static let trendWindowDays: Double = 42
    private static let minimumTrendDays: Double = 14
    private static let longRunningDays: Double = 84
    private static let weightChangeThresholdPercentPerWeek = 0.25
    private static let bodyFatChangeThresholdPercentagePoints = 0.3

    static func shouldShowPhaseInsight() -> Bool {
        true
    }

    static func insight(for metrics: [BodyMetrics]) -> PhaseInsight {
        let weightedMetrics = metrics
            .filter { $0.weight != nil }
            .sorted { $0.date < $1.date }

        guard let latest = weightedMetrics.last,
              let trendStart = trendStartMetric(from: weightedMetrics, latest: latest),
              let latestWeight = latest.weight,
              let startWeight = trendStart.weight,
              startWeight > 0 else {
            return insufficientDataInsight()
        }

        let trendDays = daysBetween(trendStart.date, latest.date)
        guard trendDays >= minimumTrendDays else {
            return insufficientDataInsight()
        }

        let weeklyWeightDelta = weightDeltaPercentPerWeek(
            startWeight: startWeight,
            latestWeight: latestWeight,
            days: trendDays
        )
        let kind = classify(weightDeltaPercentPerWeek: weeklyWeightDelta)
        let bodyFatDelta = bodyFatDeltaPercentagePoints(
            from: metrics,
            startDate: trendStart.date,
            latestDate: latest.date
        )
        let longRunning = isLongRunning(
            kind: kind,
            weightedMetrics: weightedMetrics
        )

        return PhaseInsight(
            kind: kind,
            title: title(for: kind),
            message: message(for: kind, bodyFatDelta: bodyFatDelta),
            detail: detail(for: kind, isLongRunning: longRunning),
            weightDeltaPercentPerWeek: roundedOneDecimal(weeklyWeightDelta),
            bodyFatDeltaPercentagePoints: bodyFatDelta.map(roundedOneDecimal),
            isLongRunning: longRunning
        )
    }

    private static func trendStartMetric(
        from weightedMetrics: [BodyMetrics],
        latest: BodyMetrics
    ) -> BodyMetrics? {
        let cutoff = latest.date.addingTimeInterval(-trendWindowDays * 24 * 60 * 60)
        let candidates = weightedMetrics.filter {
            $0.date >= cutoff && $0.date < latest.date
        }

        return candidates.first
    }

    private static func classify(weightDeltaPercentPerWeek: Double) -> PhaseInsightKind {
        if weightDeltaPercentPerWeek <= -weightChangeThresholdPercentPerWeek {
            return .cutting
        }

        if weightDeltaPercentPerWeek >= weightChangeThresholdPercentPerWeek {
            return .gaining
        }

        return .maintaining
    }

    private static func isLongRunning(
        kind: PhaseInsightKind,
        weightedMetrics: [BodyMetrics]
    ) -> Bool {
        guard kind == .cutting || kind == .gaining,
              let first = weightedMetrics.first,
              let latest = weightedMetrics.last,
              let firstWeight = first.weight,
              let latestWeight = latest.weight,
              firstWeight > 0 else {
            return false
        }

        let totalDays = daysBetween(first.date, latest.date)
        guard totalDays >= longRunningDays else {
            return false
        }

        let fullWindowDelta = weightDeltaPercentPerWeek(
            startWeight: firstWeight,
            latestWeight: latestWeight,
            days: totalDays
        )

        return classify(weightDeltaPercentPerWeek: fullWindowDelta) == kind
    }

    private static func bodyFatDeltaPercentagePoints(
        from metrics: [BodyMetrics],
        startDate: Date,
        latestDate: Date
    ) -> Double? {
        let bodyFatMetrics = metrics
            .filter {
                $0.bodyFatPercentage != nil &&
                    $0.date >= startDate &&
                    $0.date <= latestDate
            }
            .sorted { $0.date < $1.date }

        guard let first = bodyFatMetrics.first?.bodyFatPercentage,
              let latest = bodyFatMetrics.last?.bodyFatPercentage,
              bodyFatMetrics.count >= 2 else {
            return nil
        }

        return latest - first
    }

    private static func message(
        for kind: PhaseInsightKind,
        bodyFatDelta: Double?
    ) -> String {
        switch kind {
        case .cutting:
            if let bodyFatDelta, bodyFatDelta <= -bodyFatChangeThresholdPercentagePoints {
                return "Weight is trending down and body fat is moving lower."
            }
            return "Weight is trending down over recent check-ins."
        case .maintaining:
            return "Weight is holding steady over recent check-ins."
        case .gaining:
            if let bodyFatDelta, bodyFatDelta >= bodyFatChangeThresholdPercentagePoints {
                return "Weight is trending up and body fat is moving higher."
            }
            return "Weight is trending up over recent check-ins."
        case .insufficientData:
            return "Log two weights across two weeks to classify this phase."
        }
    }

    private static func detail(
        for kind: PhaseInsightKind,
        isLongRunning: Bool
    ) -> String? {
        guard isLongRunning else {
            return nil
        }

        switch kind {
        case .cutting:
            return "This cut has run 12+ weeks; review photos and body-fat context."
        case .gaining:
            return "This gain has run 12+ weeks; review photos and body-fat context."
        case .maintaining, .insufficientData:
            return nil
        }
    }

    private static func title(for kind: PhaseInsightKind) -> String {
        switch kind {
        case .cutting:
            return "Cutting"
        case .maintaining:
            return "Maintaining"
        case .gaining:
            return "Gaining"
        case .insufficientData:
            return "Need more data"
        }
    }

    private static func insufficientDataInsight() -> PhaseInsight {
        PhaseInsight(
            kind: .insufficientData,
            title: title(for: .insufficientData),
            message: message(for: .insufficientData, bodyFatDelta: nil),
            detail: nil,
            weightDeltaPercentPerWeek: nil,
            bodyFatDeltaPercentagePoints: nil,
            isLongRunning: false
        )
    }

    private static func weightDeltaPercentPerWeek(
        startWeight: Double,
        latestWeight: Double,
        days: Double
    ) -> Double {
        ((latestWeight - startWeight) / startWeight) / days * 7 * 100
    }

    private static func daysBetween(_ start: Date, _ end: Date) -> Double {
        max(end.timeIntervalSince(start) / (24 * 60 * 60), 0)
    }

    private static func roundedOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
