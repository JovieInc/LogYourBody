//
// BugReportManagerTests.swift
// LogYourBodyTests
//
import Combine
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


@MainActor
final class BugReportManagerTests: XCTestCase {
    private static let shakeKey = "shakeToReportBugEnabled"

    private final class FakeAnalyticsClient: AnalyticsClient {
        private(set) var trackedEvents: [String] = []
        private(set) var trackedProperties: [[String: String]?] = []

        func start() {}

        func identify(userId: String?, properties: [String: String]?) {}

        func track(event: String, properties: [String: String]?) {
            trackedEvents.append(event)
            trackedProperties.append(properties)
        }

        func reset() {}

        func isFeatureEnabled(flagKey: String) -> Bool {
            false
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var analytics: FakeAnalyticsClient!
    private var manager: BugReportManager!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        suiteName = "BugReportManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        analytics = FakeAnalyticsClient()
        manager = BugReportManager(
            userDefaults: defaults,
            analyticsService: AnalyticsService(client: analytics)
        )
    }

    override func tearDown() {
        cancellables.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        analytics = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testShakeToReportDefaultsToEnabledWhenUnset() {
        XCTAssertTrue(manager.isShakeToReportEnabled)
    }

    func testShakeToReportReadsStoredPreference() {
        defaults.set(false, forKey: Self.shakeKey)
        let reloaded = BugReportManager(userDefaults: defaults, analyticsService: AnalyticsService(client: analytics))

        XCTAssertFalse(reloaded.isShakeToReportEnabled)
    }

    func testShakeToReportTogglePersistsAcrossInstances() {
        manager.isShakeToReportEnabled = false

        XCTAssertFalse(defaults.bool(forKey: Self.shakeKey))
        let reloaded = BugReportManager(userDefaults: defaults, analyticsService: AnalyticsService(client: analytics))
        XCTAssertFalse(reloaded.isShakeToReportEnabled)
    }

    func testCanSubmitRequiresNonBlankMessage() {
        manager.message = ""
        XCTAssertFalse(manager.canSubmit)

        manager.message = "   \n\t  "
        XCTAssertFalse(manager.canSubmit)

        manager.message = "weight chart looks wrong"
        XCTAssertTrue(manager.canSubmit)
    }

    func testShakeGestureDoesNothingWhenDisabled() {
        manager.isShakeToReportEnabled = false

        manager.handleShakeGesture()

        XCTAssertFalse(manager.isPromptPresented)
        XCTAssertFalse(manager.isFormPresented)
        XCTAssertNil(manager.screenshotData)
    }

    func testShakeGestureDoesNothingWhilePromptAlreadyShown() {
        manager.isPromptPresented = true
        manager.message = "existing draft"

        manager.handleShakeGesture()

        XCTAssertTrue(manager.isPromptPresented)
        XCTAssertFalse(manager.isFormPresented)
        XCTAssertEqual(manager.message, "existing draft")
    }

    func testShakeGesturePresentsPromptAndResetsDraft() async {
        manager.message = "stale draft"
        let presented = expectation(description: "Bug report prompt presented")
        manager.$isPromptPresented
            .dropFirst()
            .sink { isPresented in
                if isPresented {
                    presented.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.handleShakeGesture()

        await fulfillment(of: [presented], timeout: 10)
        XCTAssertTrue(manager.isPromptPresented)
        XCTAssertFalse(manager.isFormPresented)
        XCTAssertEqual(manager.message, "")
        XCTAssertEqual(manager.includeScreenshot, manager.screenshotData != nil)
    }

    func testPromptTransitionsToFormAndCancelDismissesBoth() {
        manager.isPromptPresented = true

        manager.presentFormFromPrompt()

        XCTAssertFalse(manager.isPromptPresented)
        XCTAssertTrue(manager.isFormPresented)

        manager.cancel()

        XCTAssertFalse(manager.isPromptPresented)
        XCTAssertFalse(manager.isFormPresented)
    }

    func testSubmitIgnoresBlankMessage() {
        manager.isFormPresented = true
        manager.message = "   "

        manager.submit()

        XCTAssertTrue(analytics.trackedEvents.isEmpty)
        XCTAssertTrue(manager.isFormPresented)
        XCTAssertEqual(manager.message, "   ")
    }

    func testSubmitTracksEventAndDismissesForm() {
        manager.isFormPresented = true
        manager.message = "  chart is blank after sync  "

        manager.submit()

        XCTAssertEqual(analytics.trackedEvents, ["bug_report_submitted"])
        let properties = analytics.trackedProperties.first.flatMap { $0 }
        XCTAssertEqual(properties?["has_screenshot"], "false")
        XCTAssertEqual(properties?["user_id"], AuthManager.shared.currentUser?.id)
        XCTAssertFalse(manager.isFormPresented)
        XCTAssertFalse(manager.isPromptPresented)
        XCTAssertEqual(manager.message, "")
    }
}
