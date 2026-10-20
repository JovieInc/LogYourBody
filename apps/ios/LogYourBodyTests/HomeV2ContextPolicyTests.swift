//
// HomeV2ContextPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2ContextPolicyTests: XCTestCase {
    private func metric(
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
        XCTAssertTrue(
            HomeV2Provenance.subline(
                for: metric(daysAgo: 0, weight: 80, source: "healthkit", sourceName: "Withings", hour: 7)
            ).hasPrefix("Withings via Apple Health, ")
        )
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

    func testHistoricalSamplesKeepTimestampSourceAndReviewWarning() throws {
        let calendar = try fixedCalendar()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 14)))
        let sections = HomeV2EntriesPolicy.sections(
            metrics: [
                metric(
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
                metric(
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

    func testCorrectionTargetsOneRecordAndPreservesItsImportLineage() {
        let original = metric(
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
        XCTAssertEqual(corrected.metricSource, .manual)
        XCTAssertEqual(corrected.sourceMetadata, original.sourceMetadata)
        XCTAssertEqual(corrected.createdAt, original.createdAt)
        XCTAssertEqual(corrected.updatedAt, updateTime)
        XCTAssertEqual(corrected.weight, 79.5)
        XCTAssertNil(corrected.bodyFatPercentage)
        XCTAssertNil(corrected.bodyFatMethod)
        XCTAssertEqual(
            HomeV2Provenance.detailedLabel(for: corrected),
            "Withings via Apple Health · corrected in LogYourBody"
        )
    }
}
