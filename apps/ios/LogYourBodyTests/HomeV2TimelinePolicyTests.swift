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
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [last, entry("new", day: 12), first, selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let result = try XCTUnwrap(snapshot.reconcile(.init(selected)))
        XCTAssertEqual(result.id, HomeV2TimelinePolicy.EntryID(selected))
        XCTAssertEqual(snapshot.metrics.map(\.id), ["new", "last", "selected", "first"])
    }

    func testDeletionChoosesNearestSurvivingDateAndNeverEmptyWhileHistoryRemains() throws {
        let removed = entry("removed", day: 4)
        let older = entry("older", day: 2), newer = entry("newer", day: 6)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [older, newer],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertEqual(try XCTUnwrap(snapshot.reconcile(.init(removed))).id.record, "newer")
        XCTAssertEqual(snapshot.reconcile(.init(entry("last", day: 0)))?.id.record, "older")
        XCTAssertNil(HomeV2TimelinePolicy.Snapshot().reconcile(.init(removed)))
    }

    func testSameTimestampRecordsHaveStableOrderAndRemainIndividuallySelectable() throws {
        let entries = [entry("c", day: 1), entry("a", day: 1), entry("b", day: 1)]
        let first = HomeV2TimelinePolicy.Snapshot(
            metrics: entries,
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let reordered = HomeV2TimelinePolicy.Snapshot(
            metrics: Array(entries.reversed()),
            owner: "owner",
            ownership: selectedMomentOwnership
        )
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
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [updated],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let selection = try XCTUnwrap(snapshot.reconcile(.init(original)))
        XCTAssertEqual(selection.date, updated.date)
        XCTAssertEqual(snapshot.metric(for: selection.id)?.photoUrl, "file:///updated.png")
        XCTAssertEqual(snapshot.metric(for: selection.id)?.bodyFatPercentage, 18)
    }

    func testAccountReplacementCannotRetainForeignSelectionOrHistory() throws {
        let former = entry("same", day: 2)
        let other = entry("same", day: 1, owner: "other")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [former, other],
            owner: "other",
            ownership: .init(subject: "other", generation: 1)
        )
        XCTAssertEqual(snapshot.metrics, [other])
        XCTAssertEqual(snapshot.reconcile(.init(former))?.id, HomeV2TimelinePolicy.EntryID(other))
        XCTAssertNil(snapshot.metric(for: HomeV2TimelinePolicy.EntryID(former)))
        XCTAssertTrue(HomeV2TimelinePolicy.Snapshot(
            metrics: [former, other]
        ).metrics.isEmpty)
    }

    func testPagerAndRulerAdjustTowardTheSameChronologicalDirection() throws {
        let older = entry("older", day: 0), middle = entry("middle", day: 1), newer = entry("newer", day: 2)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [older, newer, middle],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
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
            let snapshot = HomeV2TimelinePolicy.Snapshot(
                metrics: [current, selected],
                owner: "owner",
                ownership: selectedMomentOwnership
            )
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
        let oldPublication = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected, older],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let incoming = HomeV2TimelinePolicy.Snapshot(
            metrics: [entry("foreign", day: 8, owner: "other"), older, entry("new", day: 9), selected],
            owner: "owner",
            ownership: selectedMomentOwnership
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
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [current, selected, baseline],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
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
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: history,
            owner: "owner",
            ownership: selectedMomentOwnership
        )
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
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: history,
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        for selected in history {
            let actual = HomeV2EditorialPolicy.weights(in: history, selected: selected)
            let expected = actual.count >= 2 ? actual.last!.kilograms - actual.first!.kilograms : nil
            XCTAssertEqual(snapshot.weightDeltaKilograms30d(for: HomeV2TimelinePolicy.EntryID(selected)), expected)
        }
    }

    func testOverflowingDisplayConversionUsesMissingTrendCopy() throws {
        let first = entry("first", day: 0, weight: 1)
        let latest = entry("latest", day: 1, weight: Double.greatestFiniteMagnitude)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [latest, first],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let id = HomeV2TimelinePolicy.EntryID(latest)
        XCTAssertNil(snapshot.weightDeltaKilograms30d(for: id))
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .imperial), "No 30-day trend yet")
    }

    func testUnsupportedWeightsUseMissingTrendCopy() {
        let first = entry("first", day: 0, weight: 1)
        let latest = entry("latest", day: 1, weight: Double.greatestFiniteMagnitude)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [latest, first],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let id = HomeV2TimelinePolicy.EntryID(latest)
        XCTAssertNil(snapshot.weightDeltaKilograms30d(for: id))
        XCTAssertEqual(snapshot.weightChangeSentence(for: id, system: .imperial), "No 30-day trend yet")
    }

    func testSelectedMomentUsesExactWeightAndCanonicalDerivedFFMI() throws {
        let metric = moment("selected", seconds: 10, weight: 80, bodyFat: 20, method: "dexa")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [moment("before", seconds: 0, weight: 100), metric,
                      moment("after", seconds: 20, weight: 120)],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(metric),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(value.weight?.amount, 80)
        XCTAssertEqual(value.weight?.kind, .recorded)
        XCTAssertEqual(value.bodyFat?.source, "From your DEXA scan")
        XCTAssertEqual(try XCTUnwrap(value.ffmi).amount, 19.753086419753, accuracy: 0.000001)
        XCTAssertEqual(value.ffmi?.kind, .derived)
        XCTAssertEqual(value.ffmi?.usesInference, false)
        XCTAssertTrue(value.provenance.body.contains("derived from recorded weight 80.00 kg"))
        XCTAssertTrue(value.provenance.body.contains("recorded body fat 20.00 % (From your DEXA scan)"))
        XCTAssertTrue(value.provenance.body.contains("180.00 cm profile height"))
        XCTAssertFalse(try XCTUnwrap(value.ffmi).explanation("FFMI").contains("measured"))
    }

    func testSelectedMomentInterpolatesEachMissingFieldByElapsedTime() throws {
        let selected = moment("selected", seconds: 25)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [
                moment("both-before", seconds: 0, weight: 80, bodyFat: 10),
                selected, moment("weight-after", seconds: 100, weight: 100),
                moment("fat-after", seconds: 200, bodyFat: 30)
            ],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(try XCTUnwrap(value.weight).amount, 85, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(value.bodyFat).amount, 12.5, accuracy: 0.000001)
        XCTAssertEqual(value.weight?.kind, .inferred)
        XCTAssertEqual(value.weight?.anchors.map(\.amount), [80, 100])
        XCTAssertEqual(value.bodyFat?.anchors.map(\.amount), [10, 30])
        XCTAssertEqual(value.weight?.anchors.map(\.unit), ["kg", "kg"])
        XCTAssertEqual(value.bodyFat?.anchors.map(\.unit), ["%", "%"])
        XCTAssertTrue(value.provenance.body.contains("80.00 kg"))
        XCTAssertTrue(value.provenance.body.contains("30.00 %"))
        XCTAssertTrue(value.provenance.body.contains("Entered by you") || value.provenance.body.contains("Manual"))
        XCTAssertEqual(value.bodyFat?.anchors.map(\.id.record), ["both-before", "fat-after"])
        XCTAssertEqual(value.weight?.anchors.map(\.id.record), ["both-before", "weight-after"])
        XCTAssertEqual(value.ffmi?.kind, .derived)
        XCTAssertEqual(value.ffmi?.usesInference, true)
        XCTAssertTrue(value.provenance.body.contains("inferred between"))
        let ffmiDetail = try XCTUnwrap(value.ffmi).explanation("FFMI")
        XCTAssertTrue(ffmiDetail.contains("inferred weight 85.00 kg (Time-weighted interpolation)"))
        XCTAssertTrue(ffmiDetail.contains("inferred body fat 12.50 % (Time-weighted interpolation)"))
        XCTAssertTrue(ffmiDetail.contains("180.00 cm profile height"))
        XCTAssertFalse(ffmiDetail.contains("measured"))
    }

    func testSelectedMomentDoesNotTreatEarlierSameDayReadingAsExact() throws {
        // Both endpoints are on the same local day, including the repeated DST hour.
        let selected = moment("selected", seconds: 1_800)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [
                moment("before", seconds: 0, weight: 80), selected,
                moment("after", seconds: 3_600, weight: 90)
            ],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.weight)
        XCTAssertEqual(value.amount, 85, accuracy: 0.000001)
        XCTAssertEqual(value.kind, .inferred)
        XCTAssertEqual(value.anchors.last?.date.timeIntervalSince(value.anchors[0].date), 3_600)
    }

    func testSelectedMomentBeforeAfterAndSingleAnchorRemainMissing() throws {
        for seconds in [-1.0, 21.0] {
            let selected = moment("selected", seconds: seconds)
            let snapshot = HomeV2TimelinePolicy.Snapshot(
                metrics: [
                    selected, moment("first", seconds: 0, weight: 80, bodyFat: 20),
                    moment("last", seconds: 20, weight: 90, bodyFat: 25)
                ],
                owner: "owner",
                ownership: selectedMomentOwnership
            )
            let value = try XCTUnwrap(snapshot.presentation(
                for: .init(selected),
                heightCm: 180,
                currentOwnership: selectedMomentOwnership
            ))
            XCTAssertNil(value.weight)
            XCTAssertNil(value.bodyFat)
            XCTAssertNil(value.ffmi)
        }
        let selected = moment("selected", seconds: 10)
        let single = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected, moment("only", seconds: 0, weight: 80)],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertNil(single.presentation(
            for: .init(selected),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        )?.weight)
    }

    func testSelectedMomentRejectsForeignOwnerAndReplacementGeneration() throws {
        let first = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let replacement = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 2)
        let foreign = AuthManager.ProfileSessionOwnership(subject: "other", generation: 1)
        let selected = moment("selected", seconds: 10, weight: 80)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected, moment("foreign", seconds: 10, weight: 1, owner: "other")],
            owner: "owner",
            ownership: first
        )
        XCTAssertTrue(snapshot.isOwned(by: first))
        XCTAssertFalse(snapshot.isOwned(by: replacement))
        XCTAssertFalse(snapshot.isOwned(by: nil))
        XCTAssertNotNil(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: first
        ))
        XCTAssertNil(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: replacement
        ))
        XCTAssertNil(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: foreign
        ))
        XCTAssertNil(snapshot.presentation(
            for: .init(selected),
            heightCm: nil
        ))
        let mismatched = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected],
            owner: "owner",
            ownership: foreign
        )
        XCTAssertTrue(mismatched.metrics.isEmpty)
            let unowned = HomeV2TimelinePolicy.Snapshot(
                metrics: [selected],
                owner: "owner"
            )
        XCTAssertNil(unowned.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: nil
        ))
    }

    func testSelectedMomentExcludesFlaggedWeightFromInferenceAndFFMI() throws {
        let flagged = moment("flagged", seconds: 5, weight: 18, bodyFat: 20)
        let selected = moment("selected", seconds: 10)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [
                moment("valid-before", seconds: 0, weight: 80), flagged, selected,
                moment("valid-after", seconds: 20, weight: 100)
            ],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.weight)
        XCTAssertEqual(value.amount, 90, accuracy: 0.000001)
        XCTAssertEqual(value.anchors.map(\.id.record), ["valid-before", "valid-after"])
        let raw = try XCTUnwrap(snapshot.presentation(
            for: .init(flagged),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(raw.weight?.amount, 18)
        XCTAssertEqual(raw.weight?.kind, .recorded)
        XCTAssertNil(raw.ffmi)
        XCTAssertEqual(snapshot.metric(for: .init(flagged))?.weight, 18)
    }

    func testSelectedMomentNearestPhotoKeepsActualDateAndStableTie() throws {
        let selected = moment("selected", seconds: 10)
        let newer = moment("newer-z", seconds: 20, photo: "https://photos.example/newer")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [
                moment("older", seconds: 0, photo: "https://photos.example/older"), selected,
                moment("newer-a", seconds: 20, photo: "https://photos.example/duplicate"), newer,
                moment("foreign", seconds: 10, photo: "https://photos.example/foreign", owner: "other")
            ],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let result = try XCTUnwrap(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(result.photo?.id, newer.id)
        XCTAssertEqual(result.photo?.date, newer.date)
        XCTAssertEqual(result.selection.date, selected.date)
        XCTAssertNotEqual(result.photo?.date, result.selection.date)
        XCTAssertEqual(snapshot.reconcile(result.selection)?.id, .init(selected))
    }

    func testSelectedMomentPreservesExactPhotoAmongTimestampDuplicates() throws {
        let selected = moment("photo-a", seconds: 10, photo: "https://photos.example/selected")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [
                selected, moment("photo-z", seconds: 10, photo: "https://photos.example/other")
            ],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertEqual(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.photo?.id, selected.id)
    }

    func testSelectedMomentResolverDoesNotMutateSourceRecords() throws {
        let selected = moment("photo-only", seconds: 10, photo: "https://photos.example/photo")
        let history = [moment("first", seconds: 0, weight: 80, bodyFat: 20), selected,
                       moment("last", seconds: 20, weight: 100, bodyFat: 30)]
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: history,
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let before = snapshot.metrics
        for _ in 0..<20 {
            let value = try XCTUnwrap(snapshot.presentation(
                for: .init(selected),
                heightCm: 180,
                currentOwnership: selectedMomentOwnership
            ))
            XCTAssertEqual(value.weight?.kind, .inferred)
        }
        XCTAssertEqual(snapshot.metrics, before)
        XCTAssertEqual(history[1], selected)
        XCTAssertNil(snapshot.metric(for: .init(selected))?.weight)
        XCTAssertNil(snapshot.metric(for: .init(selected))?.bodyFatPercentage)
        XCTAssertNil(snapshot.metric(for: .init(selected))?.bodyFatMethod)
    }

    func testSelectedMomentClearsUnavailableValuesAfterValidSelection() throws {
        let recorded = moment("recorded", seconds: 0, weight: 80, bodyFat: 20)
        let missing = moment("missing", seconds: 10)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [recorded, missing],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertNotNil(snapshot.presentation(
            for: .init(recorded),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        )?.ffmi)
        let next = try XCTUnwrap(snapshot.presentation(
            for: .init(missing),
            heightCm: 180,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertNil(next.weight)
        XCTAssertNil(next.bodyFat)
        XCTAssertNil(next.ffmi)
        XCTAssertTrue(next.provenance.body.contains("unavailable at this time"))
    }

    func testSelectedMomentReconcilesDeletedPhotoWithoutSubstitutingDate() throws {
        let selected = moment("selected", seconds: 10, weight: 80)
        let photo = moment("photo", seconds: 11, photo: "https://photos.example/photo")
        let initial = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected, photo],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let original = try XCTUnwrap(initial.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(original.photo?.id, photo.id)
        let incoming = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let retained = try XCTUnwrap(incoming.reconcile(original.selection))
        let value = try XCTUnwrap(incoming.presentation(
            for: retained,
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(value.selection, original.selection)
        XCTAssertNil(value.photo)
        XCTAssertEqual(value.weight?.amount, 80)
        XCTAssertNil(incoming.presentation(
            for: .init(photo),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        ))
    }

    func testSelectedMomentKeepsBodyFatMethodAndRejectsPersistedInferredAnchor() throws {
        let selected = moment("selected", seconds: 10, bodyFat: 20, method: "visual_estimate")
        let recorded = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let raw = try XCTUnwrap(recorded.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.bodyFat)
        XCTAssertEqual(raw.kind, .recorded)
        XCTAssertEqual(raw.source, "Visual estimate")
        let missing = moment("missing", seconds: 15)
        let invalidAnchor = moment("stored-inference", seconds: 20, bodyFat: 30, method: "interpolated")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected, missing, invalidAnchor],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertNil(snapshot.presentation(
            for: .init(missing),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.bodyFat)
    }

    func testSelectedMomentImperialOverflowKeepsRawRecordAndFiniteDisplay() throws {
        let selected = moment("huge", seconds: 0, weight: .greatestFiniteMagnitude)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(value.weight?.amount, .greatestFiniteMagnitude)
        XCTAssertEqual(snapshot.metric(for: .init(selected))?.weight, .greatestFiniteMagnitude)
        XCTAssertEqual(value.weightText(in: .imperial), "–")
        XCTAssertFalse(value.weightText(in: .imperial).lowercased().contains("inf"))
        let ordinary = moment("ordinary", seconds: 1, weight: 18)
        let raw = HomeV2TimelinePolicy.Snapshot(
            metrics: [ordinary],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertEqual(raw.presentation(
            for: .init(ordinary),
            heightCm: nil,
            currentOwnership: selectedMomentOwnership
        )?.weightText(in: .metric), "18.0")
    }

    @MainActor
    func testSelectedMomentChartFocusIsVisibleAndAccessible() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let selected = base.addingTimeInterval(86_400 * 10)
        let chart = HomeV2TrendChart(
            daily: [MetricChartDataPoint(date: base.addingTimeInterval(86_400 * 8), value: 80),
                    MetricChartDataPoint(date: base.addingTimeInterval(86_400 * 9), value: 81)],
            trend: [], accent: .primary, range: .constant(.all), usesSevenDayAverage: false,
            requiresMinimumDays: false, allowsSelection: false, selectedMoment: selected,
            selectedMomentValue: 100.5, selectedMomentProvenance: "Inferred", now: selected
        )
        XCTAssertTrue(chart.selectionDomain.contains(100.5), "The actual mounted consumer domain must contain its focus")
        XCTAssertLessThan(chart.selectionDomain.lowerBound, 80)
        XCTAssertTrue(chart.accessibilityValueText.contains("100.5"))
        XCTAssertTrue(chart.accessibilityValueText.contains("Inferred"))
        XCTAssertTrue(chart.accessibilityValueText.contains(selected.formatted(date: .complete, time: .shortened)))
    }

    func testSelectedMomentPreservesBodyFatOnlyAndFlaggedWeightBodyFatAnchors() throws {
        let origin = Date(timeIntervalSince1970: 1_793_521_800)
        func imported(_ id: String, hours: Double, weight: Double?, fat: Double?, method: String?) -> BodyMetrics {
            let date = origin.addingTimeInterval(hours * 3_600)
            return BodyMetrics(
                id: id, userId: "owner", date: date, weight: weight, weightUnit: "kg",
                bodyFatPercentage: fat, bodyFatMethod: method, muscleMass: nil, boneMass: nil,
                notes: "Imported source retained", photoUrl: nil, dataSource: "healthkit",
                sourceMetadata: BodyMetricSourceMetadata(
                    vendor: "healthkit", sourceName: "Synthetic health source",
                    sourceBundleId: "com.example.synthetic-health", sampleId: "sample-" + id,
                    quantityType: "HKQuantityTypeIdentifierBodyFatPercentage", bodyFatSampleId: "fat-" + id
                ), createdAt: date, updatedAt: date
            )
        }
        let history = [
            imported("weight-before", hours: 0, weight: 80, fat: nil, method: nil),
            imported("fat-before", hours: 1, weight: nil, fat: 16.9, method: "healthkit"),
            imported("selected", hours: 2, weight: nil, fat: nil, method: nil),
            imported("flagged-fat-after", hours: 3, weight: 18, fat: 16.2, method: "dexa"),
            imported("weight-after", hours: 4, weight: 84, fat: nil, method: nil)
        ]
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: history,
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let selected = try XCTUnwrap(snapshot.presentation(
            for: .init(history[2]),
            heightCm: 178,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(try XCTUnwrap(selected.weight).amount, 82, accuracy: 0.000001)
        XCTAssertEqual(selected.weight?.anchors.map(\.id.record), ["weight-before", "weight-after"])
        XCTAssertEqual(try XCTUnwrap(selected.bodyFat).amount, 16.55, accuracy: 0.000001)
        XCTAssertEqual(selected.bodyFat?.anchors.map(\.id.record), ["fat-before", "flagged-fat-after"])
        XCTAssertEqual(selected.bodyFat?.anchors.map(\.source), ["From Apple Health", "From your DEXA scan"])
        // Independently specified: 82*(1-16.55/100)/(1.78*1.78)+6.1*(1.8-1.78).
        XCTAssertEqual(try XCTUnwrap(selected.ffmi).amount, 21.71933619492488, accuracy: 0.000001)
        for index in [1, 3] {
            let exact = try XCTUnwrap(snapshot.presentation(
                for: .init(history[index]),
                heightCm: 178,
                currentOwnership: selectedMomentOwnership
            ))
            XCTAssertEqual(exact.bodyFat?.amount, history[index].bodyFatPercentage)
            XCTAssertEqual(exact.bodyFat?.kind, .recorded)
            XCTAssertEqual(snapshot.metric(for: .init(history[index])), history[index])
        }
        let rawFlagged = try XCTUnwrap(snapshot.presentation(
            for: .init(history[3]),
            heightCm: 178,
            currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(rawFlagged.weight?.amount, 18)
        XCTAssertNil(rawFlagged.ffmi)
        XCTAssertNil(history[1].weight)
        XCTAssertEqual(history[3].weight, 18)
        XCTAssertEqual(history[1].bodyFatMethod, "healthkit")
        XCTAssertEqual(history[3].sourceMetadata?.bodyFatSampleId, "fat-flagged-fat-after")
    }

    func testSnapshotRejectsMissingOwnershipBeforeRecordAndPhotoEligibility() {
        let owned = moment("photo", seconds: 0, weight: 18, bodyFat: 16.2,
                           method: "healthkit", photo: "file:///synthetic-owned-photo.png")
        let blankOwner = moment("blank-owner", seconds: 0, photo: "file:///synthetic-blank.png", owner: "")
        let rejected = [
            HomeV2TimelinePolicy.Snapshot(
                metrics: [owned, blankOwner]
            ),
            HomeV2TimelinePolicy.Snapshot(
                metrics: [owned],
                owner: "owner"
            ),
            HomeV2TimelinePolicy.Snapshot(
                metrics: [owned],
                ownership: selectedMomentOwnership
            ),
            HomeV2TimelinePolicy.Snapshot(
                metrics: [blankOwner],
                owner: "",
                ownership: .init(subject: "", generation: 1)
            ),
            HomeV2TimelinePolicy.Snapshot(
                metrics: [owned],
                owner: "owner",
                ownership: .init(subject: "other", generation: 1)
            )
        ]
        for snapshot in rejected {
            XCTAssertTrue(snapshot.metrics.isEmpty)
            XCTAssertTrue(snapshot.chronologicalDates.isEmpty)
            XCTAssertNil(snapshot.metric(for: .init(owned)))
            XCTAssertNil(snapshot.selection(atSourceIndex: 0))
            XCTAssertFalse(snapshot.isOwned(by: selectedMomentOwnership))
            XCTAssertNil(snapshot.presentation(
                for: .init(owned),
                heightCm: 178,
                currentOwnership: nil
            ))
        }
        let admitted = HomeV2TimelinePolicy.Snapshot(
            metrics: [owned, blankOwner],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        XCTAssertEqual(admitted.metrics, [owned])
        XCTAssertTrue(admitted.isOwned(by: selectedMomentOwnership))
        XCTAssertEqual(admitted.metric(for: .init(owned)), owned)
        XCTAssertEqual(admitted.presentation(
            for: .init(owned),
            heightCm: 178,
            currentOwnership: selectedMomentOwnership
        )?.photo?.id, owned.id)
    }

    func testPhotoImageAdmissionRejectsLiveSelectionURLAndSourceReplacement() throws {
        let selected = moment("selected", seconds: 10, weight: 83.4)
        let photo = moment("photo", seconds: 0, photo: "file:///old-synthetic.png")
        let rows = [selected, photo]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: rows, owner: "owner", ownership: selectedMomentOwnership)
        let presentation = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: nil, currentOwnership: selectedMomentOwnership
        ))
        func admitted(_ current: [BodyMetrics], _ selectedMoment: HomeV2TimelinePolicy.Selection?,
                      _ receipt: AuthManager.ProfileSessionOwnership? = nil) -> Bool {
            snapshot.admitsPhotoPresentation(
                presentation, selected: selectedMoment, currentOwnership: receipt ?? selectedMomentOwnership,
                currentMetrics: current, currentSnapshot: snapshot
            )
        }
        XCTAssertTrue(admitted(rows, .init(selected)))
        XCTAssertTrue(admitted(Array(rows.reversed()), .init(selected)), "Order alone does not change records")
        XCTAssertFalse(admitted(rows, .init(photo)), "Live parent selection revokes the old page before task clearing")
        XCTAssertFalse(admitted(rows, nil))
        let replacement = moment("photo", seconds: 0, photo: "file:///replacement-synthetic.png")
        XCTAssertFalse(admitted([selected, replacement], .init(selected)), "Same photo ID with replacement URL is not old bytes")
        XCTAssertFalse(admitted([selected], .init(selected)))
        XCTAssertFalse(admitted([selected, photo, photo], .init(selected)))
        XCTAssertFalse(admitted(rows + [moment("inserted", seconds: 5)], .init(selected)))
        XCTAssertFalse(snapshot.admitsPhotoPresentation(
            presentation, selected: .init(selected), currentOwnership: nil,
            currentMetrics: rows, currentSnapshot: snapshot
        ))
        XCTAssertFalse(admitted(rows, .init(selected), .init(subject: "owner", generation: 2)))
        XCTAssertFalse(admitted(rows, .init(selected), .init(subject: "other", generation: 1)))
    }

    @MainActor
    func testCancelledPhotoTaskCannotReadCacheOrPublish() async throws {
        let started = expectation(description: "Photo task suspended before cache admission")
        var continuation: CheckedContinuation<Void, Never>?
        var cacheReads = 0
        var publications = 0
        let task = Task { @MainActor in
            await withCheckedContinuation { continuation = $0; started.fulfill() }
            let admitted = HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: { true }, operation: {
                cacheReads += 1
                publications += 1
            })
            return admitted
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        let pending = try XCTUnwrap(continuation)
        pending.resume()
        let admitted = await task.value
        XCTAssertFalse(admitted)
        XCTAssertEqual(cacheReads, 0)
        XCTAssertEqual(publications, 0)
        XCTAssertTrue(HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: { true }, operation: { cacheReads += 1 }))
        XCTAssertEqual(cacheReads, 1)
    }

    @MainActor
    func testHeldPhotoPublicationCannotReturnAfterLiveSelectionOrURLChange() async throws {
        for replacesURL in [false, true] {
            let selected = moment("selected", seconds: 10, weight: 83.4)
            let photo = moment("photo", seconds: 0, photo: "file:///held-original.png")
            let rows = [selected, photo]
            let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: rows, owner: "owner", ownership: selectedMomentOwnership)
            let presentation = try XCTUnwrap(snapshot.presentation(
                for: .init(selected), heightCm: nil, currentOwnership: selectedMomentOwnership
            ))
            var currentRows = rows
            var currentSelection: HomeV2TimelinePolicy.Selection? = .init(selected)
            var publications = 0
            let started = expectation(description: "Image load suspended before publication")
            var continuation: CheckedContinuation<Void, Never>?
            let task = Task { @MainActor in
                await withCheckedContinuation { continuation = $0; started.fulfill() }
                return HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: {
                    snapshot.admitsPhotoPresentation(
                        presentation, selected: currentSelection, currentOwnership: self.selectedMomentOwnership,
                        currentMetrics: currentRows, currentSnapshot: snapshot
                    )
                }, operation: { publications += 1 })
            }
            await fulfillment(of: [started], timeout: 2)
            if replacesURL {
                currentRows = [selected, moment("photo", seconds: 0, photo: "file:///held-replacement.png")]
            } else {
                currentSelection = .init(photo)
            }
            let pending = try XCTUnwrap(continuation)
            pending.resume()
            let admitted = await task.value
            XCTAssertFalse(admitted)
            XCTAssertEqual(publications, 0)
        }
    }

    func testSelectedMomentDecimalMidpointDisplayPreservesAnchorPrecision() throws {
        let vectors: [(before: Double, after: Double, seconds: Double, amount: Double, display: String)] = [
            (16.9, 16.2, 50, 16.55, "16.6"),
            (16.8998, 16.2, 50, 16.5499, "16.5"),
            (16.9002, 16.2, 50, 16.5501, "16.6"),
            (16.9, 16.2, 25, 16.725, "16.7")
        ]
        for vector in vectors {
            let before = moment("before", seconds: 0, bodyFat: vector.before, method: "dexa")
            let after = moment("after", seconds: 100, bodyFat: vector.after, method: "healthkit")
            let selected = moment("selected", seconds: vector.seconds, weight: 83.4)
            let history = [before, selected, after]
            let snapshot = HomeV2TimelinePolicy.Snapshot(
                metrics: history, owner: "owner", ownership: selectedMomentOwnership
            )
            let presentation = try XCTUnwrap(snapshot.presentation(
                for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
            ))
            let value = try XCTUnwrap(presentation.bodyFat)
            XCTAssertEqual(value.amount, vector.amount, accuracy: 0.00000001)
            XCTAssertEqual(String(format: "%.1f", value.amount), vector.display)
            XCTAssertEqual(value.anchors.map(\.amount), [vector.before, vector.after])
            XCTAssertEqual(value.anchors.map(\.source), ["From your DEXA scan", "From Apple Health"])
            XCTAssertEqual(snapshot.metric(for: .init(before)), before)
            XCTAssertEqual(snapshot.metric(for: .init(after)), after)
            XCTAssertNil(snapshot.metric(for: .init(selected))?.bodyFatPercentage)
            XCTAssertEqual(snapshot.presentation(for: .init(before), heightCm: 178,
                                                 currentOwnership: selectedMomentOwnership)?.bodyFat?.amount, vector.before)
        }
    }

    func testSelectedHeroDoesNotCarryPastWeightIntoUnavailableMoment() throws {
        let past = moment("past", seconds: 0, weight: 80)
        let selected = moment("selected", seconds: 10)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [past, selected], owner: "owner", ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(HomeV2EditorialPolicy.weights(in: snapshot.metrics, selected: selected).map(\.kilograms), [80])
        XCTAssertNil(value.weight)
        XCTAssertEqual(value.heroContent, .unavailable)
        XCTAssertEqual(value.bodyFatSummary, "Body fat unavailable at this time.")
        XCTAssertEqual(snapshot.metric(for: .init(past)), past)
    }

    func testSelectedHeroRetainsBodyFatWithoutAnyWeight() throws {
        let selected = moment("fat-only", seconds: 10, bodyFat: 20, method: "dexa")
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [selected], owner: "owner", ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
        ))
        XCTAssertNil(value.weight)
        XCTAssertEqual(value.heroContent, .bodyFat(try XCTUnwrap(value.bodyFat)))
        XCTAssertEqual(value.bodyFatSummary, "Body fat 20.0% · From your DEXA scan.")
        XCTAssertEqual(snapshot.metric(for: .init(selected)), selected)
    }

    func testSelectedHeroBodyFatQualifierPreservesInferenceAndMissingTime() throws {
        let selected = moment("selected", seconds: 10)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [moment("before", seconds: 0, bodyFat: 20, method: "dexa"), selected,
                      moment("after", seconds: 20, bodyFat: 30, method: "healthkit")],
            owner: "owner", ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
        ))
        XCTAssertNil(value.weight)
        let fat = try XCTUnwrap(value.bodyFat)
        XCTAssertEqual(fat.amount, 25, accuracy: 0.000001)
        XCTAssertEqual(fat.anchors.map(\.id.record), ["before", "after"])
        XCTAssertEqual(value.heroContent, .bodyFat(fat))
        XCTAssertEqual(value.bodyFatSummary, "Inferred body fat 25.0% · Time-weighted interpolation.")
        XCTAssertNil(snapshot.metric(for: .init(selected))?.bodyFatPercentage)
    }

    func testSelectedRawReviewWinsOverOlderWeightsAndValidBodyFat() throws {
        let selected = moment("selected", seconds: 20, weight: 18, bodyFat: 20)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [moment("oldest", seconds: 0, weight: 80),
                      moment("older", seconds: 10, weight: 82), selected,
                      moment("future", seconds: 30, weight: 90)],
            owner: "owner", ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
        ))
        XCTAssertEqual(HomeV2EditorialPolicy.weights(in: snapshot.metrics, selected: selected).map(\.kilograms), [80, 82])
        XCTAssertEqual(value.weight?.amount, 18)
        XCTAssertEqual(value.bodyFat?.amount, 20)
        XCTAssertEqual(value.heroContent, .review(try XCTUnwrap(value.weight)))
        XCTAssertNil(value.ffmi)
        XCTAssertEqual(snapshot.metric(for: .init(selected)), selected)
    }

    @MainActor
    func testSelectedInferredFocusRendersWithZeroOrOnePastChartMarks() throws {
        for priorDays in [40.0, 10.0] {
            let selected = moment("selected", seconds: 0, bodyFat: 20)
            let before = moment("before", seconds: -priorDays * 86_400, weight: 80)
            let afterAmount = priorDays == 40 ? 90.0 : 84.0
            let after = moment("after", seconds: 10 * 86_400, weight: afterAmount)
            let snapshot = HomeV2TimelinePolicy.Snapshot(
                metrics: [before, selected, after], owner: "owner", ownership: selectedMomentOwnership
            )
            let value = try XCTUnwrap(snapshot.presentation(
                for: .init(selected), heightCm: 178, currentOwnership: selectedMomentOwnership
            ))
            let weight = try XCTUnwrap(value.weight)
            let expected = priorDays == 40 ? 88.0 : 82.0
            XCTAssertEqual(weight.kind, .inferred)
            XCTAssertEqual(weight.amount, expected, accuracy: 0.000001)
            XCTAssertEqual(weight.anchors.map(\.id.record), ["before", "after"])
            XCTAssertEqual(value.heroContent, .weight(weight))
            let readings = HomeV2EditorialPolicy.weights(in: snapshot.metrics, selected: selected)
            XCTAssertEqual(readings.count, priorDays == 40 ? 0 : 1)
            let points = readings.map { MetricChartDataPoint(date: $0.date, value: $0.kilograms, presence: .present) }
            let chart = HomeV2TrendChart(
                daily: points, trend: [], accent: .blue, range: .constant(.month1),
                usesSevenDayAverage: false, requiresMinimumDays: false, allowsSelection: false,
                selectedMoment: selected.date, selectedMomentValue: weight.amount,
                selectedMomentProvenance: weight.kind.rawValue, now: selected.date
            )
            XCTAssertTrue(chart.hasValidParentFocus)
            XCTAssertTrue(chart.showsPlot)
            XCTAssertTrue(chart.selectionDomain.contains(expected))
            XCTAssertTrue(chart.accessibilityValueText.contains(String(format: "%.1f", expected)))
            XCTAssertTrue(chart.accessibilityValueText.contains("inferred"))
            XCTAssertNil(snapshot.metric(for: .init(selected))?.weight)
        }
    }

    @MainActor
    func testParentFocusDoesNotBypassMinimumDaysOrAcceptInvalidFocus() {
        let selected = Date(timeIntervalSince1970: 1_793_521_800)
        let strict = HomeV2TrendChart(
            daily: [], trend: [], accent: .blue, range: .constant(.month1),
            selectedMoment: selected, selectedMomentValue: 88, now: selected
        )
        XCTAssertFalse(strict.showsPlot)
        for value in [Double.nan, Double.infinity, -1] {
            let invalid = HomeV2TrendChart(
                daily: [], trend: [], accent: .blue, range: .constant(.month1),
                requiresMinimumDays: false, selectedMoment: selected,
                selectedMomentValue: value, now: selected
            )
            XCTAssertFalse(invalid.hasValidParentFocus)
            XCTAssertFalse(invalid.showsPlot)
        }
        let invalidDate = HomeV2TrendChart(
            daily: [], trend: [], accent: .blue, range: .constant(.month1),
            requiresMinimumDays: false, selectedMoment: Date(timeIntervalSince1970: .infinity),
            selectedMomentValue: 88, now: selected
        )
        XCTAssertFalse(invalidDate.hasValidParentFocus)
        XCTAssertFalse(invalidDate.showsPlot)
    }

    private func moment(
        _ id: String, seconds: TimeInterval, weight: Double? = nil,
        bodyFat: Double? = nil, method: String = "manual", photo: String? = nil, owner: String = "owner"
    ) -> BodyMetrics {
        // 2026-11-01 08:30 UTC, immediately before Los Angeles' repeated DST hour.
        let date = Date(timeIntervalSince1970: 1_793_521_800).addingTimeInterval(seconds)
        return BodyMetrics(
            id: id, userId: owner, date: date, weight: weight, weightUnit: "kg",
            bodyFatPercentage: bodyFat, bodyFatMethod: bodyFat == nil ? nil : method,
            muscleMass: nil, boneMass: nil, notes: nil, photoUrl: photo, dataSource: "manual",
            createdAt: date, updatedAt: date
        )
    }

    private var selectedMomentOwnership: AuthManager.ProfileSessionOwnership {
        .init(subject: "owner", generation: 1)
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

    // New chosen-kind adapter witnesses run the real frozen Snapshot resolver.
    func testChosenMetricAdapterRetainsActualBracketedValuesAnchorsAndCanonicalFFMI() throws {
        let before = moment("adapter-before", seconds: 0, weight: 80, bodyFat: 20, method: "typed", photo: "file:///synthetic-before.png")
        let selected = moment("adapter-selected", seconds: 21_600)
        let after = moment("adapter-after", seconds: 86_400, weight: 100, bodyFat: 28, method: "visual_estimate", photo: "file:///synthetic-after.png")
        let original = [after, selected, before]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: original, owner: "owner", ownership: selectedMomentOwnership)
        let presentation = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 180,
                                                               currentOwnership: selectedMomentOwnership
            )
        )
        let weight = presentation.reading(for: .weight, system: .metric)
        let fat = presentation.reading(for: .bodyFat, system: .metric)
        let ffmi = presentation.reading(for: .ffmi, system: .metric)
        // At one quarter of the elapsed interval: 80→100kg =85kg and
        // 20→28% =22%. Canonical FFMI at180cm is66.3/1.8² =20.46296…
        XCTAssertEqual(weight.value, "85.0")
        XCTAssertEqual(fat.value, "22.0")
        XCTAssertEqual(ffmi.value, "20.5")
        XCTAssertEqual(weight.evidence?.kind, .inferred)
        XCTAssertEqual(fat.evidence?.kind, .inferred)
        XCTAssertEqual(ffmi.evidence?.kind, .derived)
        XCTAssertEqual(weight.evidence?.anchors.map(\.id.record), [before.id, after.id])
        XCTAssertEqual(fat.evidence?.anchors.map(\.amount), [20, 28])
        XCTAssertEqual(fat.evidence?.anchors.map(\.date), [before.date, after.date])
        XCTAssertEqual(fat.evidence?.anchors.map(\.source), ["Entered by you", "Visual estimate"])
        XCTAssertTrue(try XCTUnwrap(weight.evidence).usesInference)
        XCTAssertTrue(try XCTUnwrap(fat.evidence).usesInference)
        XCTAssertTrue(try XCTUnwrap(ffmi.evidence).usesInference)
        XCTAssertEqual(weight.detail, "Inferred between recorded values")
        XCTAssertEqual(ffmi.detail, "Derived using inferred inputs")
        XCTAssertTrue(fat.explanation.contains("20.00 %"))
        XCTAssertTrue(fat.explanation.contains("28.00 %"))
        XCTAssertEqual(try XCTUnwrap(fat.bodyFatFraction), 0.22, accuracy: 0.000001)
        XCTAssertEqual(presentation.photo?.id, before.id)
        XCTAssertEqual(presentation.photo?.date, before.date, "Nearest actual photo retains its real timestamp")
        XCTAssertEqual(presentation.selection.date, selected.date)
        XCTAssertNil(snapshot.metric(for: .init(selected))?.weight)
        XCTAssertNil(snapshot.metric(for: .init(selected))?.bodyFatPercentage)
        XCTAssertEqual(snapshot.metrics, original, "Display inference must never persist synthetic measurements")
    }

    func testChosenMetricAdapterConvertsWeightOnceAndPreservesInferenceAcrossUnitChanges() throws {
        let before = moment("unit-before", seconds: 0, weight: 80, bodyFat: 20)
        let selected = moment("unit-selected", seconds: 21_600)
        let after = moment("unit-after", seconds: 86_400, weight: 100, bodyFat: 28)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [before, after, selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 180,
                                                        currentOwnership: selectedMomentOwnership
            )
        )
        let kg = value.reading(for: .weight, system: .metric)
        let lb = value.reading(for: .weight, system: .imperial)
        XCTAssertEqual(kg.value, "85.0")
        XCTAssertEqual(kg.unit, "kg")
        XCTAssertEqual(lb.value, "187.4", "85 canonical kg ×2.20462 rounds to187.4lb")
        XCTAssertEqual(lb.unit, "lb")
        XCTAssertEqual(lb.evidence?.amount, 85)
        XCTAssertEqual(lb.evidence?.anchors.map(\.amount), [80, 100])
        XCTAssertEqual(lb.evidence?.kind, .inferred)
        XCTAssertEqual(value.reading(for: .weight, system: .metric).value, "85.0")
        XCTAssertEqual(value.reading(for: .bodyFat, system: .imperial).value, "22.0")
        XCTAssertEqual(value.reading(for: .ffmi, system: .imperial).value, "20.5")
    }

    func testChosenMetricAdapterExactSelectedRecordWinsOverBracketedHistory() throws {
        let before = moment("exact-before", seconds: 0, weight: 80, bodyFat: 20)
        let selected = moment("exact-selected", seconds: 21_600, weight: 87, bodyFat: 23, method: "visual_estimate")
        let after = moment("exact-after", seconds: 86_400, weight: 100, bodyFat: 28)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [after, selected, before],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 180,
                                                        currentOwnership: selectedMomentOwnership
            )
        )
        let weight = value.reading(for: .weight, system: .metric)
        let fat = value.reading(for: .bodyFat, system: .metric)
        XCTAssertEqual(weight.value, "87.0")
        XCTAssertEqual(fat.value, "23.0")
        XCTAssertEqual(weight.evidence?.kind, .recorded)
        XCTAssertEqual(fat.evidence?.kind, .recorded)
        XCTAssertEqual(fat.evidence?.anchors.map(\.id.record), [selected.id])
        XCTAssertEqual(fat.evidence?.anchors.map(\.source), ["Visual estimate"])
        XCTAssertFalse(try XCTUnwrap(fat.evidence).usesInference)
        XCTAssertEqual(value.reading(for: .ffmi, system: .metric).value, "20.7")
        XCTAssertFalse(try XCTUnwrap(value.reading(for: .ffmi, system: .metric).evidence).usesInference)
    }

    func testChosenMetricAdapterKeepsUnavailableKindAndDoesNotClaimFFMIWasLogged() throws {
        let selected = moment("missing-selected", seconds: 0, weight: 80)
        let later = moment("missing-later", seconds: 86_400, weight: 90, bodyFat: 20)
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [later, selected],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let value = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: nil,
                                                        currentOwnership: selectedMomentOwnership
            )
        )
        XCTAssertEqual(value.reading(for: .weight, system: .metric).value, "80.0")
        for kind: HomeV2ProgressMetric in [.bodyFat, .ffmi] {
            let reading = value.reading(for: kind, system: .metric)
            XCTAssertEqual(reading.kind, kind)
            XCTAssertNil(reading.value)
            XCTAssertNil(reading.evidence)
            XCTAssertEqual(
                reading.detail,
                kind == .ffmi ? "Needs weight, body fat and height" : "Body fat unavailable at this time."
            )
            XCTAssertFalse(reading.detail.lowercased().contains("not logged"))
        }
        let complete = moment("height-selected", seconds: 0, weight: 80, bodyFat: 20)
        let completeSnapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: [complete],
            owner: "owner",
            ownership: selectedMomentOwnership
        )
        let noHeight = try XCTUnwrap(completeSnapshot.presentation(for: .init(complete), heightCm: nil,
                                                                   currentOwnership: selectedMomentOwnership
            )
        )
        XCTAssertEqual(noHeight.reading(for: .bodyFat, system: .metric).value, "20.0")
        XCTAssertNil(
            noHeight.reading(for: .ffmi, system: .metric).value,
            "Missing height cannot silently select another available metric"
        )
    }

    func testNonPhotoPresentationAdmitsValidOwnedMomentWithoutAuthorizingPhotoWork() throws {
        let selected = moment("no-photo", seconds: 0, weight: 80, bodyFat: 20)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [selected], owner: "owner", ownership: selectedMomentOwnership)
        let value = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 180,
                                                        currentOwnership: selectedMomentOwnership
            )
        )
        XCTAssertNil(value.photo)
        XCTAssertTrue(snapshot.admitsPresentation(value, selected: .init(selected), currentOwnership: selectedMomentOwnership,
                                                  currentMetrics: [selected], currentSnapshot: snapshot))
        XCTAssertFalse(
            snapshot.admitsPhotoPresentation(
                value,
                selected: .init(selected),
                currentOwnership: selectedMomentOwnership,
                currentMetrics: [selected], currentSnapshot: snapshot))
        XCTAssertFalse(snapshot.admitsPresentation(value, selected: nil, currentOwnership: selectedMomentOwnership,
                                                   currentMetrics: [selected], currentSnapshot: snapshot))
        for replacement: AuthManager.ProfileSessionOwnership? in [
            nil, .init(subject: "owner", generation: 2), .init(subject: "other", generation: 1)
        ] {
            XCTAssertFalse(snapshot.admitsPresentation(value, selected: .init(selected), currentOwnership: replacement,
                                                       currentMetrics: [selected], currentSnapshot: snapshot))
        }
    }

    func testNonPhotoPresentationRejectsDeletedCorrectedAndReconciledReplacementRows() throws {
        let selected = moment("revised", seconds: 0, weight: 80, bodyFat: 20)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [selected], owner: "owner", ownership: selectedMomentOwnership)
        let value = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 180,
                                                        currentOwnership: selectedMomentOwnership
            )
        )
        let corrected = moment("revised", seconds: 0, weight: 81, bodyFat: 20)
        XCTAssertEqual(selected.updatedAt, corrected.updatedAt, "Correction fixture must retain stored timestamp")
        for live in [[], [corrected], [selected, selected]] {
            XCTAssertFalse(
                snapshot.admitsPresentation(
                    value,
                    selected: .init(selected),
                    currentOwnership: selectedMomentOwnership,
                    currentMetrics: live, currentSnapshot: snapshot))
        }
        let refreshed = HomeV2TimelinePolicy.Snapshot(metrics: [corrected], owner: "owner", ownership: selectedMomentOwnership)
        XCTAssertFalse(snapshot.admitsPresentation(value, selected: .init(selected), currentOwnership: selectedMomentOwnership,
                                                   currentMetrics: [corrected], currentSnapshot: refreshed))
        let admitted = try XCTUnwrap(refreshed.presentation(for: .init(corrected), heightCm: 180,
                                                            currentOwnership: selectedMomentOwnership
            )
        )
        XCTAssertTrue(
            refreshed.admitsPresentation(
                admitted,
                selected: .init(corrected),
                currentOwnership: selectedMomentOwnership,
                currentMetrics: [corrected],
                currentSnapshot: refreshed
            )
        )
        XCTAssertEqual(admitted.reading(for: .weight, system: .metric).value, "81.0")
    }

    func testOrdinaryTimelineSwipeRequiresHorizontalIntentBeforeRecognition() {
        for velocity in [CGPoint(x: 1, y: 0), CGPoint(x: -500, y: 100)] {
            XCTAssertTrue(HomeV2TimelineSwipePolicy.hasHorizontalIntent(velocity: velocity))
        }
        for velocity in [CGPoint.zero, CGPoint(x: 100, y: 100), CGPoint(x: -100, y: -100),
                         CGPoint(x: 1, y: 2), CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 1, y: CGFloat.infinity)] {
            XCTAssertFalse(HomeV2TimelineSwipePolicy.hasHorizontalIntent(velocity: velocity))
        }
    }

    func testOrdinaryTimelineSlowSwipeUsesIndependentWidthThresholdsAndDirection() {
        // Explicit oracles cover the minimum, proportional and maximum travel.
        let cases: [(width: CGFloat, accepted: CGFloat, rejected: CGFloat)] = [
            (80, 24, 23.99), (390, 46.8, 46.79), (1_000, 64, 63.99)
        ]
        for vector in cases {
            for sign: CGFloat in [-1, 1] {
                XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: sign * vector.rejected, y: 0),
                                                             velocity: .zero,
                                                             width: vector.width
                    )
                )
                XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: sign * vector.accepted, y: 0),
                                                               velocity: .zero,
                                                               width: vector.width
                    ),
                    sign > 0
                )
            }
        }
    }

    func testOrdinaryTimelineFastReverseFlickUsesFinalVelocityAndMinimumTravel() {
        XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 12, y: 0),
                                                       velocity: CGPoint(x: -350, y: 0),
                                                       width: 390
            ),
            false,
            "A reverse flick must follow the final leftward intent despite positive net travel"
        )
        XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: -12, y: 0),
                                                       velocity: CGPoint(x: 350, y: 0),
                                                       width: 390
            ),
            true
        )
        XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 11.99, y: 0),
                                                     velocity: CGPoint(x: 2_000, y: 0),
                                                     width: 390
            )
        )
        XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 12, y: 0),
                                                     velocity: CGPoint(x: 349.99, y: 0),
                                                     width: 390
            )
        )
        XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 12, y: 0),
                                                     velocity: CGPoint(x: 350, y: 350),
                                                     width: 390
            )
        )
    }

    func testOrdinaryTimelineSwipeMirrorsRTLAndRejectsMalformedOrVerticalGeometry() {
        XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: -64, y: 0),
                                                       velocity: .zero,
                                                       width: 390,
                                                       isRightToLeft: true
            ),
            true
        )
        XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 64, y: 0),
                                                       velocity: .zero,
                                                       width: 390,
                                                       isRightToLeft: true
            ),
            false
        )
        XCTAssertEqual(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 12, y: 0),
                                                       velocity: CGPoint(x: -400, y: 0),
                                                       width: 390,
                                                       isRightToLeft: true
            ),
            true
        )
        for width: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 100, y: 0), velocity: .zero, width: width))
        }
        for translation in [CGPoint.zero, CGPoint(x: 80, y: 80), CGPoint(x: -80, y: -80),
                            CGPoint(x: 80, y: 81), CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 80, y: CGFloat.infinity)] {
            XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: translation, velocity: CGPoint(x: 500, y: 0), width: 390))
        }
        for velocity in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
            XCTAssertNil(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: 100, y: 0), velocity: velocity, width: 390))
        }
    }

    func testRapidReverseSwipeResolvesExistingIDsAndKeepsTheRequestedMissingMetric() throws {
        let oldest = moment("swipe-oldest", seconds: 0, weight: 80)
        let middle = moment("swipe-middle", seconds: 100, weight: 81)
        let latest = moment("swipe-latest", seconds: 200, weight: 82, bodyFat: 20)
        let rows = [latest, oldest, middle]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: rows, owner: "owner", ownership: selectedMomentOwnership)
        var selection = HomeV2TimelinePolicy.EntryID(middle)
        let requests: [(translation: CGFloat, velocity: CGFloat, expected: String)] = [
            (12, -400, oldest.id), (-12, 400, middle.id), (64, 0, latest.id),
            (12, -400, middle.id), (12, -400, oldest.id), (12, -400, oldest.id)
        ]
        for request in requests {
            let newer = try XCTUnwrap(HomeV2TimelineSwipePolicy.newer(translation: CGPoint(x: request.translation, y: 0),
                                                                      velocity: CGPoint(x: request.velocity, y: 0),
                                                                      width: 390
                )
            )
            if let next = snapshot.adjusted(selection, newer: newer) { selection = next }
            XCTAssertEqual(selection.record, request.expected)
            let metric = try XCTUnwrap(snapshot.metric(for: selection))
            let presentation = try XCTUnwrap(snapshot.presentation(for: .init(metric), heightCm: 180,
                                                                   currentOwnership: selectedMomentOwnership
                )
            )
            XCTAssertEqual(presentation.selection.id, selection)
            XCTAssertEqual(presentation.selection.date, metric.date)
            let reading = presentation.reading(for: .bodyFat, system: .metric)
            XCTAssertEqual(reading.kind, .bodyFat)
            XCTAssertEqual(reading.value, selection.record == latest.id ? "20.0" : nil,
                           "No preceding body-fat anchor exists; swiping cannot borrow the later measurement or choose weight")
            XCTAssertNil(presentation.photo)
        }
        XCTAssertEqual(snapshot.metrics, rows)
    }

    private func viewerAdmissionFixture() throws -> (
        selected: BodyMetrics, photo: BodyMetrics, rows: [BodyMetrics],
        snapshot: HomeV2TimelinePolicy.Snapshot, presentation: HomeV2TimelinePolicy.Presentation,
        opening: UUID, admission: HomeV2TimelinePolicy.PhotoViewerAdmission
    ) {
        let selected = moment("viewer-selected-without-photo", seconds: 10, weight: 83.4)
        let photo = moment("viewer-actual-photo", seconds: 0, weight: 84, bodyFat: 20,
                           photo: "file:///synthetic-viewer-actual.png")
        let rows = [selected, photo]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: rows, owner: "owner", ownership: selectedMomentOwnership)
        let presentation = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 178,
                                                               currentOwnership: selectedMomentOwnership
            )
        )
        let opening = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        return (selected, photo, rows, snapshot, presentation, opening,
                HomeV2TimelinePolicy.PhotoViewerAdmission(openingID: opening, snapshot: snapshot, presentation: presentation))
    }

    func testPhotoViewerAdmissionRequiresTheExactOpeningEvenWhenOwnerRowsAndPhotoAreUnchanged() throws {
        let fixture = try viewerAdmissionFixture()
        let reopened = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        XCTAssertNil(fixture.selected.photoUrl)
        XCTAssertEqual(fixture.presentation.selection, .init(fixture.selected))
        XCTAssertEqual(fixture.presentation.photo, fixture.photo)
        XCTAssertNotEqual(fixture.presentation.photo?.date, fixture.presentation.selection.date)
        for (opening, expected) in [(fixture.opening as UUID?, true), (nil, false), (reopened, false)] {
            XCTAssertEqual(fixture.admission.admits(
                currentOpeningID: opening,
                visibility: .init(
                    isPresented: true,
                    isHomeForeground: true,
                    isActive: true,
                    hasCompetingPresentation: false,
                    hasChildRoute: false,
                    hasCurrentDashboardPublication: true
                ),
                currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
                currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
            ), expected, "A new opening must not revive an old callback despite identical owner, rows and actual photo")
        }
        let fresh = HomeV2TimelinePolicy.PhotoViewerAdmission(openingID: reopened, snapshot: fixture.snapshot,
                                                              presentation: fixture.presentation
        )
        XCTAssertTrue(fresh.admits(
            currentOpeningID: reopened,
            visibility: .init(
                isPresented: true,
                isHomeForeground: true,
                isActive: true,
                hasCompetingPresentation: false,
                hasChildRoute: false,
                hasCurrentDashboardPublication: true
            ),
            currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
            currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
        ), "The new opening's own callback remains usable")
        XCTAssertEqual(fixture.presentation.selection.id, HomeV2TimelinePolicy.EntryID(fixture.selected))
    }

    func testPhotoViewerAdmissionRejectsDismissalNonactiveRootAndEveryCompetingRoute() throws {
        let fixture = try viewerAdmissionFixture()
        let states: [(name: String, presented: Bool, foreground: Bool, active: Bool,
                      competing: Bool, child: Bool, published: Bool, expected: Bool)] = [
            ("current visible viewer", true, true, true, false, false, true, true),
            ("dismissed viewer", false, true, true, false, false, true, false),
            ("changed root", true, false, true, false, false, true, false),
            ("inactive or background scene", true, true, false, false, false, true, false),
            ("competing presentation", true, true, true, true, false, true, false),
            ("viewer child route", true, true, true, false, true, true, false),
            ("dashboard publication replaced", true, true, true, false, false, false, false)
                      ]
        for state in states {
            XCTAssertEqual(fixture.admission.admits(
                currentOpeningID: fixture.opening,
                visibility: .init(
                    isPresented: state.presented,
                    isHomeForeground: state.foreground,
                    isActive: state.active,
                    hasCompetingPresentation: state.competing,
                    hasChildRoute: state.child,
                    hasCurrentDashboardPublication: state.published
                ),
                currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
                currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
            ), state.expected, state.name)
        }
    }

    func testPhotoViewerAdmissionRetainsActualSelectionSessionAndRawPhotoRevisionFences() throws {
        let fixture = try viewerAdmissionFixture()
        let corrected = moment(fixture.photo.id, seconds: 0, weight: 85, bodyFat: 20,
                               photo: "file:///synthetic-viewer-actual.png")
        let changedURL = moment(fixture.photo.id, seconds: 0, weight: 84, bodyFat: 20,
                                photo: "file:///synthetic-viewer-replacement.png")
        XCTAssertEqual(corrected.id, fixture.photo.id)
        XCTAssertEqual(corrected.date, fixture.photo.date)
        XCTAssertEqual(corrected.updatedAt, fixture.photo.updatedAt)
        for rows in [[], [fixture.selected], [fixture.selected, corrected],
                     [fixture.selected, changedURL], [fixture.selected, fixture.photo, fixture.photo]] {
            XCTAssertFalse(fixture.admission.admits(
                currentOpeningID: fixture.opening,
                visibility: .init(
                    isPresented: true,
                    isHomeForeground: true,
                    isActive: true,
                    hasCompetingPresentation: false,
                    hasChildRoute: false,
                    hasCurrentDashboardPublication: true
                ),
                currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
                currentMetrics: rows, currentSnapshot: fixture.snapshot
            ), "Deletion, same-ID/date/timestamp correction, photo replacement and duplicate rows revoke callbacks")
        }
        for selection: HomeV2TimelinePolicy.Selection? in [nil, .init(fixture.photo)] {
            XCTAssertFalse(fixture.admission.admits(
                currentOpeningID: fixture.opening,
                visibility: .init(
                    isPresented: true,
                    isHomeForeground: true,
                    isActive: true,
                    hasCompetingPresentation: false,
                    hasChildRoute: false,
                    hasCurrentDashboardPublication: true
                ),
                currentSelection: selection, currentOwnership: selectedMomentOwnership,
                currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
            ))
        }
        for ownership: AuthManager.ProfileSessionOwnership? in [nil, .init(subject: "other", generation: 1),
                                                                .init(subject: "owner", generation: 2)
        ] {
            XCTAssertFalse(fixture.admission.admits(
                currentOpeningID: fixture.opening,
                visibility: .init(
                    isPresented: true,
                    isHomeForeground: true,
                    isActive: true,
                    hasCompetingPresentation: false,
                    hasChildRoute: false,
                    hasCurrentDashboardPublication: true
                ),
                currentSelection: .init(fixture.selected), currentOwnership: ownership,
                currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
            ))
        }
        let revised = HomeV2TimelinePolicy.Snapshot(metrics: [fixture.selected, corrected], owner: "owner",
                                                    ownership: selectedMomentOwnership
        )
        XCTAssertFalse(fixture.admission.admits(
            currentOpeningID: fixture.opening,
            visibility: .init(
                isPresented: true,
                isHomeForeground: true,
                isActive: true,
                hasCompetingPresentation: false,
                hasChildRoute: false,
                hasCurrentDashboardPublication: true
            ),
            currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
            currentMetrics: [fixture.selected, corrected], currentSnapshot: revised
        ), "A newly published snapshot cannot authorize an older callback's captured revision")
    }

    func testPhotoViewerAdmissionCannotUseGeneralNonPhotoAdmissionToAuthorizeViewerWork() throws {
        let selected = moment("viewer-no-image", seconds: 0, weight: 80, bodyFat: 20)
        let rows = [selected]
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: rows, owner: "owner", ownership: selectedMomentOwnership)
        let presentation = try XCTUnwrap(snapshot.presentation(for: .init(selected), heightCm: 178,
                                                               currentOwnership: selectedMomentOwnership
            )
        )
        XCTAssertNil(presentation.photo)
        XCTAssertTrue(snapshot.admitsPresentation(presentation, selected: .init(selected),
                                                  currentOwnership: selectedMomentOwnership,
                                                  currentMetrics: rows, currentSnapshot: snapshot))
        let opening = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let admission = HomeV2TimelinePolicy.PhotoViewerAdmission(openingID: opening, snapshot: snapshot,
                                                                  presentation: presentation
        )
        XCTAssertFalse(admission.admits(
            currentOpeningID: opening,
            visibility: .init(
                isPresented: true,
                isHomeForeground: true,
                isActive: true,
                hasCompetingPresentation: false,
                hasChildRoute: false,
                hasCurrentDashboardPublication: true
            ),
            currentSelection: .init(selected), currentOwnership: selectedMomentOwnership,
            currentMetrics: rows, currentSnapshot: snapshot
        ), "An otherwise current data-only moment cannot authorize actual-photo callbacks")
    }

    @MainActor
    func testHeldPhotoViewerCallbackCannotActAfterSameOwnerDataAndPhotoCloseReopen() async throws {
        let fixture = try viewerAdmissionFixture()
        let reopened = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        var currentOpening: UUID? = fixture.opening
        var presented = true
        var callbacks = 0
        XCTAssertTrue(fixture.admission.admits(
            currentOpeningID: currentOpening,
            visibility: .init(
                isPresented: presented,
                isHomeForeground: true,
                isActive: true,
                hasCompetingPresentation: false,
                hasChildRoute: false,
                hasCurrentDashboardPublication: true
            ),
            currentSelection: .init(fixture.selected), currentOwnership: selectedMomentOwnership,
            currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
        ))
        let started = expectation(description: "Viewer callback held before actual invocation")
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { @MainActor in
            await withCheckedContinuation { continuation = $0; started.fulfill() }
            return HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: {
                fixture.admission.admits(
                    currentOpeningID: currentOpening,
                    visibility: .init(
                        isPresented: presented,
                        isHomeForeground: true,
                        isActive: true,
                        hasCompetingPresentation: false,
                        hasChildRoute: false,
                        hasCurrentDashboardPublication: true
                    ),
                    currentSelection: .init(fixture.selected), currentOwnership: self.selectedMomentOwnership,
                    currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
                )
            }, operation: { callbacks += 1 })
        }
        await fulfillment(of: [started], timeout: 2)
        presented = false
        currentOpening = nil
        // The exact same owner, selected moment, raw rows and actual image reopen.
        presented = true
        currentOpening = reopened
        let pending = try XCTUnwrap(continuation)
        pending.resume()
        let admitted = await task.value
        XCTAssertFalse(admitted)
        XCTAssertEqual(callbacks, 0, "A stale close/page/tool callback must not act on the new opening")
        let current = HomeV2TimelinePolicy.PhotoViewerAdmission(openingID: reopened, snapshot: fixture.snapshot,
                                                                presentation: fixture.presentation
        )
        XCTAssertTrue(HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: {
            current.admits(
                currentOpeningID: currentOpening,
                visibility: .init(
                    isPresented: presented,
                    isHomeForeground: true,
                    isActive: true,
                    hasCompetingPresentation: false,
                    hasChildRoute: false,
                    hasCurrentDashboardPublication: true
                ),
                currentSelection: .init(fixture.selected), currentOwnership: self.selectedMomentOwnership,
                currentMetrics: fixture.rows, currentSnapshot: fixture.snapshot
            )
        }, operation: { callbacks += 1 }))
        XCTAssertEqual(callbacks, 1, "The current opening remains interactive")
    }
}
