//
// TimelinePhotoSamplerTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


final class TimelinePhotoSamplerTests: XCTestCase {
    private func makeMetric(id: String, weight: Double? = nil, bodyFat: Double? = nil, photo: String? = nil) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user-1",
            date: Date(timeIntervalSince1970: 1_000),
            localDate: "1970-01-01",
            weight: weight,
            weightUnit: weight == nil ? nil : "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photo,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func makeBucket(candidates: [BodyMetrics]) -> TimelineBucket {
        var bucket = TimelineBucket(startDate: Date(timeIntervalSince1970: 0), days: 2)
        for candidate in candidates {
            bucket.addCandidate(candidate)
        }
        return bucket
    }

    func testSelectRepresentativeReturnsNilForEmptyBucket() {
        XCTAssertNil(TimelinePhotoSampler.selectRepresentative(from: makeBucket(candidates: []), previousMetric: nil))
    }

    func testSelectRepresentativeReturnsOnlyCandidate() {
        let only = makeMetric(id: "only")

        XCTAssertEqual(
            TimelinePhotoSampler.selectRepresentative(from: makeBucket(candidates: [only]), previousMetric: nil)?.id,
            "only"
        )
    }

    func testSignificantWeightChangeBeatsCompleteMetrics() {
        let previous = makeMetric(id: "prev", weight: 100)
        let milestone = makeMetric(id: "milestone", weight: 105)
        let complete = makeMetric(id: "complete", weight: 100.5, bodyFat: 20)

        let selected = TimelinePhotoSampler.selectRepresentative(
            from: makeBucket(candidates: [complete, milestone]),
            previousMetric: previous
        )

        XCTAssertEqual(selected?.id, "milestone")
    }

    func testSignificantBodyFatChangeBeatsCompleteMetrics() {
        let previous = makeMetric(id: "prev", weight: 100, bodyFat: 20)
        let milestone = makeMetric(id: "milestone", bodyFat: 21.5)
        let complete = makeMetric(id: "complete", weight: 100, bodyFat: 20.5)

        let selected = TimelinePhotoSampler.selectRepresentative(
            from: makeBucket(candidates: [complete, milestone]),
            previousMetric: previous
        )

        XCTAssertEqual(selected?.id, "milestone")
    }

    func testCompleteMetricsBeatPhotoOnlyCandidate() {
        let complete = makeMetric(id: "complete", weight: 80, bodyFat: 15)
        let photoOnly = makeMetric(id: "photo", photo: "https://example.com/p.jpg")

        let selected = TimelinePhotoSampler.selectRepresentative(
            from: makeBucket(candidates: [photoOnly, complete]),
            previousMetric: nil
        )

        XCTAssertEqual(selected?.id, "complete")
    }

    func testPhotoCandidateBeatsMetriclessCandidate() {
        let photo = makeMetric(id: "photo", photo: "https://example.com/p.jpg")
        let empty = makeMetric(id: "empty")

        let selected = TimelinePhotoSampler.selectRepresentative(
            from: makeBucket(candidates: [empty, photo]),
            previousMetric: nil
        )

        XCTAssertEqual(selected?.id, "photo")
    }

    func testSamplePhotosTakesOnePerBucketWhenBucketsFitLimit() {
        let buckets = [
            makeBucket(candidates: [makeMetric(id: "a", weight: 80)]),
            makeBucket(candidates: [makeMetric(id: "b", weight: 81)]),
            makeBucket(candidates: [])
        ]

        let sampled = TimelinePhotoSampler.samplePhotos(from: buckets, maxThumbnails: 5, sortedMetrics: [])

        XCTAssertEqual(sampled.map(\.id), ["a", "b"])
    }

    func testSamplePhotosThinsBucketsByStrideWhenOverLimit() {
        let buckets = (0..<5).map { index in
            makeBucket(candidates: [makeMetric(id: "bucket-\(index)", weight: 80)])
        }

        let sampled = TimelinePhotoSampler.samplePhotos(from: buckets, maxThumbnails: 2, sortedMetrics: [])

        XCTAssertEqual(sampled.map(\.id), ["bucket-0", "bucket-2"])
    }

    func testSamplePhotosUsesPreviouslySampledMetricForMilestoneScoring() {
        let anchor = makeMetric(id: "anchor", weight: 100)
        let milestone = makeMetric(id: "milestone", weight: 104)
        let flat = makeMetric(id: "flat", weight: 100.5, photo: "https://example.com/p.jpg")
        let buckets = [
            makeBucket(candidates: [anchor]),
            makeBucket(candidates: [flat, milestone])
        ]

        let sampled = TimelinePhotoSampler.samplePhotos(from: buckets, maxThumbnails: 5, sortedMetrics: [])

        XCTAssertEqual(sampled.map(\.id), ["anchor", "milestone"])
    }

    func testMetricsWithPhotosFiltersMissingOrEmptyPhotoUrls() {
        let metrics = [
            makeMetric(id: "none"),
            makeMetric(id: "empty", photo: ""),
            makeMetric(id: "has", photo: "https://example.com/p.jpg")
        ]

        XCTAssertEqual(TimelinePhotoSampler.metricsWithPhotos(from: metrics).map(\.id), ["has"])
    }

    func testMetricsWithDataKeepsAnySignal() {
        let metrics = [
            makeMetric(id: "weight", weight: 80),
            makeMetric(id: "bf", bodyFat: 15),
            makeMetric(id: "photo", photo: "https://example.com/p.jpg"),
            makeMetric(id: "empty")
        ]

        XCTAssertEqual(
            TimelinePhotoSampler.metricsWithData(from: metrics).map(\.id),
            ["weight", "bf", "photo"]
        )
    }
}
