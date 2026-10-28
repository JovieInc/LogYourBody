import XCTest
@testable import LogYourBody

final class QuickPillRankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let weightWindow: TimeInterval = 24 * 60 * 60
    private let photoWindow: TimeInterval = 7 * 24 * 60 * 60

    func testNoDataIncludesEveryPillInDeterministicDefaultOrder() {
        let context = QuickPillRanker.Context()
        let expected: [QuickPill] = [.addPhoto, .weight, .bodyFat, .plainInput]

        XCTAssertEqual(QuickPillRanker.rank(context), expected)
        XCTAssertEqual(QuickPillRanker.rank(context), QuickPillRanker.rank(context))
        XCTAssertEqual(Set(QuickPillRanker.rank(context)), Set(QuickPill.allCases))
    }

    func testFreshSuccessfulHealthKitWeightSuppressesWeightAndElevatesMissingPhoto() {
        // A successful stored HealthKit sample and a typed entry share this context.
        let context = QuickPillRanker.Context(weight: freshness(age: 60, window: weightWindow))

        XCTAssertEqual(QuickPillRanker.rank(context), [.addPhoto, .bodyFat, .plainInput])
    }

    func testFreshManualWeightAlsoSuppressesWeight() {
        let context = QuickPillRanker.Context(weight: freshness(age: 0, window: weightWindow), photo: .fresh)

        XCTAssertEqual(QuickPillRanker.rank(context), [.bodyFat, .plainInput, .addPhoto])
    }

    func testStaleWeightLeadsWhenOtherSignalsAreFresh() {
        let context = QuickPillRanker.Context(
            weight: freshness(age: weightWindow + 1, window: weightWindow),
            bodyFat: .fresh,
            photo: .fresh
        )

        XCTAssertEqual(QuickPillRanker.rank(context), [.weight, .plainInput, .addPhoto, .bodyFat])
    }

    func testNoPhotoThisWeekElevatesPhotoAfterFreshWeightAndBodyFat() {
        let context = QuickPillRanker.Context(
            weight: .fresh,
            bodyFat: .fresh,
            photo: freshness(age: photoWindow + 1, window: photoWindow)
        )

        XCTAssertEqual(QuickPillRanker.rank(context), [.addPhoto, .plainInput, .bodyFat])
    }

    func testBodyFatLeadsWhenItIsTheOnlyUsefulSignal() {
        let context = QuickPillRanker.Context(weight: .fresh, photo: .fresh)

        XCTAssertEqual(QuickPillRanker.rank(context), [.bodyFat, .plainInput, .addPhoto])
    }

    func testNothingUsefulLeadsWithPlainInputAndNeverReturnsEmpty() {
        let context = QuickPillRanker.Context(weight: .fresh, bodyFat: .fresh, photo: .fresh)

        XCTAssertEqual(QuickPillRanker.rank(context), [.plainInput, .addPhoto, .bodyFat])
    }

    func testEveryContextRetainsPlainInputWithoutDuplicatePills() {
        for weight in SignalFreshness.allCases {
            for bodyFat in SignalFreshness.allCases {
                for photo in SignalFreshness.allCases {
                    let context = QuickPillRanker.Context(weight: weight, bodyFat: bodyFat, photo: photo)
                    let pills = QuickPillRanker.rank(context)

                    XCTAssertFalse(pills.isEmpty)
                    XCTAssertTrue(pills.contains(.plainInput), "Keyboard and VoiceOver must retain an entry action")
                    XCTAssertEqual(pills.count, Set(pills).count)
                    XCTAssertEqual(pills.contains(.weight), weight != .fresh)
                }
            }
        }
    }

    func testWeightReturnsAtTheExactFreshnessBoundary() {
        let before = QuickPillRanker.Context(weight: freshness(age: weightWindow - 1, window: weightWindow))
        let expired = QuickPillRanker.Context(weight: freshness(age: weightWindow, window: weightWindow))

        XCTAssertFalse(QuickPillRanker.rank(before).contains(.weight))
        XCTAssertTrue(QuickPillRanker.rank(expired).contains(.weight))
    }

    func testFreshnessUsesTheCallerWindow() {
        XCTAssertEqual(freshness(age: weightWindow, window: weightWindow), .stale)
        XCTAssertEqual(freshness(age: weightWindow, window: photoWindow), .fresh)
    }

    func testRecentImportOfHistoricalWeightDoesNotSuppressWeight() {
        // Import completion is now; the sample's recorded time remains historical.
        let recordedAt = now.addingTimeInterval(-weightWindow * 2)
        let weight = SignalFreshness(measuredAt: recordedAt, now: now, window: weightWindow, isUsable: true)

        XCTAssertTrue(QuickPillRanker.rank(.init(weight: weight)).contains(.weight))
    }

    func testUnusableOrMissingReadingDoesNotSuppressWeight() {
        let unusable = SignalFreshness(measuredAt: now, now: now, window: weightWindow, isUsable: false)
        let missing = SignalFreshness(measuredAt: nil, now: now, window: weightWindow, isUsable: true)

        for weight in [unusable, missing] {
            XCTAssertEqual(weight, .missing)
            XCTAssertTrue(QuickPillRanker.rank(.init(weight: weight)).contains(.weight))
        }
    }

    func testFutureOrInvalidTimestampCannotSuppressWeight() {
        let timestamps = [now.addingTimeInterval(1), Date(timeIntervalSince1970: .nan)]
        for timestamp in timestamps {
            let weight = SignalFreshness(measuredAt: timestamp, now: now, window: weightWindow, isUsable: true)

            XCTAssertEqual(weight, .stale)
            XCTAssertTrue(QuickPillRanker.rank(.init(weight: weight)).contains(.weight))
        }
    }

    func testInvalidWindowCannotSuppressWeight() {
        for window: TimeInterval in [0, -1, .nan, .infinity] {
            let weight = SignalFreshness(measuredAt: now, now: now, window: window, isUsable: true)

            XCTAssertEqual(weight, .stale)
            XCTAssertTrue(QuickPillRanker.rank(.init(weight: weight)).contains(.weight))
        }
    }

    private func freshness(age: TimeInterval, window: TimeInterval) -> SignalFreshness {
        SignalFreshness(measuredAt: now.addingTimeInterval(-age), now: now, window: window, isUsable: true)
    }
}
