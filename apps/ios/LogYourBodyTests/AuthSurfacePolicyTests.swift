import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

final class AuthSurfacePolicyTests: XCTestCase {
    func testAppleIsTheOnlyPrimarySignInMethod() {
        XCTAssertEqual(AuthSurfacePolicy.primarySignInMethod, "apple")
    }
}
