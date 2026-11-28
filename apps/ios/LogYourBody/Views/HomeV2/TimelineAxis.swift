//
// TimelineAxis.swift
// LogYourBody
//
// Unified Timeline Slice 0 foundations: axis + playhead value types.
// No user-visible UI. Extends Home V2 EntryID selection; does not replace it.
//

import Foundation

/// HUD-locked scrub metrics (TimelinePhotoScrubLock 1.1.1). Lean/waist wait for Slice 5.
enum TimelineMetricKind: String, CaseIterable, Hashable, Sendable {
    case ffmi
    case weight
    case bodyFat
}

/// Scrub axis for the unified timeline. Default is chronological time.
enum TimelineAxis: Hashable, Sendable {
    case time
    case metric(TimelineMetricKind)
}

/// Selected entry on the active axis. Fractional offset is reserved for morph
/// crossfade (later slices); selection for logging/share always snaps to EntryID.
struct TimelinePlayhead: Equatable, Sendable {
    var entryID: HomeV2TimelinePolicy.EntryID
    /// Offset toward the next neighbor on the ordered axis. Zero when snapped.
    var fractionalOffset: Double

    init(entryID: HomeV2TimelinePolicy.EntryID, fractionalOffset: Double = 0) {
        self.entryID = entryID
        self.fractionalOffset = Self.clampedOffset(fractionalOffset)
    }

    static func clampedOffset(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }

    /// Snap to an entry (clears morph offset).
    static func snapped(_ entryID: HomeV2TimelinePolicy.EntryID) -> TimelinePlayhead {
        TimelinePlayhead(entryID: entryID, fractionalOffset: 0)
    }
}
