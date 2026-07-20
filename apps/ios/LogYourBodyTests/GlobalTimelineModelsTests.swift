//
// GlobalTimelineModelsTests.swift
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


final class GlobalTimelineModelsTests: XCTestCase {
    private func decodePresence(_ rawValue: String) throws -> MetricPresence {
        let data = Data("\"\(rawValue)\"".utf8)
        return try JSONDecoder().decode(MetricPresence.self, from: data)
    }

    func testMetricPresenceDecodesCanonicalRawValues() throws {
        XCTAssertEqual(try decodePresence("present"), .present)
        XCTAssertEqual(try decodePresence("interpolated"), .interpolated)
        XCTAssertEqual(try decodePresence("last_known"), .lastKnown)
        XCTAssertEqual(try decodePresence("missing"), .missing)
    }

    func testMetricPresenceDecodesLegacyEstimatedAliasAsInterpolated() throws {
        XCTAssertEqual(try decodePresence("estimated"), .interpolated)
    }

    func testMetricPresenceRejectsUnknownRawValues() {
        XCTAssertThrowsError(try decodePresence("stale"))
    }

    func testMetricPresenceEncodesBackToCanonicalRawValues() throws {
        let encoder = JSONEncoder()

        let encoded = try encoder.encode(MetricPresence.interpolated)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"interpolated\"")
    }

    func testGlobalTimelineScaleRawValuesStayStableForBucketAndCursorCoding() {
        XCTAssertEqual(GlobalTimelineScale.week.rawValue, "week")
        XCTAssertEqual(GlobalTimelineScale.month.rawValue, "month")
        XCTAssertEqual(GlobalTimelineScale.year.rawValue, "year")
    }
}
