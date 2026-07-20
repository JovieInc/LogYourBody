//
// ErrorTrackingServiceTests.swift
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


final class ErrorTrackingServiceTests: XCTestCase {
    private final class FakeErrorTrackingVendor: ErrorTrackingVendor {
        private(set) var startCallCount = 0
        private(set) var tags: [(value: String, key: String)] = []
        private(set) var extras: [(value: String, key: String)] = []
        private(set) var capturedErrors: [Error] = []
        private(set) var breadcrumbLevels: [ErrorTrackingService.BreadcrumbLevel] = []
        private(set) var breadcrumbCategories: [String] = []
        private(set) var breadcrumbMessages: [String] = []
        private(set) var breadcrumbData: [[String: String]?] = []

        func start() {
            startCallCount += 1
        }

        func setTag(value: String, key: String) {
            tags.append((value, key))
        }

        func setExtra(value: String, key: String) {
            extras.append((value, key))
        }

        func capture(error: Error) {
            capturedErrors.append(error)
        }

        func addBreadcrumb(
            level: ErrorTrackingService.BreadcrumbLevel,
            category: String,
            message: String,
            data: [String: String]?
        ) {
            breadcrumbLevels.append(level)
            breadcrumbCategories.append(category)
            breadcrumbMessages.append(message)
            breadcrumbData.append(data)
        }
    }

    private func makeService() -> (ErrorTrackingService, FakeErrorTrackingVendor) {
        let vendor = FakeErrorTrackingVendor()
        return (ErrorTrackingService(vendor: vendor), vendor)
    }

    private func tagValues(_ vendor: FakeErrorTrackingVendor, forKey key: String) -> [String] {
        vendor.tags.filter { $0.key == key }.map { $0.value }
    }

    func testStartDelegatesToVendor() {
        let (service, vendor) = makeService()

        service.start()

        XCTAssertEqual(vendor.startCallCount, 1)
    }

    func testCaptureMapsFullContextToTagsAndExtra() {
        let (service, vendor) = makeService()
        let appError = AppError.network(operation: "fetchMetrics", underlying: NSError(domain: "test", code: 42))
        let context = ErrorContext(feature: "sync", operation: "push", screen: "dashboard", userId: "user-1")

        service.capture(appError: appError, context: context)

        XCTAssertEqual(tagValues(vendor, forKey: "feature"), ["sync"])
        XCTAssertEqual(tagValues(vendor, forKey: "operation"), ["push"])
        XCTAssertEqual(tagValues(vendor, forKey: "screen"), ["dashboard"])
        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["user-1"])
        XCTAssertEqual(vendor.extras.count, 1)
        XCTAssertEqual(vendor.extras.first?.key, "appError")
        XCTAssertEqual(vendor.extras.first?.value, String(describing: appError))

        XCTAssertEqual(vendor.capturedErrors.count, 1)
        guard case .network(let operation, _)? = vendor.capturedErrors.first as? AppError else {
            return XCTFail("Expected the original AppError to reach the vendor")
        }
        XCTAssertEqual(operation, "fetchMetrics")
    }

    func testCaptureOmitsAbsentContextFields() {
        let (service, vendor) = makeService()
        let context = ErrorContext(feature: "photos", operation: nil, screen: nil, userId: nil)

        service.capture(appError: .unexpected(context: "photos", underlying: NSError(domain: "t", code: 1)), context: context)

        XCTAssertEqual(vendor.tags.count, 1)
        XCTAssertEqual(vendor.tags.first?.key, "feature")
        XCTAssertEqual(vendor.capturedErrors.count, 1)
    }

    func testAddBreadcrumbForwardsLevelCategoryMessageAndData() throws {
        let (service, vendor) = makeService()

        service.addBreadcrumb(
            message: "upload failed",
            category: "photos",
            level: .error,
            data: ["photo_id": "abc"]
        )

        XCTAssertEqual(vendor.breadcrumbLevels, [.error])
        XCTAssertEqual(vendor.breadcrumbCategories, ["photos"])
        XCTAssertEqual(vendor.breadcrumbMessages, ["upload failed"])
        XCTAssertEqual(try XCTUnwrap(vendor.breadcrumbData.first), ["photo_id": "abc"])
    }

    func testAddBreadcrumbDefaultsToInfoLevelWithNoData() throws {
        let (service, vendor) = makeService()

        service.addBreadcrumb(message: "sync started", category: "sync")

        XCTAssertEqual(vendor.breadcrumbLevels, [.info])
        XCTAssertNil(try XCTUnwrap(vendor.breadcrumbData.first))
    }

    func testUpdateUserIdTagsNonEmptyValue() {
        let (service, vendor) = makeService()

        service.updateUserId("user-9")

        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["user-9"])
    }

    func testUpdateUserIdFallsBackToNoneForNilOrEmpty() {
        let (service, vendor) = makeService()

        service.updateUserId(nil)
        service.updateUserId("")

        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["none", "none"])
    }
}
