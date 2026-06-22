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


final class RevenueCatProductConfigurationTests: XCTestCase {
    private let annualProductID = "com.logyourbody.app.pro1.annual.3daytrial"
    private let monthlyProductID = "com.logyourbody.app.pro1.monthly.3daytrial"

    func testStoreKitProductIdentifiersMatchReleasePreflight() throws {
        let storeKitURL = iOSDirectory.appendingPathComponent("LogYourBody.storekit")
        let storeKitData = try Data(contentsOf: storeKitURL)
        let storeKitObject = try JSONSerialization.jsonObject(with: storeKitData)
        let productIDs = try storeKitProductIDs(from: storeKitObject)

        XCTAssertEqual(Set(productIDs), [annualProductID, monthlyProductID])
        XCTAssertFalse(productIDs.contains { $0.contains(".pro.") })

        let preflightScriptURL = iOSDirectory
            .appendingPathComponent("Scripts")
            .appendingPathComponent("verify_revenuecat_offerings.sh")
        let preflightScript = try String(contentsOf: preflightScriptURL, encoding: .utf8)

        XCTAssertTrue(preflightScript.contains("$rc_annual:\(annualProductID)"))
        XCTAssertTrue(preflightScript.contains("$rc_monthly:\(monthlyProductID)"))
    }

    private var iOSDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func storeKitProductIDs(from object: Any) throws -> [String] {
        let dictionary = try XCTUnwrap(object as? [String: Any])
        let subscriptionGroups = try XCTUnwrap(dictionary["subscriptionGroups"] as? [[String: Any]])

        return try subscriptionGroups.flatMap { group in
            let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])
            return try subscriptions.map { subscription in
                try XCTUnwrap(subscription["productID"] as? String)
            }
        }
    }
}
