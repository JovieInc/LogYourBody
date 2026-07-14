//
// ProgressPhotoCarouselPreloadRangeTests.swift
// LogYourBodyTests
//
// Regression coverage for a confirmed crash: the photo carousel built its
// preload window as `max(0, i-2)...min(count-1, i+2)`, which trapped with
// "Range requires lowerBound <= upperBound" whenever the shared selection index
// exceeded the metric count (processing-placeholder tags `count + i`, or a stale
// index after the metrics array shrank). `preloadIndexRange` clamps and guards.
//
import XCTest
@testable import LogYourBody

final class ProgressPhotoCarouselPreloadRangeTests: XCTestCase {
    func test_emptyCollection_returnsNil() {
        XCTAssertNil(ProgressPhotoCarouselView.preloadIndexRange(around: 0, count: 0))
        XCTAssertNil(ProgressPhotoCarouselView.preloadIndexRange(around: 5, count: 0))
    }

    func test_midIndex_returnsClampedWindow() {
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 5, count: 10), 3...7)
    }

    func test_startIndex_clampsLowerBoundToZero() {
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 0, count: 10), 0...2)
    }

    func test_endIndex_clampsUpperBoundToLastIndex() {
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 9, count: 10), 7...9)
    }

    func test_negativeIndex_clampsToStart() {
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: -4, count: 10), 0...2)
    }

    /// The crash case: an index beyond `count` must not form an inverted range.
    func test_indexBeyondCount_doesNotTrap_andClampsToTail() {
        // count = 5, index = 7 (== count + 2) → clamp to last index 4 → 2...4
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 7, count: 5), 2...4)
    }

    func test_singleItem_isAlwaysSafe() {
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 0, count: 1), 0...0)
        XCTAssertEqual(ProgressPhotoCarouselView.preloadIndexRange(around: 3, count: 1), 0...0)
    }
}
