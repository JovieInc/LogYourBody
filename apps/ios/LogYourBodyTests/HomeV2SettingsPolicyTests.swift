//
// HomeV2SettingsPolicyTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

final class HomeV2SettingsPolicyTests: XCTestCase {
    func testPlanTextReadsTheProductIdentifier() {
        XCTAssertEqual(HomeV2SettingsCopy.planText(isSubscribed: false, productIdentifier: "lyb_pro_annual"), "Free")
        XCTAssertEqual(HomeV2SettingsCopy.planText(isSubscribed: true, productIdentifier: "lyb_pro_annual"), "Pro, annual")
        XCTAssertEqual(HomeV2SettingsCopy.planText(isSubscribed: true, productIdentifier: "lyb_pro_monthly"), "Pro, monthly")
        XCTAssertEqual(HomeV2SettingsCopy.planText(isSubscribed: true, productIdentifier: nil), "Pro")
    }

    func testUnitTextsFollowTheMeasurementSystem() {
        XCTAssertEqual(HomeV2SettingsCopy.unitsText(.imperial), "lb, %")
        XCTAssertEqual(HomeV2SettingsCopy.unitsText(.metric), "kg, %")
        XCTAssertEqual(HomeV2SettingsCopy.heightUnitText(.imperial), "ft, in")
        XCTAssertEqual(HomeV2SettingsCopy.heightUnitText(.metric), "cm")
        XCTAssertEqual(HomeV2SettingsCopy.circumferenceUnitText(.imperial), "in")
        XCTAssertEqual(
            HomeV2SettingsCopy.renews(on: "Mar 12, 2027", price: "$69.99 a year"),
            "Renews Mar 12, 2027 for $69.99 a year"
        )
        XCTAssertEqual(HomeV2SettingsCopy.renews(on: "Mar 12, 2027", price: nil), "Renews Mar 12, 2027")
    }

    func testEverySidebarDestinationHasATitleAndGlyph() {
        for destination in HomeV2SidebarDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty)
            XCTAssertFalse(destination.systemImage.isEmpty)
        }
        XCTAssertEqual(HomeV2SidebarDestination.today.title, "Today")
        XCTAssertEqual(HomeV2SettingsRoute.allRoutes.count, 8)
    }

    @MainActor
    func testSidebarDismissSwipePreservesImmediateRowTouches() {
        let coordinator = HomeV2SidebarDismissSwipe.Coordinator()
        let recognizer = HomeV2SidebarDismissSwipe.makeRecognizer(delegate: coordinator)
        XCTAssertEqual(recognizer.direction, .left, "Only a left swipe dismisses the drawer")
        XCTAssertEqual(recognizer.numberOfTouchesRequired, 1)
        XCTAssertFalse(recognizer.cancelsTouchesInView, "Swipe observation must not cancel row buttons")
        XCTAssertFalse(recognizer.delaysTouchesBegan, "A row press must begin immediately")
        XCTAssertFalse(recognizer.delaysTouchesEnded, "A single row tap must not wait for swipe recognition")
        XCTAssertEqual(
            recognizer.delegate?.gestureRecognizer?(recognizer, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()),
            true,
            "Swipe observation must coexist with the row's tap recognizer"
        )
    }
}
