//
// TimelinePlayheadStore.swift
// LogYourBody
//
// Slice 0 playhead store: axis + EntryID selection. No UI wiring.
// MainActor assigns finished membership results only.
//

import Foundation
import Observation

@MainActor
@Observable
final class TimelinePlayheadStore {
    private(set) var axis: TimelineAxis = .time
    private(set) var playhead: TimelinePlayhead?
    private(set) var orderedEntryIDs: [HomeV2TimelinePolicy.EntryID] = []

    private var metricsByID: [HomeV2TimelinePolicy.EntryID: BodyMetrics] = [:]
    private var owner: String?
    private var heightCm: Double?
    private var contentSignature: ContentSignature?

    private struct ContentSignature: Equatable {
        let metricIDs: [String]
        let dates: [Date]
        let weights: [UInt64?]
        let bodyFats: [UInt64?]
        let owner: String?
        let heightBitPattern: UInt64?
    }

    /// Rebuild axis membership when published history changes. Selection is
    /// reconciled against the new order; the MainActor only assigns finished values.
    func updateContent(
        metrics: [BodyMetrics],
        owner: String?,
        heightCm: Double? = nil
    ) {
        let signature = ContentSignature(
            metricIDs: metrics.map(\.id),
            dates: metrics.map(\.date),
            weights: metrics.map { $0.weight?.bitPattern },
            bodyFats: metrics.map { $0.bodyFatPercentage?.bitPattern },
            owner: owner,
            heightBitPattern: heightCm?.bitPattern
        )
        guard signature != contentSignature else { return }
        contentSignature = signature
        self.owner = owner
        self.heightCm = heightCm
        metricsByID = metrics.reduce(into: [:]) { lookup, metric in
            lookup[HomeV2TimelinePolicy.EntryID(metric)] = metric
        }
        applyMembership(reusingSelection: playhead?.entryID)
    }

    func setAxis(_ newAxis: TimelineAxis) {
        guard newAxis != axis else { return }
        axis = newAxis
        applyMembership(reusingSelection: playhead?.entryID)
    }

    func select(_ entryID: HomeV2TimelinePolicy.EntryID) {
        guard orderedEntryIDs.contains(entryID) else { return }
        playhead = .snapped(entryID)
    }

    /// Conceptual step along the active axis. Clamps at ends (no wrap).
    func step(forward: Bool) {
        guard let next = UnifiedTimelinePolicy.stepped(
            from: playhead?.entryID,
            in: orderedEntryIDs,
            forward: forward
        ) else {
            playhead = nil
            return
        }
        playhead = .snapped(next)
    }

    func reset() {
        axis = .time
        playhead = nil
        orderedEntryIDs = []
        metricsByID = [:]
        owner = nil
        heightCm = nil
        contentSignature = nil
    }

    private func applyMembership(reusingSelection selection: HomeV2TimelinePolicy.EntryID?) {
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: axis,
            metrics: Array(metricsByID.values),
            owner: owner,
            heightCm: heightCm
        )
        let clamped = UnifiedTimelinePolicy.clamp(
            selection: selection,
            into: ordered,
            metricsByID: metricsByID
        )
        orderedEntryIDs = ordered
        playhead = clamped.map(TimelinePlayhead.snapped)
    }
}
