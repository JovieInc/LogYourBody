//
// HeroMetricInterpolationCacheTests.swift
// LogYourBodyTests
//
// Value-exactness guard for the scrub optimization: HeroMetricInterpolationCache
// must produce EXACTLY the same weight / body-fat / FFMI values as the previous
// per-call MetricsInterpolationService.estimate{Weight,BodyFat,FFMI} path it replaces.
// Also verifies the cache rebuilds when the underlying metrics change.
//
import XCTest
@testable import LogYourBody

final class HeroMetricInterpolationCacheTests: XCTestCase {
    private let service = MetricsInterpolationService.shared
    private let heightInches: Double = 70

    // MARK: - Reference (pre-optimization) computation

    private func referenceWeight(for metric: BodyMetrics, in metrics: [BodyMetrics]) -> Double? {
        if let weight = metric.weight { return weight }
        return service.estimateWeight(for: metric.date, metrics: metrics)?.value
    }

    private func referenceBodyFat(for metric: BodyMetrics, in metrics: [BodyMetrics]) -> Double? {
        if let bodyFat = metric.bodyFatPercentage { return bodyFat }
        return service.estimateBodyFat(for: metric.date, metrics: metrics)?.value
    }

    private func referenceFFMI(for metric: BodyMetrics, in metrics: [BodyMetrics], heightInches: Double?) -> Double? {
        service.estimateFFMI(for: metric.date, metrics: metrics, heightInches: heightInches)?.value
    }

    private func assertMatchesReference(
        _ metrics: [BodyMetrics],
        heightInches: Double?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cache = HeroMetricInterpolationCache(service: service)
        for (index, metric) in metrics.enumerated() {
            let values = cache.values(for: metric, in: metrics, heightInches: heightInches)
            XCTAssertEqual(values.weight, referenceWeight(for: metric, in: metrics),
                           "weight mismatch at index \(index)", file: file, line: line)
            XCTAssertEqual(values.bodyFat, referenceBodyFat(for: metric, in: metrics),
                           "bodyFat mismatch at index \(index)", file: file, line: line)
            XCTAssertEqual(values.ffmi, referenceFFMI(for: metric, in: metrics, heightInches: heightInches),
                           "ffmi mismatch at index \(index)", file: file, line: line)
        }
    }

    // MARK: - Tests

    func testMatchesReferenceForMixedMetrics() {
        assertMatchesReference(Self.mixedMetrics(), heightInches: heightInches)
    }

    func testMatchesReferenceWithoutHeight_ffmiAlwaysNil() {
        let metrics = Self.mixedMetrics()
        let cache = HeroMetricInterpolationCache(service: service)
        for metric in metrics {
            let values = cache.values(for: metric, in: metrics, heightInches: nil)
            XCTAssertNil(values.ffmi)
            XCTAssertEqual(values.weight, referenceWeight(for: metric, in: metrics))
            XCTAssertEqual(values.bodyFat, referenceBodyFat(for: metric, in: metrics))
        }
    }

    func testMatchesReferenceForSingleMetric() {
        assertMatchesReference([Self.metric(daysAgo: 0, weight: 80, bodyFat: 18)], heightInches: heightInches)
    }

    func testMatchesReferenceWhenValuesSparse() {
        // Only the endpoints carry weight/bf; the middle entries must interpolate.
        let metrics = [
            Self.metric(daysAgo: 40, weight: 84, bodyFat: 22),
            Self.metric(daysAgo: 30, weight: nil, bodyFat: nil),
            Self.metric(daysAgo: 20, weight: nil, bodyFat: nil),
            Self.metric(daysAgo: 10, weight: nil, bodyFat: nil),
            Self.metric(daysAgo: 0, weight: 79, bodyFat: 17)
        ]
        assertMatchesReference(metrics, heightInches: heightInches)
    }

    func testRepeatedCallsAreStable() {
        let metrics = Self.mixedMetrics()
        let cache = HeroMetricInterpolationCache(service: service)
        let first = metrics.map { cache.values(for: $0, in: metrics, heightInches: heightInches) }
        let second = metrics.map { cache.values(for: $0, in: metrics, heightInches: heightInches) }
        XCTAssertEqual(first, second)
    }

    func testCacheInvalidatesWhenMetricsChange() {
        let cache = HeroMetricInterpolationCache(service: service)

        let metricsA = Self.mixedMetrics()
        // Warm the cache on data set A.
        _ = cache.values(for: metricsA[1], in: metricsA, heightInches: heightInches)

        // Different data set (shifted values) — the cache must rebuild, not return A.
        let metricsB = [
            Self.metric(daysAgo: 30, weight: 90, bodyFat: 25),
            Self.metric(daysAgo: 20, weight: nil, bodyFat: nil),
            Self.metric(daysAgo: 10, weight: 88, bodyFat: 23),
            Self.metric(daysAgo: 0, weight: 86, bodyFat: 21)
        ]
        for metric in metricsB {
            let values = cache.values(for: metric, in: metricsB, heightInches: heightInches)
            XCTAssertEqual(values.weight, referenceWeight(for: metric, in: metricsB))
            XCTAssertEqual(values.bodyFat, referenceBodyFat(for: metric, in: metricsB))
            XCTAssertEqual(values.ffmi, referenceFFMI(for: metric, in: metricsB, heightInches: heightInches))
        }
    }

    // MARK: - Fixtures

    private static let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private static func metric(daysAgo: Int, weight: Double?, bodyFat: Double?) -> BodyMetrics {
        let date = baseDate.addingTimeInterval(TimeInterval(-daysAgo) * 86_400)
        return BodyMetrics(
            id: "metric-\(daysAgo)",
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }

    /// Oldest → newest, mixing recorded and missing weight/body-fat so weight, body
    /// fat and FFMI each exercise actual, interpolated and last-known paths.
    private static func mixedMetrics() -> [BodyMetrics] {
        [
            metric(daysAgo: 40, weight: 84, bodyFat: 22),
            metric(daysAgo: 30, weight: nil, bodyFat: 20),
            metric(daysAgo: 20, weight: 81, bodyFat: nil),
            metric(daysAgo: 10, weight: nil, bodyFat: nil),
            metric(daysAgo: 5, weight: 79, bodyFat: 18),
            metric(daysAgo: 0, weight: 78, bodyFat: nil)
        ]
    }
}
