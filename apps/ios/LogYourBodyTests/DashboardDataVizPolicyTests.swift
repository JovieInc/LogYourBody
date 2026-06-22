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


final class DashboardDataVizPolicyTests: XCTestCase {
    func testMetricSummaryFootnoteKeepsOneGoalStatWhenGoalExists() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "181.4 lb average",
                goalText: "Target 180.0 lb"
            ),
            "Target 180.0 lb"
        )
    }

    func testMetricSummaryFootnoteFallsBackToOneAverageStat() {
        XCTAssertEqual(
            metricSummaryFootnote(
                averageText: "18.2 average",
                goalText: nil
            ),
            "18.2 average"
        )
    }

    func testMetricSummaryFootnoteOmitsEmptyStats() {
        XCTAssertNil(
            metricSummaryFootnote(
                averageText: "",
                goalText: ""
            )
        )
    }
}
