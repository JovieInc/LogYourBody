//
// HealthSyncPipelineTests.swift
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


final class MetricChartDataPointPresenceTests: XCTestCase {
    func testEstimatedInitializerMapsToInterpolatedPresence() {
        let point = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 100),
            value: 15.2,
            isEstimated: true
        )

        XCTAssertEqual(point.presence, .interpolated)
        XCTAssertTrue(point.isEstimated)
    }

    func testExplicitPresenceSupportsLastKnownAndMissingStates() {
        let lastKnownPoint = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 200),
            value: 181.0,
            presence: .lastKnown
        )
        let measuredPoint = MetricChartDataPoint(
            date: Date(timeIntervalSince1970: 300),
            value: 180.5
        )

        XCTAssertEqual(lastKnownPoint.presence, .lastKnown)
        XCTAssertTrue(lastKnownPoint.isEstimated)
        XCTAssertEqual(measuredPoint.presence, .present)
        XCTAssertFalse(measuredPoint.isEstimated)
        XCTAssertTrue(MetricPresence.allCases.contains(.missing))
    }

    func testChartLayoutPolicyLimitsXAxisLabelsForCompactAndAccessibilityLayouts() {
        XCTAssertEqual(
            MetricChartLayoutPolicy.xAxisTickCount(for: .week1, isAccessibilitySize: false),
            4
        )
        XCTAssertEqual(
            MetricChartLayoutPolicy.xAxisTickCount(for: .month6, isAccessibilitySize: false),
            4
        )
        XCTAssertEqual(
            MetricChartLayoutPolicy.xAxisTickCount(for: .year1, isAccessibilitySize: false),
            3
        )

        for range in TimeRange.allCases {
            XCTAssertEqual(
                MetricChartLayoutPolicy.xAxisTickCount(for: range, isAccessibilitySize: true),
                3,
                "\(range.rawValue) should retain room for readable accessibility labels"
            )
        }
    }
}
