//
// EarnedWinDetectorTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class EarnedWinDetectorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private var anchor: Date {
        calendar.date(from: DateComponents(year: 2_026, month: 1, day: 1, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Named fixtures

    func testNoiseOnlyChangeReturnsNoWin() {
        let values = [180.0, 179.95, 180.0, 179.9, 179.92, 179.96, 179.85]
        let (history, goal) = weightHistory(values: values, dayStride: 1, target: 170)

        let win = EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar)

        XCTAssertNil(win)
    }

    func testFewerThanMinimumReadingsReturnsNoWin() {
        let (history, goal) = weightHistory(
            values: [200, 196, 192, 188, 184, 180],
            dayStride: 1,
            target: 170
        )
        XCTAssertEqual(
            Set(history.rows.map { calendar.startOfDay(for: $0.occurredAt) }).count,
            EarnedWinDetector.minimumReadings - 1
        )

        XCTAssertNil(EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar))
    }

    func testRealGoalRelativeGainCarriesItsReadings() throws {
        let (history, goal) = weightHistory(
            values: [200, 199, 198, 197, 196, 195, 194],
            dayStride: 1,
            target: 180
        )

        let earned = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar)
        )
        XCTAssertEqual(earned.kind, .goalRelativeGain)
        XCTAssertNil(earned.milestone)
        XCTAssertEqual(earned.metric, .weight)
        XCTAssertEqual(earned.evidence.map(\.id), history.rows.map(\.id))
        XCTAssertFalse(earned.evidence.isEmpty)
    }

    func testFirstPhotoCarriesThePhotoRow() throws {
        let photo = row(id: "photo-b", kind: .photo, day: 3)
        let sameTime = row(id: "photo-a", kind: .photo, day: 3)
        let later = row(id: "photo-c", kind: .photo, day: 9)
        let history = EarnedWinHistory(rows: [later, photo, sameTime])

        let win = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar)
        )
        XCTAssertEqual(win.kind, .firstEver)
        XCTAssertEqual(win.milestone, .firstPhoto)
        XCTAssertEqual(win.evidence.map(\.id), ["photo-a"])
    }

    func testRepeatedCallAfterAShownWinReturnsNone() throws {
        let photo = row(id: "photo-1", kind: .photo, day: 1)
        let history = EarnedWinHistory(rows: [photo])
        let shown = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar)
        )

        let again = EarnedWinDetector.detect(
            history: history.markingShown(shown),
            goal: nil,
            calendar: calendar
        )

        XCTAssertNil(again)
    }

    // MARK: - Floor, noise, and evidence

    func testMinimumReadingsMatchTheHomeTrendFloor() {
        XCTAssertEqual(EarnedWinDetector.minimumReadings, HomeV2TrendPolicy.minimumDistinctDays)
        XCTAssertEqual(
            EarnedWinDetector.weightNoiseFloor(start: 200, spanDays: 14) ?? -1,
            1,
            accuracy: 0.000001
        )
        XCTAssertEqual(EarnedWinDetector.bodyCompositionNoisePoints, 0.3, accuracy: 0.000001)
    }

    func testSameDayRepeatsDoNotSatisfyTheReadingFloor() {
        // Twelve weigh-ins across six days would clear the noise band, and still are not a trend.
        let rows = (0..<12).map { index in
            row(
                id: "same-\(index)",
                kind: .reading,
                day: index / 2,
                metric: .weight,
                value: 200 - Double(index)
            )
        }
        let history = EarnedWinHistory(rows: rows)
        let goal = EarnedWinGoal(metric: .weight, target: 160)

        XCTAssertNil(EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar))
    }

    func testEmptyHistoryAndMissingGoalReturnNoWin() {
        XCTAssertNil(
            EarnedWinDetector.detect(
                history: EarnedWinHistory(rows: []),
                goal: EarnedWinGoal(metric: .weight, target: 170),
                calendar: calendar
            )
        )
        let (history, _) = weightHistory(
            values: [200, 198, 196, 194, 192, 190, 188],
            dayStride: 1,
            target: 170
        )
        XCTAssertNil(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))
        XCTAssertNil(
            EarnedWinDetector.detect(
                history: history,
                goal: EarnedWinGoal(metric: .weight, target: .nan),
                calendar: calendar
            )
        )
    }

    func testMovementAwayFromTheGoalIsNotAWin() {
        let (history, goal) = weightHistory(
            values: [180, 182, 184, 186, 188, 190, 192],
            dayStride: 1,
            target: 170
        )

        XCTAssertNil(EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar))
    }

    func testWeightChangeAtTheNoiseFloorIsAWinAndJustUnderIsNot() throws {
        let floor = try XCTUnwrap(EarnedWinDetector.weightNoiseFloor(start: 200, spanDays: 14))
        let days = [0, 2, 4, 6, 8, 10, 14]
        let atFloor = history(
            readings: days.enumerated().map { index, day in
                (id: "at-\(index)", day: day, value: index == days.count - 1 ? 200 - floor : 200)
            },
            target: 100
        )
        let under = history(
            readings: days.enumerated().map { index, day in
                (id: "under-\(index)", day: day, value: index == days.count - 1 ? 200 - floor + 0.05 : 200)
            },
            target: 100
        )

        let earned = try XCTUnwrap(
            EarnedWinDetector.detect(history: atFloor.history, goal: atFloor.goal, calendar: calendar)
        )
        XCTAssertEqual(earned.kind, .goalRelativeGain)
        XCTAssertEqual(earned.evidence.map(\.id), atFloor.history.rows.map(\.id))
        XCTAssertNil(EarnedWinDetector.detect(history: under.history, goal: under.goal, calendar: calendar))
    }

    func testBodyCompositionUsesThePointFloor() {
        let gain = compositionHistory(start: 22, end: 21.6, metric: .bodyFat, target: 18)
        let noise = compositionHistory(start: 22, end: 21.8, metric: .bodyFat, target: 18)
        let ffmi = compositionHistory(start: 21, end: 21.4, metric: .ffmi, target: 23)

        XCTAssertEqual(
            EarnedWinDetector.detect(history: gain.history, goal: gain.goal, calendar: calendar)?.kind,
            .goalRelativeGain
        )
        XCTAssertNil(EarnedWinDetector.detect(history: noise.history, goal: noise.goal, calendar: calendar))
        XCTAssertEqual(
            EarnedWinDetector.detect(history: ffmi.history, goal: ffmi.goal, calendar: calendar)?.metric,
            .ffmi
        )
    }

    func testGainEvidenceOmitsUnrelatedRows() throws {
        let (weights, goal) = weightHistory(
            values: [200, 199, 198, 197, 196, 195, 194],
            dayStride: 1,
            target: 180
        )
        let extra = [
            row(id: "photo", kind: .photo, day: 2),
            row(id: "fat", kind: .reading, day: 3, metric: .bodyFat, value: 20),
            row(id: "nan", kind: .reading, day: 4, metric: .weight, value: .nan)
        ]
        let history = EarnedWinHistory(
            rows: extra + weights.rows,
            shown: [
                EarnedWinShownToken(kind: .firstEver, milestone: .firstPhoto, evidenceIDs: ["photo"])
            ]
        )

        let win = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar)
        )

        XCTAssertEqual(win.evidence.map(\.id), weights.rows.map(\.id))
        let knownIDs = Set(history.rows.map(\.id))
        XCTAssertTrue(win.evidence.allSatisfy { knownIDs.contains($0.id) })
    }

    func testShownGainDoesNotRepeatUntilTheEvidenceChanges() throws {
        let (history, goal) = weightHistory(
            values: [200, 199, 198, 197, 196, 195, 194],
            dayStride: 1,
            target: 180
        )
        let first = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar)
        )
        XCTAssertNil(
            EarnedWinDetector.detect(history: history.markingShown(first), goal: goal, calendar: calendar)
        )

        var rows = history.rows
        rows.append(row(id: "w-next", kind: .reading, day: 8, metric: .weight, value: 192))
        let extended = EarnedWinHistory(rows: rows, shown: history.markingShown(first).shown)
        let next = try XCTUnwrap(
            EarnedWinDetector.detect(history: extended, goal: goal, calendar: calendar)
        )
        XCTAssertEqual(next.kind, .goalRelativeGain)
        XCTAssertEqual(next.evidence.map(\.id).last, "w-next")
    }

    // MARK: - Milestones

    func testFirstImportAndFirstWorkoutFireOnce() throws {
        let imported = row(id: "import-late", kind: .importEvent, day: 4)
        let firstImport = row(id: "import-early", kind: .importEvent, day: 1)
        let workout = row(id: "workout-1", kind: .workout, day: 2)
        let history = EarnedWinHistory(rows: [workout, imported, firstImport])

        let win = try XCTUnwrap(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))
        XCTAssertEqual(win.milestone, .firstImport)
        XCTAssertEqual(win.evidence.map(\.id), ["import-early"])

        let afterImport = history.markingShown(win)
        let next = try XCTUnwrap(
            EarnedWinDetector.detect(history: afterImport, goal: nil, calendar: calendar)
        )
        XCTAssertEqual(next.milestone, .firstWorkout)
        XCTAssertEqual(next.evidence.map(\.id), ["workout-1"])
        let quiet = EarnedWinHistory(
            rows: afterImport.rows + [row(id: "import-new", kind: .importEvent, day: 6)],
            shown: afterImport.markingShown(next).shown
        )
        XCTAssertNil(EarnedWinDetector.detect(history: quiet, goal: nil, calendar: calendar))
    }

    func testAnotherPhotoDoesNotRepeatAShownFirstPhoto() throws {
        let history = EarnedWinHistory(rows: [row(id: "photo-1", kind: .photo, day: 0)])
        let win = try XCTUnwrap(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))
        let later = EarnedWinHistory(
            rows: history.rows + [row(id: "photo-2", kind: .photo, day: 12)],
            shown: history.markingShown(win).shown
        )

        XCTAssertNil(EarnedWinDetector.detect(history: later, goal: nil, calendar: calendar))
    }

    func testWorkoutCountIsNotAWinAfterTheFirstWorkoutWasShown() throws {
        let workouts = (0..<20).map { index in
            row(id: "workout-\(index)", kind: .workout, day: index)
        }
        let history = EarnedWinHistory(rows: workouts)
        let first = try XCTUnwrap(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))
        XCTAssertEqual(first.evidence.count, 1)

        XCTAssertNil(
            EarnedWinDetector.detect(history: history.markingShown(first), goal: nil, calendar: calendar)
        )
    }

    func testOneCallReturnsTheEarliestUnshownMilestoneAheadOfAGain() throws {
        let (weights, goal) = weightHistory(
            values: [200, 198, 196, 194, 192, 190, 188],
            dayStride: 1,
            target: 170
        )
        let history = EarnedWinHistory(
            rows: weights.rows + [row(id: "photo", kind: .photo, day: 0)]
        )

        let win = try XCTUnwrap(
            EarnedWinDetector.detect(history: history, goal: goal, calendar: calendar)
        )
        XCTAssertEqual(win.kind, .firstEver)
        XCTAssertEqual(win.milestone, .firstPhoto)
        XCTAssertEqual(win.evidence.count, 1)

        let gain = try XCTUnwrap(
            EarnedWinDetector.detect(
                history: history.markingShown(win),
                goal: goal,
                calendar: calendar
            )
        )
        XCTAssertEqual(gain.kind, .goalRelativeGain)
        XCTAssertEqual(gain.evidence.map(\.id), weights.rows.map(\.id))
    }

    // MARK: - Time saved

    func testMeasuredDurationDropIsTimeSavedAndCarriesThoseRows() throws {
        let rows = durationRows(minutes: [60, 60, 60, 40, 40, 40, 40], activity: .workout)
        let history = EarnedWinHistory(rows: rows)

        let win = try XCTUnwrap(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))

        XCTAssertEqual(win.kind, .timeSaved)
        XCTAssertEqual(win.evidence.map(\.id), rows.map(\.id))
    }

    func testDurationNoiseAndShortSeriesReturnNoWin() {
        let noisy = EarnedWinHistory(rows: durationRows(minutes: [60, 60, 60, 58, 58, 59, 58], activity: .logging))
        let short = EarnedWinHistory(rows: durationRows(minutes: [60, 60, 20, 20, 20, 20], activity: .workout))
        let unscoped = EarnedWinHistory(rows: [
            row(id: "loose", kind: .duration, day: 0, durationMinutes: 10)
        ])

        XCTAssertNil(EarnedWinDetector.detect(history: noisy, goal: nil, calendar: calendar))
        XCTAssertNil(EarnedWinDetector.detect(history: short, goal: nil, calendar: calendar))
        XCTAssertNil(EarnedWinDetector.detect(history: unscoped, goal: nil, calendar: calendar))
    }

    func testTimeSavedUsesOneActivityAndDoesNotRepeatOnceShown() throws {
        let workouts = durationRows(minutes: [70, 70, 70, 50, 50, 50, 50], activity: .workout)
        let logging = durationRows(
            minutes: [30, 30, 30, 10, 10, 10, 10],
            activity: .logging,
            idPrefix: "log"
        )
        let history = EarnedWinHistory(rows: logging + workouts)
        let win = try XCTUnwrap(EarnedWinDetector.detect(history: history, goal: nil, calendar: calendar))

        XCTAssertEqual(win.kind, .timeSaved)
        XCTAssertEqual(win.evidence.compactMap(\.activity), Array(repeating: .logging, count: 7))

        let rest = try XCTUnwrap(
            EarnedWinDetector.detect(
                history: history.markingShown(win),
                goal: nil,
                calendar: calendar
            )
        )
        XCTAssertEqual(rest.evidence.compactMap(\.activity), Array(repeating: .workout, count: 7))
    }

    // MARK: - Fixtures

    private func date(day offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    private func row(
        id: String,
        kind: EarnedWinRowKind,
        day: Int,
        metric: EarnedWinMetric? = nil,
        value: Double? = nil,
        durationMinutes: Double? = nil,
        activity: EarnedWinDurationActivity? = nil
    ) -> EarnedWinRow {
        EarnedWinRow(
            id: id,
            kind: kind,
            occurredAt: date(day: day),
            metric: metric,
            value: value,
            durationMinutes: durationMinutes,
            activity: activity
        )
    }

    private func weightHistory(
        values: [Double],
        dayStride: Int,
        target: Double
    ) -> (history: EarnedWinHistory, goal: EarnedWinGoal) {
        history(
            readings: values.enumerated().map { index, value in
                (id: "w\(index)", day: index * dayStride, value: value)
            },
            target: target
        )
    }

    private func history(
        readings: [(id: String, day: Int, value: Double)],
        target: Double,
        metric: EarnedWinMetric = .weight
    ) -> (history: EarnedWinHistory, goal: EarnedWinGoal) {
        let rows = readings.map { reading in
            row(
                id: reading.id,
                kind: .reading,
                day: reading.day,
                metric: metric,
                value: reading.value
            )
        }
        return (EarnedWinHistory(rows: rows), EarnedWinGoal(metric: metric, target: target))
    }

    private func compositionHistory(
        start: Double,
        end: Double,
        metric: EarnedWinMetric,
        target: Double
    ) -> (history: EarnedWinHistory, goal: EarnedWinGoal) {
        let step = (end - start) / 6
        let values = (0..<7).map { index in start + (step * Double(index)) }
        return history(
            readings: values.enumerated().map { index, value in
                (id: "\(metric.rawValue)-\(index)", day: index, value: value)
            },
            target: target,
            metric: metric
        )
    }

    private func durationRows(
        minutes: [Double],
        activity: EarnedWinDurationActivity,
        idPrefix: String = "dur"
    ) -> [EarnedWinRow] {
        minutes.enumerated().map { index, minutes in
            row(
                id: "\(idPrefix)-\(index)",
                kind: .duration,
                day: index,
                durationMinutes: minutes,
                activity: activity
            )
        }
    }
}
