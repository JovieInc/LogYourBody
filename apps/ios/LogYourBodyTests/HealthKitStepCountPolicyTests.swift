//
// HealthKitStepCountPolicyTests.swift
// LogYourBodyTests
//
import HealthKit
import XCTest
@testable import LogYourBody

final class HealthKitStepCountPolicyTests: XCTestCase {
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
