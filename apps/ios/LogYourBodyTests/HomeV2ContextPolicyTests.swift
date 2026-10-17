//
// HomeV2ContextPolicyTests.swift
// LogYourBodyTests
//
import CoreData
import XCTest
import UIKit
@testable import LogYourBody

final class HomeV2ContextPolicyTests: XCTestCase {
    private func metric(
        daysAgo: Int,
        weight: Double?,
        bodyFat: Double? = nil,
        source: String = "manual",
        sourceName: String? = nil,
        photo: String? = nil,
        hour: Int = 0,
        minute: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BodyMetrics {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return BodyMetrics(
            id: "m\(daysAgo)",
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photo,
            dataSource: source,
            sourceMetadata: sourceName.map { BodyMetricSourceMetadata(sourceName: $0) },
            createdAt: date,
            updatedAt: date
        )
    }

    func testProvenanceNamesTheSourceAndTheTime() {
        XCTAssertEqual(HomeV2Provenance.label(for: metric(daysAgo: 0, weight: 80, source: "healthkit")), "Apple Health")
        XCTAssertEqual(
            HomeV2Provenance.label(for: metric(daysAgo: 0, weight: 80, source: "healthkit", sourceName: "Withings")),
            "Withings"
        )
        XCTAssertEqual(HomeV2Provenance.label(for: metric(daysAgo: 0, weight: 80, source: "manual")), "Typed")
        XCTAssertEqual(HomeV2Provenance.label(for: metric(daysAgo: 0, weight: 80, source: "bodyspec_dexa")), "BodySpec DEXA")

        let timed = metric(daysAgo: 0, weight: 80, source: "healthkit", hour: 7, minute: 2)
        XCTAssertTrue(HomeV2Provenance.subline(for: timed).hasPrefix("Apple Health, "), HomeV2Provenance.subline(for: timed))
        XCTAssertEqual(HomeV2Provenance.subline(for: metric(daysAgo: 0, weight: 80, source: "healthkit")), "Apple Health")
        XCTAssertTrue(HomeV2Provenance.subline(
            for: metric(daysAgo: 0, weight: 80, source: "healthkit", sourceName: "Withings", hour: 7)
        ).hasPrefix("Withings via Apple Health, "))
    }

    func testWeekStripCoversSevenDaysAroundTheDate() {
        let calendar = Calendar.current
        let days = HomeV2WeekStrip.days(containing: Date(), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), calendar.firstWeekday)
        XCTAssertTrue(days.contains { calendar.isDateInToday($0) })
        XCTAssertFalse(HomeV2WeekStrip.weekdayLetter(for: Date(), calendar: calendar).isEmpty)
    }

    func testDeleteScopeIsSpelledOut() {
        XCTAssertEqual(
            HomeV2ContextCopy.deleteBody(date: "Sep 25, 2026", includesPhoto: false),
            "Removes the weight and body fat logged for Sep 25, 2026. Nothing is deleted from Apple Health."
        )
        XCTAssertTrue(HomeV2ContextCopy.deleteBody(date: "Sep 25", includesPhoto: true).contains("including its photo"))
        XCTAssertEqual(HomeV2ContextCopy.monthDelta(first: 175.9, last: 173.4, unit: "lb"), "Down 2.5 lb")
        XCTAssertEqual(HomeV2ContextCopy.monthDelta(first: 80.0, last: 80.02, unit: "kg"), "No change")
        XCTAssertNil(HomeV2ContextCopy.monthDelta(first: nil, last: 80, unit: "kg"))
    }

    private func fixedCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    func testEntriesGroupByMonthNewestFirstWithTheMonthsChange() throws {
        let calendar = try fixedCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 9, day: 25)))
        let metrics = [
            metric(daysAgo: 0, weight: 79.0, source: "healthkit", now: now, calendar: calendar),
            metric(daysAgo: 1, weight: 79.4, source: "healthkit", now: now, calendar: calendar),
            metric(daysAgo: 2, weight: nil, photo: "file:///photo.jpg", now: now, calendar: calendar),
            metric(daysAgo: 2, weight: nil, now: now, calendar: calendar),
            metric(daysAgo: 45, weight: 81.0, now: now, calendar: calendar)
        ]
        let sections = HomeV2EntriesPolicy.sections(
            metrics: metrics,
            unit: "kg",
            weightValue: { $0.weight },
            hasPhoto: { $0.photoUrl != nil },
            calendar: calendar,
            now: now
        )
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].rows.count, 3, "Weight-only, weight+photo and photo-only days all list; empty days do not")
        XCTAssertEqual(sections[0].rows.first?.valueText, "79.0 kg")
        XCTAssertEqual(sections[0].rows.last?.valueText, "—")
        XCTAssertEqual(sections[0].delta, "Down 0.4 kg")
        XCTAssertNil(sections[1].delta, "One weight is not a change")
        XCTAssertEqual(sections[1].rows.first?.source, "Typed")
    }

    func testEntriesOrderSeptemberAndOctoberChronologicallyAtMonthBoundary() throws {
        let calendar = try fixedCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 1)))
        let sections = HomeV2EntriesPolicy.sections(
            metrics: [
                metric(daysAgo: 0, weight: 79.0, now: now, calendar: calendar),
                metric(daysAgo: 1, weight: 79.4, now: now, calendar: calendar),
                metric(daysAgo: 2, weight: nil, photo: "file:///photo.jpg", now: now, calendar: calendar),
                metric(daysAgo: 2, weight: nil, now: now, calendar: calendar),
                metric(daysAgo: 45, weight: 81.0, now: now, calendar: calendar)
            ],
            unit: "kg",
            weightValue: { $0.weight },
            hasPhoto: { $0.photoUrl != nil },
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(sections.map(\.id), ["2026-10", "2026-9", "2026-8"])
        XCTAssertEqual(sections.map { $0.rows.count }, [1, 2, 1])
        XCTAssertEqual(sections[0].rows.first?.valueText, "79.0 kg")
        XCTAssertEqual(sections[1].rows.first?.valueText, "79.4 kg")
        XCTAssertEqual(sections[1].rows.last?.valueText, "—")
        XCTAssertTrue(sections.allSatisfy { $0.delta == nil }, "Month changes must not cross month boundaries")
    }

    func testEntriesOrderDecemberAndJanuaryAcrossYearBoundary() throws {
        let calendar = try fixedCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_027, month: 1, day: 1)))
        let sections = HomeV2EntriesPolicy.sections(
            metrics: [
                metric(daysAgo: 0, weight: 79.0, now: now, calendar: calendar),
                metric(daysAgo: 1, weight: 79.4, now: now, calendar: calendar),
                metric(daysAgo: 2, weight: 79.8, now: now, calendar: calendar),
                metric(daysAgo: 45, weight: 81.0, now: now, calendar: calendar)
            ],
            unit: "kg",
            weightValue: { $0.weight },
            hasPhoto: { $0.photoUrl != nil },
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(sections.map(\.id), ["2027-1", "2026-12", "2026-11"])
        XCTAssertEqual(sections.map { $0.rows.count }, [1, 2, 1])
        XCTAssertEqual(sections[0].rows.first?.valueText, "79.0 kg")
        XCTAssertEqual(sections[1].rows.first?.valueText, "79.4 kg")
        XCTAssertEqual(sections[1].delta, "Down 0.4 kg")
        XCTAssertNil(sections[0].delta)
        XCTAssertNil(sections[2].delta)
    }
}

@MainActor
extension HomeV2ContextPolicyTests {
    func testDailyStepsCanReadTodayWithoutFabricatingABodyMetric() async throws {
        let today = Date()
        let ownership = stepsOwner()
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { owner, start, _ in
            [self.stepsRow(owner: owner, date: start, steps: 0)]
        }
        XCTAssertEqual(reader.state(for: today, ownership: ownership, ownsSession: { $0 == ownership }), .loading)

        await reader.load(date: today, ownership: ownership, ownsSession: { $0 == ownership })

        XCTAssertEqual(reader.state(for: today, ownership: ownership, ownsSession: { $0 == ownership }), .value(0))
        XCTAssertEqual(reader.snapshot?.key, reader.key(for: today, ownership: ownership))
    }

    func testDailyStepsDoesNotInventAZeroFromMissingOrAmbiguousStoredSteps() async throws {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        let manager = CoreDataManager(persistentStoreDescriptions: [description])
        let ready = expectation(
            for: NSPredicate { _, _ in manager.persistentStoreLoadState != .loading },
            evaluatedWith: manager
        )
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(manager.persistentStoreLoadState, .ready)
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { owner, start, end in
            await HomeV2DailyStepsReader.readStoredMetrics(for: owner, from: start, to: end, coreDataManager: manager)
        }
        let ownership = stepsOwner()

        let values: [Int?] = [nil, 0, 321]
        for (index, value) in values.enumerated() {
            let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 86_400)
            let selected = stepsMetric(date: date)
            let row = stepsRow(id: "persisted-\(index)", date: date, steps: value)
            try await manager.saveDailyMetricsAndWait(row, userId: ownership.subject)
            let stored = await manager.fetchDailyMetrics(for: ownership.subject, date: date)
            XCTAssertEqual(stored?.steps, Int32(value ?? 0), "The legacy writer loses nil-versus-zero presence")

            await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })

            let expected: HomeV2DailyStepsReader.State = value == 321 ? .value(321) : .missing
            XCTAssertEqual(reader.state(for: selected, ownership: ownership, ownsSession: { $0 == ownership }), expected)
        }
    }

    func testDailyStepsFiltersOwnerAndHalfOpenDayBeforeSelectingNewestDuplicate() async throws {
        let selected = stepsMetric()
        let calendar = try fixedCalendar()
        let start = calendar.startOfDay(for: selected.date)
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let reader = HomeV2DailyStepsReader(calendar: calendar) { _, _, _ in
            [
                self.stepsRow(id: "older", date: selected.date, steps: 400, updated: 1),
                self.stepsRow(id: "latest-a", date: selected.date, steps: 500, updated: 2),
                self.stepsRow(id: "latest-z", date: selected.date, steps: 600, updated: 2),
                self.stepsRow(owner: "other", date: selected.date, steps: 900, updated: 9),
                self.stepsRow(date: end, steps: 1_000, updated: 10),
                self.stepsRow(date: start.addingTimeInterval(-1), steps: 2_000, updated: 11)
            ]
        }
        let ownership = stepsOwner()

        await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })

        XCTAssertEqual(reader.snapshot?.state, .value(600))
    }

    func testDailyStepsMissingOrNegativeNewestValueDoesNotBorrowAnOlderValue() async throws {
        let selected = stepsMetric()
        let ownership = stepsOwner()
        for value: Int? in [nil, -1] {
            let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in
                [
                    self.stepsRow(id: "old", date: selected.date, steps: 8_000, updated: 1),
                    self.stepsRow(id: "new", date: selected.date, steps: value, updated: 2)
                ]
            }
            await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })
            XCTAssertEqual(reader.snapshot?.state, .missing)
        }
    }

    func testDailyStepsFetchesOldSelectedDayWithoutThirtyDayLimitOrTodayFallback() async throws {
        let calendar = try fixedCalendar()
        let selected = metric(daysAgo: 90, weight: nil, now: Date(), calendar: calendar)
        let start = calendar.startOfDay(for: selected.date)
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let ownership = stepsOwner()
        let reader = HomeV2DailyStepsReader(calendar: calendar) { owner, from, to in
            XCTAssertEqual(owner, ownership.subject)
            XCTAssertEqual(from, start)
            XCTAssertEqual(to, end)
            return [self.stepsRow(date: Date(), steps: 9_000)]
        }

        await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })
        XCTAssertEqual(reader.snapshot?.state, .missing)
        let oldReader = HomeV2DailyStepsReader(calendar: calendar) { _, _, _ in
            [self.stepsRow(date: selected.date, steps: 123)]
        }
        await oldReader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })
        XCTAssertEqual(oldReader.snapshot?.state, .value(123))
    }

    func testDailyStepsUsesCalendarDayAcrossDaylightSavingChange() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 3, day: 8, hour: 12)))
        let selected = stepsMetric(date: date)
        let reader = HomeV2DailyStepsReader(calendar: calendar) { _, start, end in
            XCTAssertEqual(end.timeIntervalSince(start), 23 * 60 * 60)
            return [self.stepsRow(date: start, steps: 0)]
        }
        let ownership = stepsOwner()

        await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })

        XCTAssertEqual(reader.snapshot?.state, .value(0))
    }

    func testDailyStepsLateDayReadCannotReplaceNewSelection() async throws {
        let calendar = try fixedCalendar()
        let first = stepsMetric()
        let second = stepsMetric(date: first.date.addingTimeInterval(86_400))
        let held = HeldDailyStepsRead()
        let ownership = stepsOwner()
        let reader = HomeV2DailyStepsReader(calendar: calendar) { _, start, _ in
            if start == calendar.startOfDay(for: first.date) { return await held.read() }
            return [self.stepsRow(date: second.date, steps: 222)]
        }
        let task = Task { await reader.load(metric: first, ownership: ownership, ownsSession: { $0 == ownership }) }
        await fulfillment(of: [held.started], timeout: 2)
        XCTAssertEqual(reader.state(for: first, ownership: ownership, ownsSession: { $0 == ownership }), .loading)
        XCTAssertEqual(reader.state(for: second, ownership: ownership, ownsSession: { $0 == ownership }), .loading)
        await reader.load(metric: second, ownership: ownership, ownsSession: { $0 == ownership })
        try held.resume(with: [stepsRow(date: first.date, steps: 111)])
        await task.value

        XCTAssertEqual(reader.state(for: second, ownership: ownership, ownsSession: { $0 == ownership }), .value(222))
        XCTAssertEqual(reader.state(for: first, ownership: ownership, ownsSession: { $0 == ownership }), .loading)
    }

    func testDailyStepsLateSameDayReadCannotOverwriteReload() async throws {
        let selected = stepsMetric()
        let ownership = stepsOwner()
        let held = HeldDailyStepsRead()
        var reads = 0
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in
            reads += 1
            if reads == 1 { return await held.read() }
            return [self.stepsRow(date: selected.date, steps: 222)]
        }
        let task = Task { await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership }) }
        await fulfillment(of: [held.started], timeout: 2)
        await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == ownership })
        try held.resume(with: [stepsRow(date: selected.date, steps: 111)])
        await task.value

        XCTAssertEqual(reader.snapshot?.state, .value(222))
    }

    func testDailyStepsHeldAccountAReadCannotReplaceAccountB() async throws {
        try await assertHeldStepsReadRejectsReplacement(stepsOwner(subject: "other", generation: 2))
    }

    func testDailyStepsHeldOldLifetimeCannotReplaceSameSubjectNewLifetime() async throws {
        try await assertHeldStepsReadRejectsReplacement(stepsOwner(generation: 2))
    }

    func testDailyStepsRenderHidesOldLifetimeBeforeReplacementLoadStarts() async throws {
        let selected = stepsMetric()
        let ownership = stepsOwner()
        var current = ownership
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in
            [self.stepsRow(date: selected.date, steps: 100)]
        }
        await reader.load(metric: selected, ownership: ownership, ownsSession: { $0 == current })
        XCTAssertEqual(reader.state(for: selected, ownership: ownership, ownsSession: { $0 == current }), .value(100))
        current = stepsOwner(generation: 2)

        XCTAssertEqual(reader.state(for: selected, ownership: ownership, ownsSession: { $0 == current }), .missing)
        XCTAssertEqual(reader.state(for: selected, ownership: current, ownsSession: { $0 == current }), .loading)
        XCTAssertEqual(reader.state(for: selected, ownership: nil, ownsSession: { $0 == current }), .missing)
    }

    func testDailyStepsRejectsMismatchedMetricOrStaleOwnershipBeforeReading() async throws {
        let selected = stepsMetric()
        let ownership = stepsOwner()
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in
            XCTFail("Unowned selected days must not enter the reader")
            return []
        }
        await reader.load(metric: selected, ownership: stepsOwner(subject: "other"), ownsSession: { _ in true })
        await reader.load(metric: selected, ownership: ownership, ownsSession: { _ in false })

        XCTAssertNil(reader.snapshot)
        XCTAssertNil(reader.key(for: selected, ownership: stepsOwner(subject: "other")))
    }

    func testDailyStepsCancelledHeldReadDoesNotPublishItsValue() async throws {
        let selected = stepsMetric()
        let ownership = stepsOwner()
        let held = HeldDailyStepsRead()
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in await held.read() }
        let task = Task { await reader.load(metric: selected, ownership: ownership, ownsSession: { _ in true }) }
        await fulfillment(of: [held.started], timeout: 2)
        task.cancel()
        try held.resume(with: [stepsRow(date: selected.date, steps: 999)])
        await task.value

        XCTAssertEqual(reader.snapshot?.state, .loading)
    }

    private func assertHeldStepsReadRejectsReplacement(
        _ replacement: AuthManager.ProfileSessionOwnership
    ) async throws {
        let original = stepsOwner()
        var current = original
        let first = stepsMetric()
        let second = stepsMetric(owner: replacement.subject)
        let held = HeldDailyStepsRead()
        var reads = 0
        let reader = HomeV2DailyStepsReader(calendar: try fixedCalendar()) { _, _, _ in
            reads += 1
            if reads == 1 { return await held.read() }
            return [self.stepsRow(owner: replacement.subject, date: second.date, steps: 222)]
        }
        let task = Task { await reader.load(metric: first, ownership: original, ownsSession: { $0 == current }) }
        await fulfillment(of: [held.started], timeout: 2)
        current = replacement
        XCTAssertEqual(reader.state(for: first, ownership: original, ownsSession: { $0 == current }), .missing)
        try held.resume(with: [stepsRow(date: first.date, steps: 111)])
        await task.value
        // No replacement request has run: this proves lifetime admission, not only request-ID rejection.
        XCTAssertEqual(reader.snapshot?.state, .loading)
        await reader.load(metric: second, ownership: replacement, ownsSession: { $0 == current })
        // A late old load must not clear the replacement's successfully published value either.
        await reader.load(metric: first, ownership: original, ownsSession: { $0 == current })

        XCTAssertEqual(reader.state(for: second, ownership: replacement, ownsSession: { $0 == current }), .value(222))
        XCTAssertEqual(reader.snapshot?.key.ownership, replacement)
    }

    private func stepsOwner(subject: String = "user", generation: UInt64 = 1) -> AuthManager.ProfileSessionOwnership {
        AuthManager.ProfileSessionOwnership(subject: subject, generation: generation)
    }

    private func stepsMetric(owner: String = "user", date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> BodyMetrics {
        BodyMetrics(
            id: "body", userId: owner, date: date, weight: nil, weightUnit: "kg",
            bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: "manual", createdAt: date, updatedAt: date
        )
    }

    private func stepsRow(
        id: String = "daily",
        owner: String = "user",
        date: Date,
        steps: Int?,
        updated: TimeInterval = 0
    ) -> DailyMetrics {
        DailyMetrics(
            id: id, userId: owner, date: date, steps: steps, notes: nil,
            createdAt: date, updatedAt: date.addingTimeInterval(updated)
        )
    }
}

