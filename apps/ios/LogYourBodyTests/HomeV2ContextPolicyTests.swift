//
// HomeV2ContextPolicyTests.swift
// LogYourBodyTests
//
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
