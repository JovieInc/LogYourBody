//
// RevenueCatFlowTests.swift
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


final class RevenueCatSubscriptionAnalyticsTransitionTests: XCTestCase {
    func testTrialStartTracksWhenEnteringTrial() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .none, to: .trial),
            .trialStart
        )
    }

    func testTrialStartDoesNotDuplicateForRepeatedTrialRefresh() {
        XCTAssertNil(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .trial)
        )
    }

    func testTrialConversionTracksWhenTrialBecomesPaid() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .paid),
            .trialConvertedToPaid
        )
    }

    func testTrialExpirationTracksWhenTrialExpiresUnpaid() {
        XCTAssertEqual(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .trial, to: .expiredUnpaid),
            .trialExpiredUnpaid
        )
    }

    func testExistingPaidSubscriberDoesNotBackfillTrialConversion() {
        XCTAssertNil(
            RevenueCatSubscriptionAnalyticsTransition.event(from: .none, to: .paid)
        )
    }
}
