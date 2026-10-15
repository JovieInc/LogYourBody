//
// HomeV2ContextPolicyTests.swift
// LogYourBodyTests
//
import CoreData
import XCTest
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
