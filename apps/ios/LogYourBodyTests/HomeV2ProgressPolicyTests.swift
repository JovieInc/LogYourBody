//
// HomeV2ProgressPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2ProgressPolicyTests: XCTestCase {
    private func point(daysAgo: Int, value: Double) -> MetricChartDataPoint {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return MetricChartDataPoint(date: date, value: value, presence: .present)
    }

    func testDeltaSentencesReadAsSentences() {
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: -4.1, unit: "lb", range: .month3), "Down 4.1 lb in 3 months")
        XCTAssertEqual(
            HomeV2ProgressCopy.deltaSentence(delta: 0.9, unit: "points", range: .month1),
            "Up 0.9 points in 30 days"
        )
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: -0.3, unit: "", range: .year1), "Down 0.3 in a year")
        XCTAssertEqual(HomeV2ProgressCopy.deltaSentence(delta: 0.01, unit: "lb", range: .all), "No change overall")
        XCTAssertEqual(
            HomeV2ProgressCopy.deltaSentence(delta: nil, unit: "lb", range: .month6),
            "Your trend appears after 7 days"
        )
        XCTAssertEqual(HomeV2ProgressCopy.loggedDaysSentence(days: 3), "3 days logged. Your trend appears after 7.")
        XCTAssertEqual(HomeV2ProgressCopy.loggedDaysSentence(days: 1), "1 day logged. Your trend appears after 7.")
        XCTAssertEqual(HomeV2ProgressCopy.estimatedBy("Withings"), "Estimated by your Withings")
        XCTAssertEqual(HomeV2ProgressCopy.estimatedBy("Typed"), "Estimated, typed by you")
        XCTAssertTrue(HomeV2ProgressCopy.stepsAverageSentence(average: 8_412, range: .month3).hasPrefix("Averaging "))
    }

    func testStepFormatterPreservesOrdinaryRoundingAndLocale() {
        let formatter = FormatterCache.stepsFormatter
        let originalLocale = formatter.locale
        defer { formatter.locale = originalLocale }
        formatter.locale = Locale(identifier: "en_US")
        XCTAssertEqual(FormatterCache.formattedSteps(0), "0")
        XCTAssertEqual(FormatterCache.formattedSteps(8_421.49), "8,421")
        XCTAssertEqual(FormatterCache.formattedSteps(8_421.5), "8,422")
        XCTAssertEqual(FormatterCache.formattedSteps(-8_421.5), "-8,422")
        XCTAssertEqual(FormatterCache.formattedSteps(Double(Int32.max)), "2,147,483,647")
        formatter.locale = Locale(identifier: "de_DE")
        XCTAssertEqual(FormatterCache.formattedSteps(8_421.5), "8.422")
        formatter.locale = Locale(identifier: "hi_IN")
        XCTAssertEqual(FormatterCache.formattedSteps(123_456), "1,23,456")
    }

    func testStepFormatterHandlesFiniteValuesBeyondIntegerRange() {
        let formatter = FormatterCache.stepsFormatter
        let originalLocale = formatter.locale
        defer { formatter.locale = originalLocale }
        formatter.locale = Locale(identifier: "en_US")
        XCTAssertEqual(FormatterCache.formattedSteps(1e20), "100,000,000,000,000,000,000")
        for value in [Double(Int.max), Double(Int.min), Double.greatestFiniteMagnitude] {
            XCTAssertFalse(FormatterCache.formattedSteps(value)?.isEmpty ?? true)
        }
    }

    func testStepFormatterTreatsNonfiniteValuesAsMissing() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(FormatterCache.formattedSteps(value))
        }
    }

    func testStepAverageFormatsFractionalAndLargeValuesWithoutIntegerConversion() {
        let formatter = FormatterCache.stepsFormatter
        let originalLocale = formatter.locale
        defer { formatter.locale = originalLocale }
        formatter.locale = Locale(identifier: "en_US")
        XCTAssertEqual(
            HomeV2ProgressCopy.stepsAverageSentence(average: 8_421.5, range: .month3),
            "Averaging 8,422 a day in 3 months"
        )
        XCTAssertEqual(
            HomeV2ProgressCopy.stepsAverageSentence(average: 1e20, range: .all),
            "Averaging 100,000,000,000,000,000,000 a day overall"
        )
        XCTAssertEqual(
            HomeV2ProgressCopy.stepsAverageSentence(average: 0, range: .week1),
            "Averaging 0 a day in 7 days"
        )
    }

    func testStepAverageTreatsMissingAndNonfiniteValuesAsNoTrend() {
        for value: Double? in [nil, .nan, .infinity, -.infinity] {
            XCTAssertEqual(
                HomeV2ProgressCopy.stepsAverageSentence(average: value, range: .month1),
                HomeV2ProgressCopy.noTrendYet
            )
        }
    }

    func testStatsTakeStartLowAndChangeFromTheVisiblePoints() {
        let points = [point(daysAgo: 0, value: 173.4), point(daysAgo: 10, value: 172.9), point(daysAgo: 40, value: 186.2)]
        let stats = HomeV2ProgressPolicy.stats(points: points, prefersHigh: false)
        XCTAssertEqual(stats.latest ?? 0, 173.4, accuracy: 0.001)
        XCTAssertEqual(stats.start ?? 0, 186.2, accuracy: 0.001)
        XCTAssertEqual(stats.extreme ?? 0, 172.9, accuracy: 0.001)
        XCTAssertEqual(stats.delta ?? 0, -12.8, accuracy: 0.001)
        XCTAssertEqual(stats.distinctDays, 3)

        let steps = HomeV2ProgressPolicy.stats(
            points: [point(daysAgo: 0, value: 9_842), point(daysAgo: 1, value: 4_000)],
            prefersHigh: true
        )
        XCTAssertEqual(steps.extreme ?? 0, 9_842, accuracy: 0.001)
        XCTAssertEqual(steps.average ?? 0, 6_921, accuracy: 0.001)

        let empty = HomeV2ProgressPolicy.stats(points: [], prefersHigh: false)
        XCTAssertNil(empty.latest)
        XCTAssertNil(empty.delta)
        XCTAssertEqual(empty.distinctDays, 0)
    }

    func testEveryMetricHasAnAccentAndATitle() {
        for metric in HomeV2ProgressMetric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.identifier.isEmpty)
        }
        XCTAssertTrue(HomeV2ProgressMetric.steps.prefersHigh)
        XCTAssertFalse(HomeV2ProgressMetric.weight.prefersHigh)
    }
}
