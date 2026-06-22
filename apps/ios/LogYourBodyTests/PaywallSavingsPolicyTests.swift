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


final class PaywallSavingsPolicyTests: XCTestCase {
    func testSavingsPercentUsesLiveMonthlyAndAnnualPrices() throws {
        let monthly = try XCTUnwrap(Decimal(string: "9.99"))
        let annual = try XCTUnwrap(Decimal(string: "69.99"))

        XCTAssertEqual(
            PaywallSavingsPolicy.savingsPercent(monthlyPrice: monthly, annualPrice: annual),
            42
        )
    }

    func testMonthlyEquivalentUsesAnnualPriceDividedByTwelve() throws {
        let annual = try XCTUnwrap(Decimal(string: "69.99"))
        let monthlyEquivalent = try XCTUnwrap(PaywallSavingsPolicy.monthlyEquivalent(annualPrice: annual))
        let rounded = monthlyEquivalent.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )

        XCTAssertEqual(rounded, NSDecimalNumber(string: "5.83"))
    }

    func testSavingsPercentOmitsNonDiscountedAnnualPrice() throws {
        let monthly = try XCTUnwrap(Decimal(string: "9.99"))
        let annual = try XCTUnwrap(Decimal(string: "119.88"))

        XCTAssertNil(PaywallSavingsPolicy.savingsPercent(monthlyPrice: monthly, annualPrice: annual))
    }

    func testSavingsPercentOmitsInvalidPrices() throws {
        let annual = try XCTUnwrap(Decimal(string: "69.99"))

        XCTAssertNil(PaywallSavingsPolicy.savingsPercent(monthlyPrice: 0, annualPrice: annual))
        XCTAssertNil(PaywallSavingsPolicy.monthlyEquivalent(annualPrice: 0))
    }
}
