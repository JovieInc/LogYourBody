//
// DashboardTimelineAndPolicyTests.swift
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


final class DashboardTimelineProviderPerformanceTests: XCTestCase {
    func testNearestBodyMetricIndexSelectsClosestTimelineDate() {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2_026, month: 6, day: 1))!
        let metrics = [
            makeMetric(id: "old", date: baseDate, weight: 181, bodyFat: 18.5),
            makeMetric(
                id: "middle",
                date: calendar.date(byAdding: .day, value: 7, to: baseDate)!,
                weight: 180,
                bodyFat: 18.2
            ),
            makeMetric(
                id: "new",
                date: calendar.date(byAdding: .day, value: 14, to: baseDate)!,
                weight: 179,
                bodyFat: 18.0
            )
        ]

        let scrubDate = calendar.date(byAdding: .day, value: 9, to: baseDate)!

        XCTAssertEqual(nearestBodyMetricIndex(in: metrics, to: scrubDate), 1)
    }

    func testNearestBodyMetricIndexReturnsNilForEmptyTimeline() {
        XCTAssertNil(nearestBodyMetricIndex(in: [], to: Date()))
    }

    func testTimelineRenderSignatureTracksOnlyRenderInputs() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let metric = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg"
        )
        let sameMetric = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg"
        )
        let changedPhoto = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/changed.jpg"
        )
        let changedUpdatedAt = makeMetric(
            id: "metric",
            date: baseDate,
            weight: 181,
            bodyFat: 18.4,
            photoUrl: "https://example.com/original.jpg",
            updatedAt: baseDate.addingTimeInterval(1)
        )

        let signature = TimelineRenderSignature(metrics: [metric], mode: .photo)

        XCTAssertEqual(
            signature,
            TimelineRenderSignature(metrics: [sameMetric], mode: .photo)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [metric], mode: .avatar)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [changedPhoto], mode: .photo)
        )
        XCTAssertNotEqual(
            signature,
            TimelineRenderSignature(metrics: [changedUpdatedAt], mode: .photo)
        )
    }

    func testTimelineRenderDataFactorySortsMetricsAndBuildsAnchors() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newest = makeMetric(id: "newest", date: baseDate, weight: 181, bodyFat: nil)
        let oldest = makeMetric(id: "oldest", date: baseDate.addingTimeInterval(-86_400 * 3), weight: 184, bodyFat: nil)
        let photo = makeMetric(
            id: "photo",
            date: baseDate.addingTimeInterval(-86_400),
            weight: nil,
            bodyFat: 18.4,
            photoUrl: "https://example.com/photo.jpg"
        )

        let renderData = TimelineRenderData.make(metrics: [newest, photo, oldest], mode: .photo)

        XCTAssertEqual(renderData.metrics.map(\.id), ["oldest", "photo", "newest"])
        XCTAssertEqual(renderData.provider.bodyMetrics.map(\.id), ["oldest", "photo", "newest"])
        XCTAssertFalse(renderData.anchors.isEmpty)
        XCTAssertTrue(renderData.anchors.contains { $0.id == "photo" })
    }

    func testLoadMetricsBuildsSortedTimelineIndexesOnce() {
        let provider = TimelineDataProvider()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let oldest = makeMetric(id: "oldest", date: baseDate.addingTimeInterval(-86_400 * 2), weight: 181, bodyFat: nil)
        let photo = makeMetric(
            id: "photo",
            date: baseDate.addingTimeInterval(-86_400),
            weight: nil,
            bodyFat: nil,
            photoUrl: "https://example.com/photo.jpg"
        )
        let bodyData = makeMetric(id: "body-data", date: baseDate, weight: nil, bodyFat: 18.4)

        provider.loadMetrics([bodyData, photo, oldest])

        XCTAssertEqual(provider.bodyMetrics.map(\.id), ["oldest", "photo", "body-data"])
        XCTAssertEqual(provider.getAllDataDates(), [oldest.date, photo.date, bodyData.date])
        XCTAssertEqual(provider.findNearestDataDate(to: baseDate.addingTimeInterval(-3_600)), bodyData.date)
    }

    func testLocalDateLookupHandlesMultipleMetricsOnSameDay() throws {
        let provider = TimelineDataProvider()
        let calendar = Calendar(identifier: .gregorian)
        let morningDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2_026,
            month: 6,
            day: 14,
            hour: 8
        )))
        let eveningDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2_026,
            month: 6,
            day: 14,
            hour: 16
        )))
        let morning = makeMetric(
            id: "morning",
            date: morningDate,
            localDate: "2026-06-14",
            weight: 181,
            bodyFat: nil
        )
        let evening = makeMetric(
            id: "evening",
            date: eveningDate,
            localDate: "2026-06-14",
            weight: 180.5,
            bodyFat: nil
        )

        provider.loadMetrics([evening, morning])

        XCTAssertEqual(provider.getMetric(for: morning.date)?.id, "evening")
    }

    private func makeMetric(
        id: String,
        date: Date,
        localDate: String? = nil,
        weight: Double?,
        bodyFat: Double?,
        photoUrl: String? = nil,
        updatedAt: Date? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "timeline-performance-user",
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
            createdAt: date,
            updatedAt: updatedAt ?? date
        )
    }
}
