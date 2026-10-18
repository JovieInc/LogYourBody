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

    func testMeasuredBodyFatWinsAndKeepsItsOwnFFMI() {
        let selected = entry("today", day: 7, weight: 82.1, bodyFat: 15.8, method: "manual")
        let history = [entry("older", day: 0, bodyFat: 10, method: "manual"), selected,
                       entry("newer", day: 14, bodyFat: 30, method: "manual")]
        let moment = HomeV2SelectedMomentPolicy.presentation(for: selected, in: history)
        XCTAssertEqual(moment.kind, .measured)
        XCTAssertEqual(moment.sentence, HomeV2TimelinePolicy.bodyFatSentence(for: selected))
        XCTAssertFalse(moment.sentence.contains("Inferred"))
        XCTAssertEqual(HomeV2SelectedMomentPolicy.sentence(for: selected, in: history), moment.sentence)
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.displayFFMI(for: selected, in: history, owner: "owner", heightCm: 178),
            HomeV2EditorialPolicy.ffmi(in: selected, owner: "owner", heightCm: 178)
        )
    }

    func testBracketedBodyFatIsTimeWeightedLabeledAndNotStored() throws {
        let older = entry("older", day: 0, weight: 84, bodyFat: 16.9, method: "bodyspec_dexa")
        let selected = entry("selected", day: 7, weight: 83.4)
        let newer = entry("newer", day: 14, weight: 82.8, bodyFat: 16.2, method: "healthkit")
        let history = [newer, selected, older]
        let moment = HomeV2SelectedMomentPolicy.presentation(for: selected, in: history)
        XCTAssertEqual(moment.kind, .inferred)
        XCTAssertEqual(moment.sentence, "Inferred body fat 16.6%.")
        XCTAssertEqual(moment.percentage ?? 0, 16.55, accuracy: 0.0001)
        XCTAssertNil(selected.bodyFatPercentage)
        XCTAssertEqual(moment.older?.id, "older")
        XCTAssertEqual(moment.newer?.id, "newer")
        let ffmi = try XCTUnwrap(HomeV2SelectedMomentPolicy.displayFFMI(
            for: selected, in: history, owner: "owner", heightCm: 178
        ))
        XCTAssertEqual(String(format: "%.1f", ffmi), "22.1")
        XCTAssertNil(HomeV2SelectedMomentPolicy.displayFFMI(
            for: selected, in: history, owner: "other", heightCm: 178
        ))
        XCTAssertNil(HomeV2SelectedMomentPolicy.displayFFMI(
            for: selected, in: history, owner: "owner", heightCm: nil
        ))
        let detail = try XCTUnwrap(HomeV2MetricEditorial.timelineProvenance(
            for: selected, in: history, heightCm: 178
        ))
        XCTAssertEqual(detail.chip, "Inferred")
        XCTAssertTrue(detail.body.contains("Weight is from"))
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        for token in [formatter.string(from: older.date), formatter.string(from: newer.date),
                      "16.90 %", "16.20 %", "From your DEXA scan", "From Apple Health", "178"] {
            XCTAssertTrue(detail.body.contains(token), token)
        }
        let fractional = HomeV2SelectedMomentPolicy.provenanceSentence(for: moment, heightCm: 178.4)
        XCTAssertTrue(fractional.contains("178.4"))
        XCTAssertTrue(HomeV2SelectedMomentPolicy.provenanceSentence(for: moment, heightCm: nil).contains("not recorded"))
        XCTAssertTrue(
            HomeV2SelectedMomentPolicy.provenanceSentence(for: moment, heightCm: .nan).contains("not recorded")
        )
        let missing = HomeV2SelectedMomentPolicy.presentation(for: entry("none", day: 1), in: [])
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.provenanceSentence(for: missing, heightCm: 178), missing.sentence
        )
    }

    func testBodyFatStopsAtBracketsAndIgnoresForeignOrSyntheticAnchors() {
        let older = entry("older", day: 0, bodyFat: 10, method: "manual")
        let second = entry("second", day: 10, bodyFat: 30, method: "manual")
        let after = entry("after", day: 20, weight: 80)
        let history = [older, second, after]
        let lastKnown = HomeV2SelectedMomentPolicy.presentation(for: after, in: history)
        XCTAssertEqual(lastKnown.kind, .lastKnown)
        XCTAssertTrue(lastKnown.sentence.contains("30"))
        XCTAssertFalse(lastKnown.sentence.contains("Inferred"))
        XCTAssertFalse(lastKnown.sentence.contains("50"))
        XCTAssertNil(HomeV2SelectedMomentPolicy.displayFFMI(
            for: after, in: history, owner: "owner", heightCm: 178
        ))
        let detail = HomeV2MetricEditorial.timelineProvenance(for: after, in: history, heightCm: 178)
        XCTAssertNotEqual(detail?.chip, "Inferred")
        XCTAssertTrue(detail?.body.contains("Last known") == true)
        XCTAssertFalse(detail?.body.contains("Inferred") == true)

        let before = entry("before", day: -5)
        let futureOnly = [before, entry("later", day: 30, bodyFat: 21, method: "manual")]
        let unavailable = HomeV2SelectedMomentPolicy.presentation(for: before, in: futureOnly)
        XCTAssertEqual(unavailable.kind, .unavailable)
        XCTAssertEqual(unavailable.sentence, "Body fat not logged for this day.")

        let wide = HomeV2SelectedMomentPolicy.presentation(
            for: entry("middle", day: 50, weight: 80),
            in: [entry("early", day: 0, bodyFat: 10, method: "manual"),
                 entry("late", day: 100, bodyFat: 20, method: "manual")]
        )
        XCTAssertEqual(wide.kind, .inferred)
        XCTAssertEqual(wide.sentence, "Inferred body fat 15.0%.")
        let flagged = HomeV2SelectedMomentPolicy.presentation(
            for: entry("between", day: 7, weight: 83.4),
            in: [entry("low", day: 0, weight: 1, bodyFat: 10, method: "manual"),
                 entry("high", day: 14, weight: 1, bodyFat: 20, method: "manual")]
        )
        XCTAssertEqual(flagged.kind, .inferred)
        XCTAssertEqual(flagged.sentence, "Inferred body fat 15.0%.")

        let selected = entry("selected", day: 10, weight: 80)
        let synthetic = entry("synthetic", day: 8, bodyFat: 50, method: "interpolated estimate")
        let twin = entry("twin", day: 10, bodyFat: 12, method: "manual")
        let foreign = entry("foreign", day: 9, owner: "other", bodyFat: 40, method: "manual")
        let later = entry("later", day: 20, bodyFat: 20, method: "manual")
        let bracket = HomeV2SelectedMomentPolicy.presentation(
            for: selected, in: [older, synthetic, foreign, twin, selected, later]
        )
        XCTAssertEqual(bracket.kind, .inferred)
        XCTAssertEqual(bracket.older?.id, "older")
        XCTAssertEqual(bracket.newer?.id, "later")
        XCTAssertFalse(bracket.sentence.contains("50"))
        XCTAssertFalse(bracket.sentence.contains("12"))
        let alone = HomeV2SelectedMomentPolicy.presentation(for: selected, in: [selected, twin])
        XCTAssertEqual(alone.kind, .unavailable)
    }

    func testInterpolationRejectsFlatSpansEdgesAndNonFiniteValues() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 86_400)
        XCTAssertNil(HomeV2SelectedMomentPolicy.interpolatedBodyFat(
            olderDate: start, olderValue: 10, newerDate: start, newerValue: 20, at: start
        ))
        XCTAssertNil(HomeV2SelectedMomentPolicy.interpolatedBodyFat(
            olderDate: start, olderValue: 10, newerDate: end, newerValue: 20, at: start
        ))
        XCTAssertNil(HomeV2SelectedMomentPolicy.interpolatedBodyFat(
            olderDate: start, olderValue: 10, newerDate: end, newerValue: 20, at: end
        ))
        XCTAssertNil(HomeV2SelectedMomentPolicy.interpolatedBodyFat(
            olderDate: start, olderValue: 0, newerDate: end, newerValue: 0, at: start.addingTimeInterval(43_200)
        ))
        XCTAssertNil(HomeV2SelectedMomentPolicy.interpolatedBodyFat(
            olderDate: start, olderValue: .nan, newerDate: end, newerValue: 20, at: start.addingTimeInterval(43_200)
        ))
        let older = entry("older", day: 0, bodyFat: 10, method: "manual")
        let newer = entry("newer", day: 0, bodyFat: 20, method: "manual")
        let reading = HomeV2EditorialPolicy.BodyFatReading(percentage: 10, caption: "Entered by you")
        XCTAssertNil(HomeV2SelectedMomentPolicy.inferredPresentation(
            selected: entry("selected", day: 0),
            older: HomeV2SelectedMomentPolicy.Anchor(metric: older, reading: reading),
            newer: HomeV2SelectedMomentPolicy.Anchor(metric: newer, reading: reading)
        ))
    }

    func testNearestPhotoKeepsItsOwnCaptureAndBreaksTiesTowardNewerThenSmallerId() {
        let selected = entry("selected", day: 10)
        let nearer = entry("near", day: 11, photo: "file:///near.jpg")
        let farther = entry("far", day: 0, photo: "file:///far.jpg")
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.displayPhoto(for: selected, in: [selected, nearer, farther])?.id, "near"
        )
        let olderTie = entry("older-tie", day: 8, photo: "file:///older.jpg")
        let newerTie = entry("newer-tie", day: 12, photo: "file:///newer.jpg")
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.displayPhoto(for: selected, in: [olderTie, newerTie])?.id, "newer-tie"
        )
        let lowId = entry("a", day: 10, photo: "file:///a.jpg")
        let highId = entry("b", day: 10, photo: "file:///b.jpg")
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.displayPhoto(for: selected, in: [highId, lowId])?.id, "a"
        )
        let own = entry("own", day: 10, photo: "file:///own.jpg")
        XCTAssertEqual(HomeV2SelectedMomentPolicy.displayPhoto(for: own, in: [own, nearer])?.id, "own")
        let blank = entry("blank", day: 10, photo: "   ")
        let foreign = entry("foreign", day: 10, owner: "other", photo: "file:///foreign.jpg")
        XCTAssertEqual(
            HomeV2SelectedMomentPolicy.displayPhoto(for: selected, in: [blank, foreign, farther])?.id, "far"
        )
        XCTAssertNil(HomeV2SelectedMomentPolicy.displayPhoto(for: selected, in: [selected, blank]))
        let withPhoto = HomeV2TimelinePolicy.Snapshot(metrics: [selected, nearer], owner: "owner")
        XCTAssertEqual(withPhoto.photoCaptionDate(for: selected).id, "near")
        let bare = entry("bare", day: 3)
        let withoutPhoto = HomeV2TimelinePolicy.Snapshot(metrics: [bare], owner: "owner")
        XCTAssertEqual(withoutPhoto.photoCaptionDate(for: bare).id, "bare")
    }

    func testAnchorOrderUsesTheLaterBoundaryThenTheSmallerIdentifier() {
        let selected = entry("selected", day: 10, weight: 80)
        let earlyHigh = entry("b", day: 0, bodyFat: 10, method: "manual")
        let earlyLow = entry("a", day: 0, bodyFat: 12, method: "manual")
        let laterOlder = entry("c", day: 5, bodyFat: 20, method: "manual")
        let newerHigh = entry("z", day: 20, bodyFat: 30, method: "manual")
        let newerLow = entry("m", day: 20, bodyFat: 40, method: "manual")
        let distant = entry("q", day: 30, bodyFat: 50, method: "manual")
        let moment = HomeV2SelectedMomentPolicy.presentation(
            for: selected, in: [earlyHigh, earlyLow, laterOlder, selected, newerHigh, newerLow, distant]
        )
        XCTAssertEqual(moment.older?.id, "c")
        XCTAssertEqual(moment.newer?.id, "m")
        XCTAssertEqual(moment.kind, .inferred)
    }

    func testUnsupportedWeightsUseMissingTrendCopy() {
        let first = entry("first", day: 0, weight: 1)
        let latest = entry("latest", day: 1, weight: Double.greatestFiniteMagnitude)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [latest, first], owner: "owner")
        let id = HomeV2TimelinePolicy.EntryID(latest)
        XCTAssertNil(snapshot.weightDeltaKilograms30d(for: id))
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
