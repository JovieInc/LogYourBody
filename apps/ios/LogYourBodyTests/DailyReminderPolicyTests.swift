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
    func testPromptRequiresSubscriptionIncompletePromptAndAFirstWeighIn() {
        XCTAssertTrue(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: false,
                hasLoggedFirstWeighIn: true
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: false,
                hasLoggedFirstWeighIn: false
            ),
            "No reminder ask between the paywall and Today"
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: false,
                hasCompletedPrompt: false,
                hasLoggedFirstWeighIn: true
            )
        )
        XCTAssertFalse(
            DailyReminderPolicy.shouldShowPostPaywallPrompt(
                isSubscribed: true,
                hasCompletedPrompt: true,
                hasLoggedFirstWeighIn: true
            )
        )
    }

    @MainActor
    func testRecordingTheFirstWeighInUnlocksTheOfferOnce() throws {
        let suite = "daily-reminder-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = NotificationManager(defaults: defaults)

        XCTAssertFalse(manager.shouldShowPostPaywallPrompt(isSubscribed: true))
        manager.recordWeighInLogged()
        XCTAssertTrue(manager.shouldShowPostPaywallPrompt(isSubscribed: true))
        XCTAssertTrue(defaults.bool(forKey: Constants.hasLoggedFirstWeighInKey))

        manager.skipDailyWeighInPrompt()
        manager.recordWeighInLogged()
        XCTAssertFalse(manager.shouldShowPostPaywallPrompt(isSubscribed: true), "Answered once, never asked again")
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

    func testDailyReminderPromptUsesNativePermissionAlert() {
        XCTAssertTrue(DailyReminderPromptPresentationPolicy.usesNativePermissionAlert)
        XCTAssertFalse(DailyReminderPromptPresentationPolicy.usesCustomGrabber)
        XCTAssertTrue(NativeSheetPresentationPolicy.detents(for: .dailyReminder).isEmpty)
        XCTAssertFalse(NativeSheetPresentationPolicy.usesCustomDimOverlay(.dailyReminder))
    }
}
