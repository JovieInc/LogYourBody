//
// HomeV2TrendPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2TrendPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func point(daysAgo: Int, value: Double = 170) -> MetricChartDataPoint {
        MetricChartDataPoint(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
            value: value,
            presence: .present
        )
    }

    func testRangeTabsSkipTheOneWeekRangeTheHomeNeverShows() {
        XCTAssertEqual(HomeV2TrendPolicy.visibleRanges, [.month1, .month3, .month6, .year1, .all])
    }

    func testPointsAreFilteredToTheSelectedRangeAndAllKeepsHistory() {
        let points = [point(daysAgo: 0), point(daysAgo: 20), point(daysAgo: 45), point(daysAgo: 400)]

        XCTAssertEqual(HomeV2TrendPolicy.points(points, in: .month1, now: now, calendar: calendar).count, 2)
        XCTAssertEqual(HomeV2TrendPolicy.points(points, in: .month3, now: now, calendar: calendar).count, 3)
        XCTAssertEqual(HomeV2TrendPolicy.points(points, in: .all, now: now, calendar: calendar).count, 4)
    }

    func testTrendNeedsSevenDistinctDaysNotSevenSamples() {
        let sameDay = (0..<7).map { _ in point(daysAgo: 0) }
        XCTAssertFalse(HomeV2TrendPolicy.hasEnoughData(sameDay, calendar: calendar))

        let sixDays = (0..<6).map { point(daysAgo: $0) }
        XCTAssertFalse(HomeV2TrendPolicy.hasEnoughData(sixDays, calendar: calendar))

        let sevenDays = (0..<7).map { point(daysAgo: $0) }
        XCTAssertTrue(HomeV2TrendPolicy.hasEnoughData(sevenDays, calendar: calendar))
    }

    func testStartLabelReadsTheEarliestVisibleDayOrStaysBlank() {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"

        XCTAssertEqual(HomeV2TrendPolicy.startLabel(for: [], formatter: formatter), " ")
        let earliest = point(daysAgo: 30)
        XCTAssertEqual(
            HomeV2TrendPolicy.startLabel(for: [point(daysAgo: 1), earliest], formatter: formatter),
            formatter.string(from: earliest.date)
        )
    }
}
