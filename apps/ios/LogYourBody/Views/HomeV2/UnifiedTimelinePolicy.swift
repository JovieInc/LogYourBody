//
// UnifiedTimelinePolicy.swift
// LogYourBody
//
// Slice 0: axis membership, reorder, and clamp for EntryID selection.
// Metric-axis membership is recorded-only (no interpolated companions).
// User-visible metric-axis scrub remains gated for Slice 1.
//

import Foundation

enum UnifiedTimelinePolicy {
    static let metricAxisGateKey = "unified_timeline_metric_axis_v1"
    static let morphScrubGateKey = "unified_timeline_morph_scrub_v1"
    static let morphShareGateKey = "unified_timeline_morph_share_v1"
    static let photoCurationGateKey = "unified_timeline_photo_curation_v1"
    static let hudMetricsV2GateKey = "unified_timeline_hud_metrics_v2"

    /// Slice 0 ships foundations ungated. Slice 1 consults this gate before UI.
    @MainActor
    static func isMetricAxisEnabled(
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(metricAxisGateKey)
    }

    /// Ordered EntryIDs for the active axis.
    /// - Time: chronological oldest → newest (matches Home V2 scrubber values).
    /// - Metric: recorded values only, ascending by value; ties by date then id.
    static func orderedEntryIDs(
        axis: TimelineAxis,
        metrics: [BodyMetrics],
        owner: String?,
        heightCm: Double? = nil
    ) -> [HomeV2TimelinePolicy.EntryID] {
        let owned = metrics.filter { !$0.isExcluded && $0.userId == owner }
        switch axis {
        case .time:
            return owned
                .sorted {
                    $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
                }
                .map(HomeV2TimelinePolicy.EntryID.init)
        case .metric(let kind):
            typealias Member = (
                id: HomeV2TimelinePolicy.EntryID, value: Double, date: Date, record: String
            )
            let members: [Member] = owned.compactMap { metric in
                guard let value = recordedValue(
                    kind, in: metric, owner: owner, heightCm: heightCm
                ) else {
                    return nil
                }
                return (HomeV2TimelinePolicy.EntryID(metric), value, metric.date, metric.id)
            }
            return members
                .sorted {
                    if $0.value != $1.value { return $0.value < $1.value }
                    if $0.date != $1.date { return $0.date < $1.date }
                    return $0.record < $1.record
                }
                .map(\.id)
        }
    }

    /// Recorded axis value only. Interpolated companions are out of Slice 0.
    static func recordedValue(
        _ kind: TimelineMetricKind,
        in metric: BodyMetrics,
        owner: String?,
        heightCm: Double?
    ) -> Double? {
        switch kind {
        case .weight:
            return HomeV2EditorialPolicy.weight(in: metric)
        case .bodyFat:
            return HomeV2EditorialPolicy.bodyFat(in: metric)?.percentage
        case .ffmi:
            return HomeV2EditorialPolicy.ffmi(in: metric, owner: owner, heightCm: heightCm)
        }
    }

    /// Keep selection when it remains a member; otherwise clamp to the nearest
    /// surviving entry by date (newer on tie), or nil when the axis is empty.
    static func clamp(
        selection: HomeV2TimelinePolicy.EntryID?,
        into ordered: [HomeV2TimelinePolicy.EntryID],
        metricsByID: [HomeV2TimelinePolicy.EntryID: BodyMetrics] = [:]
    ) -> HomeV2TimelinePolicy.EntryID? {
        guard !ordered.isEmpty else { return nil }
        guard let selection else { return ordered.last }
        if ordered.contains(selection) { return selection }

        guard let previousDate = metricsByID[selection]?.date else {
            return ordered.last
        }
        return ordered.min {
            let left = metricsByID[$0]?.date ?? .distantPast
            let right = metricsByID[$1]?.date ?? .distantPast
            let leftDelta = abs(left.timeIntervalSince(previousDate))
            let rightDelta = abs(right.timeIntervalSince(previousDate))
            if leftDelta != rightDelta { return leftDelta < rightDelta }
            return left > right
        }
    }

    /// Index of selection on the ordered axis, clamped to ends when stepping.
    static func index(
        of selection: HomeV2TimelinePolicy.EntryID?,
        in ordered: [HomeV2TimelinePolicy.EntryID]
    ) -> Int? {
        guard let selection else { return nil }
        return ordered.firstIndex(of: selection)
    }

    static func stepped(
        from selection: HomeV2TimelinePolicy.EntryID?,
        in ordered: [HomeV2TimelinePolicy.EntryID],
        forward: Bool
    ) -> HomeV2TimelinePolicy.EntryID? {
        guard !ordered.isEmpty else { return nil }
        guard let selection, let index = ordered.firstIndex(of: selection) else {
            return ordered.last
        }
        let next = forward ? index + 1 : index - 1
        guard ordered.indices.contains(next) else { return selection }
        return ordered[next]
    }
}
