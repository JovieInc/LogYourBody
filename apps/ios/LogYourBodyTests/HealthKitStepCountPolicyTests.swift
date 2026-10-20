//
// HealthKitStepCountPolicyTests.swift
// LogYourBodyTests
//
import HealthKit
import XCTest
@testable import LogYourBody

final class HealthKitStepCountPolicyTests: XCTestCase {
    func testMissingQuantityAndZeroRemainZero() throws {
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: nil), 0)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: 0), 0)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: -0.0), 0)
    }

    func testWholeCountsPreserveTheStorageBoundary() throws {
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: 8_421), 8_421)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: Double(Int32.max)), Int(Int32.max))
    }

    func testFiniteFractionalAggregatesKeepExistingTruncation() throws {
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: 0.5), 0)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: 8_421.75), 8_421)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: Double(Int32.max).nextDown), Int(Int32.max) - 1)
        XCTAssertEqual(try HealthKitStepCountPolicy.stepCount(from: Double(Int32.max) + 0.75), Int(Int32.max))
    }

    func testNegativeCountsAreRejectedInsteadOfPublished() {
        for quantity in [-1.0, -8_421, -Double.leastNonzeroMagnitude] {
            XCTAssertThrowsError(try HealthKitStepCountPolicy.stepCount(from: quantity)) { error in
                XCTAssertEqual(error as? HealthKitStepCountPolicy.QuantityError, .invalidStepCount)
            }
        }
    }

    func testNonfiniteAndOversizedCountsFailWithoutIntegerTraps() {
        for quantity in [Double.nan, .infinity, -.infinity, Double(Int32.max) + 1,
                         Double(Int.max), Double.greatestFiniteMagnitude] {
            XCTAssertThrowsError(try HealthKitStepCountPolicy.stepCount(from: quantity)) { error in
                XCTAssertEqual(error as? HealthKitStepCountPolicy.QuantityError, .invalidStepCount)
            }
        }
    }

    func testNoDataForTodayReadsAsZeroSteps() {
        let noData = NSError(
            domain: HKErrorDomain,
            code: HKError.Code.errorNoData.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No data available for the specified predicate."]
        )

        XCTAssertEqual(HealthKitStepCountPolicy.stepCount(forNoData: noData), 0)
    }

    func testOtherHealthKitErrorsStillPropagate() {
        let denied = NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)

        XCTAssertNil(HealthKitStepCountPolicy.stepCount(forNoData: denied))
    }

    func testNonHealthKitErrorsStillPropagate() {
        let sameCodeDifferentDomain = NSError(domain: "com.logyourbody.test", code: HKError.Code.errorNoData.rawValue)

        XCTAssertNil(HealthKitStepCountPolicy.stepCount(forNoData: sameCodeDifferentDomain))
        XCTAssertNil(HealthKitStepCountPolicy.stepCount(forNoData: HealthKitError.notAuthorized))
    }
}
