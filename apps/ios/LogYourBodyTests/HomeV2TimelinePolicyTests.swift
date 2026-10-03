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