@MainActor
private final class HeldDailyStepsRead {
    let started = XCTestExpectation(description: "Selected-day read admitted")
    private var continuation: CheckedContinuation<[DailyMetrics], Never>?

    func read() async -> [DailyMetrics] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func resume(with rows: [DailyMetrics]) throws {
        let continuation = try XCTUnwrap(continuation)
        self.continuation = nil
        continuation.resume(returning: rows)
    }
}

@MainActor
extension HomeV2ContextPolicyTests {
    func testHistoricalSamplesKeepTimestampSourceAndReviewWarning() throws {
        let original = correctionMetric(weight: 18, bodyFat: 16.9, method: "dexa")
        XCTAssertTrue(HomeV2Provenance.detailedLabel(for: original).contains("Withings via Apple Health"))
        XCTAssertTrue(HomeV2Provenance.weightSubline(for: original).contains(HomeV2WeightQuality.reviewMessage))
        XCTAssertEqual(HomeV2Provenance.weightText(displayValue: 18, metric: original, unit: "kg"), "18.00 kg")
        let corrected = HomeV2CorrectionPolicy.correctedMetric(
            original, changes: .init(weight: .kilograms(81), bodyFat: .unchanged),
            updatedAt: original.updatedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(corrected.date, original.date)
        XCTAssertEqual(HomeV2Provenance.detailedLabel(for: corrected, field: .weight), "Typed")
        XCTAssertEqual(HomeV2Provenance.detailedLabel(for: corrected, field: .bodyFat), "Withings via Apple Health")
        XCTAssertEqual(corrected.metricSource, .healthKit, "Import origin remains; only the edited field is manual")
        XCTAssertFalse(HomeV2Provenance.detailedLabel(for: corrected).contains("corrected"))
        assertCorrectionImportLineage(corrected, equals: original, manuallyEdited: [.weight])
        XCTAssertEqual(original.weight, 18)
    }

    func testCorrectionTargetsOneRecordAndPreservesItsImportLineage() throws {
        let original = correctionMetric()
        let untouched = try HomeV2CorrectionPolicy.changes(
            weightText: "81.2",
            weightWasEdited: false,
            unit: "kg",
            bodyFat: .init(
                text: "16.9",
                wasEdited: false,
                original: original.bodyFatPercentage,
                method: original.bodyFatMethod,
                originalMethod: original.bodyFatMethod
            )
        )
        XCTAssertEqual(HomeV2CorrectionPolicy.correctedMetric(original, changes: untouched), original)
        let changes = try HomeV2CorrectionPolicy.changes(
            weightText: "82.0",
            weightWasEdited: true,
            unit: "kg",
            bodyFat: .init(
                text: "16.9",
                wasEdited: false,
                original: original.bodyFatPercentage,
                method: original.bodyFatMethod,
                originalMethod: original.bodyFatMethod
            )
        )
        let corrected = HomeV2CorrectionPolicy.correctedMetric(original, changes: changes)
        XCTAssertEqual(corrected.id, original.id)
        XCTAssertEqual(corrected.userId, original.userId)
        XCTAssertEqual(corrected.date, original.date)
        XCTAssertEqual(corrected.localDate, original.localDate)
        XCTAssertEqual(corrected.createdAt, original.createdAt)
        XCTAssertEqual(corrected.weight, 82)
        XCTAssertEqual(corrected.bodyFatPercentage, original.bodyFatPercentage)
        XCTAssertEqual(corrected.bodyFatMethod, original.bodyFatMethod)
        assertCorrectionImportLineage(corrected, equals: original, manuallyEdited: [.weight])
        XCTAssertEqual(corrected.notes, original.notes)
        XCTAssertEqual(corrected.photoUrl, original.photoUrl)
        XCTAssertEqual(corrected.muscleMass, original.muscleMass)
        XCTAssertEqual(corrected.boneMass, original.boneMass)
        XCTAssertEqual(corrected.waistCm, original.waistCm)
        XCTAssertEqual(corrected.hipCm, original.hipCm)
        XCTAssertEqual(corrected.waistUnit, original.waistUnit)
        XCTAssertEqual(original.weight, 81.234567)
        XCTAssertEqual(original.bodyFatPercentage, 16.912345)
    }

    func testCorrectionUsesChosenMethodAndOnlyExplicitlyClearsBodyFat() throws {
        let original = correctionMetric()
        let methodOnly = try HomeV2CorrectionPolicy.changes(
            weightText: "81.2",
            weightWasEdited: false,
            unit: "kg",
            bodyFat: .init(
                text: "16.9",
                wasEdited: false,
                original: original.bodyFatPercentage,
                method: BodyFatEntryMethod.calipers.rawValue,
                originalMethod: original.bodyFatMethod
            )
        )
        let changedMethod = HomeV2CorrectionPolicy.correctedMetric(original, changes: methodOnly)
        XCTAssertEqual(changedMethod.bodyFatPercentage, original.bodyFatPercentage)
        XCTAssertEqual(changedMethod.bodyFatMethod, BodyFatEntryMethod.calipers.rawValue)
        let explicitClear = try HomeV2CorrectionPolicy.changes(
            weightText: "81.2",
            weightWasEdited: false,
            unit: "kg",
            bodyFat: .init(
                text: "",
                wasEdited: true,
                original: original.bodyFatPercentage,
                method: original.bodyFatMethod,
                originalMethod: original.bodyFatMethod
            )
        )
        let cleared = HomeV2CorrectionPolicy.correctedMetric(original, changes: explicitClear)
        XCTAssertNil(cleared.bodyFatPercentage)
        XCTAssertNil(cleared.bodyFatMethod)
        XCTAssertEqual(cleared.weight, original.weight)
        assertCorrectionImportLineage(cleared, equals: original, manuallyEdited: [.bodyFat])
        let bodyOnly = correctionMetric(weight: nil, bodyFat: nil, method: nil)
        let added = HomeV2CorrectionPolicy.correctedMetric(
            bodyOnly, changes: .init(bodyFat: .reading(20, method: BodyFatEntryMethod.dexa.rawValue))
        )
        XCTAssertNil(added.weight)
        XCTAssertEqual(added.bodyFatMethod, BodyFatEntryMethod.dexa.rawValue)
        let flagged = correctionMetric(weight: 18)
        XCTAssertEqual(HomeV2CorrectionPolicy.correctedMetric(
            flagged, changes: .init(bodyFat: .reading(20, method: "caliper"))
        ).weight, 18)
    }

    func testHeldCorrectionRejectsReplacementLogoutAndCancellationInsideActualStore() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        for scenario in ["other-owner", "same-owner-new-generation", "logout", "cancel"] {
            let store = correctionStore()
            let original = correctionMetric()
            try await store.saveBodyMetricsAndWait(original, userId: original.userId)
            let savedRows = await store.fetchBodyMetrics(for: original.userId)
            let row = try XCTUnwrap(savedRows.first)
            let storedOriginal = correctionMetric(updatedAt: try XCTUnwrap(row.updatedAt))
            installCorrectionSession(original.userId)
            let ownership = try XCTUnwrap(auth.captureAccountSession())
            let held = HeldHomeV2Correction()
            var admitted = 0
            var published = 0
            let task = Task { await HomeV2CorrectionPolicy.save(
                storedOriginal, changes: .init(weight: .kilograms(82)), ownership: ownership,
                ownsSession: { auth.ownsAccountSession($0) },
                persist: { corrected, admission in
                    await held.wait()
                    try await HomeV2CorrectionPolicy.persistCorrection(
                        corrected, replacing: storedOriginal, store: store, admission: {
                            try admission()
                            admitted += 1
                        }
                    )
                },
                didSave: { _, _ in published += 1 }
            )
            }
            await fulfillment(of: [held.started], timeout: 2)
            switch scenario {
            case "other-owner": installCorrectionSession("replacement")
            case "same-owner-new-generation": installCorrectionSession(original.userId)
            case "logout": auth.currentUser = nil; auth.authSession = nil
            default: task.cancel()
            }
            try held.resume()
            let saved = await task.value
            XCTAssertFalse(saved, scenario)
            XCTAssertEqual(admitted, 0, scenario)
            XCTAssertEqual(published, 0, scenario)
            XCTAssertEqual(row.weight, original.weight, scenario)
            XCTAssertEqual(row.updatedAt, storedOriginal.updatedAt, scenario)
            XCTAssertFalse(store.viewContext.hasChanges, scenario)
        }
    }

