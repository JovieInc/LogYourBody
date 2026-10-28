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


final class BodyMetricLoggingServiceTests: XCTestCase {
    func testStoredWeightConvertsPoundsToKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 180,
            unit: "lbs"
        )

        XCTAssertEqual(stored ?? 0, 81.6467, accuracy: 0.001)
    }

    func testStoredWeightKeepsKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 82.5,
            unit: "kg"
        )

        XCTAssertEqual(stored, 82.5)
    }

    func testLoggedSummaryUsesPreferredWeightUnitAndBodyFatPercent() {
        let metric = BodyMetrics(
            id: "metric-1",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            BodyMetricLoggingService.loggedSummary(for: metric, preferredSystem: .imperial),
            "Logged 180.0 lbs and 14.8% body fat."
        )
    }

    func testSpotlightDocumentUsesLatestMetricSearchCopy() {
        let metric = BodyMetrics(
            id: "metric-spotlight",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial)

        XCTAssertEqual(document?.identifier, "body-metric-metric-spotlight")
        XCTAssertEqual(document?.title, "Latest LogYourBody metrics")
        XCTAssertEqual(document?.contentDescription, "180.0 lbs, 14.8% body fat on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            [
                "LogYourBody",
                "body metrics",
                "weight",
                "body composition",
                "1970-01-01",
                "latest weight",
                "body fat"
            ]
        )
    }

    func testSpotlightDocumentSkipsEntriesWithoutSearchableMetrics() {
        let metric = BodyMetrics(
            id: "metric-empty",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial))
    }

    func testSpotlightDocumentWithWeightOnlyOmitsBodyFatKeyword() {
        let metric = BodyMetrics(
            id: "metric-weight-only",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .metric)

        XCTAssertEqual(document?.contentDescription, "80.0 kg on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            ["LogYourBody", "body metrics", "weight", "body composition", "1970-01-01", "latest weight"]
        )
    }

    func testSpotlightDocumentWithBodyFatOnlyOmitsLatestWeightKeyword() {
        let metric = BodyMetrics(
            id: "metric-bf-only",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: 15,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .metric)

        XCTAssertEqual(document?.contentDescription, "15.0% body fat on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            ["LogYourBody", "body metrics", "weight", "body composition", "1970-01-01", "body fat"]
        )
    }
}
