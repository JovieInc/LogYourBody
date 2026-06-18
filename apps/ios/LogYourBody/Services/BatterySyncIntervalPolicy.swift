//
// BatterySyncIntervalPolicy.swift
// LogYourBody
//
import UIKit

/// Maps device battery state/level to an auto-sync interval.
///
/// Extracted from `RealtimeSyncManager.adjustSyncIntervalForBattery()` so the
/// thresholds can be unit tested without a physical device (battery level/state
/// are not controllable in the simulator).
enum BatterySyncIntervalPolicy {
    /// Sync aggressively while charging, then back off as the battery drains.
    ///
    /// - Note: `level` is `-1` when battery monitoring is unavailable; that falls
    ///   through to the most conservative interval, which is the safe default.
    static func interval(state: UIDevice.BatteryState, level: Float) -> TimeInterval {
        switch (state, level) {
        case (.charging, _), (.full, _):
            return 60      // 1 minute — charging or full
        case (_, let level) where level > 0.5:
            return 300     // 5 minutes — above 50%
        case (_, let level) where level > 0.2:
            return 900     // 15 minutes — 20% to 50%
        default:
            return 1_800   // 30 minutes — below 20% (or level unknown)
        }
    }
}