    func testCorrectionCurrentOwnerPersistsExactRecordAndSuppressesPostWriteStaleCompletion() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        for replaceAfterWrite in [false, true] {
            let store = correctionStore()
            let original = correctionMetric()
            try await store.saveBodyMetricsAndWait(original, userId: original.userId)
            let savedRows = await store.fetchBodyMetrics(for: original.userId)
            let row = try XCTUnwrap(savedRows.first)
            let storedOriginal = correctionMetric(updatedAt: try XCTUnwrap(row.updatedAt))
            installCorrectionSession(original.userId)
            let ownership = try XCTUnwrap(auth.captureAccountSession())
            let held = HeldHomeV2Correction()
            var published = 0
            let task = Task { await HomeV2CorrectionPolicy.save(
                storedOriginal, changes: .init(weight: .kilograms(82)), ownership: ownership,
                ownsSession: { auth.ownsAccountSession($0) },
                persist: { corrected, admission in
                    try await HomeV2CorrectionPolicy.persistCorrection(
                        corrected, replacing: storedOriginal, store: store, admission: admission
                    )
                    if replaceAfterWrite { await held.wait() }
                },
                didSave: { _, canPublish in
                    guard canPublish() else { return }
                    published += 1
                }
            )
            }
            if replaceAfterWrite {
                await fulfillment(of: [held.started], timeout: 2)
                installCorrectionSession(original.userId)
                try held.resume()
            }
            let saved = await task.value
            XCTAssertEqual(saved, !replaceAfterWrite)
            XCTAssertEqual(published, replaceAfterWrite ? 0 : 1)
            XCTAssertEqual(row.weight, 82)
            let rowsAfterWrite = await store.fetchBodyMetrics(for: original.userId)
            XCTAssertEqual(rowsAfterWrite.map(\.id), [original.id])
            XCTAssertEqual(row.photoUrl, original.photoUrl)
            // A write already admitted for A remains A's write; this is not rollback.
        }
        var writes = 0
        let denied = await HomeV2CorrectionPolicy.save(
            correctionMetric(), changes: .init(weight: .kilograms(82)), ownership: nil,
            ownsSession: { _ in true }, persist: { _, _ in writes += 1 },
            didSave: { _, _ in XCTFail("A correction without an original session must not complete") }
        )
        XCTAssertFalse(denied)
        XCTAssertEqual(writes, 0)
    }

    func testCorrectionRefusesDeletedMissingAndNewerExactTargetRecords() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        for scenario in ["tombstone", "missing", "newer"] {
            let store = correctionStore()
            let original = correctionMetric()
            try await store.saveBodyMetricsAndWait(original, userId: original.userId)
            let savedRows = await store.fetchBodyMetrics(for: original.userId)
            let row = try XCTUnwrap(savedRows.first)
            let storedOriginal = correctionMetric(updatedAt: try XCTUnwrap(row.updatedAt))
            if scenario == "tombstone" { row.isMarkedDeleted = true }
            if scenario == "newer" { row.updatedAt = storedOriginal.updatedAt.addingTimeInterval(1) }
            if scenario == "missing" { store.viewContext.delete(row) }
            try store.viewContext.save()
            installCorrectionSession(original.userId)
            let ownership = try XCTUnwrap(auth.captureAccountSession())
            var completed = 0
            let saved = await HomeV2CorrectionPolicy.save(
                storedOriginal, changes: .init(weight: .kilograms(82)), ownership: ownership,
                ownsSession: { auth.ownsAccountSession($0) },
                persist: { corrected, admission in
                    try await HomeV2CorrectionPolicy.persistCorrection(
                        corrected, replacing: storedOriginal, store: store, admission: admission
                    )
                },
                didSave: { _, _ in completed += 1 }
            )
            XCTAssertFalse(saved, scenario)
            XCTAssertEqual(completed, 0, scenario)
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", original.id)
            let remaining = try store.viewContext.fetch(request)
            if scenario == "missing" {
                XCTAssertTrue(remaining.isEmpty)
            } else {
                XCTAssertEqual(remaining.count, 1)
                XCTAssertEqual(remaining.first?.weight, original.weight)
                XCTAssertEqual(remaining.first?.isMarkedDeleted, scenario == "tombstone")
            }
            XCTAssertFalse(store.viewContext.hasChanges)
        }
    }

    func testCorrectionAdmissionRejectsOwnedAndEmptyOwnerDuplicateWriterCandidates() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let store = correctionStore()
        let original = correctionMetric()
        try await store.saveBodyMetricsAndWait(original, userId: original.userId)
        let savedRows = await store.fetchBodyMetrics(for: original.userId)
        let owned = try XCTUnwrap(savedRows.first)
        let storedOriginal = correctionMetric(updatedAt: try XCTUnwrap(owned.updatedAt))
        // Deliberate legitimate pending context row: do not save/uniqueness-merge it away.
        let legacy = CachedBodyMetrics(context: store.viewContext)
        legacy.id = original.id
        legacy.userId = ""
        legacy.date = original.date
        legacy.weight = 90
        legacy.updatedAt = original.updatedAt
        legacy.syncStatus = "pending"
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", original.id)
        XCTAssertEqual(try store.viewContext.fetch(request).count, 2, "Actual writer id-only set must contain both candidates")
        XCTAssertTrue(store.viewContext.hasChanges)
        let beforeOwnedWeight = owned.weight
        let beforeOwnedUpdated = owned.updatedAt
        let beforeLegacyWeight = legacy.weight
        let beforeLegacyOwner = legacy.userId
        let beforeLegacyUpdated = legacy.updatedAt
        installCorrectionSession(original.userId)
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        var completed = 0
        let saved = await HomeV2CorrectionPolicy.save(
            storedOriginal, changes: .init(weight: .kilograms(82)), ownership: ownership,
            ownsSession: { auth.ownsAccountSession($0) },
            persist: { corrected, admission in
                try await HomeV2CorrectionPolicy.persistCorrection(
                    corrected, replacing: storedOriginal, store: store, admission: admission
                )
            },
            didSave: { _, _ in completed += 1 }
        )
        XCTAssertFalse(saved)
        XCTAssertEqual(completed, 0)
        XCTAssertEqual(try store.viewContext.fetch(request).count, 2)
        XCTAssertEqual(owned.weight, beforeOwnedWeight)
        XCTAssertEqual(owned.updatedAt, beforeOwnedUpdated)
        XCTAssertEqual(legacy.weight, beforeLegacyWeight)
        XCTAssertEqual(legacy.userId, beforeLegacyOwner)
        XCTAssertEqual(legacy.updatedAt, beforeLegacyUpdated)
        XCTAssertTrue(legacy.isInserted)
        XCTAssertTrue(store.viewContext.hasChanges, "Preserve preexisting pending state; do not save or roll back other work")
        store.viewContext.rollback() // Test-owned cleanup after assertions only.
    }

    func testCorrectionNeutralProvenanceAndActualImperialEditorConversion() throws {
        let metric = correctionMetric()
        func source(_ raw: String?) -> BodyMetrics {
            BodyMetrics(
                id: metric.id, userId: metric.userId, date: metric.date, weight: metric.weight,
                weightUnit: metric.weightUnit, bodyFatPercentage: metric.bodyFatPercentage,
                bodyFatMethod: metric.bodyFatMethod, muscleMass: nil, boneMass: nil,
                notes: nil, photoUrl: nil, dataSource: raw,
                sourceMetadata: .init(sourceName: "Named source", sourceBundleId: "arbitrary.bundle", quantityType: "arbitrary"),
                createdAt: metric.createdAt, updatedAt: metric.updatedAt
            )
        }
        for raw in [Optional("manual"), nil, Optional("unknown-source")] {
            let row = source(raw)
            let label = HomeV2Provenance.detailedLabel(for: row)
            XCTAssertFalse(label.contains("corrected"))
            XCTAssertFalse(label.contains("via Apple Health"), "Arbitrary bundle/type metadata is not HealthKit history")
            XCTAssertTrue(label.contains("Named source"))
        }
        XCTAssertEqual(HomeV2Provenance.detailedLabel(for: metric), "Withings via Apple Health")
        let changes = try HomeV2CorrectionPolicy.changes(
            weightText: "180",
            weightWasEdited: true,
            unit: "lb",
            bodyFat: .init(
                text: "16.9",
                wasEdited: false,
                original: metric.bodyFatPercentage,
                method: metric.bodyFatMethod,
                originalMethod: metric.bodyFatMethod
            )
        )
        let corrected = HomeV2CorrectionPolicy.correctedMetric(metric, changes: changes)
        XCTAssertEqual(try XCTUnwrap(corrected.weight), 81.64672369841515, accuracy: 0.000000001)
        XCTAssertEqual(corrected.bodyFatPercentage, metric.bodyFatPercentage)
        XCTAssertEqual(corrected.bodyFatMethod, metric.bodyFatMethod)
        assertCorrectionImportLineage(corrected, equals: metric, manuallyEdited: [.weight])
        XCTAssertFalse(HomeV2Provenance.detailedLabel(for: corrected).contains("corrected"))
    }

    func testCorrectionEditorOriginalReceiptCannotRebaseToSameAccountGeneration() {
        let original = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        XCTAssertTrue(HomeV2CorrectionPolicy.isEditorCurrent(original: original, current: original))
        XCTAssertFalse(HomeV2CorrectionPolicy.isEditorCurrent(
            original: original, current: .init(subject: "owner", generation: 2)
        ))
        XCTAssertFalse(HomeV2CorrectionPolicy.isEditorCurrent(
            original: original, current: .init(subject: "other", generation: 1)
        ))
        XCTAssertFalse(HomeV2CorrectionPolicy.isEditorCurrent(original: original, current: nil))
        XCTAssertFalse(HomeV2CorrectionPolicy.isEditorCurrent(original: nil, current: nil))
        // Actual mounted held-save observation is additionally mandatory; this is not mounted UI proof.
    }

    func testEntriesSelectExactRawRecordAcrossSameDayReorderAndRejectReplacement() throws {
        let receipt = AuthManager.ProfileSessionOwnership(subject: "entries-owner", generation: 1)
        let first = entriesBoundaryMetric("first")
        let second = entriesBoundaryMetric("second", bodyFat: 20)
        for rows in [[first, second], [second, first]] {
            let resolved = HomeV2EntriesPolicy.contextMetric(
                on: first.date, selected: .init(first), metrics: rows,
                ownership: receipt, currentOwnership: receipt
            )
            XCTAssertEqual(resolved, first)
            XCTAssertNil(resolved?.bodyFatPercentage, "A same-day neighbor must not fill the stored raw record")
        }
        let replaced = entriesBoundaryMetric("first", weight: 90)
        XCTAssertNil(HomeV2EntriesPolicy.admittedMetric(
            first, metrics: [replaced, second], ownership: receipt, currentOwnership: receipt
        ))
        XCTAssertNil(HomeV2EntriesPolicy.admittedMetric(
            first, metrics: [first, entriesBoundaryMetric("first", owner: "")],
            ownership: receipt, currentOwnership: receipt
        ))
        XCTAssertNil(HomeV2EntriesPolicy.admittedMetric(
            first, metrics: [first], ownership: nil, currentOwnership: nil
        ))
        XCTAssertNil(HomeV2EntriesPolicy.admittedMetric(
            first, metrics: [first], ownership: receipt,
            currentOwnership: .init(subject: "entries-owner", generation: 2)
        ))
        XCTAssertNil(HomeV2EntriesPolicy.contextMetric(
            on: first.date, selected: .init(first), metrics: [second],
            ownership: receipt, currentOwnership: receipt
        ), "Deleted explicit selection must not retarget its same-day neighbor")
    }

    func testEntriesPreserveBFOnlyAndFlaggedWeightMetadataWithoutInference() throws {
        let bfOnly = entriesBoundaryMetric("bf-only", weight: nil, bodyFat: 16.2, method: "dexa")
        let rawFlagged = entriesBoundaryMetric("raw-18", weight: 18, bodyFat: 17.4)
        let rows = HomeV2EntriesPolicy.sections(
            metrics: [bfOnly, rawFlagged], unit: "kg", weightValue: { $0.weight }, hasPhoto: { _ in false }
        ).flatMap(\.rows)
        XCTAssertEqual(Set(rows.map(\.id)), Set(["bf-only", "raw-18"]))
        let bf = try XCTUnwrap(rows.first(where: { $0.id == "bf-only" }))
        XCTAssertEqual(bf.metric, bfOnly)
        XCTAssertEqual(bf.valueText, "16.2%")
        XCTAssertNil(bf.metric.weight)
        XCTAssertEqual(bf.metric.bodyFatMethod, "dexa")
        XCTAssertEqual(bf.metric.sourceMetadata, bfOnly.sourceMetadata)
        XCTAssertEqual(rows.first(where: { $0.id == "raw-18" })?.metric, rawFlagged)
        XCTAssertEqual(rawFlagged.weight, 18, "Weight-quality filtering must not remove a raw Entries row")
    }

    func testEntriesCalendarTieIsDeterministicAndExplicitSelectionWins() {
        let receipt = AuthManager.ProfileSessionOwnership(subject: "entries-owner", generation: 1)
        let first = entriesBoundaryMetric("a")
        let second = entriesBoundaryMetric("b", bodyFat: 20)
        for rows in [[first, second], [second, first]] {
            XCTAssertEqual(HomeV2EntriesPolicy.contextMetric(
                on: first.date, selected: nil, metrics: rows,
                ownership: receipt, currentOwnership: receipt
            ), second)
            XCTAssertEqual(HomeV2EntriesPolicy.contextMetric(
                on: first.date, selected: .init(first), metrics: rows,
                ownership: receipt, currentOwnership: receipt
            ), first)
        }
    }

    func testEntriesDestinationRejectsCorrectionDeletionGenerationAndABAReturn() {
        let receipt = AuthManager.ProfileSessionOwnership(subject: "entries-owner", generation: 1)
        let original = entriesBoundaryMetric("selected")
        let corrected = HomeV2CorrectionPolicy.correctedMetric(original, changes: .init(weight: .kilograms(90)))
        let route = HomeV2ContextRoute(metric: original, ownership: receipt)
        XCTAssertEqual(HomeV2EntriesPolicy.admittedDestination(
            route, current: route, metrics: [original], currentOwnership: receipt
        ), original)
        XCTAssertNil(HomeV2EntriesPolicy.admittedDestination(
            route, current: route, metrics: [corrected], currentOwnership: receipt
        ), "Same-id correction is not the captured destination revision")
        XCTAssertNil(HomeV2EntriesPolicy.admittedDestination(
            route, current: route, metrics: [entriesBoundaryMetric("neighbor")], currentOwnership: receipt
        ))
        XCTAssertNil(HomeV2EntriesPolicy.admittedDestination(
            route, current: route, metrics: [original],
            currentOwnership: .init(subject: "entries-owner", generation: 2)
        ))
        XCTAssertNil(HomeV2EntriesPolicy.admittedDestination(
            route, current: nil, metrics: [original], currentOwnership: receipt
        ))
        let reopened = HomeV2ContextRoute(metric: original, ownership: receipt)
        XCTAssertNotEqual(route.id, reopened.id)
        XCTAssertNil(HomeV2EntriesPolicy.admittedDestination(
            route, current: reopened, metrics: [original], currentOwnership: receipt
        ), "Close/reopen with the same payload cannot admit an old callback")
        let correctedReopen = HomeV2ContextRoute(metric: corrected, ownership: receipt)
        XCTAssertEqual(HomeV2EntriesPolicy.admittedDestination(
            correctedReopen, current: correctedReopen, metrics: [corrected], currentOwnership: receipt
        ), corrected, "Only explicit re-open captures the new actual raw revision")
    }

    @MainActor
    func testPresentationAndEntriesReadLeaveActualStoredRecordsUnchanged() async throws {
        let auth = AuthManager.shared
        let previousUser = auth.currentUser
        let previousSession = auth.authSession
        defer { auth.currentUser = previousUser; auth.authSession = previousSession }
        let store = correctionStore()
        let date = Date(timeIntervalSince1970: 1_790_000_123)
        let originals = [
            entriesBoundaryMetric("before", date: date.addingTimeInterval(-604_800), bodyFat: 16.9, method: "dexa"),
            entriesBoundaryMetric("selected", date: date, weight: 83.4),
            entriesBoundaryMetric("after", date: date.addingTimeInterval(604_800), bodyFat: 16.2)
        ]
        installCorrectionSession("entries-owner")
        let receipt = try XCTUnwrap(auth.captureAccountSession())
        for metric in originals { try await store.saveBodyMetricsAndWait(metric, userId: metric.userId) }
        let beforeRows = await store.fetchBodyMetrics(for: "entries-owner")
        let before = beforeRows.compactMap { $0.toBodyMetrics() }
            .sorted { $0.id < $1.id }
        XCTAssertEqual(before.count, 3)
        let selected = try XCTUnwrap(before.first(where: { $0.id == "selected" }))
        XCTAssertNil(selected.bodyFatPercentage)
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: before, owner: "entries-owner", ownership: receipt)
        let presentation = try XCTUnwrap(snapshot.presentation(
            for: .init(selected), heightCm: 178, currentOwnership: receipt
        ))
        XCTAssertEqual(try XCTUnwrap(presentation.bodyFat).amount, 16.55, accuracy: 0.00000001)
        XCTAssertEqual(String(format: "%.1f", try XCTUnwrap(presentation.bodyFat).amount), "16.6")
        XCTAssertEqual(String(format: "%.1f", try XCTUnwrap(presentation.ffmi).amount), "22.1")
        let rows = HomeV2EntriesPolicy.sections(
            metrics: snapshot.metrics, unit: "kg", weightValue: { $0.weight }, hasPhoto: { _ in false }
        ).flatMap(\.rows)
        XCTAssertNil(try XCTUnwrap(rows.first(where: { $0.id == "selected" })).metric.bodyFatPercentage)
        let afterRows = await store.fetchBodyMetrics(for: "entries-owner")
        let after = afterRows.compactMap { $0.toBodyMetrics() }
            .sorted { $0.id < $1.id }
        XCTAssertEqual(after, before, "Re-fetch actual stored values/methods/metadata/revisions after read-only presentation")
        XCTAssertFalse(store.viewContext.hasChanges)
        // Actual mounted application and owning raw UI proof remain additionally required.
    }

    @MainActor
    func testOwnContextCorrectionRestoresVerifiedStoredRevisionAfterRefresh() async throws {
        let store = correctionStore()
        let originalInput = entriesBoundaryMetric("return-target", bodyFat: 16.2, method: "dexa")
        try await store.saveBodyMetricsAndWait(originalInput, userId: originalInput.userId)
        let originalRows = await store.fetchBodyMetrics(for: originalInput.userId)
        let original = try XCTUnwrap(originalRows.first?.toBodyMetrics())
        let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
        let route = HomeV2ContextRoute(metric: original, ownership: ownership)
        let receipt = HomeV2CorrectionReturnReceipt(destination: route, editorLifetime: UUID())
        let changes = HomeV2CorrectionPolicy.Changes(bodyFat: .reading(17.4, method: "caliper"))
        let corrected = HomeV2CorrectionPolicy.correctedMetric(original, changes: changes)
        var captured: BodyMetrics?
        let stored = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
            corrected, replacing: original, changes: changes, store: store,
            admission: {}, onStored: { captured = $0 }
        )
        XCTAssertEqual(captured, stored, "Completion must capture the actual post-save row")
        XCTAssertEqual(try HomeV2CorrectionPolicy.storedMetric(stored, store: store), stored)
        XCTAssertEqual(stored.bodyFatPercentage, 17.4)
        XCTAssertEqual(stored.bodyFatMethod, "caliper")
        XCTAssertEqual(stored.weight, original.weight)
        assertCorrectionImportLineage(stored, equals: original, manuallyEdited: [.bodyFat])
        let bridge = HomeV2CorrectionReturnBridge(receipt: receipt, stored: stored)
        XCTAssertEqual(bridge.destination.id, route.id)
        XCTAssertTrue(bridge.admits(current: bridge.destination, metrics: [original], currentOwnership: ownership))
        XCTAssertTrue(bridge.admits(current: bridge.destination, metrics: [stored], currentOwnership: ownership))
        XCTAssertFalse(bridge.completed(current: bridge.destination, metrics: [original], currentOwnership: ownership))
        let refreshedRows = await store.fetchBodyMetrics(for: original.userId)
        let refreshed = refreshedRows.compactMap { $0.toBodyMetrics() }
        XCTAssertTrue(bridge.completed(current: bridge.destination, metrics: refreshed, currentOwnership: ownership))
        XCTAssertEqual(HomeV2EntriesPolicy.admittedDestination(
            bridge.destination, current: bridge.destination, metrics: refreshed, currentOwnership: ownership
        ), stored)
        XCTAssertFalse(store.viewContext.hasChanges)
        // This real writer/readback + pure bridge control is NOT mounted Context/terminal-state proof.
    }

    @MainActor
    func testHeldContextCorrectionRejectsExternalRevisionAndDestinationABA() async throws {
        let store = correctionStore()
        let input = entriesBoundaryMetric("return-target")
        try await store.saveBodyMetricsAndWait(input, userId: input.userId)
        let originalRows = await store.fetchBodyMetrics(for: input.userId)
        let original = try XCTUnwrap(originalRows.first?.toBodyMetrics())
        let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
        let route = HomeV2ContextRoute(metric: original, ownership: ownership)
        let receipt = HomeV2CorrectionReturnReceipt(destination: route, editorLifetime: UUID())
        let changes = HomeV2CorrectionPolicy.Changes(weight: .kilograms(84))
        let corrected = HomeV2CorrectionPolicy.correctedMetric(original, changes: changes)
        let stored = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
            corrected, replacing: original, changes: changes, store: store, admission: {}, onStored: { _ in }
        )
        let bridge = HomeV2CorrectionReturnBridge(receipt: receipt, stored: stored)
        let held = HeldHomeV2Correction()
        let task = Task { @MainActor in
            await held.wait()
            return try? HomeV2CorrectionPolicy.storedMetric(stored, store: store)
        }
        await fulfillment(of: [held.started], timeout: 2)
        let external = HomeV2CorrectionPolicy.correctedMetric(stored, changes: .init(weight: .kilograms(85)))
        try await store.saveBodyMetricsAndWait(external, userId: external.userId)
        try held.resume()
        let heldResult = await task.value
        XCTAssertNil(heldResult, "An external actual stored revision cannot become this Save's return receipt")
        let reopened = HomeV2ContextRoute(metric: stored, ownership: ownership)
        XCTAssertFalse(bridge.admits(current: reopened, metrics: [stored], currentOwnership: ownership))
        let newerEditor = HomeV2CorrectionReturnReceipt(destination: route, editorLifetime: UUID())
        XCTAssertNotEqual(receipt, newerEditor, "Same-route reopen still gets a distinct editor lifetime")
        XCTAssertFalse(bridge.owns(newerEditor), "Actual return admission rejects the old editor callback")
        XCTAssertFalse(bridge.admits(current: bridge.destination, metrics: [], currentOwnership: ownership))
        XCTAssertFalse(bridge.admits(
            current: bridge.destination, metrics: [stored, entriesBoundaryMetric(stored.id, owner: "")],
            currentOwnership: ownership
        ))
        // Mounted old-callback/new-editor terminal-state preservation remains a separate required witness.
    }

    @MainActor
    func testHeldContextCorrectionRejectsSameSubjectGenerationAfterStoredWrite() async throws {
        let store = correctionStore()
        let input = entriesBoundaryMetric("generation-target")
        try await store.saveBodyMetricsAndWait(input, userId: input.userId)
        let originalRows = await store.fetchBodyMetrics(for: input.userId)
        let original = try XCTUnwrap(originalRows.first?.toBodyMetrics())
        let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
        var current = ownership
        let changes = HomeV2CorrectionPolicy.Changes(weight: .kilograms(84))
        let stored = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
            HomeV2CorrectionPolicy.correctedMetric(original, changes: changes),
            replacing: original, changes: changes, store: store,
            admission: {
                guard current == ownership else { throw CancellationError() }
            }, onStored: { _ in }
        )
        let route = HomeV2ContextRoute(metric: original, ownership: ownership)
        let bridge = HomeV2CorrectionReturnBridge(
            receipt: .init(destination: route, editorLifetime: UUID()), stored: stored
        )
        let held = HeldHomeV2Correction()
        let task = Task { @MainActor in
            await held.wait()
            return bridge.completed(current: bridge.destination, metrics: [stored], currentOwnership: current)
        }
        await fulfillment(of: [held.started], timeout: 2)
        current = .init(subject: ownership.subject, generation: 2)
        try held.resume()
        let heldResult = await task.value
        XCTAssertFalse(heldResult)
        XCTAssertFalse(bridge.admits(current: bridge.destination, metrics: [stored], currentOwnership: nil))
        XCTAssertEqual(try HomeV2CorrectionPolicy.storedMetric(stored, store: store), stored)
        XCTAssertEqual(stored.userId, ownership.subject, "An admitted A write remains A; no rollback or rebasing to B")
        // Synthetic receipts only: no Keychain/account persist. Mounted generation/terminal-state proof is separate.
    }


    @MainActor
    func testFailedCaseCleanupRejectsForeignOwnershipAndTerminatesActualHeldWriterBeforeDisposal() async throws {
        let nonce = UUID()
        let suiteName = "lyb.fixture.correction.\(nonce.uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let cleanup = HomeV2CorrectionFixtureCleanup(nonce: nonce, defaults: defaults, suiteName: suiteName)
        let callback = XCTestExpectation(description: "Actual session callback disposes the exact owned suite")
        let teardownCallback = XCTestExpectation(description: "Owned teardown callback, separate bounded waiter")
        let transport = try HomeV2CorrectionFixtureTransport.make(nonce: nonce, onInvalidated: {
            Task { @MainActor in
                cleanup.didInvalidateOwnedSession()
                callback.fulfill()
                teardownCallback.fulfill()
            }
        })
        defaults.set(nonce.uuidString, forKey: "correctionFixtureOwnedNonce")
        let started = XCTestExpectation(description: "Actual original writer reaches its exact held latch")
        let held = HomeV2CorrectionFixtureHold(nonce: nonce, onHeld: { _ in started.fulfill() })
        guard cleanup.bind(held: held, transport: transport) else {
            transport.session.finishTasksAndInvalidate()
            let result = await XCTWaiter.fulfillment(of: [callback], timeout: 2)
            XCTAssertEqual(result, .completed, "Even a binding prerequisite failure owns this exact private session")
            XCTFail("The real holder/session/nonce/suite must bind before creating a writer task")
            return
        }
        let box = FailedCaseCleanupUnitTask()
        let teardownDone = XCTestExpectation(description: "Same cleanup helper completes before teardown reads its task")
        addTeardownBlock { @MainActor in
            if box.task == nil {
                box.task = Task { @MainActor in
                    let accepted = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
                        nonce: nonce, held: held, cleanup: cleanup, transport: transport,
                        originalFailure: "Owned unit teardown after a prerequisite or assertion failure"
                    )
                    teardownDone.fulfill()
                    return accepted
                }
            }
            let terminalResult = await XCTWaiter.fulfillment(of: [teardownDone], timeout: 2)
            if terminalResult == .completed, let task = box.task { _ = await task.value }
            let callbackResult = await XCTWaiter.fulfillment(of: [teardownCallback], timeout: 2)
            // Attempt both owned bounded cleanup phases before recording any additional teardown assertion.
            XCTAssertEqual(terminalResult, .completed, "Owned failed-test cleanup must observe actual terminal")
            XCTAssertEqual(callbackResult, .completed, "No invented invalidation callback or manual suite removal")
        }

        let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let ownership = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
        let store = correctionStore()
        let input = entriesBoundaryMetric("failed-case-real-writer", owner: owner)
        try await store.saveBodyMetricsAndWait(input, userId: owner)
        let originalRows = await store.fetchBodyMetrics(for: owner)
        let original = try XCTUnwrap(originalRows.first?.toBodyMetrics())
        let receipt = HomeV2CorrectionReturnReceipt(
            destination: .init(metric: original, ownership: ownership), editorLifetime: UUID()
        )
        held.bindInitialOwner(ownership)
        guard held.armNextWriter(for: receipt) else { XCTFail("Require the owned original full receipt"); return }
        let changes = HomeV2CorrectionPolicy.Changes(weight: .kilograms(84))
        let writerTask = Task { @MainActor in
            _ = await HomeV2CorrectionPolicy.save(
                original, changes: changes, ownership: ownership, ownsSession: { $0 == ownership },
                persist: { corrected, admission in
                    await held.waitBeforeWriter(receipt)
                    _ = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
                        corrected, replacing: original, changes: changes, store: store, admission: admission,
                        onStored: { held.recordStored($0, receipt: receipt) },
                        onWriterAdmission: { held.recordWriterAdmission($0, receipt: receipt) }
                    )
                }, didSave: { _, _ in XCTFail("Failure cleanup cancellation cannot publish a correction") }
            )
        }
        held.observeTask(writerTask, receipt: receipt)
        let startedResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        guard startedResult == .completed, held.attempts.count == 1,
              let attemptID = held.attempts.keys.first else {
            XCTFail("Require actual owned hold before cleanup controls")
            return
        }
        XCTAssertTrue(held.attempts[attemptID]?.isHeld == true)
        XCTAssertFalse(held.attempts[attemptID]?.isTerminal == true)
        let wrongNonce = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
            nonce: UUID(), held: held, cleanup: cleanup, transport: transport,
            originalFailure: "Wrong nonce must not consume this attempt"
        )
        XCTAssertFalse(wrongNonce)
        XCTAssertFalse(cleanup.failedCaseRequested)
        XCTAssertTrue(held.attempts[attemptID]?.isHeld == true)
        XCTAssertFalse(writerTask.isCancelled)

        let wrongSuite = HomeV2CorrectionFixtureCleanup(
            nonce: nonce, defaults: defaults, suiteName: "lyb.fixture.correction.\(UUID().uuidString)"
        )
        XCTAssertFalse(wrongSuite.bind(held: held, transport: transport),
                       "A different suite name cannot bind this actual owned defaults instance")
        let wrongSuiteResult = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
            nonce: nonce, held: held, cleanup: wrongSuite, transport: transport,
            originalFailure: "Foreign suite must not cancel/release or dispose the actual owned suite"
        )
        XCTAssertFalse(wrongSuiteResult)
        XCTAssertFalse(cleanup.failedCaseRequested)
        XCTAssertTrue(held.attempts[attemptID]?.isHeld == true)
        XCTAssertEqual(defaults.string(forKey: "correctionFixtureOwnedNonce"), nonce.uuidString)

        let foreign = HomeV2CorrectionFixtureHold(nonce: nonce)
        foreign.bindInitialOwner(ownership)
        let foreignReceipt = HomeV2CorrectionReturnReceipt(
            destination: .init(metric: original, ownership: ownership), editorLifetime: UUID()
        )
        XCTAssertTrue(foreign.armNextWriter(for: foreignReceipt))
        let wrongHolder = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
            nonce: nonce, held: foreign, cleanup: cleanup, transport: transport,
            originalFailure: "Same nonce must not authorize a foreign holder"
        )
        XCTAssertFalse(wrongHolder)
        XCTAssertTrue(foreign.isArmed(for: foreignReceipt))
        XCTAssertFalse(cleanup.failedCaseRequested)
        XCTAssertTrue(held.attempts[attemptID]?.isHeld == true)
        foreign.disarmExact(foreignReceipt) // Test-owned foreign arm only; no foreign task/session was created.
        XCTAssertFalse(held.releaseExact(UUID(), nonce: nonce), "A foreign attempt UUID must never release the real hold")

        let helperDone = XCTestExpectation(description: "Actual cleanup helper awaits real terminal observer")
        let failureMarker = "Injected unit failure marker retained across cleanup"
        box.task = Task { @MainActor in
            let accepted = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
                nonce: nonce, held: held, cleanup: cleanup, transport: transport, originalFailure: failureMarker
            )
            helperDone.fulfill()
            teardownDone.fulfill()
            return accepted
        }
        let helperResult = await XCTWaiter.fulfillment(of: [helperDone], timeout: 2)
        guard helperResult == .completed, let cleanupTask = box.task else {
            XCTFail("The actual helper must complete within the bounded wait before task.value")
            return
        }
        let acceptedCleanup = await cleanupTask.value
        XCTAssertTrue(acceptedCleanup)
        await writerTask.value // Actual retained terminal observer has already completed.
        XCTAssertTrue(writerTask.isCancelled)
        XCTAssertTrue(held.attempts[attemptID]?.wasReleased == true)
        XCTAssertFalse(held.attempts[attemptID]?.isHeld == true)
        XCTAssertTrue(held.attempts[attemptID]?.isTerminal == true)
        XCTAssertEqual(held.attempts[attemptID]?.writerAdmissions, 0)
        XCTAssertEqual(held.attempts[attemptID]?.writerRejections, 1,
                       "Actual in-context admission rejects cancellation before any persisted write")
        XCTAssertNil(held.attempts[attemptID]?.stored)
        XCTAssertFalse(held.attempts[attemptID]?.publicationReturned == true)
        XCTAssertFalse(held.hasPendingWork)
        XCTAssertEqual(try HomeV2CorrectionPolicy.storedMetric(original, store: store), original)
        let callbackResult = await XCTWaiter.fulfillment(of: [callback], timeout: 2)
        XCTAssertEqual(callbackResult, .completed)
        XCTAssertTrue(cleanup.failedCaseTasksTerminal)
        XCTAssertTrue(cleanup.invalidated)
        XCTAssertTrue(cleanup.disposed)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(transport.recorder.snapshot().invalidationCount, 1)
        XCTAssertNil(transport.recorder.snapshot().invalidationError)
        XCTAssertEqual(cleanup.originalFailureMarker, failureMarker)
        // Real helper/store/session control only: this does NOT prove mounted teardown/root reachability.
    }


    @MainActor
    func testFixtureHeldWriterRejectsCancellationInActualStoreAndWaitsForTaskTerminal() async throws {
        let store = correctionStore()
        let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let input = entriesBoundaryMetric("held-real-writer", owner: owner)
        try await store.saveBodyMetricsAndWait(input, userId: owner)
        let originalRows = await store.fetchBodyMetrics(for: owner)
        let original = try XCTUnwrap(originalRows.first?.toBodyMetrics())
        let ownership = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
        let receipt = HomeV2CorrectionReturnReceipt(
            destination: .init(metric: original, ownership: ownership), editorLifetime: UUID()
        )
        let started = XCTestExpectation(description: "Actual correction held before real writer")
        let terminal = XCTestExpectation(description: "Actual captured task.value completed")
        let cleanupTerminal = XCTestExpectation(description: "Owned failure cleanup observes actual task terminal")
        var heldID: UUID?
        let nonce = UUID()
        let held = HomeV2CorrectionFixtureHold(
            nonce: nonce, onHeld: { heldID = $0; started.fulfill() },
            onTerminal: { _ in terminal.fulfill(); cleanupTerminal.fulfill() }
        )
        held.bindInitialOwner(ownership)
        guard held.armNextWriter(for: receipt) else {
            XCTFail("The exact owned receipt must arm before starting any task")
            return
        }
        let changes = HomeV2CorrectionPolicy.Changes(weight: .kilograms(84))
        let task = Task { @MainActor in
            _ = await HomeV2CorrectionPolicy.save(
                original, changes: changes, ownership: ownership, ownsSession: { $0 == ownership },
                persist: { corrected, admission in
                    await held.waitBeforeWriter(receipt)
                    _ = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
                        corrected, replacing: original, changes: changes, store: store, admission: admission,
                        onStored: { held.recordStored($0, receipt: receipt) },
                        onWriterAdmission: { held.recordWriterAdmission($0, receipt: receipt) }
                    )
                }, didSave: { _, _ in XCTFail("Cancelled store admission must not publish") }
            )
        }
        held.observeTask(task, receipt: receipt)
        let cleanup: @MainActor () async -> Void = {
            // Exact test-owned attempt only. Disarm first prevents a not-yet-entered hold.
            held.disarmExact(receipt)
            task.cancel()
            if let heldID { _ = held.releaseExact(heldID, nonce: nonce) }
            let cleaned = await XCTWaiter.fulfillment(of: [cleanupTerminal], timeout: 2)
            XCTAssertEqual(cleaned, .completed, "Owned failure cleanup must observe real terminal, never cancel alone")
        }
        let startedResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        guard startedResult == .completed, let id = heldID else {
            XCTFail("Require actual hold event and exact attempt ID before the cancellation control")
            await cleanup()
            return
        }
        task.cancel()
        held.recordCancellation(receipt)
        XCTAssertTrue(held.attempts[id]?.cancellationObserved == true)
        XCTAssertTrue(held.attempts[id]?.isHeld == true)
        XCTAssertFalse(held.attempts[id]?.isTerminal == true, "Cancellation/cleared handle is not terminal")
        XCTAssertFalse(held.releaseExact(id, nonce: UUID()))
        XCTAssertFalse(held.releaseExact(UUID(), nonce: nonce))
        guard held.releaseExact(id, nonce: nonce) else {
            XCTFail("Require the one exact owned latch release")
            await cleanup()
            return
        }
        XCTAssertFalse(held.releaseExact(id, nonce: nonce), "One exact release only")
        let terminalResult = await XCTWaiter.fulfillment(of: [terminal], timeout: 2)
        guard terminalResult == .completed else {
            XCTFail("The actual captured task must finish within the bounded terminal wait")
            await cleanup()
            return
        }
        // onTerminal fires only AFTER this same captured task.value has completed.
        await task.value
        XCTAssertTrue(held.attempts[id]?.isTerminal == true)
        XCTAssertEqual(held.attempts[id]?.writerAdmissions, 0)
        XCTAssertEqual(held.attempts[id]?.writerRejections, 1)
        XCTAssertNil(held.attempts[id]?.stored)
        XCTAssertFalse(held.attempts[id]?.publicationReturned == true)
        XCTAssertEqual(try HomeV2CorrectionPolicy.storedMetric(original, store: store), original)
        // Synthetic receipt/store control; actual mounted old/new route/editor/root chronology remains C2.
    }

    @MainActor
    func testFixtureHeldWriterRequiresFullReceiptWhenEditorUUIDIsReused() async throws {
        let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let ownership = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
        let metric = entriesBoundaryMetric("same-editor-receipt", owner: owner)
        let editor = UUID()
        let armed = HomeV2CorrectionReturnReceipt(
            destination: .init(metric: metric, ownership: ownership), editorLifetime: editor
        )
        let wrong = HomeV2CorrectionReturnReceipt(
            destination: .init(metric: metric, ownership: ownership), editorLifetime: editor
        )
        XCTAssertNotEqual(armed.destination.id, wrong.destination.id)
        XCTAssertEqual(armed.editorLifetime, wrong.editorLifetime)
        let terminal = XCTestExpectation(description: "Wrong-destination task finishes without consuming held receipt")
        let cleanupTerminal = XCTestExpectation(description: "Wrong-receipt owned task cleanup terminal")
        let nonce = UUID()
        var heldID: UUID?
        let held = HomeV2CorrectionFixtureHold(
            nonce: nonce, onHeld: { heldID = $0; XCTFail("Same editor UUID must not admit another full destination") },
            onTerminal: { _ in terminal.fulfill(); cleanupTerminal.fulfill() }
        )
        held.bindInitialOwner(ownership)
        guard held.armNextWriter(for: armed) else { XCTFail("Require exact original receipt arm"); return }
        let task = Task { @MainActor in await held.waitBeforeWriter(wrong) }
        held.observeTask(task, receipt: wrong)
        let result = await XCTWaiter.fulfillment(of: [terminal], timeout: 2)
        guard result == .completed else {
            XCTFail("Wrong receipt must complete without holding or consuming the original arm")
            held.disarmExact(armed)
            task.cancel()
            if let heldID { _ = held.releaseExact(heldID, nonce: nonce) }
            let cleaned = await XCTWaiter.fulfillment(of: [cleanupTerminal], timeout: 2)
            XCTAssertEqual(cleaned, .completed, "Bounded exact wrong-task cleanup must finish")
            return
        }
        await task.value // Real task terminal already established by the bounded waiter.
        XCTAssertNil(heldID)
        XCTAssertTrue(held.isArmed(for: armed), "Wrong destination must not consume the original full receipt")
        XCTAssertFalse(held.isArmed(for: wrong))
        let attempt = try XCTUnwrap(held.attempts.values.first(where: { $0.receipt == wrong }))
        XCTAssertFalse(attempt.isHeld)
        XCTAssertTrue(attempt.isTerminal)
        held.disarmExact(armed)
        XCTAssertFalse(held.isArmed(for: armed))
        // This is a producer receipt control, not mounted navigation/root identity proof.
    }

    @MainActor
    func testAppSeedReadbackAcceptsActualOwnedRowsAndPreservesRawMetadata() async throws {
        let store = correctionStore()
        let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let foreign = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let input = entriesBoundaryMetric("actual-boot-owned", owner: owner, weight: 83.456789)
        try await store.saveBodyMetricsAndWait(input, userId: owner)
        let other = entriesBoundaryMetric("actual-boot-foreign", owner: foreign)
        try await store.saveBodyMetricsAndWait(other, userId: foreign)
        let rows = await HomeV2CorrectionFixtureBoot.readSeededRows(for: owner, context: store.viewContext)
        XCTAssertEqual(rows.count, 1)
        let actual = try XCTUnwrap(rows.first)
        XCTAssertEqual(actual.id, input.id)
        XCTAssertEqual(actual.userId, owner)
        XCTAssertEqual(actual.date, input.date)
        XCTAssertEqual(actual.weight, input.weight)
        XCTAssertEqual(actual.sourceMetadata, input.sourceMetadata)
        XCTAssertEqual(actual.notes, input.notes)
        let receipt = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
        var boot = HomeV2CorrectionFixtureBoot()
        XCTAssertTrue(boot.begin())
        XCTAssertFalse(boot.admitGeneratedOwner(owner, ownership: nil, seededRows: rows))
        XCTAssertFalse(boot.admitGeneratedOwner(
            owner, ownership: .init(subject: foreign, generation: 1), seededRows: rows
        ))
        XCTAssertTrue(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: rows))
        XCTAssertTrue(boot.isReady)
    }

    @MainActor
    func testAppSeedReadbackRejectsWholePartialCachedConversionAndRecovers() async throws {
        for missing in ["id", "date", "createdAt", "updatedAt"] {
            let store = correctionStore()
            let context = store.viewContext
            let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
            let input = entriesBoundaryMetric("actual-boot-good", owner: owner)
            try await store.saveBodyMetricsAndWait(input, userId: owner)
            let calibration = try await context.perform {
                let malformed = CachedBodyMetrics(context: context)
                malformed.id = "actual-boot-malformed"
                malformed.userId = owner
                malformed.date = input.date
                malformed.createdAt = input.createdAt
                malformed.updatedAt = input.updatedAt
                malformed.lastModified = input.updatedAt
                malformed.syncStatus = "pending"
                malformed.isMarkedDeleted = false
                malformed.weight = 82
                malformed.setValue(nil, forKey: missing)
                let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
                request.predicate = NSPredicate(format: "userId == %@", owner)
                return (try context.fetch(request).count, malformed.toBodyMetrics() == nil)
            }
            XCTAssertEqual(calibration.0, 2, "Actual fetch must contain valid and malformed owned Cached rows")
            XCTAssertTrue(calibration.1, "The actual DTO converter must reject the missing required field")
            let rows = await HomeV2CorrectionFixtureBoot.readSeededRows(for: owner, context: context)
            XCTAssertTrue(rows.isEmpty, "Partial conversion must reject the WHOLE App readback: \(missing)")
            var boot = HomeV2CorrectionFixtureBoot()
            XCTAssertTrue(boot.begin())
            let receipt = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
            XCTAssertFalse(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: rows))
            XCTAssertFalse(boot.isReady)
            // Required fields are nonoptional in the real model. This bad row is
            // intentionally pending, NEVER saved as a fictitious corrupt store.
            await context.perform { context.rollback() }
            let recovered = await HomeV2CorrectionFixtureBoot.readSeededRows(for: owner, context: context)
            XCTAssertEqual(recovered.map(\.id), [input.id])
            XCTAssertTrue(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: recovered))
        }
    }

    @MainActor
    func testAppSeedReadbackRejectsEmptyAndMismatchedOwnerData() async throws {
        let store = correctionStore()
        let context = store.viewContext
        let owner = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let foreign = "ui_test_photo_hud_user_\(UUID().uuidString)"
        let receipt = AuthManager.ProfileSessionOwnership(subject: owner, generation: 1)
        var boot = HomeV2CorrectionFixtureBoot()
        XCTAssertTrue(boot.begin())
        let empty = await HomeV2CorrectionFixtureBoot.readSeededRows(for: owner, context: context)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: empty))
        let other = entriesBoundaryMetric("actual-boot-other-owner", owner: foreign)
        try await store.saveBodyMetricsAndWait(other, userId: foreign)
        await context.perform {
            let unowned = CachedBodyMetrics(context: context)
            unowned.id = "actual-boot-empty-owner"
            unowned.userId = ""
            unowned.date = other.date
            unowned.createdAt = other.createdAt
            unowned.updatedAt = other.updatedAt
            unowned.lastModified = other.updatedAt
            unowned.syncStatus = "pending"
            unowned.isMarkedDeleted = false
        }
        let filtered = await HomeV2CorrectionFixtureBoot.readSeededRows(for: owner, context: context)
        XCTAssertTrue(filtered.isEmpty, "Foreign and empty-owner rows cannot seed the selected generated owner")
        XCTAssertFalse(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: filtered))
        let foreignRows = await HomeV2CorrectionFixtureBoot.readSeededRows(for: foreign, context: context)
        XCTAssertEqual(foreignRows.map(\.id), [other.id])
        XCTAssertFalse(boot.admitGeneratedOwner(owner, ownership: receipt, seededRows: foreignRows))
        XCTAssertFalse(boot.isReady)
        await context.perform { context.rollback() }
    }

    private func entriesBoundaryMetric(
        _ id: String, owner: String = "entries-owner",
        date: Date = Date(timeIntervalSince1970: 1_790_000_123),
        weight: Double? = 83.4, bodyFat: Double? = nil, method: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id, userId: owner, date: date, weight: weight, weightUnit: "kg",
            bodyFatPercentage: bodyFat, bodyFatMethod: method,
            muscleMass: nil, boneMass: nil, notes: "Raw record", photoUrl: nil, dataSource: "healthkit",
            sourceMetadata: .init(
                vendor: "healthkit", sourceName: "Apple Health", sourceBundleId: "synthetic.healthkit",
                sampleId: "synthetic-weight-sample", quantityType: "bodyMass",
                bodyFatSampleId: "synthetic-body-fat-sample", importedAt: "2026-09-22T01:02:03Z"
            ), createdAt: date, updatedAt: date
        )
    }

    @MainActor
    func testCorrectionFixtureTransportCalibratesActualProductAPIAndInvalidation() async throws {
        let invalidated = XCTestExpectation(description: "Owned calibration session invalidated")
        let transport = try HomeV2CorrectionFixtureTransport.make(
            nonce: UUID(), onInvalidated: { invalidated.fulfill() }
        )
        let product = transport.product
        let endpoint = transport.endpoint
        XCTAssertTrue(["https", "http"].contains(endpoint.scheme ?? ""))
        XCTAssertFalse(endpoint.host?.isEmpty ?? true)
        let recorder = transport.recorder
        let session = transport.session
        // The test observes the App-owned producer; no test-private session or Auth lookup.
        var rejected: URLError.Code?
        var unexpectedError: Error?
        do {
            _ = try await product.upsertBodyMetricsBatch([], token: "synthetic-noncredential-calibration")
            XCTFail("The stateless local transport must never return a successful provider response")
        } catch let error as URLError {
            rejected = error.code
        } catch {
            unexpectedError = error
        }
        session.finishTasksAndInvalidate()
        await fulfillment(of: [invalidated], timeout: 2)
        XCTAssertNil(unexpectedError)
        XCTAssertEqual(rejected, .cancelled, "Actual ProductAPI must reach the rejecting URLProtocol")
        let observations = recorder.snapshot()
        XCTAssertEqual(observations.tasks.count, 1, "Zero means this SDK async path is NOT calibrated")
        guard observations.tasks.count == 1 else { return }
        XCTAssertEqual(observations.tasks[0].session, ObjectIdentifier(session))
        XCTAssertGreaterThan(observations.tasks[0].taskIdentifier, 0)
        XCTAssertEqual(observations.tasks[0].method, "POST")
        XCTAssertEqual(observations.tasks[0].path, endpoint.path)
        XCTAssertEqual(observations.invalidationCount, 1)
        XCTAssertNil(observations.invalidationError)
        // No token, headers, body, user, or host is captured in the recorder.
    }

    @MainActor
    func testCorrectionFixtureFreshSessionZeroCannotBorrowAnotherSessionsCalibration() async throws {
        let usedInvalidated = XCTestExpectation(description: "Used calibration session invalidated")
        let freshInvalidated = XCTestExpectation(description: "Fresh calibration session invalidated")
        let usedTransport = try HomeV2CorrectionFixtureTransport.make(
            nonce: UUID(), onInvalidated: { usedInvalidated.fulfill() }
        )
        let freshTransport = try HomeV2CorrectionFixtureTransport.make(
            nonce: UUID(), onInvalidated: { freshInvalidated.fulfill() }
        )
        let product = usedTransport.product
        _ = usedTransport.endpoint
        let used = usedTransport.recorder
        let fresh = freshTransport.recorder
        XCTAssertNotEqual(used.nonce, fresh.nonce)
        let usedSession = usedTransport.session
        let freshSession = freshTransport.session
        var rejected: URLError.Code?
        do {
            _ = try await product.upsertBodyMetricsBatch([], token: "synthetic-noncredential-calibration")
            XCTFail("Actual ProductAPI calibration must reject locally")
        } catch let error as URLError {
            rejected = error.code
        } catch {
            XCTFail("Unexpected local calibration error: \(type(of: error))")
        }
        usedSession.finishTasksAndInvalidate()
        freshSession.finishTasksAndInvalidate()
        await fulfillment(of: [usedInvalidated, freshInvalidated], timeout: 2)
        XCTAssertEqual(rejected, .cancelled)
        XCTAssertEqual(used.snapshot().tasks.count, 1)
        XCTAssertTrue(fresh.snapshot().tasks.isEmpty, "Unused fresh-session zero is measured only for this session")
        XCTAssertEqual(used.snapshot().invalidationCount, 1)
        XCTAssertEqual(fresh.snapshot().invalidationCount, 1)
        XCTAssertNil(used.snapshot().invalidationError)
        XCTAssertNil(fresh.snapshot().invalidationError)
        // This zero is NOT mounted-App isolation or proof of all external-service zero calls.
    }

    private func correctionMetric(
        weight: Double? = 81.234567, bodyFat: Double? = 16.912345,
        method: String? = "dexa", updatedAt: Date? = nil
    ) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_790_000_123)
        return BodyMetrics(
            id: "exact-correction", userId: "correction-owner", date: date,
            weight: weight, weightUnit: "kg", bodyFatPercentage: bodyFat, bodyFatMethod: method,
            muscleMass: 60.123, boneMass: 3.123, waistCm: 80.123, hipCm: 90.123, waistUnit: "cm",
            notes: "Keep note", photoUrl: "file:///synthetic-correction.jpg", dataSource: "healthkit",
            sourceMetadata: BodyMetricSourceMetadata(
                vendor: "healthkit", sourceName: "Withings", sourceBundleId: "synthetic.withings",
                sampleId: "synthetic-weight-sample", quantityType: "bodyMass",
                bodyFatSampleId: "synthetic-body-fat-sample", importedAt: "2026-09-22T01:02:03Z"
            ), createdAt: date.addingTimeInterval(-60), updatedAt: updatedAt ?? date
        )
    }

    private func correctionStore() -> CoreDataManager {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        return CoreDataManager(persistentStoreDescriptions: [description])
    }

    private func installCorrectionSession(_ subject: String) {
        AuthManager.shared.authSession = .localFixture(subject: subject, email: "correction@example.invalid")
        AuthManager.shared.currentUser = LocalUser(id: subject, email: "correction@example.invalid", name: "Correction")
    }
}

