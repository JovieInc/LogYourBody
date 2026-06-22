//
// CoreDataAndPhotoPolicyTests.swift
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


final class AuthSurfacePolicyTests: XCTestCase {
    func testAppleSignInShowsByDefaultForV1Launch() {
        XCTAssertTrue(AuthSurfacePolicy.defaultShowsAppleSignIn)
        XCTAssertTrue(AuthSurfacePolicy.shouldShowAppleSignIn())
    }

    func testEmailOTPRemainsPrimaryLaunchMethod() {
        XCTAssertEqual(AuthSurfacePolicy.primarySignInMethod, "email_otp")
    }
}
