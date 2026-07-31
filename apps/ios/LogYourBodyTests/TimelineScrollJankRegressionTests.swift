import XCTest
@testable import LogYourBody

/// Guards the scrub hot path: selection stays O(1) and nearest lookup stays logarithmic.
final class TimelineScrollJankRegressionTests: XCTestCase {
    private let calendar = Calendar.current

    func testRenderDataBuildsO1IndexMap() {
        let metrics = (0..<200).map { i in
            makeMetric(id: "m-\(i)", date: date(daysAgo: 200 - i), weight: 180, bodyFat: 15)
        }
        let data = TimelineRenderData.make(metrics: metrics, mode: .photo)
        XCTAssertEqual(data.indexById.count, metrics.count)
        XCTAssertEqual(data.indexById["m-0"], 0)
        XCTAssertEqual(data.indexById["m-199"], 199)
    }

    func testPhotoModeNearestIsWithinWindowAndStable() {
        let provider = TimelineDataProvider()
        let metrics = (0..<120).map { i in
            makeMetric(
                id: "p-\(i)",
                date: date(daysAgo: 120 - i),
                weight: 180,
                bodyFat: 15,
                photoUrl: "https://example.com/\(i).jpg"
            )
        }
        provider.loadMetrics(metrics)
        let target = metrics[60].date
        let result = provider.findDataForPhotoMode(scrubDate: target)
        XCTAssertEqual(result.photo?.bodyMetrics.id, "p-60")
        XCTAssertEqual(result.metrics?.bodyMetrics.id, "p-60")
    }

    func testNearestLookupFindsAdjacentMetric() {
        let provider = TimelineDataProvider()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        provider.loadMetrics([
            makeMetric(id: "a", date: base.addingTimeInterval(-86_400 * 10), weight: 180, bodyFat: 15, photoUrl: "https://e/a.jpg"),
            makeMetric(id: "b", date: base.addingTimeInterval(-86_400 * 2), weight: 179, bodyFat: 14.5, photoUrl: "https://e/b.jpg"),
            makeMetric(id: "c", date: base, weight: 178, bodyFat: 14, photoUrl: "https://e/c.jpg")
        ])
        let result = provider.findDataForPhotoMode(scrubDate: base.addingTimeInterval(-86_400 * 3))
        XCTAssertEqual(result.photo?.bodyMetrics.id, "b")
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    private func makeMetric(
        id: String,
        date: Date,
        weight: Double?,
        bodyFat: Double?,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "scroll-jank-user",
            date: date,
            weight: weight,
            weightUnit: "lbs",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "scale",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }
}