@MainActor
private final class HeldHomeV2Correction {
    let started = XCTestExpectation(description: "Correction store boundary suspended")
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func resume() throws {
        let continuation = try XCTUnwrap(continuation)
        self.continuation = nil
        continuation.resume()
    }
}


@MainActor
private final class FailedCaseCleanupUnitTask {
    var task: Task<Bool, Never>?
}


// Current-main purposes retained alongside the frozen Context44 controls.
extension HomeV2ContextPolicyTests {
    @MainActor
    func testBodyFatEditorGateRequiresExplicitRolloutOrAuthenticatedExclusiveFixture() {
        let context = ["XCTestSessionIdentifier": UUID().uuidString,
                       "XCTestBundlePath": "/Fixtures/LogYourBodyUITests.xctest"]
        let base = ["-lybUITestPhotoTimelineHUDFixture", HomeV2Policy.photoFixtureArgument]
        let enabled = base + [HomeV2EntryBodyFatPrimaryPolicy.fixtureArgument]
        let disabled = base + [HomeV2EntryBodyFatPrimaryPolicy.disabledFixtureArgument]
        XCTAssertFalse(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(arguments: [], environment: [:], isGateEnabled: { _ in false }))
        XCTAssertTrue(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(arguments: [], environment: [:], isGateEnabled: { key in
            XCTAssertEqual(key, HomeV2EntryBodyFatPrimaryPolicy.gateKey)
            return true
        }))
        #if DEBUG
        XCTAssertTrue(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(
                arguments: enabled, environment: context, isGateEnabled: { _ in false }
            ))
        XCTAssertFalse(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(
                arguments: disabled, environment: context, isGateEnabled: { _ in true }
            ))
        for arguments in [enabled + [HomeV2EntryBodyFatPrimaryPolicy.fixtureArgument], enabled + disabled,
                          enabled + [HomeV2Policy.rollbackFixtureArgument], [HomeV2EntryBodyFatPrimaryPolicy.fixtureArgument]] {
            XCTAssertFalse(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(
                arguments: arguments, environment: context, isGateEnabled: { _ in false }
            ))
        }
        for environment in [[:], context.merging(["XCTestSessionIdentifier": "invalid"]) { _, new in new },
                            context.merging(["XCTestBundlePath": "/Fixtures/Other.xctest"]) { _, new in new }] {
            XCTAssertFalse(HomeV2EntryBodyFatPrimaryPolicy.isEnabled(
                arguments: enabled, environment: environment, isGateEnabled: { _ in false }
            ))
        }
        #endif
    }

