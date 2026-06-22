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


final class CachedPaywallOfferingDisplayTests: XCTestCase {
    func testPreferredPackageUsesAnnualBeforeMonthly() {
        let display = CachedPaywallOfferingDisplay(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            packages: [
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_monthly",
                    productIdentifier: "com.logyourbody.app.pro1.monthly.3daytrial",
                    localizedPrice: "$9.99",
                    billingPeriod: "month",
                    trialText: "3 days free"
                ),
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_annual",
                    productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                    localizedPrice: "$79.99",
                    billingPeriod: "year",
                    trialText: "3 days free"
                )
            ]
        )

        XCTAssertEqual(display.preferredPackage?.packageIdentifier, "$rc_annual")
        XCTAssertEqual(display.preferredPackage?.localizedPrice, "$79.99")
    }

    func testCachedPaywallOfferingDisplayPersistsAsDisplayOnlyData() throws {
        let display = CachedPaywallOfferingDisplay(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            packages: [
                CachedPaywallOfferingDisplay.PackageDisplay(
                    packageIdentifier: "$rc_annual",
                    productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                    localizedPrice: "$79.99",
                    billingPeriod: "year",
                    trialText: "3 days free"
                )
            ]
        )

        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(CachedPaywallOfferingDisplay.self, from: data)

        XCTAssertEqual(decoded, display)
        XCTAssertEqual(decoded.preferredPackage?.productIdentifier, "com.logyourbody.app.pro1.annual.3daytrial")
    }
}
