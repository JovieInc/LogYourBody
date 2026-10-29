import Foundation

/// Shared measurement freshness for check-in decisions and quick-action ranking.
/// Callers supply the same signal-specific windows and measurement-quality result.
/// Use the recorded measurement time, never the time a sync/import completed.
enum SignalFreshness: CaseIterable, Equatable {
    case missing
    case stale
    case fresh

    /// Fresh only when the measurement age is nonnegative and less than the window.
    /// Missing/unusable readings and future timestamps cannot satisfy a signal.
    init(measuredAt: Date?, now: Date, window: TimeInterval, isUsable: Bool) {
        guard isUsable, let measuredAt else {
            self = .missing
            return
        }
        let age = now.timeIntervalSince(measuredAt)
        self = window.isFinite && window > 0 && age.isFinite && age >= 0 && age < window ? .fresh : .stale
    }
}
