import Foundation

/// Shared, deterministic input to the decision selector and pill ranker.
/// Freshness describes availability, not trust: even `.current` can have reduced
/// confidence. Consumers must retain the confidence reasons when presenting it.
enum MeasurementValue {
    enum MetricKind: CaseIterable {
        case weight
        case photo

        var freshnessInterval: TimeInterval {
            switch self {
            case .weight: return MeasurementValueConstants.weightFreshness
            case .photo: return MeasurementValueConstants.photoFreshness
            }
        }
    }

    enum Status: Equatable {
        case current
        case usefulToAsk
        case notWorthAsking
    }

    enum ConfidenceReason: Hashable {
        case missingMeasurement
        case staleMeasurement
        case unreliableSource
        case measurementNoise
        case futureEffectiveDate
        case invalidInput
    }

    struct Assessment: Equatable {
        let status: Status
        /// Confidence in the existing reading, from zero to one; zero if missing.
        let confidence: Double
        let confidenceReasons: Set<ConfidenceReason>
        /// Expected benefit of another reading, from zero to one.
        let decisionValue: Double
    }

    /// `lastEffectiveDate` is when the latest reading was observed/captured,
    /// never when it was imported. Pass nil only when no reading exists.
    /// Freshness uses inclusive elapsed-time windows, independent of time zone.
    /// Reliability, noise and decision impact must be finite values in 0...1.
    /// Quality also describes the reading obtainable by asking; callers estimate
    /// decision impact, so this policy never invents a coaching prescription.
    static func evaluate(
        metric: MetricKind,
        lastEffectiveDate: Date?,
        sourceReliability: Double,
        noise: Double,
        decisionImpact: Double,
        now: Date
    ) -> Assessment {
        var reasons = Set<ConfidenceReason>()
        let age = lastEffectiveDate.map { now.timeIntervalSince($0) }
        let validDate = now.timeIntervalSinceReferenceDate.isFinite && (age?.isFinite ?? true)
        let isCurrent = validDate && age.map { $0 >= 0 && $0 <= metric.freshnessInterval } == true

        if lastEffectiveDate == nil { reasons.insert(.missingMeasurement) }
        if let age, age > metric.freshnessInterval { reasons.insert(.staleMeasurement) }
        if let age, age < 0 { reasons.insert(.futureEffectiveDate) }
        if sourceReliability < 1 { reasons.insert(.unreliableSource) }
        if noise > 0 { reasons.insert(.measurementNoise) }

        let validScores = [sourceReliability, noise, decisionImpact].allSatisfy {
            $0.isFinite && (0...1).contains($0)
        }
        guard validDate, validScores else {
            reasons.insert(.invalidInput)
            return Assessment(
                status: isCurrent ? .current : .notWorthAsking,
                confidence: 0, confidenceReasons: reasons, decisionValue: 0
            )
        }
        guard age.map({ $0 >= 0 }) ?? true else {
            return Assessment(status: .notWorthAsking, confidence: 0, confidenceReasons: reasons, decisionValue: 0)
        }

        let quality = sourceReliability * (1 - noise)
        let confidence = age == nil ? 0 : quality * (isCurrent ? 1 : MeasurementValueConstants.staleConfidenceMultiplier)
        let decisionValue = isCurrent ? 0 : quality * decisionImpact
        let status: Status = isCurrent ? .current : (
            decisionValue >= MeasurementValueConstants.minimumDecisionValueToAsk ? .usefulToAsk : .notWorthAsking
        )
        return Assessment(status: status, confidence: confidence, confidenceReasons: reasons, decisionValue: decisionValue)
    }
}
