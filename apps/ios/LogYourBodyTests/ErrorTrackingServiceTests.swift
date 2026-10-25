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
        private(set) var calls: [String] = []
        private(set) var callsWereOnMain: [Bool] = []
        var onCapture: (() -> Void)?
        var onBreadcrumb: (() -> Void)?
        private(set) var startCallCount = 0
        private(set) var tags: [(value: String, key: String)] = []
        private(set) var extras: [(value: String, key: String)] = []
        private(set) var capturedErrors: [Error] = []
        private(set) var breadcrumbLevels: [ErrorTrackingService.BreadcrumbLevel] = []
        private(set) var breadcrumbCategories: [String] = []
        private(set) var breadcrumbMessages: [String] = []
        private(set) var breadcrumbData: [[String: String]?] = []

        private func record(_ call: String) {
            calls.append(call)
            callsWereOnMain.append(Thread.isMainThread)
        }

        func start() {
            record("start")
            startCallCount += 1
        }

        func setTag(value: String, key: String) {
            record("tag:\(key)=\(value)")
            tags.append((value, key))
        }

        private(set) var userIDs: [String] = []

        func setUser(id: String) {
            record("user:\(id)")
            userIDs.append(id)
        }

        func setExtra(value: String, key: String) {
            record("extra:\(key)=\(value)")
            extras.append((value, key))
        }

        func capture(error: Error) {
            record("capture")
            capturedErrors.append(error)
            onCapture?()
        }

        func addBreadcrumb(
            level: ErrorTrackingService.BreadcrumbLevel,
            category: String,
            message: String,
            data: [String: String]?
        ) {
            record("breadcrumb")
            breadcrumbLevels.append(level)
            breadcrumbCategories.append(category)
            breadcrumbMessages.append(message)
            breadcrumbData.append(data)
            onBreadcrumb?()
        }
    }

    private func makeService() -> (ErrorTrackingService, FakeErrorTrackingVendor) {
        let vendor = FakeErrorTrackingVendor()
        return (ErrorTrackingService(vendor: vendor, installID: { "i_test-install" }), vendor)
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
        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["[Filtered]"])
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
        XCTAssertEqual(try XCTUnwrap(vendor.breadcrumbData.first), ["photo_id": "[Filtered]"])
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

        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["[Filtered]"])
    }

    func testUpdateUserIdSendsOnlyAnOpaqueHashedUser() throws {
        let (service, vendor) = makeService()

        service.updateUserId("user-9")

        let id = try XCTUnwrap(vendor.userIDs.first)
        XCTAssertTrue(id.hasPrefix("u_"))
        XCTAssertEqual(id.count, 18)
        XCTAssertFalse(id.contains("user-9"))
        XCTAssertEqual(id, ErrorTrackingIdentity.anonymousID(for: "user-9"))
        XCTAssertNotEqual(id, ErrorTrackingIdentity.anonymousID(for: "user-10"))
    }

    func testSignedOutSessionsReportTheInstallIdSoImpactIsNeverZeroUsers() {
        let (service, vendor) = makeService()

        service.updateUserId(nil)
        service.updateUserId("")

        XCTAssertEqual(vendor.userIDs, ["i_test-install", "i_test-install"])
    }

    func testUpdateUserIdFallsBackToNoneForNilOrEmpty() {
        let (service, vendor) = makeService()

        service.updateUserId(nil)
        service.updateUserId("")

        XCTAssertEqual(tagValues(vendor, forKey: "userId"), ["none", "none"])
    }

    func testBackgroundCapturePreservesOrderedRedactedContextAndOriginalErrorOnMain() async {
        let (service, vendor) = makeService()
        let delivered = expectation(description: "background error delivered")
        vendor.onCapture = { delivered.fulfill() }
        let underlying = NSError(domain: "background-test", code: 42)
        let appError = AppError.unexpected(context: "person@example.com", underlying: underlying)
        let context = ErrorContext(feature: "healthKit", operation: "background", screen: "profile", userId: "user-1")

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            service.capture(appError: appError, context: context)
        }
        await fulfillment(of: [delivered], timeout: 2)

        await MainActor.run {
            XCTAssertEqual(vendor.calls, [
                "tag:feature=healthKit", "tag:operation=background", "tag:screen=profile",
                "tag:userId=[Filtered]", "extra:appError=[Filtered]", "capture"
            ])
            XCTAssertTrue(vendor.callsWereOnMain.allSatisfy { $0 })
            XCTAssertEqual(vendor.capturedErrors.count, 1)
            guard case .unexpected(let originalContext, let originalError)? = vendor.capturedErrors.first as? AppError else {
                return XCTFail("Expected the original error, not a replacement")
            }
            XCTAssertEqual(originalContext, "person@example.com")
            XCTAssertTrue((originalError as NSError) === underlying)
        }
    }

    func testBackgroundStartIdentityAndBreadcrumbKeepOrderAndRedactionOnMain() async {
        let (service, vendor) = makeService()
        let delivered = expectation(description: "background breadcrumb delivered")
        vendor.onBreadcrumb = { delivered.fulfill() }

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            service.start()
            service.updateUserId("user-9")
            service.addBreadcrumb(
                message: "person@example.com", category: "healthKit", level: .error,
                data: ["weight_kg": "72.5", "operation": "read"]
            )
        }
        await fulfillment(of: [delivered], timeout: 2)

        await MainActor.run {
            XCTAssertEqual(vendor.calls.count, 4)
            XCTAssertEqual(vendor.calls.first, "start")
            XCTAssertTrue(vendor.calls[1].hasPrefix("user:u_"))
            XCTAssertEqual(Array(vendor.calls.suffix(2)), ["tag:userId=[Filtered]", "breadcrumb"])
            XCTAssertTrue(vendor.callsWereOnMain.allSatisfy { $0 })
            XCTAssertEqual(vendor.startCallCount, 1)
            XCTAssertEqual(vendor.breadcrumbMessages, ["[Filtered]"])
            XCTAssertEqual(vendor.breadcrumbLevels, [.error])
            XCTAssertEqual(vendor.breadcrumbCategories, ["healthKit"])
            XCTAssertEqual(vendor.breadcrumbData.compactMap { $0 }, [["weight_kg": "[Filtered]", "operation": "read"]])
        }
    }

    func testConcurrentBackgroundCapturesKeepEachContextWithItsEvent() async {
        let (service, vendor) = makeService()
        let delivered = expectation(description: "all background errors delivered")
        delivered.expectedFulfillmentCount = 8
        vendor.onCapture = { delivered.fulfill() }

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.concurrentPerform(iterations: 8) { index in
                let operation = "operation-\(index)"
                let context = ErrorContext(feature: operation, operation: nil, screen: nil, userId: nil)
                service.capture(appError: .network(operation: operation, underlying: nil), context: context)
            }
        }
        await fulfillment(of: [delivered], timeout: 2)

        await MainActor.run {
            XCTAssertEqual(vendor.capturedErrors.count, 8)
            guard vendor.calls.count == 24 else {
                return XCTFail("Expected three ordered calls for each of eight events")
            }
            XCTAssertTrue(vendor.callsWereOnMain.allSatisfy { $0 })
            XCTAssertEqual(Set(vendor.tags.map(\.value)), Set((0..<8).map { "operation-\($0)" }))
            for (index, error) in vendor.capturedErrors.enumerated() {
                guard case .network(let operation, _)? = error as? AppError else {
                    return XCTFail("Expected the original network error")
                }
                XCTAssertEqual(Array(vendor.calls[(index * 3)..<(index * 3 + 3)]), [
                    "tag:feature=\(operation)", "extra:appError=\(String(describing: error))", "capture"
                ])
            }
        }
    }

    func testRedactorFiltersEmailHealthValuesAndIdentifiers() {
        XCTAssertEqual(
            ErrorTrackingRedactor.sanitize("tim@example.com"),
            ErrorTrackingRedactor.filteredValue
        )
        XCTAssertEqual(
            ErrorTrackingRedactor.sanitize("72.5", key: "weight_kg"),
            ErrorTrackingRedactor.filteredValue
        )
        XCTAssertEqual(
            ErrorTrackingRedactor.sanitize("user-123", key: "user_id"),
            ErrorTrackingRedactor.filteredValue
        )
    }
}