    func testContextStepsDoesNotInventAValueForMissingData() {
        XCTAssertNil(HomeV2DayEntryRow.steps(nil))
    }

    func testContextStepsPreservesPositiveCountFormatting() throws {
        let row = try XCTUnwrap(HomeV2DayEntryRow.steps(5_432))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        XCTAssertEqual(row.value, formatter.string(from: 5_432))
    }

    func testContextStepsRejectsNegativeCounts() {
        XCTAssertNil(HomeV2DayEntryRow.steps(-1))
        XCTAssertNil(HomeV2DayEntryRow.steps(Int.min))
    }

    func testContextStepsRetainsAnExplicitZero() throws {
        let row = try XCTUnwrap(HomeV2DayEntryRow.steps(0))
        XCTAssertEqual(row.id, "steps")
        XCTAssertEqual(row.label, "Steps")
        XCTAssertEqual(row.subline, "Apple Health")
        XCTAssertEqual(row.value, "0")
    }

    func testEditorDisplayFontIsBundledAndRegistered() throws {
        let bundle = Bundle(for: AuthManager.self)
        XCTAssertNotNil(bundle.url(forResource: "InterTight", withExtension: "ttf"))
        XCTAssertNotNil(bundle.url(forResource: "InterTight-OFL", withExtension: "txt"))
        XCTAssertTrue((bundle.object(forInfoDictionaryKey: "UIAppFonts") as? [String])?.contains("InterTight.ttf") == true)
        XCTAssertNotNil(UIFont(name: "InterTight-Regular", size: 84), "Editorial display must use its actual bundled font")
    }

