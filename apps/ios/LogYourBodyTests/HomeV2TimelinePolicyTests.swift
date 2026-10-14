//
// HomeV2TimelinePolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2TimelinePolicyTests: XCTestCase {
    /// Pager and scrubber must agree: a scrubber position resolves to the same
    /// index the pager shows, oldest first regardless of bodyMetrics order.
    func testChronologicalPositionRoundTripsThroughIndexAtPosition() {
        let now = Date()
        let metrics = [
            timelineMetric(daysAgo: 0, now: now),
            timelineMetric(daysAgo: 7, now: now),
            timelineMetric(daysAgo: 21, now: now)
        ]

        let order = HomeV2TimelinePolicy.chronologicalIndices(in: metrics)
        XCTAssertEqual(order, [2, 1, 0], "Newest-first input maps to oldest-first positions")

        for (position, index) in order.enumerated() {
            XCTAssertEqual(HomeV2TimelinePolicy.chronologicalPosition(of: index, in: metrics), position)
            XCTAssertEqual(HomeV2TimelinePolicy.index(at: position, in: metrics), index)
        }
    }

    func testIndexAtPositionRejectsOutOfRangePositions() {
        let metrics = [timelineMetric(daysAgo: 0, now: Date())]
        XCTAssertNil(HomeV2TimelinePolicy.index(at: -1, in: metrics))
        XCTAssertNil(HomeV2TimelinePolicy.index(at: 1, in: metrics))
        XCTAssertNil(HomeV2TimelinePolicy.index(at: 0, in: []))
    }

    func testUnknownIndexResolvesToFirstPosition() {
        let now = Date()
        let metrics = [timelineMetric(daysAgo: 3, now: now), timelineMetric(daysAgo: 0, now: now)]
        XCTAssertEqual(HomeV2TimelinePolicy.chronologicalPosition(of: 99, in: metrics), 0)
    }

    func testInsertionAndReorderingKeepTheSelectedRecord() throws {
        let first = entry("first", day: 0), selected = entry("selected", day: 4), last = entry("last", day: 8)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [last, entry("new", day: 12), first, selected], owner: "owner")
        let result = try XCTUnwrap(snapshot.reconcile(.init(selected)))
        XCTAssertEqual(result.id, HomeV2TimelinePolicy.EntryID(selected))
        XCTAssertEqual(snapshot.metrics.map(\.id), ["new", "last", "selected", "first"])
    }

    func testDeletionChoosesNearestSurvivingDateAndNeverEmptyWhileHistoryRemains() throws {
        let removed = entry("removed", day: 4)
        let older = entry("older", day: 2), newer = entry("newer", day: 6)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [older, newer], owner: "owner")
        XCTAssertEqual(try XCTUnwrap(snapshot.reconcile(.init(removed))).id.record, "newer")
        XCTAssertEqual(snapshot.reconcile(.init(entry("last", day: 0)))?.id.record, "older")
        XCTAssertNil(HomeV2TimelinePolicy.Snapshot().reconcile(.init(removed)))
    }

    func testSameTimestampRecordsHaveStableOrderAndRemainIndividuallySelectable() throws {
        let entries = [entry("c", day: 1), entry("a", day: 1), entry("b", day: 1)]
        let first = HomeV2TimelinePolicy.Snapshot(metrics: entries, owner: "owner")
        let reordered = HomeV2TimelinePolicy.Snapshot(metrics: Array(entries.reversed()), owner: "owner")
        XCTAssertEqual(first.metrics.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(first.metrics, reordered.metrics)
        for metric in entries {
            let id = HomeV2TimelinePolicy.EntryID(metric)
            XCTAssertEqual(first.id(atChronologicalPosition: first.chronologicalPosition(for: id)), id)
        }
    }

    func testUpdatedRecordRetainsIdentityAndUsesItsNewPayload() throws {
        let original = entry("same", day: 2, bodyFat: 20, photo: "file:///original.png")
        let updated = entry("same", day: 3, bodyFat: 18, photo: "file:///updated.png")
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [updated], owner: "owner")
        let selection = try XCTUnwrap(snapshot.reconcile(.init(original)))
        XCTAssertEqual(selection.date, updated.date)
        XCTAssertEqual(snapshot.metric(for: selection.id)?.photoUrl, "file:///updated.png")
        XCTAssertEqual(snapshot.metric(for: selection.id)?.bodyFatPercentage, 18)
    }

    func testAccountReplacementCannotRetainForeignSelectionOrHistory() throws {
        let former = entry("same", day: 2)
        let other = entry("same", day: 1, owner: "other")
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [former, other], owner: "other")
        XCTAssertEqual(snapshot.metrics, [other])
        XCTAssertEqual(snapshot.reconcile(.init(former))?.id, HomeV2TimelinePolicy.EntryID(other))
        XCTAssertNil(snapshot.metric(for: HomeV2TimelinePolicy.EntryID(former)))
        XCTAssertTrue(HomeV2TimelinePolicy.Snapshot(metrics: [former, other]).metrics.isEmpty)
    }

    func testPagerAndRulerAdjustTowardTheSameChronologicalDirection() throws {
        let older = entry("older", day: 0), middle = entry("middle", day: 1), newer = entry("newer", day: 2)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [older, newer, middle], owner: "owner")
        let id = HomeV2TimelinePolicy.EntryID(middle)
        XCTAssertEqual(snapshot.adjusted(id, newer: true), HomeV2TimelinePolicy.EntryID(newer))
        XCTAssertEqual(snapshot.adjusted(id, newer: false), HomeV2TimelinePolicy.EntryID(older))
        XCTAssertNil(snapshot.adjusted(HomeV2TimelinePolicy.EntryID(newer), newer: true))
        XCTAssertNil(snapshot.adjusted(HomeV2TimelinePolicy.EntryID(older), newer: false))
        XCTAssertNil(snapshot.adjusted(HomeV2TimelinePolicy.EntryID(entry("absent", day: 1)), newer: true))
    }

    func testMissingOrInvalidSelectedBodyFatDoesNotBorrowAnotherDaysValue() {
        for value: Double? in [nil, .nan, .infinity, 0, 100] {
            let selected = entry("missing", day: 0, bodyFat: value)
            let current = entry("current", day: 30, bodyFat: 21)
            let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [current, selected], owner: "owner")
            let resolved = snapshot.metric(for: HomeV2TimelinePolicy.EntryID(selected))
            XCTAssertEqual(resolved.map(HomeV2TimelinePolicy.bodyFatSentence), "Body fat not logged for this day.")
        }
    }

    func testSelectedBodyFatRetainsEstimateProvenance() {
        let estimate = entry("estimate", day: 0, bodyFat: 19.5, method: "visual_estimate")
        XCTAssertEqual(HomeV2TimelinePolicy.bodyFatSentence(for: estimate), "Body fat 19.5% · Visual estimate")
        let typed = entry("typed", day: 0, bodyFat: 21, method: "typed")
        XCTAssertEqual(HomeV2TimelinePolicy.bodyFatSentence(for: typed), "Body fat 21.0% · Entered by you")
    }

    func testPublicationIndexAdapterNeverReadsThePreviousArrayOrder() throws {
        let selected = entry("selected", day: 4), older = entry("older", day: 2)
        let oldPublication = HomeV2TimelinePolicy.Snapshot(metrics: [selected, older], owner: "owner")
        let incoming = HomeV2TimelinePolicy.Snapshot(
            metrics: [entry("foreign", day: 8, owner: "other"), older, entry("new", day: 9), selected], owner: "owner"
        )
        let retained = try XCTUnwrap(incoming.reconcile(oldPublication.selection(atSourceIndex: 0)))
        let sourceIndex = try XCTUnwrap(incoming.sourceIndex(for: retained.id))
        XCTAssertEqual(sourceIndex, 3)
        XCTAssertEqual(incoming.selection(atSourceIndex: sourceIndex)?.id, retained.id)
        XCTAssertNil(oldPublication.selection(atSourceIndex: sourceIndex))
        XCTAssertNil(incoming.selection(atSourceIndex: 0), "Foreign rows cannot become the owned selection")
        XCTAssertEqual(incoming.selection(atSourceIndex: 1)?.id.record, "older")
    }

    func testHistoricalChangeUsesTheSelectedDatesWindowWithoutFutureWeights() throws {
        let baseline = entry("baseline", day: 0, weight: 90)
        let selected = entry("selected", day: 20, weight: 85)
        let current = entry("current", day: 80, weight: 110)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [current, selected, baseline], owner: "owner")
        let id = HomeV2TimelinePolicy.EntryID(selected)
        XCTAssertEqual(try XCTUnwrap(snapshot.weightDeltaKilograms30d(for: id)), -5)
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .metric), "Down 5.0 kg in 30 days")
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .imperial), "Down 11.0 lb in 30 days")
        XCTAssertNil(snapshot.weightDeltaKilograms30d(for: HomeV2TimelinePolicy.EntryID(current)))
    }

    func testSingleActualWeightNeverInventsAChangeFromInvalidOrFutureReadings() {
        let selected = entry("selected", day: 20, weight: nil)
        let history = [
            entry("too-old", day: -11, weight: 100), entry("zero", day: 1, weight: 0),
            entry("negative", day: 2, weight: -10), entry("nan", day: 3, weight: .nan),
            entry("infinite", day: 4, weight: .infinity), entry("only", day: 10, weight: 80),
            selected, entry("future", day: 21, weight: 75), entry("foreign", day: 19, owner: "other", weight: 90)
        ]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: history, owner: "owner")
        let id = HomeV2TimelinePolicy.EntryID(selected)
        XCTAssertNil(snapshot.weightDeltaKilograms30d(for: id))
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .metric), "No 30-day trend yet")
    }

    func testCachedChangesMatchActualWeightPolicyAtWindowAndSameDateBoundaries() {
        let history = [
            entry("a", day: 0, weight: 100), entry("b", day: 0, weight: 99),
            entry("c", day: 30, weight: 95), entry("d", day: 31, weight: nil),
            entry("e", day: 31, weight: 93), entry("f", day: 61, weight: 94)
        ]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: history, owner: "owner")
        for selected in history {
            let actual = HomeV2EditorialPolicy.weights(in: history, selected: selected)
            let expected = actual.count >= 2 ? actual.last!.kilograms - actual.first!.kilograms : nil
            XCTAssertEqual(snapshot.weightDeltaKilograms30d(for: HomeV2TimelinePolicy.EntryID(selected)), expected)
        }
    }

    func testOverflowingDisplayConversionUsesMissingTrendCopy() throws {
        let first = entry("first", day: 0, weight: 1)
        let latest = entry("latest", day: 1, weight: Double.greatestFiniteMagnitude)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [latest, first], owner: "owner")
        let id = HomeV2TimelinePolicy.EntryID(latest)
        XCTAssertTrue(try XCTUnwrap(snapshot.weightDeltaKilograms30d(for: id)).isFinite)
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .imperial), "No 30-day trend yet")
    }

    private func entry(
        _ id: String, day: Int, owner: String = "owner", weight: Double? = 80, bodyFat: Double? = nil,
        method: String? = nil, photo: String? = nil
    ) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: Double(day) * 86_400)
        return BodyMetrics(id: id, userId: owner, date: date, weight: weight, weightUnit: "kg",
                           bodyFatPercentage: bodyFat, bodyFatMethod: method, muscleMass: nil, boneMass: nil,
                           notes: nil, photoUrl: photo, dataSource: "manual", createdAt: date, updatedAt: date)
    }

    private func timelineMetric(daysAgo: Int, now: Date) -> BodyMetrics {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return BodyMetrics(
            id: "timeline-policy-\(daysAgo)",
            userId: "timeline-policy-test",
            date: date,
            localDate: BodyMetricLocalDate.key(for: date),
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
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
