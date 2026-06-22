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


final class DailyReminderPolicyTests: XCTestCase {
    func testPromptRequiresSubscriptionAndIncompletePrompt() {
        XCTAssertTrue(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: false
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: false,
                hasCompletedPrompt: false
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: true
            )
        )
    }

    func testDailyWeighInReminderDefaultsToSevenAM() {
        XCTAssertEqual(DailyReminderPolicy.defaultHour, 7)
        XCTAssertEqual(DailyReminderPolicy.defaultMinute, 0)
        XCTAssertEqual(
            NotificationReminderKind.dailyWeighIn.requestIdentifier,
            "lyb.notification.daily_weigh_in"
        )
    }

    func testReminderTimeNormalizationClampsInvalidValues() {
        let low = DailyReminderPolicy.normalizedTime(hour: -2, minute: -10)
        XCTAssertEqual(low.hour, 0)
        XCTAssertEqual(low.minute, 0)

        let high = DailyReminderPolicy.normalizedTime(hour: 30, minute: 91)
        XCTAssertEqual(high.hour, 23)
        XCTAssertEqual(high.minute, 59)
    }

    func testTriggerComponentsUseNormalizedHourAndMinuteOnly() {
        let components = DailyReminderPolicy.triggerDateComponents(hour: 26, minute: 75)

        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertNil(components.day)
        XCTAssertNil(components.month)
    }
}
