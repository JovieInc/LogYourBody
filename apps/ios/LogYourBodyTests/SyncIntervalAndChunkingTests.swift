//
// SyncIntervalAndChunkingTests.swift
// LogYourBodyTests
//
// Coverage for the pure sync helpers in RealtimeSyncManager's subsystem:
// the battery -> sync-interval policy and the Array.chunked batching primitive
// that all five sync-batch upload paths rely on.
//
import XCTest
import UIKit
@testable import LogYourBody

final class SyncIntervalAndChunkingTests: XCTestCase {
    // MARK: - BatterySyncIntervalPolicy

    func testChargingOrFullSyncsAggressivelyRegardlessOfLevel() {
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .charging, level: 0.1), 60)
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .full, level: 0.95), 60)
        // Charging overrides an unknown (-1) level.
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .charging, level: -1), 60)
    }

    func testAboveFiftyPercentUsesNormalInterval() {
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.6), 300)
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.51), 300)
    }

    func testBoundaryAtFiftyPercentIsConservative() {
        // Exactly 0.5 is not > 0.5, so it falls into the 20-50% band.
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.5), 900)
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.3), 900)
    }

    func testBoundaryAtTwentyPercentIsMinimal() {
        // Exactly 0.2 is not > 0.2, so it falls into the < 20% band.
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.2), 1_800)
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unplugged, level: 0.1), 1_800)
    }

    func testUnknownLevelFallsBackToMinimal() {
        // Battery monitoring unavailable reports level -1; default to the safest interval.
        XCTAssertEqual(BatterySyncIntervalPolicy.interval(state: .unknown, level: -1), 1_800)
    }

    // MARK: - Array.chunked(into:)

    func testChunkExactMultiple() {
        let chunks = Array(1...10).chunked(into: 5)
        XCTAssertEqual(chunks, [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]])
    }

    func testChunkWithRemainder() {
        let chunks = Array(1...12).chunked(into: 5)
        XCTAssertEqual(chunks.map(\.count), [5, 5, 2])
        XCTAssertEqual(chunks.last, [11, 12])
    }

    func testChunkEmptyIsEmpty() {
        XCTAssertTrue([Int]().chunked(into: 50).isEmpty)
    }

    func testChunkLargerThanCountIsSingleChunk() {
        XCTAssertEqual([1, 2, 3].chunked(into: 10), [[1, 2, 3]])
    }

    func testChunkNonPositiveSizePreservesElementsWithoutTrapping() {
        XCTAssertEqual([1, 2, 3].chunked(into: 0), [[1, 2, 3]])
        XCTAssertEqual([1, 2, 3].chunked(into: -5), [[1, 2, 3]])
        XCTAssertEqual([Int]().chunked(into: 0), [])
    }

    func testChunkSizeOneSplitsEveryElement() {
        XCTAssertEqual([1, 2, 3].chunked(into: 1), [[1], [2], [3]])
    }

    func testChunkPreservesAllElementsInOrder() {
        let source = Array(0..<137)
        let chunks = source.chunked(into: 50)
        XCTAssertEqual(chunks.count, 3) // 50 + 50 + 37
        XCTAssertEqual(chunks.flatMap { $0 }, source)
    }
}
