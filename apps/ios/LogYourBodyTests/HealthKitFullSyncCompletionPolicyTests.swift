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


final class HealthKitFullSyncCompletionPolicyTests: XCTestCase {
    func testFullSyncCompletionIsOnlyMarkedAfterSuccessfulImport() {
        XCTAssertTrue(
            HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: true)
        )
        XCTAssertFalse(
            HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: false)
        )
    }
}
