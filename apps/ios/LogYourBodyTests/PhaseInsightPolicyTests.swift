//
// BodyMetricLoggingAndInsightTests.swift
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


final class PhaseInsightPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testPhaseInsightShowsByDefaultForV1Launch() {
        XCTAssertTrue(PhaseInsightPolicy.defaultShowsPhaseInsight)
        XCTAssertTrue(PhaseInsightPolicy.shouldShowPhaseInsight())
    }

    func testClassifiesCuttingWithBodyFatContext() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 1), weight: 85, bodyFat: 18),
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 29), weight: 82, bodyFat: 16.9)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .cutting)
        XCTAssertEqual(insight.title, "Cutting")
        XCTAssertTrue(insight.message.contains("body fat is moving lower"))
        XCTAssertLessThan(try XCTUnwrap(insight.weightDeltaPercentPerWeek), -0.25)
        XCTAssertEqual(try XCTUnwrap(insight.bodyFatDeltaPercentagePoints), -1.1, accuracy: 0.001)
    }

    func testClassifiesMaintainingWhenWeightIsStable() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 2, day: 1), weight: 80, bodyFat: 15),
            makePhaseMetric(date: makeDate(year: 2_026, month: 2, day: 28), weight: 80.2, bodyFat: 15.1)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .maintaining)
        XCTAssertEqual(insight.title, "Maintaining")
        XCTAssertTrue(insight.message.contains("holding steady"))
        XCTAssertFalse(insight.isLongRunning)
    }

    func testClassifiesGainingWithBodyFatContext() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 1), weight: 80, bodyFat: 14),
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 29), weight: 82, bodyFat: 14.8)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .gaining)
        XCTAssertEqual(insight.title, "Gaining")
        XCTAssertTrue(insight.message.contains("body fat is moving higher"))
        XCTAssertGreaterThan(try XCTUnwrap(insight.weightDeltaPercentPerWeek), 0.25)
    }

    func testInsufficientDataRequiresTwoWeeksOfWeights() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 1), weight: 80, bodyFat: nil),
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 7), weight: 79.5, bodyFat: nil)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .insufficientData)
        XCTAssertEqual(insight.title, "Need more data")
        XCTAssertNil(insight.weightDeltaPercentPerWeek)
    }

    func testLongRunningCutAddsCautionWithoutChatCopy() {
        let metrics = [
            makePhaseMetric(date: makeDate(year: 2_026, month: 1, day: 1), weight: 90, bodyFat: 22),
            makePhaseMetric(date: makeDate(year: 2_026, month: 3, day: 1), weight: 86, bodyFat: 20),
            makePhaseMetric(date: makeDate(year: 2_026, month: 4, day: 1), weight: 84, bodyFat: 19),
            makePhaseMetric(date: makeDate(year: 2_026, month: 5, day: 1), weight: 82, bodyFat: 18)
        ]

        let insight = PhaseInsightPolicy.insight(for: metrics)

        XCTAssertEqual(insight.kind, .cutting)
        XCTAssertTrue(insight.isLongRunning)
        XCTAssertEqual(insight.detail, "This cut has run 12+ weeks; review photos and body-fat context.")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makePhaseMetric(
        date: Date,
        weight: Double,
        bodyFat: Double?
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "phase-user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: bodyFat == nil ? nil : "manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: date,
            updatedAt: date
        )
    }
}
