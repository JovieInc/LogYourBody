//
// HomeV2PhotoJourneyPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2PhotoJourneyPolicyTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    func testCopyReadsAsTheDesignWrites() {
        XCTAssertEqual(HomeV2PhotoCopy.compareTitle(days: 176), "Compare · 176 days")
        XCTAssertEqual(HomeV2PhotoCopy.compareTitle(days: 1), "Compare · 1 day")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: -12.8, unit: "lb", days: 176), "−12.8 lb in 176 days")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: 0.3, unit: "kg", days: 30), "+0.3 kg in 30 days")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: 0.01, unit: "lb", days: 3), "No change in 3 days")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatDeltaLine(-7.2), "Est. body fat −7.2 pts")
        XCTAssertNil(HomeV2PhotoCopy.bodyFatDeltaLine(nil))
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatTransition(from: 21.4, to: 14.2), "Body fat: 21.4% → 14.2%")
        XCTAssertEqual(HomeV2PhotoCopy.playbackSummary(speed: 1, loops: false), "Playback · 1× · Loop off")
        XCTAssertEqual(HomeV2PhotoCopy.playbackSummary(speed: 0.5, loops: true), "Playback · 0.5× · Loop on")
        XCTAssertEqual(HomeV2PhotoCopy.photoDetails(weight: "173.4 lb"), "Photo details · 173.4 lb")
        XCTAssertEqual(HomeV2PhotoCopy.timelapseSubtitle(from: "Apr 2", to: "Sep 25", count: 24), "Apr 2 to Sep 25, 24 photos")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(-7.2), "Body fat · −7.2 pts")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(0.0), "Body fat · no change")
    }

    func testRulerSpansAtLeastEightWeeksAndFindsTheNearestPhoto() {
        let dates = [day(20), day(10), day(0)]
        let span = HomeV2PhotoRulerPolicy.span(for: dates)
        XCTAssertEqual(span.start, day(20))
        XCTAssertGreaterThanOrEqual(span.duration, TimeInterval(HomeV2PhotoRulerPolicy.minimumSpanDays * 24 * 60 * 60) - 1)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.fraction(of: day(20), in: span), 0, accuracy: 0.001)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 0, dates: dates, span: span), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 1, dates: dates, span: span), 2)
        XCTAssertNil(HomeV2PhotoRulerPolicy.nearestIndex(to: 0.5, dates: [], span: span))
        XCTAssertGreaterThanOrEqual(HomeV2PhotoRulerPolicy.weekTicks(in: span).count, 8)
        XCTAssertFalse(HomeV2PhotoRulerPolicy.monthStarts(in: span).isEmpty)

        let long = HomeV2PhotoRulerPolicy.span(for: [day(200), day(0)])
        XCTAssertEqual(long.end, day(0))
    }

    func testTimelapseAdvancesAndStopsOrLoops() {
        XCTAssertEqual(HomeV2TimelapsePolicy.next(after: 0, count: 3, loops: false), 1)
        XCTAssertNil(HomeV2TimelapsePolicy.next(after: 2, count: 3, loops: false))
        XCTAssertEqual(HomeV2TimelapsePolicy.next(after: 2, count: 3, loops: true), 0)
        XCTAssertNil(HomeV2TimelapsePolicy.next(after: 0, count: 0, loops: true))
        XCTAssertEqual(HomeV2TimelapsePolicy.frameInterval(speed: 2), 0.3, accuracy: 0.001)
        XCTAssertEqual(HomeV2TimelapsePolicy.frameInterval(speed: 0.5), 1.2, accuracy: 0.001)
    }

    func testEveryToolNamesItsDestination() {
        for tool in HomeV2PhotoTool.allCases {
            XCTAssertFalse(tool.title.isEmpty)
            XCTAssertFalse(tool.systemImage.isEmpty)
            XCTAssertFalse(tool.identifier.isEmpty)
        }
        XCTAssertEqual(HomeV2PhotoPair(before: 2, after: 5).id, "2-5")
    }
}
