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
}