    func testEntryEditHistoricalReadingsSurviveButReplacementValuesAreValidated() throws {
        for (raw, unit) in [(31.2345, "kg"), (700.1234, "lb")] {
            let text = HomeV2WeightStepPolicy.text(raw)
            XCTAssertNotNil(try HomeV2EntryEditPolicy.weight(text: text, initialValue: raw, unit: unit, preserving: true))
            XCTAssertThrowsError(try HomeV2EntryEditPolicy.weight(text: text, initialValue: raw, unit: unit, preserving: false))
            XCTAssertThrowsError(try HomeV2EntryEditPolicy.weight(text: text, initialValue: nil, unit: unit, preserving: true))
        }
        for raw in [2.4567, 61.2345, 71.2345] {
            let text = String(format: "%.1f", raw)
            XCTAssertNotNil(try HomeV2EntryEditPolicy.bodyFat(text: text, initialValue: raw, preserving: true))
            XCTAssertThrowsError(try HomeV2EntryEditPolicy.bodyFat(text: text, initialValue: nil, preserving: true))
        }
        XCTAssertEqual(try HomeV2EntryEditPolicy.bodyFat(text: "21,25", initialValue: nil, preserving: true), 21.3)
        XCTAssertNil(try HomeV2EntryEditPolicy.bodyFat(text: "", initialValue: 21.3, preserving: true),
                     "Clearing body fat remains an explicit removal, unlike an untouched historical value")
        XCTAssertEqual(try HomeV2EntryEditPolicy.bodyFat(text: "65", initialValue: nil, preserving: false), 65,
                       "The disabled gate retains the existing editor range")
    }

    func testEntryEditMissingWeightStaysMissingAndExistingWeightCannotBeCleared() throws {
        XCTAssertNil(try HomeV2EntryEditPolicy.weight(text: " \n", initialValue: nil, unit: "kg", preserving: true))
        XCTAssertThrowsError(try HomeV2EntryEditPolicy.weight(text: "", initialValue: 80, unit: "kg", preserving: true))
        XCTAssertThrowsError(try HomeV2EntryEditPolicy.weight(text: "", initialValue: nil, unit: "kg", preserving: false))
        XCTAssertEqual(try HomeV2EntryEditPolicy.weight(text: "80,5", initialValue: nil, unit: "kg", preserving: true), 80.5)
    }

    @MainActor
    func testEntryEditPreservationRequiresItsOwnGateOrAuthenticatedTestFixture() {
        let arguments = ["-lybUITestPhotoTimelineHUDFixture", HomeV2Policy.photoFixtureArgument,
                         HomeV2EntryEditPolicy.fixtureArgument]
        let context = ["XCTestSessionIdentifier": UUID().uuidString,
                       "XCTestBundlePath": "/Fixtures/LogYourBodyUITests.xctest"]
        for environment in [[:], context.merging(["XCTestSessionIdentifier": "invalid"]) { _, new in new }] {
            XCTAssertFalse(HomeV2EntryEditPolicy.isEnabled(
                arguments: arguments, environment: environment, isGateEnabled: { key in
                    XCTAssertEqual(key, HomeV2EntryEditPolicy.gateKey)
                    return false
                }
            ))
        }
        XCTAssertTrue(HomeV2EntryEditPolicy.isEnabled(
            arguments: [], environment: [:], isGateEnabled: { $0 == HomeV2EntryEditPolicy.gateKey }
        ))
        #if DEBUG
        XCTAssertTrue(HomeV2EntryEditPolicy.isEnabled(
            arguments: arguments, environment: context, isGateEnabled: { _ in
                XCTFail("The isolated UI fixture must not depend on remote flags")
                return false
            }
        ))
        for invalid in [arguments + [HomeV2EntryEditPolicy.fixtureArgument],
                        arguments + [HomeV2Policy.rollbackFixtureArgument],
                        [HomeV2EntryEditPolicy.fixtureArgument]] {
            XCTAssertFalse(HomeV2EntryEditPolicy.isEnabled(
                arguments: invalid, environment: context, isGateEnabled: { _ in false }
            ))
        }
        #endif
    }

    func testEntryEditRejectsInvalidNumbersWithoutSubstitutingDefaults() {
        for text in ["0", "-1", "NaN", "infinity", "1.2.3", "no reading"] {
            XCTAssertThrowsError(try HomeV2EntryEditPolicy.weight(text: text, initialValue: nil, unit: "kg", preserving: true))
            XCTAssertThrowsError(try HomeV2EntryEditPolicy.bodyFat(text: text, initialValue: nil, preserving: true))
        }
    }

    func testEntrySavedConfirmationDoesNotInventWeight() {
        let entry = HomeV2LoggedEntry(
            metricId: "photo", userId: "owner", date: Date(), previousMetric: nil, valueText: "", unit: "kg"
        )
        XCTAssertEqual(entry.confirmationText, "Entry saved.")
        let weight = HomeV2LoggedEntry(
            metricId: "weight", userId: "owner", date: Date(), previousMetric: nil, valueText: "80.1", unit: "kg"
        )
        XCTAssertEqual(weight.confirmationText, HomeV2Copy.loggedSentence(value: "80.1", unit: "kg"))
    }

    func testCurrentMainHistoricalEntriesPreserveFlaggedTimesAndImportProvenance() throws {
        let calendar = try fixedCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 14)))
        let sections = HomeV2EntriesPolicy.sections(
            metrics: [
                mainBoundaryMetric(
                    id: "morning",
                    daysAgo: 2_903,
                    weight: 18,
                    source: "healthkit",
                    sourceName: "Withings",
                    hour: 7,
                    minute: 2,
                    now: now,
                    calendar: calendar
                ),
                mainBoundaryMetric(
                    id: "evening",
                    daysAgo: 2_903,
                    weight: 17.99,
                    source: "healthkit",
                    sourceName: "Withings",
                    hour: 19,
                    minute: 4,
                    now: now,
                    calendar: calendar
                )
            ],
            unit: "kg",
            weightValue: { $0.weight },
            hasPhoto: { _ in false },
            calendar: calendar,
            now: now
        )

        let rows = try XCTUnwrap(sections.first?.rows)
        XCTAssertEqual(sections.first?.title, "November 2018")
        XCTAssertEqual(rows.count, 2, "Repeated-day source samples stay individually visible")
        XCTAssertTrue(rows.allSatisfy { $0.dayText.contains("Nov 2") })
        XCTAssertNotEqual(rows[0].dayText, rows[1].dayText, "Their timestamps disambiguate repeated-day labels")
        XCTAssertTrue(rows.allSatisfy { $0.source.contains("Withings via Apple Health") })
        XCTAssertTrue(rows.allSatisfy { $0.source.contains("Source value kept unchanged") })
        XCTAssertEqual(Set(rows.map(\.valueText)), Set(["18.00 kg", "17.99 kg"]))
        XCTAssertNil(sections.first?.delta, "Flagged source values must not create a misleading trend")
    }

    func testCurrentMainLegacyCorrectionPreservesImportOriginAndManualFieldProvenance() {
        let original = mainBoundaryMetric(
            id: "specific-sample",
            daysAgo: 2_903,
            weight: 17.99,
            bodyFat: 12,
            source: "healthkit",
            sourceName: "Withings",
            hour: 19,
            minute: 4
        )
        let updateTime = Date(timeIntervalSince1970: 1_800_000_000)

        let corrected = HomeV2CorrectionPolicy.correctedMetric(
            original,
            kilograms: 79.5,
            bodyFatPercentage: nil,
            updatedAt: updateTime
        )

        XCTAssertEqual(corrected.id, original.id)
        XCTAssertEqual(corrected.date, original.date)
        XCTAssertEqual(corrected.localDate, original.localDate)
        XCTAssertEqual(corrected.metricSource, .healthKit)
        XCTAssertEqual(corrected.measurementSource(for: .weight), .manual)
        XCTAssertEqual(corrected.sourceMetadata?.sourceName, original.sourceMetadata?.sourceName)
        XCTAssertEqual(corrected.createdAt, original.createdAt)
        XCTAssertEqual(corrected.updatedAt, updateTime)
        XCTAssertEqual(corrected.weight, 79.5)
        XCTAssertNil(corrected.bodyFatPercentage)
        XCTAssertNil(corrected.bodyFatMethod)
        XCTAssertEqual(
            HomeV2Provenance.detailedLabel(for: corrected, field: .weight),
            "Typed"
        )
    }

    private func mainBoundaryMetric(
        id: String? = nil,
        daysAgo: Int,
        weight: Double?,
        bodyFat: Double? = nil,
        source: String = "manual",
        sourceName: String? = nil,
        photo: String? = nil,
        hour: Int = 0,
        minute: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BodyMetrics {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        return BodyMetrics(
            id: id ?? "m\(daysAgo)",
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photo,
            dataSource: source,
            sourceMetadata: sourceName.map {
                BodyMetricSourceMetadata(
                    vendor: source == "healthkit" ? "healthkit" : nil,
                    sourceName: $0,
                    sourceBundleId: source == "healthkit" ? "com.withings.wiScaleNG" : nil,
                    quantityType: source == "healthkit" ? "HKQuantityTypeIdentifierBodyMass" : nil
                )
            },
            createdAt: date,
            updatedAt: date
        )
    }

    private func assertCorrectionImportLineage(
        _ corrected: BodyMetrics, equals original: BodyMetrics, manuallyEdited: Set<BodyMetricField>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(corrected.dataSource, original.dataSource, file: file, line: line)
        XCTAssertEqual(corrected.sourceMetadata?.vendor, original.sourceMetadata?.vendor, file: file, line: line)
        XCTAssertEqual(corrected.sourceMetadata?.sourceName, original.sourceMetadata?.sourceName, file: file, line: line)
        XCTAssertEqual(corrected.sourceMetadata?.sourceBundleId, original.sourceMetadata?.sourceBundleId, file: file, line: line)
        XCTAssertEqual(corrected.sourceMetadata?.sampleId, original.sourceMetadata?.sampleId, file: file, line: line)
        XCTAssertEqual(corrected.sourceMetadata?.quantityType, original.sourceMetadata?.quantityType, file: file, line: line)
        XCTAssertEqual(
            corrected.sourceMetadata?.bodyFatSampleId,
            original.sourceMetadata?.bodyFatSampleId,
            file: file,
            line: line
        )
        XCTAssertEqual(corrected.sourceMetadata?.importedAt, original.sourceMetadata?.importedAt, file: file, line: line)
        for field: BodyMetricField in [.weight, .bodyFat] {
            if manuallyEdited.contains(field) {
                XCTAssertEqual(corrected.measurementSource(for: field), .manual, file: file, line: line)
            } else {
                XCTAssertEqual(
                    corrected.measurementSource(for: field),
                    original.measurementSource(for: field),
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    corrected.sourceMetadata?.entrySource(for: field),
                    original.sourceMetadata?.entrySource(for: field),
                    file: file,
                    line: line
                )
            }
        }
    }
}


