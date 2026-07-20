//
// LRUCacheTests.swift
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


final class LRUCacheTests: XCTestCase {
    func testValueReturnsNilForMissingKey() {
        let cache = LRUCache<String, Int>(capacity: 2)

        XCTAssertNil(cache.value(for: "missing"))
    }

    func testSetThenReadRoundTripsValue() {
        let cache = LRUCache<String, Int>(capacity: 2)

        cache.setValue(7, for: "a")

        XCTAssertEqual(cache.value(for: "a"), 7)
    }

    func testLeastRecentlyUsedEntryIsEvictedAtCapacity() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")

        cache.setValue(3, for: "c")

        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 2)
        XCTAssertEqual(cache.value(for: "c"), 3)
    }

    func testReadRefreshesRecencySoReadEntrySurvivesEviction() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")

        XCTAssertEqual(cache.value(for: "a"), 1)
        cache.setValue(3, for: "c")

        XCTAssertEqual(cache.value(for: "a"), 1)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "c"), 3)
    }

    func testUpdatingExistingKeyRefreshesValueAndRecency() {
        let cache = LRUCache<String, Int>(capacity: 2)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")

        cache.setValue(9, for: "a")
        cache.setValue(3, for: "c")

        XCTAssertEqual(cache.value(for: "a"), 9)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.value(for: "c"), 3)
    }

    func testCapacityOneKeepsOnlyNewestEntry() {
        let cache = LRUCache<String, Int>(capacity: 1)
        cache.setValue(1, for: "a")

        cache.setValue(2, for: "b")

        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 2)
    }

    func testRemoveValueDeletesOnlyThatKey() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")

        cache.removeValue(for: "a")

        XCTAssertNil(cache.value(for: "a"))
        XCTAssertEqual(cache.value(for: "b"), 2)
    }

    func testRemoveAllClearsEveryEntry() {
        let cache = LRUCache<String, Int>(capacity: 3)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")

        cache.removeAll()

        XCTAssertNil(cache.value(for: "a"))
        XCTAssertNil(cache.value(for: "b"))
    }

    func testRemoveAllMatchingPredicateKeepsNonMatchingEntries() {
        let cache = LRUCache<String, Int>(capacity: 5)
        cache.setValue(1, for: "a")
        cache.setValue(2, for: "b")
        cache.setValue(3, for: "c")

        cache.removeAll { key, value in
            key == "b" || value > 2
        }

        XCTAssertEqual(cache.value(for: "a"), 1)
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertNil(cache.value(for: "c"))
    }
}
