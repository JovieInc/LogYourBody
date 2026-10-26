import Foundation

/// LYB-173: ask only for valuable missing information. These are tunable product
/// heuristics, not clinical thresholds or measurement/scan recommendations.
enum MeasurementValueConstants {
    static let weightFreshness: TimeInterval = 24 * 60 * 60
    static let photoFreshness: TimeInterval = 7 * 24 * 60 * 60
    static let staleConfidenceMultiplier = 0.5
    static let minimumDecisionValueToAsk = 0.2
}