private enum ContextWriterTestError: Error { case denied, storedBridge, afterCommit, postflight }

@MainActor
extension HomeV2ContextPolicyTests {
    private func contextWriterRead(_ store: CoreDataManager, id: String) throws -> (
        metric: BodyMetrics, attributes: [String: Any]
    ) {
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        return try reader.performAndWait {
            let request = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            let rows = try reader.fetch(request)
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            return (
                try XCTUnwrap(row.toBodyMetrics()),
                row.dictionaryWithValues(forKeys: Array(row.entity.attributesByName.keys))
            )
        }
    }

    private func contextWriterSeed(_ store: CoreDataManager, weight: Double? = 81.234567,
                                   bodyFat: Double? = 16.912345, method: String? = "dexa") async throws -> BodyMetrics {
        let input = correctionMetric(weight: weight, bodyFat: bodyFat, method: method)
        try await store.saveBodyMetricsAndWait(input, userId: input.userId, markAsSynced: true)
        return try contextWriterRead(store, id: input.id).metric
    }

    func testCorrectionWriterDirtyTargetAndMovedCommittedIdentityKeepEveryPendingDraft() async throws {
        for moveIdentity in [false, true] {
            let store = correctionStore()
            let original = try await contextWriterSeed(store)
            let targetRows = await store.fetchBodyMetrics(for: original.userId)
            let row = try XCTUnwrap(targetRows.first)
            row.notes = "Uncommitted selected target"
            if moveIdentity { row.id = "moved-uncommitted-id" }
            let draft = CachedBodyMetrics(context: store.viewContext)
            draft.id = "unrelated-incomplete-draft"
            draft.notes = "Keep unsaved unrelated work"
            var admissions = 0, accepted = 0, rejected = 0, commits = 0, bridges = 0
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
                    bodyFatMethod: nil, expectedOriginal: original,
                    writeAdmission: { admissions += 1 }, onStored: { _ in bridges += 1 },
                    onWriterAdmission: { result in
                        switch result {
                        case .success: accepted += 1
                        case .failure: rejected += 1
                        }
                    }, commit: { context in commits += 1; try context.save() }
                )
                XCTFail("A dirty target cannot be overwritten or committed by the correction writer")
            } catch PhotoMetricsEditError.pendingEdit { }
            XCTAssertEqual(admissions, 1)
            XCTAssertEqual(accepted, 0)
            XCTAssertEqual(rejected, 1)
            XCTAssertEqual(commits, 0)
            XCTAssertEqual(bridges, 0)
            XCTAssertEqual(try contextWriterRead(store, id: original.id).metric, original)
            XCTAssertEqual(row.notes, "Uncommitted selected target")
            XCTAssertEqual(row.id, moveIdentity ? "moved-uncommitted-id" : original.id)
            XCTAssertTrue(row.isUpdated)
            XCTAssertTrue(draft.isInserted)
            XCTAssertEqual(draft.notes, "Keep unsaved unrelated work")
            XCTAssertTrue(store.viewContext.hasChanges)
            store.viewContext.rollback() // Only test-owned pending objects after verification.
        }
    }

    func testCorrectionWriterComparesActualFetchedFullPreimageAfterFirstInsideAdmission() async throws {
        for field in ["weight", "notes", "photo"] {
            let store = correctionStore()
            let expected = try await contextWriterSeed(store)
            let targetRows = await store.fetchBodyMetrics(for: expected.userId)
            let row = try XCTUnwrap(targetRows.first)
            var admissions = 0, commits = 0, bridges = 0, rejected = 0
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: expected.id, userId: expected.userId, weight: 82, bodyFatPercentage: nil,
                    bodyFatMethod: nil, expectedOriginal: expected,
                    writeAdmission: {
                        admissions += 1
                        if admissions == 1 {
                            if field == "weight" { row.weight = 79.123456 }
                            if field == "notes" { row.notes = "Actual intervening committed revision" }
                            if field == "photo" { row.photoUrl = "file:///synthetic-intervening-photo.jpg" }
                            try store.viewContext.save()
                            XCTAssertEqual(
                                row.updatedAt,
                                expected.updatedAt,
                                "Date-only revision checks would miss this actual change"
                            )
                        }
                    },
                    onStored: { _ in bridges += 1 },
                    onWriterAdmission: { result in
                        if case .failure = result {
                            rejected += 1
                        } else {
                            XCTFail("A stale preimage has no successful admission")
                        }
                    }, commit: { context in commits += 1; try context.save() }
                )
                XCTFail("Full fetched transaction DTO must reject an intervening \(field) change")
            } catch PhotoMetricsEditError.entryChanged { }
            let actual = try contextWriterRead(store, id: expected.id).metric
            XCTAssertEqual(actual.id, expected.id)
            XCTAssertEqual(actual.date, expected.date)
            XCTAssertEqual(actual.updatedAt, expected.updatedAt)
            XCTAssertEqual(actual.weight, field == "weight" ? 79.123456 : expected.weight)
            if field == "notes" { XCTAssertEqual(actual.notes, "Actual intervening committed revision") }
            if field == "photo" { XCTAssertEqual(actual.photoUrl, "file:///synthetic-intervening-photo.jpg") }
            XCTAssertEqual(admissions, 1)
            XCTAssertEqual(rejected, 1)
            XCTAssertEqual(commits, 0)
            XCTAssertEqual(bridges, 0)
            XCTAssertFalse(store.viewContext.hasChanges)
        }
    }

    func testCorrectionWriterKeepsOpaqueColumnsAndUnrelatedDraftThroughRealIndependentRead() async throws {
        let store = correctionStore()
        let seeded = try await contextWriterSeed(store)
        let targetRows = await store.fetchBodyMetrics(for: seeded.userId)
        let row = try XCTUnwrap(targetRows.first)
        row.originalPhotoUrl = "synthetic-original-owner/photo.jpg"
        row.photoProcessedAt = seeded.date
        row.waistCircumference = 89.123
        row.hipCircumference = 99.456
        row.sourceMetadataJSON =
            "{\"vendor\":\"healthkit\",\"source_name\":\"Withings\",\"vendor_field\":{\"opaque\":\"preserve exactly\"}}"
        try store.viewContext.save()
        let before = try contextWriterRead(store, id: seeded.id)
        let draft = CachedBodyMetrics(context: store.viewContext)
        draft.id = "unrelated-opaque-writer-draft"
        draft.notes = "Keep me pending"
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: seeded.id, userId: seeded.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: before.metric, writeAdmission: {}
        )
        let after = try contextWriterRead(store, id: seeded.id)
        XCTAssertEqual(result.previousMetric, before.metric)
        XCTAssertEqual(result.metrics, after.metric)
        XCTAssertEqual(result.metrics.weight, 82)
        XCTAssertEqual(result.metrics.bodyFatPercentage, before.metric.bodyFatPercentage)
        XCTAssertEqual(result.metrics.bodyFatMethod, before.metric.bodyFatMethod)
        let allowed: Set<String> = [
            "weight", "weightUnit", "sourceMetadataJSON", "updatedAt", "lastModified", "isSynced", "syncStatus"
        ]
        for key in before.attributes.keys where !allowed.contains(key) {
            XCTAssertEqual(before.attributes[key] as? NSObject, after.attributes[key] as? NSObject, "Unexpected raw-column change: \(key)")
        }
        let json = try XCTUnwrap(after.attributes["sourceMetadataJSON"] as? String)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(metadata["vendor_field"] as? NSDictionary, ["opaque": "preserve exactly"] as NSDictionary)
        XCTAssertEqual(result.metrics.measurementSource(for: .weight), .manual)
        XCTAssertEqual(result.metrics.measurementSource(for: .bodyFat), before.metric.measurementSource(for: .bodyFat))
        XCTAssertTrue(draft.isInserted)
        XCTAssertEqual(draft.notes, "Keep me pending")
        XCTAssertTrue(store.viewContext.hasChanges)
        store.viewContext.rollback()
    }

    func testCorrectionWriterOrdersTwoInsideAdmissionsOneObserverAndImmediateActualStoredDTO() async throws {
        let store = correctionStore()
        let original = try await contextWriterSeed(store)
        let draft = CachedBodyMetrics(context: store.viewContext)
        draft.id = "unrelated-ordering-draft"
        draft.notes = "Still pending inside onStored"
        var events: [String] = []
        var admissions = 0
        var captured: PhotoMetricsUpdateResult?
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: original,
            writeAdmission: { admissions += 1; events.append("admission\(admissions)") },
            onStored: { actual in
                events.append("stored")
                captured = actual
                XCTAssertEqual(actual.previousMetric, original)
                XCTAssertEqual(try self.contextWriterRead(store, id: original.id).metric, actual.metrics)
                // Keep this shared-context witness inside onStored, before the writer returns.
                // An awaited read here would weaken the synchronous ordering assertion.
                let request = CachedBodyMetrics.fetchRequest()
                request.predicate = NSPredicate(
                    format: "id == %@ AND userId == %@ AND isMarkedDeleted == NO", original.id, original.userId
                )
                let shared = try store.viewContext.performAndWait {
                    let rows = try store.viewContext.fetch(request)
                    XCTAssertEqual(rows.count, 1)
                    return try XCTUnwrap(rows.first?.toBodyMetrics())
                }
                XCTAssertEqual(
                    shared,
                    actual.metrics,
                    "Immediate Context route read sees the actual committed DTO before writer returns"
                )
                XCTAssertEqual(events, ["admission1", "admission2", "observer", "commit", "durable", "stored"])
                XCTAssertTrue(draft.isInserted)
                XCTAssertEqual(draft.notes, "Still pending inside onStored")
            }, onWriterAdmission: { decision in
                if case .failure = decision { XCTFail("Current transaction must have one final successful admission") }
                events.append("observer")
                XCTAssertEqual(try? self.contextWriterRead(store, id: original.id).metric, original,
                               "Validated precommit observation precedes durable measurement change")
            }, commit: { transaction in
                events.append("commit")
                try transaction.save()
                events.append("durable")
            }
        )
        events.append("returned")
        XCTAssertEqual(events, ["admission1", "admission2", "observer", "commit", "durable", "stored", "returned"])
        XCTAssertEqual(admissions, 2)
        XCTAssertEqual(captured?.metrics, result.metrics)
        XCTAssertEqual(captured?.previousMetric, result.previousMetric)
        XCTAssertFalse(result.createdNewEntry)
        store.viewContext.rollback()
    }

    func testCorrectionWriterRejectsSecondAdmissionOrLateDirtyTargetBeforeObserverSuccessAndCommit() async throws {
        for mode in ["denied", "late-dirty"] {
            let store = correctionStore()
            let original = try await contextWriterSeed(store)
            let targetRows = await store.fetchBodyMetrics(for: original.userId)
            let row = try XCTUnwrap(targetRows.first)
            var admissions = 0, accepted = 0, rejected = 0, commits = 0, stored = 0
            do {
                _ = try await store.updateExistingMetricMeasurementsAndWait(
                    id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
                    bodyFatMethod: nil, expectedOriginal: original,
                    writeAdmission: {
                        admissions += 1
                        if admissions == 2 {
                            if mode == "denied" { throw ContextWriterTestError.denied }
                            row.notes = "Late uncommitted target revision"
                        }
                    },
                    onStored: { _ in stored += 1 },
                    onWriterAdmission: { result in
                        switch result {
                        case .success: accepted += 1
                        case .failure: rejected += 1
                        }
                    }, commit: { context in commits += 1; try context.save() }
                )
                XCTFail("Final admission/dirty check must stop the actual transaction")
            } catch ContextWriterTestError.denied { XCTAssertEqual(mode, "denied")
            } catch PhotoMetricsEditError.pendingEdit { XCTAssertEqual(mode, "late-dirty") }
            XCTAssertEqual(admissions, 2)
            XCTAssertEqual(accepted, 0)
            XCTAssertEqual(rejected, 1)
            XCTAssertEqual(commits, 0)
            XCTAssertEqual(stored, 0)
            XCTAssertEqual(try contextWriterRead(store, id: original.id).metric, original)
            if mode == "late-dirty" {
                XCTAssertTrue(row.isUpdated)
                XCTAssertEqual(row.notes, "Late uncommitted target revision")
            }
            store.viewContext.rollback()
        }
    }

    func testCorrectionPostcommitFailuresKeepDurableDataAndNeverBecomeAdmissionRejections() async throws {
        for mode in ["stored-bridge", "service-postflight", "commit-after-save"] {
            let store = correctionStore()
            let original = try await contextWriterSeed(store)
            var admissions = 0, accepted = 0, rejected = 0, bridges = 0
            do {
                if mode == "service-postflight" {
                    _ = try await PhotoMetadataService.shared.updateExistingMeasurementsWithResult(
                        id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
                        bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: original,
                        writeAdmission: {
                            admissions += 1
                            if admissions == 4 { throw ContextWriterTestError.postflight }
                        },
                        onStored: { _ in bridges += 1 },
                        onWriterAdmission: { result in
                            switch result {
                            case .success: accepted += 1
                            case .failure: rejected += 1
                            }
                        }, coreDataManager: store
                    )
                } else {
                    _ = try await store.updateExistingMetricMeasurementsAndWait(
                        id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
                        bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: original,
                        writeAdmission: { admissions += 1 },
                        onStored: { actual in
                            bridges += 1
                            XCTAssertEqual(try self.contextWriterRead(store, id: original.id).metric, actual.metrics)
                            throw ContextWriterTestError.storedBridge
                        }, onWriterAdmission: { result in
                            switch result {
                            case .success: accepted += 1
                            case .failure: rejected += 1
                            }
                        }, commit: { context in
                            try context.save()
                            if mode == "commit-after-save" { throw ContextWriterTestError.afterCommit }
                        }
                    )
                }
                XCTFail("The deliberately injected postcommit error must propagate")
            } catch ContextWriterTestError.storedBridge { XCTAssertEqual(mode, "stored-bridge")
            } catch ContextWriterTestError.postflight { XCTAssertEqual(mode, "service-postflight")
            } catch ContextWriterTestError.afterCommit { XCTAssertEqual(mode, "commit-after-save") }
            let durable = try contextWriterRead(store, id: original.id).metric
            XCTAssertEqual(durable.weight, 82)
            XCTAssertEqual(durable.id, original.id)
            XCTAssertEqual(durable.bodyFatPercentage, original.bodyFatPercentage)
            XCTAssertEqual(durable.photoUrl, original.photoUrl)
            XCTAssertEqual(accepted, 1)
            XCTAssertEqual(rejected, 0, "Durable save/publication errors must not masquerade as rejected admission")
            XCTAssertEqual(admissions, mode == "service-postflight" ? 4 : 2)
            XCTAssertEqual(bridges, mode == "commit-after-save" ? 0 : 1)
        }
    }

    func testCorrectionWriterGenericNilRetainsButExplicitMethodNilAndClearUseActualStoredValues() async throws {
        let store = correctionStore()
        let original = try await contextWriterSeed(store, weight: nil)
        let retained = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: nil, bodyFatPercentage: original.bodyFatPercentage,
            bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: original, writeAdmission: {}
        )
        XCTAssertEqual(retained.metrics, original, "Generic nil method retains the stored method and precision without a write")
        let replaced = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: nil, bodyFatPercentage: original.bodyFatPercentage,
            bodyFatMethod: nil, markManualCorrection: true, replaceBodyFatMethod: true,
            expectedOriginal: retained.metrics, writeAdmission: {}
        )
        XCTAssertEqual(replaced.previousMetric, retained.metrics)
        XCTAssertNil(replaced.metrics.weight)
        XCTAssertEqual(replaced.metrics.bodyFatPercentage, 16.912345)
        XCTAssertNil(replaced.metrics.bodyFatMethod)
        XCTAssertEqual(replaced.metrics.measurementSource(for: .bodyFat), .manual)
        let cleared = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: nil, bodyFatPercentage: nil,
            bodyFatMethod: nil, clearBodyFat: true, markManualCorrection: true, replaceBodyFatMethod: true,
            expectedOriginal: replaced.metrics, writeAdmission: {}
        )
        XCTAssertEqual(cleared.previousMetric, replaced.metrics)
        XCTAssertNil(cleared.metrics.weight)
        XCTAssertNil(cleared.metrics.bodyFatPercentage)
        XCTAssertNil(cleared.metrics.bodyFatMethod)
        XCTAssertEqual(try contextWriterRead(store, id: original.id).metric, cleared.metrics)

        // Raw and field-attributed methods can differ after an earlier manual edit.
        // Selecting the raw method again must correct the actual field metadata.
        let attributedStore = correctionStore()
        let imported = try await contextWriterSeed(attributedStore)
        let attributedRows = await attributedStore.fetchBodyMetrics(for: imported.userId)
        let attributedRow = try XCTUnwrap(attributedRows.first)
        attributedRow.sourceMetadataJSON = try XCTUnwrap(imported.sourceMetadata)
            .settingEntrySource(.manual, fields: [.bodyFat], bodyFatMethod: "bia_scale").jsonString
        try attributedStore.viewContext.save()
        let attributed = try contextWriterRead(attributedStore, id: imported.id).metric
        XCTAssertEqual(attributed.bodyFatMethod, "dexa")
        XCTAssertEqual(attributed.attributedBodyFatMethod, "bia_scale")
        let reconciled = try await attributedStore.updateExistingMetricMeasurementsAndWait(
            id: attributed.id, userId: attributed.userId, weight: nil,
            bodyFatPercentage: attributed.bodyFatPercentage, bodyFatMethod: "dexa",
            markManualCorrection: true, replaceBodyFatMethod: true,
            expectedOriginal: attributed, writeAdmission: {}
        )
        XCTAssertEqual(reconciled.previousMetric, attributed)
        XCTAssertEqual(reconciled.metrics.bodyFatPercentage, 16.912345)
        XCTAssertEqual(reconciled.metrics.bodyFatMethod, "dexa")
        XCTAssertEqual(reconciled.metrics.attributedBodyFatMethod, "dexa")
        XCTAssertEqual(reconciled.metrics.sourceMetadata?.enteredBodyFatMethod, "dexa")
        XCTAssertEqual(try contextWriterRead(attributedStore, id: imported.id).metric, reconciled.metrics)
    }

    func testDisplayedCorrectionIntentPreservesRawNoOpPrecisionAndParsesOnlyGenuineUnitEdits() throws {
        let original = correctionMetric()
        let untouched = try HomeV2CorrectionPolicy.changes(
            weightText: "179.1", weightWasEdited: false, unit: "lb",
            bodyFat: .init(text: "16.9", wasEdited: false, original: original.bodyFatPercentage,
                           method: original.bodyFatMethod, originalMethod: original.bodyFatMethod)
        )
        XCTAssertTrue(untouched.isEmpty)
        XCTAssertEqual(HomeV2CorrectionPolicy.correctedMetric(original, changes: untouched), original,
                       "Untouched rounded display/unit state never persists rounded raw readings")
        let changed = try HomeV2CorrectionPolicy.changes(
            weightText: "180", weightWasEdited: true, unit: "lb",
            bodyFat: .init(text: "16.9", wasEdited: false, original: original.bodyFatPercentage,
                           method: original.bodyFatMethod, originalMethod: original.bodyFatMethod)
        )
        let edited = HomeV2CorrectionPolicy.correctedMetric(original, changes: changed)
        XCTAssertEqual(try XCTUnwrap(edited.weight), 81.64672369841515, accuracy: 0.000000001)
        XCTAssertEqual(edited.bodyFatPercentage, 16.912345)
        let methodOnly = try HomeV2CorrectionPolicy.changes(
            weightText: "81.2", weightWasEdited: false, unit: "kg",
            bodyFat: .init(text: "16.9", wasEdited: false, original: original.bodyFatPercentage,
                           method: nil, originalMethod: "dexa")
        )
        let unspecified = HomeV2CorrectionPolicy.correctedMetric(original, changes: methodOnly)
        XCTAssertEqual(unspecified.weight, 81.234567)
        XCTAssertEqual(unspecified.bodyFatPercentage, 16.912345)
        XCTAssertNil(unspecified.bodyFatMethod)
    }

    func testCorrectionSaveSkipsSemanticNoOpEffectsButPersistsExplicitMethodChanges() async throws {
        let original = correctionMetric()
        let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
        let unchangedWeight = try XCTUnwrap(original.weight)
        let unchangedBodyFat = try XCTUnwrap(original.bodyFatPercentage)
        let structuralNoOps: [HomeV2CorrectionPolicy.Changes] = [
            .init(weight: .kilograms(unchangedWeight)),
            .init(bodyFat: .reading(unchangedBodyFat, method: original.bodyFatMethod)),
            .init(weight: .kilograms(unchangedWeight),
                  bodyFat: .reading(unchangedBodyFat, method: original.bodyFatMethod))
        ]
        for changes in structuralNoOps {
            XCTAssertFalse(changes.isEmpty, "Exercise an explicit edit rather than the existing empty-Changes control")
            var writes = 0, publications = 0
            let saved = await HomeV2CorrectionPolicy.save(
                original, changes: changes, ownership: ownership, ownsSession: { $0 == ownership },
                persist: { _, _ in writes += 1 }, didSave: { _, _ in publications += 1 }
            )
            XCTAssertTrue(saved, "An owned unchanged edit closes successfully without side effects")
            XCTAssertEqual(writes, 0, "No-op must stop before the persistence boundary")
            XCTAssertEqual(publications, 0, "No-op must not publish a saved receipt or weight observation")
        }

        for changesAttribution in [false, true] {
            let store = correctionStore()
            let seeded = try await contextWriterSeed(store)
            if changesAttribution {
                let seededRows = await store.fetchBodyMetrics(for: seeded.userId)
                let row = try XCTUnwrap(seededRows.first)
                row.sourceMetadataJSON = try XCTUnwrap(seeded.sourceMetadata)
                    .settingEntrySource(.manual, fields: [.bodyFat], bodyFatMethod: "bia_scale").jsonString
                try store.viewContext.save()
            }
            let previous = try contextWriterRead(store, id: seeded.id).metric
            let method: String? = changesAttribution ? "dexa" : nil
            let changes = HomeV2CorrectionPolicy.Changes(
                bodyFat: .reading(try XCTUnwrap(previous.bodyFatPercentage), method: method)
            )
            var writes = 0, publications = 0, admissions = 0
            var committed: PhotoMetricsUpdateResult?
            let saved = await HomeV2CorrectionPolicy.save(
                previous, changes: changes, ownership: ownership, ownsSession: { $0 == ownership },
                persist: { proposed, admission in
                    writes += 1
                    _ = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
                        proposed, replacing: previous, changes: changes, store: store,
                        admission: { admissions += 1; try admission() },
                        onStored: { actual in
                            XCTAssertEqual(try self.contextWriterRead(store, id: previous.id).metric, actual)
                        }, onCommitted: { actual in committed = actual }
                    )
                }, didSave: { _, canPublish in
                    XCTAssertTrue(canPublish())
                    publications += 1
                    XCTAssertNotNil(committed, "Publication follows the actual committed result")
                }
            )
            XCTAssertTrue(saved)
            XCTAssertEqual(writes, 1, "Method-only edits must not be swallowed by the no-op guard")
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(admissions, 2)
            let actual = try XCTUnwrap(committed)
            XCTAssertEqual(actual.previousMetric, previous)
            XCTAssertEqual(actual.metrics, try contextWriterRead(store, id: previous.id).metric)
            XCTAssertEqual(actual.metrics.weight, 81.234567)
            XCTAssertEqual(actual.metrics.bodyFatPercentage, 16.912345)
            XCTAssertEqual(actual.metrics.bodyFatMethod, method)
            XCTAssertEqual(actual.metrics.measurementSource(for: .bodyFat), .manual)
            XCTAssertEqual(actual.metrics.sourceMetadata?.enteredBodyFatMethod, method)
            if changesAttribution {
                XCTAssertEqual(previous.bodyFatMethod, "dexa")
                XCTAssertEqual(previous.attributedBodyFatMethod, "bia_scale")
                XCTAssertEqual(actual.metrics.attributedBodyFatMethod, "dexa")
            } else {
                XCTAssertEqual(previous.bodyFatMethod, "dexa")
                XCTAssertNil(actual.metrics.bodyFatMethod)
            }
        }
    }

    func testTodayCorrectionReceiptUsesActualWriterPreviousAndCommittedChangedWeight() async throws {
        let store = correctionStore()
        let original = try await contextWriterSeed(store)
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: 82, bodyFatPercentage: nil,
            bodyFatMethod: nil, markManualCorrection: true, expectedOriginal: original, writeAdmission: {}
        )
        let actualPrevious = try XCTUnwrap(result.previousMetric)
        XCTAssertEqual(actualPrevious, original)
        let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
        let calendar = try fixedCalendar()
        let metric = try XCTUnwrap(HomeV2LoggedEntry.correction(
            previous: actualPrevious, stored: result.metrics, ownership: ownership, system: .metric,
            now: original.date, calendar: calendar
        ))
        XCTAssertEqual(metric.previousMetric, actualPrevious)
        XCTAssertEqual(metric.savedMetric, try contextWriterRead(store, id: original.id).metric)
        XCTAssertEqual(metric.metricId, original.id)
        XCTAssertEqual(metric.date, original.date)
        XCTAssertEqual(metric.valueText, "82.0")
        XCTAssertEqual(metric.unit, "kg")
        let imperial = try XCTUnwrap(HomeV2LoggedEntry.correction(
            previous: actualPrevious, stored: result.metrics, ownership: ownership, system: .imperial,
            now: original.date, calendar: calendar
        ))
        XCTAssertEqual(imperial.valueText, "180.8")
        XCTAssertEqual(imperial.unit, "lb")
        XCTAssertNil(HomeV2LoggedEntry.correction(previous: actualPrevious, stored: result.metrics,
                                                  ownership: .init(subject: "other", generation: 1),
                                                  system: .metric,
                                                  now: original.date,
                                                  calendar: calendar
            )
        )
        XCTAssertNil(HomeV2LoggedEntry.correction(previous: actualPrevious, stored: result.metrics,
                                                  ownership: ownership,
                                                  system: .metric,
                                                  now: original.date.addingTimeInterval(172_800),
                                                  calendar: calendar
            )
        )
    }

    func testTodayCorrectionReceiptRejectsActualBodyFatOnlyMissingWeightAndNoOpWriterResults() async throws {
        for scenario in ["body-fat-only", "missing-weight", "no-op"] {
            let store = correctionStore()
            let original = try await contextWriterSeed(store, weight: scenario == "missing-weight" ? nil : 81.234567)
            var commits = 0
            let result = try await store.updateExistingMetricMeasurementsAndWait(
                id: original.id, userId: original.userId, weight: nil,
                bodyFatPercentage: scenario == "no-op" ? nil : 20, bodyFatMethod: nil,
                markManualCorrection: true, replaceBodyFatMethod: scenario != "no-op",
                expectedOriginal: original, writeAdmission: {},
                commit: { context in commits += 1; try context.save() }
            )
            XCTAssertEqual(result.previousMetric, original)
            XCTAssertEqual(result.metrics.weight, original.weight)
            XCTAssertEqual(result.metrics.bodyFatPercentage, scenario == "no-op" ? original.bodyFatPercentage : 20)
            let ownership = AuthManager.ProfileSessionOwnership(subject: original.userId, generation: 1)
            XCTAssertNil(HomeV2LoggedEntry.correction(
                previous: try XCTUnwrap(result.previousMetric), stored: result.metrics,
                ownership: ownership, system: .metric, now: original.date, calendar: try fixedCalendar()
            ), "No weight receipt, weight observation or weight undo may come from \(scenario)")
            if scenario == "no-op" {
                XCTAssertEqual(commits, 0)
                XCTAssertEqual(result.metrics, original)
            } else { XCTAssertEqual(commits, 1) }
            XCTAssertEqual(try contextWriterRead(store, id: original.id).metric, result.metrics)
        }
    }
}
