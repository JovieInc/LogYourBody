//
// ErrorReporterTests.swift
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


final class ErrorReporterTests: XCTestCase {
    private final class RecordingVendor: ErrorTrackingVendor {
        private(set) var capturedErrors: [Error] = []
        private(set) var tags: [(value: String, key: String)] = []

        func start() {}

        func setTag(value: String, key: String) {
            tags.append((value, key))
        }

        func setExtra(value: String, key: String) {}

        func capture(error: Error) {
            capturedErrors.append(error)
        }

        func addBreadcrumb(
            level: ErrorTrackingService.BreadcrumbLevel,
            category: String,
            message: String,
            data: [String: String]?
        ) {}
    }

    private func makeReporter() -> (ErrorReporter, RecordingVendor) {
        let vendor = RecordingVendor()
        let tracking = ErrorTrackingService(vendor: vendor)
        return (ErrorReporter(errorTracking: tracking), vendor)
    }

    func testCaptureForwardsOriginalErrorAndContextToTracking() {
        let (reporter, vendor) = makeReporter()
        let appError = AppError.billing(operation: "purchase", underlying: NSError(domain: "rc", code: 1))
        let context = ErrorContext(feature: "billing", operation: "purchase", screen: "paywall", userId: "user-1")

        reporter.capture(appError, context: context)

        XCTAssertEqual(vendor.capturedErrors.count, 1)
        guard case .billing(let operation, _)? = vendor.capturedErrors.first as? AppError else {
            return XCTFail("Expected the original AppError to be forwarded unchanged")
        }
        XCTAssertEqual(operation, "purchase")
        XCTAssertEqual(vendor.tags.filter { $0.key == "feature" }.map { $0.value }, ["billing"])
    }

    func testCaptureNonFatalWrapsUnderlyingErrorWithOperationContext() {
        let (reporter, vendor) = makeReporter()
        let underlying = NSError(domain: "sync", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let context = ErrorContext(feature: "sync", operation: "pushMetrics", screen: nil, userId: nil)

        reporter.captureNonFatal(underlying, context: context)

        XCTAssertEqual(vendor.capturedErrors.count, 1)
        guard case .unexpected(let wrappedContext, let wrappedUnderlying)? = vendor.capturedErrors.first as? AppError else {
            return XCTFail("Expected non-fatal error to be wrapped as AppError.unexpected")
        }
        XCTAssertEqual(wrappedContext, "pushMetrics")
        XCTAssertEqual((wrappedUnderlying as NSError).domain, "sync")
        XCTAssertEqual((wrappedUnderlying as NSError).code, 7)
    }

    func testCaptureNonFatalFallsBackToFeatureWhenOperationIsNil() {
        let (reporter, vendor) = makeReporter()
        let context = ErrorContext(feature: "coreData", operation: nil, screen: nil, userId: nil)

        reporter.captureNonFatal(NSError(domain: "cd", code: 2), context: context)

        guard case .unexpected(let wrappedContext, _)? = vendor.capturedErrors.first as? AppError else {
            return XCTFail("Expected non-fatal error to be wrapped as AppError.unexpected")
        }
        XCTAssertEqual(wrappedContext, "coreData")
    }
}
