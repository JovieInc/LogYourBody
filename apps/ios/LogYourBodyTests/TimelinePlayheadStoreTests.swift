//
// TimelinePlayheadStoreTests.swift
// LogYourBodyTests
//
// Slice 0: axis membership reorder/clamp + playhead store (fixtures only).
//

import XCTest
@testable import LogYourBody

@MainActor
final class TimelinePlayheadStoreTests: XCTestCase {
    private let owner = "owner"
    private let heightCm = 180.0

    // MARK: - Axis membership / reorder

    func testTimeAxisOrdersChronologicallyOldestFirst() {
        let older = entry("older", day: 0, weight: 80)
        let middle = entry("middle", day: 2, weight: 81)
        let newer = entry("newer", day: 4, weight: 82)
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .time,
            metrics: [newer, older, middle],
            owner: owner
        )
        XCTAssertEqual(ordered.map(\.record), ["older", "middle", "newer"])
    }

    func testWeightAxisIncludesRecordedOnlyAndSortsAscending() {
        let low = entry("low", day: 0, weight: 70)
        let high = entry("high", day: 1, weight: 90)
        let missing = entry("missing", day: 2, weight: nil)
        let invalid = entry("invalid", day: 3, weight: .nan)
        let mid = entry("mid", day: 4, weight: 80)
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.weight),
            metrics: [high, missing, invalid, low, mid],
            owner: owner
        )
        XCTAssertEqual(ordered.map(\.record), ["low", "mid", "high"])
    }

    func testBodyFatAxisExcludesInterpolatedMethodProvenance() {
        let recorded = entry("recorded", day: 0, bodyFat: 18)
        let interpolated = entry("interp", day: 1, bodyFat: 19, method: "interpolated")
        let derived = entry("derived", day: 2, bodyFat: 20, method: "derived_chart")
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.bodyFat),
            metrics: [interpolated, recorded, derived],
            owner: owner
        )
        XCTAssertEqual(ordered.map(\.record), ["recorded"])
    }

    func testFFMIAxisRequiresRecordedWeightBodyFatAndHeight() {
        let complete = entry("complete", day: 0, weight: 80, bodyFat: 15)
        let noFat = entry("no-fat", day: 1, weight: 80, bodyFat: nil)
        let foreign = entry("foreign", day: 2, owner: "other", weight: 80, bodyFat: 15)
        let withHeight = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.ffmi),
            metrics: [complete, noFat, foreign],
            owner: owner,
            heightCm: heightCm
        )
        XCTAssertEqual(withHeight.map(\.record), ["complete"])
        let withoutHeight = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.ffmi),
            metrics: [complete],
            owner: owner,
            heightCm: nil
        )
        XCTAssertTrue(withoutHeight.isEmpty)
    }

    func testMetricAxisTieBreaksByDateThenID() {
        let first = entry("a", day: 1, weight: 80)
        let second = entry("b", day: 1, weight: 80)
        let later = entry("c", day: 2, weight: 80)
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.weight),
            metrics: [later, second, first],
            owner: owner
        )
        XCTAssertEqual(ordered.map(\.record), ["a", "b", "c"])
    }

    // MARK: - Clamp

    func testClampKeepsSelectionWhenStillAMember() {
        let ids = ["a", "b", "c"].map { HomeV2TimelinePolicy.EntryID(entry($0, day: 0)) }
        let kept = UnifiedTimelinePolicy.clamp(selection: ids[1], into: ids)
        XCTAssertEqual(kept, ids[1])
    }

    func testClampPicksNearestByDateWhenSelectionLeavesMembership() {
        let older = entry("older", day: 0, weight: 70)
        let middle = entry("middle", day: 5, weight: 80)
        let newer = entry("newer", day: 10, weight: 90)
        let removed = entry("removed", day: 6, weight: 85)
        let ordered = UnifiedTimelinePolicy.orderedEntryIDs(
            axis: .metric(.weight),
            metrics: [older, middle, newer],
            owner: owner
        )
        let lookup = [older, middle, newer, removed].reduce(into: [:]) {
            $0[HomeV2TimelinePolicy.EntryID($1)] = $1
        }
        let clamped = UnifiedTimelinePolicy.clamp(
            selection: HomeV2TimelinePolicy.EntryID(removed),
            into: ordered,
            metricsByID: lookup
        )
        XCTAssertEqual(clamped?.record, "middle")
    }

    func testClampEmptyAxisClearsSelection() {
        XCTAssertNil(UnifiedTimelinePolicy.clamp(
            selection: HomeV2TimelinePolicy.EntryID(entry("gone", day: 0)),
            into: []
        ))
    }

    func testStepClampsAtEndsWithoutWrapping() {
        let ordered = ["a", "b", "c"].map { HomeV2TimelinePolicy.EntryID(entry($0, day: 0)) }
        XCTAssertEqual(
            UnifiedTimelinePolicy.stepped(from: ordered[0], in: ordered, forward: false)?.record,
            "a"
        )
        XCTAssertEqual(
            UnifiedTimelinePolicy.stepped(from: ordered[2], in: ordered, forward: true)?.record,
            "c"
        )
        XCTAssertEqual(
            UnifiedTimelinePolicy.stepped(from: ordered[1], in: ordered, forward: true)?.record,
            "c"
        )
    }

    // MARK: - Playhead store

    func testStoreRebuildsOrderWhenSwitchingToMetricAxis() {
        let low = entry("low", day: 0, weight: 70)
        let high = entry("high", day: 2, weight: 90)
        let store = TimelinePlayheadStore()
        store.updateContent(metrics: [high, low], owner: owner, heightCm: heightCm)
        XCTAssertEqual(store.orderedEntryIDs.map(\.record), ["low", "high"])
        store.select(HomeV2TimelinePolicy.EntryID(high))
        store.setAxis(.metric(.weight))
        XCTAssertEqual(store.orderedEntryIDs.map(\.record), ["low", "high"])
        XCTAssertEqual(store.playhead?.entryID.record, "high")
        XCTAssertEqual(store.playhead?.fractionalOffset, 0)
    }

    func testStoreClampsSelectionWhenMetricMembershipShrinks() {
        let withFat = entry("with-fat", day: 0, weight: 80, bodyFat: 18)
        let weightOnly = entry("weight-only", day: 1, weight: 82, bodyFat: nil)
        let store = TimelinePlayheadStore()
        store.updateContent(metrics: [withFat, weightOnly], owner: owner, heightCm: heightCm)
        store.select(HomeV2TimelinePolicy.EntryID(weightOnly))
        store.setAxis(.metric(.bodyFat))
        XCTAssertEqual(store.orderedEntryIDs.map(\.record), ["with-fat"])
        XCTAssertEqual(store.playhead?.entryID.record, "with-fat")
    }

    func testStoreIgnoresSelectOutsideMembership() {
        let only = entry("only", day: 0, weight: 80)
        let foreign = entry("foreign", day: 1, weight: 90)
        let store = TimelinePlayheadStore()
        store.updateContent(metrics: [only], owner: owner)
        store.select(HomeV2TimelinePolicy.EntryID(only))
        store.select(HomeV2TimelinePolicy.EntryID(foreign))
        XCTAssertEqual(store.playhead?.entryID.record, "only")
    }

    func testMetricAxisGateDefaultsOffWhenInjected() {
        XCTAssertFalse(UnifiedTimelinePolicy.isMetricAxisEnabled(isGateEnabled: { _ in false }))
        XCTAssertTrue(UnifiedTimelinePolicy.isMetricAxisEnabled(isGateEnabled: { $0 == UnifiedTimelinePolicy.metricAxisGateKey }))
    }

    func testHUDMetricKindsMatchScrubLock() {
        XCTAssertEqual(
            TimelineMetricKind.allCases.map(\.rawValue),
            ["ffmi", "weight", "bodyFat"]
        )
        XCTAssertEqual(TimelinePhotoScrubLock.visibleMetricTitles, ["FFMI", "Weight", "Body Fat"])
    }

    // MARK: - Fixtures

    private func entry(
        _ id: String,
        day: Int,
        owner: String? = nil,
        weight: Double? = 80,
        bodyFat: Double? = nil,
        method: String? = nil
    ) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        return BodyMetrics(
            id: id,
            userId: owner ?? self.owner,
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: method,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}
