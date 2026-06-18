//
// TimelineDataProviderScrubTests.swift
// LogYourBodyTests
//
// Coverage for the live hero photo-scrubber logic (ProgressTimelineView ->
// TimelineDataProvider): position<->date mapping, photo/metrics search windows,
// nearest-date snapping, anchor generation, and a perf guard on the per-frame
// render signature.
//
import XCTest
@testable import LogYourBody

final class TimelineDataProviderScrubTests: XCTestCase {
    private let calendar = Calendar.current

    // MARK: - dateFromPosition (position -> date, three-zone time weighting)

    func testDateFromPositionMapsZoneBoundaries() throws {
        let endDate = Date(timeIntervalSince1970: 1_800_000_000)
        let startDate = endDate.addingTimeInterval(-86_400 * 800) // ~2.2 years back
        let provider = TimelineDataProvider()

        let thirtyDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: endDate))
        let oneYearAgo = try XCTUnwrap(calendar.date(byAdding: .year, value: -1, to: endDate))

        // 1.0 -> now, 0.3 -> 30d ago, 0.1 -> 1y ago, 0.0 -> startDate
        XCTAssertEqual(provider.dateFromPosition(1.0, from: startDate, to: endDate).timeIntervalSince1970,
                       endDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(provider.dateFromPosition(0.3, from: startDate, to: endDate).timeIntervalSince1970,
                       thirtyDaysAgo.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(provider.dateFromPosition(0.1, from: startDate, to: endDate).timeIntervalSince1970,
                       oneYearAgo.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(provider.dateFromPosition(0.0, from: startDate, to: endDate).timeIntervalSince1970,
                       startDate.timeIntervalSince1970, accuracy: 1)
    }

    func testDateFromPositionIsMonotonicallyIncreasing() {
        let endDate = Date(timeIntervalSince1970: 1_800_000_000)
        let startDate = endDate.addingTimeInterval(-86_400 * 800)
        let provider = TimelineDataProvider()

        var previous = provider.dateFromPosition(0, from: startDate, to: endDate)
        for step in 1...20 {
            let next = provider.dateFromPosition(Double(step) / 20.0, from: startDate, to: endDate)
            XCTAssertGreaterThanOrEqual(next, previous, "position \(step) should not move backward in time")
            previous = next
        }
    }

    func testDateFromPositionGivesRecentZoneMostOfTheTrack() {
        // The last-30-days zone occupies 70% of the track (0.3...1.0).
        let endDate = Date(timeIntervalSince1970: 1_800_000_000)
        let startDate = endDate.addingTimeInterval(-86_400 * 800)
        let provider = TimelineDataProvider()

        // Midpoint of the recent zone (0.65) should sit ~15 days before now.
        let midRecent = provider.dateFromPosition(0.65, from: startDate, to: endDate)
        let daysBeforeNow = endDate.timeIntervalSince(midRecent) / 86_400
        XCTAssertEqual(daysBeforeNow, 15, accuracy: 1)
    }

    // MARK: - findDataForPhotoMode (independent ±7d photo / metrics windows)

    func testFindDataForPhotoModeReturnsNearestPhotoAndMetrics() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        provider.loadMetrics([
            makeMetric(id: "photo-old", date: base.addingTimeInterval(-86_400 * 40),
                       weight: nil, bodyFat: nil, photoUrl: "https://e/p1.jpg"),
            makeMetric(id: "metrics-mid", date: base.addingTimeInterval(-86_400 * 20),
                       weight: 180, bodyFat: 18.0),
            makeMetric(id: "photo-metrics-recent", date: base.addingTimeInterval(-86_400 * 2),
                       weight: 179, bodyFat: 17.5, photoUrl: "https://e/p2.jpg")
        ])

        let result = provider.findDataForPhotoMode(scrubDate: base.addingTimeInterval(-86_400 * 2))
        XCTAssertEqual(result.photo?.bodyMetrics.id, "photo-metrics-recent")
        XCTAssertEqual(result.photo?.daysFromScrub, 0)
        XCTAssertEqual(result.metrics?.bodyMetrics.id, "photo-metrics-recent")
        XCTAssertEqual(result.metrics?.isInterpolated, false)
    }

    func testFindDataForPhotoModeResolvesPhotoAndMetricsIndependently() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        provider.loadMetrics([
            makeMetric(id: "photo-old", date: base.addingTimeInterval(-86_400 * 40),
                       weight: nil, bodyFat: nil, photoUrl: "https://e/p1.jpg"),
            makeMetric(id: "metrics-mid", date: base.addingTimeInterval(-86_400 * 20),
                       weight: 180, bodyFat: 18.0),
            makeMetric(id: "photo-metrics-recent", date: base.addingTimeInterval(-86_400 * 2),
                       weight: 179, bodyFat: 17.5, photoUrl: "https://e/p2.jpg")
        ])

        // Near the metrics-only entry: no photo within ±7d, but the metric resolves.
        let result = provider.findDataForPhotoMode(scrubDate: base.addingTimeInterval(-86_400 * 20))
        XCTAssertNil(result.photo)
        XCTAssertEqual(result.metrics?.bodyMetrics.id, "metrics-mid")
    }

    func testFindDataForPhotoModeReturnsNilOutsideWindow() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        provider.loadMetrics([
            makeMetric(id: "metrics-mid", date: base.addingTimeInterval(-86_400 * 20),
                       weight: 180, bodyFat: 18.0)
        ])

        // 100 days from the only entry -> nothing within either ±7d window.
        let result = provider.findDataForPhotoMode(scrubDate: base.addingTimeInterval(-86_400 * 120))
        XCTAssertNil(result.photo)
        XCTAssertNil(result.metrics)
    }

    // MARK: - findNearestDataDate (binary-search snap)

    func testFindNearestDataDateSnapsToClosest() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        let d0 = base
        let d1 = base.addingTimeInterval(86_400 * 10)
        let d2 = base.addingTimeInterval(86_400 * 20)
        provider.loadMetrics([
            makeMetric(id: "a", date: d0, weight: 180, bodyFat: nil),
            makeMetric(id: "b", date: d1, weight: 181, bodyFat: nil),
            makeMetric(id: "c", date: d2, weight: 182, bodyFat: nil)
        ])

        // Closer to d1 than d2.
        XCTAssertEqual(provider.findNearestDataDate(to: base.addingTimeInterval(86_400 * 12)), d1)
        // Before the first / after the last clamp to the ends.
        XCTAssertEqual(provider.findNearestDataDate(to: base.addingTimeInterval(-86_400 * 5)), d0)
        XCTAssertEqual(provider.findNearestDataDate(to: base.addingTimeInterval(86_400 * 50)), d2)
    }

    func testFindNearestDataDateReturnsNilForEmpty() {
        XCTAssertNil(TimelineDataProvider().findNearestDataDate(to: Date()))
    }

    // MARK: - generateAnchors

    func testGenerateAnchorsProducesInRangePositionsAndTypes() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        let metrics = (0..<8).map { i -> BodyMetrics in
            makeMetric(
                id: "m\(i)",
                date: base.addingTimeInterval(-86_400 * Double(i * 9)),
                weight: 180 - Double(i),
                bodyFat: 18 + Double(i) * 0.1,
                photoUrl: i.isMultiple(of: 2) ? "https://e/m\(i).jpg" : nil
            )
        }
        provider.loadMetrics(metrics)
        let firstDate = provider.bodyMetrics.first!.date
        let lastDate = provider.bodyMetrics.last!.date
        let zoom = TimelineZoomLevel.calculate(from: firstDate, to: lastDate)

        let anchors = provider.generateAnchors(mode: .photo, zoomLevel: zoom)
        XCTAssertFalse(anchors.isEmpty)
        let inputIDs = Set(metrics.map(\.id))
        for anchor in anchors {
            XCTAssertGreaterThanOrEqual(anchor.position, 0)
            XCTAssertLessThanOrEqual(anchor.position, 1)
            XCTAssertTrue(inputIDs.contains(anchor.id))
        }
        // Photo mode must surface at least one photo-bearing anchor.
        XCTAssertTrue(anchors.contains { $0.anchorType == .photo || $0.anchorType == .photoWithMetrics })
    }

    func testGenerateAnchorsEmptyForNoMetrics() {
        let provider = TimelineDataProvider()
        provider.loadMetrics([])
        let anchors = provider.generateAnchors(mode: .photo, zoomLevel: .month)
        XCTAssertTrue(anchors.isEmpty)
    }

    // MARK: - Round-trip (position math consistency)

    func testAnchorPositionRoundTripsThroughDateFromPosition() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = TimelineDataProvider()
        let metrics = [
            makeMetric(id: "old", date: base.addingTimeInterval(-86_400 * 200), weight: 185, bodyFat: nil,
                       photoUrl: "https://e/old.jpg"),
            makeMetric(id: "recent", date: base.addingTimeInterval(-86_400 * 3), weight: 180, bodyFat: nil,
                       photoUrl: "https://e/recent.jpg")
        ]
        provider.loadMetrics(metrics)
        let firstDate = provider.bodyMetrics.first!.date
        let lastDate = provider.bodyMetrics.last!.date
        let zoom = TimelineZoomLevel.calculate(from: firstDate, to: lastDate)
        let anchors = provider.generateAnchors(mode: .photo, zoomLevel: zoom)

        for anchor in anchors {
            let roundTripped = provider.dateFromPosition(anchor.position, from: firstDate, to: lastDate)
            XCTAssertEqual(roundTripped.timeIntervalSince1970,
                           anchor.date.timeIntervalSince1970,
                           accuracy: 86_400, // within a day; positions are time-weighted
                           "anchor \(anchor.id) position should map back to ~its date")
        }
    }

    // MARK: - Render signature (perf-sensitive equality semantics + guard)

    func testRenderSignatureEqualityIgnoresUntrackedFields() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let metric = makeMetric(id: "x", date: base, weight: 180, bodyFat: 18,
                                photoUrl: "https://e/a.jpg")
        let sameRenderInputs = makeMetric(id: "x", date: base, weight: 180, bodyFat: 18,
                                          photoUrl: "https://e/a.jpg", createdAtOffset: 9_999)
        let changedWeight = makeMetric(id: "x", date: base, weight: 181, bodyFat: 18,
                                       photoUrl: "https://e/a.jpg")

        let signature = TimelineRenderSignature(metrics: [metric], mode: .photo)
        XCTAssertEqual(signature, TimelineRenderSignature(metrics: [sameRenderInputs], mode: .photo))
        XCTAssertNotEqual(signature, TimelineRenderSignature(metrics: [metric], mode: .avatar))
        XCTAssertNotEqual(signature, TimelineRenderSignature(metrics: [changedWeight], mode: .photo))
        XCTAssertNotEqual(signature, TimelineRenderSignature(metrics: [metric, metric], mode: .photo))
    }

    func testRenderSignatureConstructionPerformance() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let metrics = (0..<400).map { i in
            makeMetric(id: "m\(i)", date: base.addingTimeInterval(Double(i) * 3_600),
                       weight: 180, bodyFat: 18, photoUrl: "https://e/m\(i).jpg")
        }
        // Simulates the per-frame cost during a drag: build + compare the signature.
        measure {
            var equalCount = 0
            let reference = TimelineRenderSignature(metrics: metrics, mode: .photo)
            for _ in 0..<200 where TimelineRenderSignature(metrics: metrics, mode: .photo) == reference {
                equalCount += 1
            }
            XCTAssertEqual(equalCount, 200)
        }
    }

    // MARK: - Fixture

    private func makeMetric(
        id: String,
        date: Date,
        localDate: String? = nil,
        weight: Double?,
        bodyFat: Double?,
        photoUrl: String? = nil,
        updatedAt: Date? = nil,
        createdAtOffset: TimeInterval = 0
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "timeline-scrub-user",
            date: date,
            localDate: localDate,
            weight: weight,
            weightUnit: "lbs",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date.addingTimeInterval(createdAtOffset),
            updatedAt: updatedAt ?? date
        )
    }
}
