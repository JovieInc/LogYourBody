//
// AnalyticsServiceTests.swift
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


final class AnalyticsServiceTests: XCTestCase {
    private final class FakeAnalyticsClient: AnalyticsClient {
        private(set) var startCallCount = 0
        private(set) var resetCallCount = 0
        private(set) var identifiedUserIds: [String?] = []
        private(set) var identifiedProperties: [[String: String]?] = []
        private(set) var trackedEvents: [String] = []
        private(set) var trackedProperties: [[String: String]?] = []
        private(set) var queriedFlags: [String] = []
        var gateResult = true

        func start() {
            startCallCount += 1
        }

        func identify(userId: String?, properties: [String: String]?) {
            identifiedUserIds.append(userId)
            identifiedProperties.append(properties)
        }

        func track(event: String, properties: [String: String]?) {
            trackedEvents.append(event)
            trackedProperties.append(properties)
        }

        func reset() {
            resetCallCount += 1
        }

        func isFeatureEnabled(flagKey: String) -> Bool {
            queriedFlags.append(flagKey)
            return gateResult
        }
    }

    private func makeService() -> (AnalyticsService, FakeAnalyticsClient) {
        let client = FakeAnalyticsClient()
        return (AnalyticsService(client: client), client)
    }

    func testStartDelegatesToClientAndPostsGateChangeNotification() async {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)

        service.start()

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.startCallCount, 1)
    }

    func testIdentifyForwardsUserIdAndPropertiesAndPostsNotification() async throws {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)
        let properties = ["email": "user@example.com", "country": "US"]

        service.identify(userId: "user-123", properties: properties)

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.identifiedUserIds, ["user-123"])
        XCTAssertEqual(try XCTUnwrap(client.identifiedProperties.first), properties)
    }

    func testIdentifyWithoutPropertiesForwardsNil() throws {
        let (service, client) = makeService()

        service.identify(userId: nil)

        XCTAssertEqual(client.identifiedUserIds.count, 1)
        XCTAssertNil(client.identifiedUserIds.first ?? "sentinel")
        XCTAssertNil(try XCTUnwrap(client.identifiedProperties.first))
    }

    func testTrackForwardsEventNameAndProperties() throws {
        let (service, client) = makeService()

        service.track(event: "weight_logged", properties: ["source": "manual"])

        XCTAssertEqual(client.trackedEvents, ["weight_logged"])
        XCTAssertEqual(try XCTUnwrap(client.trackedProperties.first), ["source": "manual"])
    }

    func testTrackWithoutPropertiesForwardsNilProperties() throws {
        let (service, client) = makeService()

        service.track(event: "app_opened")

        XCTAssertEqual(client.trackedEvents, ["app_opened"])
        XCTAssertNil(try XCTUnwrap(client.trackedProperties.first))
    }

    func testResetDelegatesToClientAndPostsNotification() async {
        let (service, client) = makeService()
        let notification = expectation(forNotification: .featureGatesDidChange, object: nil)

        service.reset()

        await fulfillment(of: [notification], timeout: 5)
        XCTAssertEqual(client.resetCallCount, 1)
    }

    func testFeatureGateReturnsFalseBeforeStart() {
        let (service, client) = makeService()
        client.gateResult = true

        XCTAssertFalse(service.isFeatureEnabled(flagKey: "new_onboarding_v2"))
        XCTAssertTrue(client.queriedFlags.isEmpty)
    }

    func testFeatureGateForwardsToClientAfterStart() async {
        let (service, client) = makeService()
        client.gateResult = true

        service.start()
        XCTAssertTrue(service.isFeatureEnabled(flagKey: "strict_reminders"))
        XCTAssertEqual(client.queriedFlags, ["strict_reminders"])

        client.gateResult = false
        XCTAssertFalse(service.isFeatureEnabled(flagKey: "strict_reminders"))
    }
}
