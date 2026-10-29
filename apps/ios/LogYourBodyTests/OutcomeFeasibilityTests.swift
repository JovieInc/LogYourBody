import XCTest
@testable import LogYourBody

final class OutcomeFeasibilityTests: XCTestCase {
    private typealias Classification = OutcomeFeasibility.Classification
    private typealias Measurement = OutcomeFeasibility.Measurement
    private typealias Thresholds = OutcomeFeasibility.Thresholds

    private let now = Date(timeIntervalSince1970: 1_798_761_600) // 2027-01-01 UTC
    // Arithmetic examples only, not approved physiological policy.
    private let bounds = Thresholds(minimumTarget: 1, maximumTarget: 200,
                                    minimumWeeklyChange: -1, maximumWeeklyChange: 1)

    func testPinnedContractHasNoThresholdsAndThereforeFailsClosedForEveryMetric() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "lyb-launch-contract", withExtension: "json"))
        let contract = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(contract["schema"] as? String, "lyb-launch-contract/v1")
        // Reconcile any new policy/case schema explicitly when the decision issue supplies it.
        XCTAssertEqual(Set(contract.keys), Set([
            "schema", "sourceIssue", "product", "repository", "source", "promise",
            "primarySurfaces", "requiredPaths", "surfaces"
        ]))
        let paths = try XCTUnwrap(contract["requiredPaths"] as? [[String: Any]])
        XCTAssertTrue(paths.contains { $0["id"] as? String == "launch.safety" })
        let classifier = OutcomeFeasibility(now: now)
        for metric in DatedOutcome.Metric.allCases {
            for target in [76.0, 80] {
                let outcome = outcome(target: target, metric: metric)
                for history in [[], [measurement(80, metric: metric)]] {
                    XCTAssertEqual(classifier.classify(outcome: outcome, history: history), .unsafe)
                }
            }
        }
    }

    func testArithmeticExamplesCoverEveryClassification() {
        let classifier = classifier()
        let examples: [(DatedOutcome, [Measurement], Classification)] = [
            (outcome(), [measurement(80)], .ok),
            (outcome(target: 201), [measurement(80)], .unsafe),
            (outcome(target: 60), [measurement(80)], .impossible),
            (outcome(date: "2026-12-31"), [], .expired),
            (outcome(), [], .noData)
        ]
        for (outcome, history, expected) in examples {
            XCTAssertEqual(classifier.classify(outcome: outcome, history: history), expected)
        }
    }

    func testEachMissingThresholdIsUnsafeEvenForMaintenanceOrNoData() {
        let fields: [WritableKeyPath<Thresholds, Double?>] = [
            \.minimumTarget, \.maximumTarget, \.minimumWeeklyChange, \.maximumWeeklyChange
        ]
        for field in fields {
            var incomplete = bounds
            incomplete[keyPath: field] = nil
            for history in [[], [measurement(80)]] {
                XCTAssertEqual(classifier(incomplete).classify(outcome: outcome(target: 80), history: history), .unsafe)
            }
        }
    }

    func testMalformedThresholdsFailClosed() {
        let fields: [WritableKeyPath<Thresholds, Double?>] = [
            \.minimumTarget, \.maximumTarget, \.minimumWeeklyChange, \.maximumWeeklyChange
        ]
        for field in fields {
            for value in [Double.nan, .infinity, -.infinity] {
                var invalid = bounds
                invalid[keyPath: field] = value
                XCTAssertEqual(classifier(invalid).classify(outcome: outcome(), history: [measurement(80)]), .unsafe)
            }
        }
        for invalid in [
            Thresholds(minimumTarget: 0, maximumTarget: 200, minimumWeeklyChange: -1, maximumWeeklyChange: 1),
            Thresholds(minimumTarget: 200, maximumTarget: 1, minimumWeeklyChange: -1, maximumWeeklyChange: 1),
            Thresholds(minimumTarget: 1, maximumTarget: 200, minimumWeeklyChange: 1, maximumWeeklyChange: 2),
            Thresholds(minimumTarget: 1, maximumTarget: 200, minimumWeeklyChange: -2, maximumWeeklyChange: -1)
        ] {
            XCTAssertEqual(classifier(invalid).classify(outcome: outcome(), history: [measurement(80)]), .unsafe)
        }
    }

    func testExpiryOverridesMissingPolicyInvalidTargetsAndEveryHistory() {
        let histories: [[Measurement]] = [
            [], [measurement(80)], [measurement(.nan)],
            [measurement(80), measurement(81)], [measurement(80, date: now.addingTimeInterval(1))]
        ]
        for date in ["2026-12-31", "2027-01-01"] {
            for target in [76.0, .nan, .infinity, -1] {
                for history in histories {
                    let expired = outcome(target: target, date: date)
                    XCTAssertEqual(classifier().classify(outcome: expired, history: history), .expired)
                    XCTAssertEqual(OutcomeFeasibility(now: now).classify(outcome: expired, history: history), .expired)
                }
            }
        }
    }

    func testLossGainAndMaintenanceUseSuppliedInclusiveBounds() {
        let classifier = classifier()
        for (target, expected) in [(72.0, Classification.ok), (88, .ok), (80, .ok), (71.999, .impossible),
                                   (88.001, .impossible), (1, .impossible), (200, .impossible), (0.999, .unsafe)] {
            XCTAssertEqual(classifier.classify(outcome: outcome(target: target), history: [measurement(80)]), expected)
        }
        let asymmetric = Thresholds(
            minimumTarget: 1, maximumTarget: 200, minimumWeeklyChange: -0.5, maximumWeeklyChange: 1
        )
        XCTAssertEqual(self.classifier(asymmetric).classify(outcome: outcome(target: 76), history: [measurement(80)]), .ok)
        XCTAssertEqual(self.classifier(asymmetric).classify(outcome: outcome(target: 75), history: [measurement(80)]),
                       .impossible)
    }

    func testChangingDateOrLatestMeasurementReevaluatesRemainingTime() {
        let classifier = classifier()
        XCTAssertEqual(classifier.classify(outcome: outcome(), history: [measurement(80)]), .ok)
        XCTAssertEqual(classifier.classify(outcome: outcome(date: "2027-01-02"), history: [measurement(80)]), .impossible)
        XCTAssertEqual(classifier.classify(outcome: outcome(), history: [measurement(90)]), .impossible)
        let later = OutcomeFeasibility(now: now.addingTimeInterval(7 * 7 * 24 * 60 * 60), thresholds: [.weightKg: bounds])
        XCTAssertEqual(later.classify(outcome: outcome(), history: [measurement(80)]), .impossible)
    }

    func testMissingUnusableOrConflictingMeasurementsAreNoData() {
        let histories: [[Measurement]] = [
            [], [measurement(.nan)], [measurement(.infinity)], [measurement(0)], [measurement(-80)],
            [measurement(80, date: now.addingTimeInterval(1))],
            [measurement(80, date: Date(timeIntervalSince1970: .nan))],
            [measurement(80, metric: .bodyFatPercentage)], [measurement(80), measurement(81)]
        ]
        for history in histories {
            XCTAssertEqual(classifier().classify(outcome: outcome(), history: history), .noData)
        }
    }

    func testHistoryOrderDuplicatesAndFutureValuesDoNotChangeResult() {
        let old = measurement(100, date: now.addingTimeInterval(-86_400))
        let history = [old, measurement(80), measurement(80), measurement(100, date: now.addingTimeInterval(1))]
        let original = history
        let classifier = classifier()
        for _ in 0..<3 {
            XCTAssertEqual(classifier.classify(outcome: outcome(), history: history), .ok)
            XCTAssertEqual(classifier.classify(outcome: outcome(), history: Array(history.reversed())), .ok)
        }
        XCTAssertEqual(history, original)
    }

    func testPolicyAndMeasurementsMustMatchTheOutcomeMetric() {
        for metric in DatedOutcome.Metric.allCases {
            let outcome = outcome(metric: metric)
            let history = [measurement(80, metric: metric)]
            XCTAssertEqual(OutcomeFeasibility(now: now, thresholds: [metric: bounds])
                .classify(outcome: outcome, history: history), .ok)
            if metric != .weightKg {
                XCTAssertEqual(classifier().classify(outcome: outcome, history: history), .unsafe)
            }
        }
    }

    func testInvalidOutcomeOrClockIsUnsafe() {
        for date in ["2027-02-30", "2027-2-26", "not-a-date"] {
            XCTAssertEqual(classifier().classify(outcome: outcome(date: date), history: []), .unsafe)
        }
        for target in [Double.nan, .infinity, 0, -1] {
            XCTAssertEqual(classifier().classify(outcome: outcome(target: target), history: [measurement(80)]), .unsafe)
        }
        for time in [Double.nan, .infinity, -.infinity] {
            let invalid = OutcomeFeasibility(now: Date(timeIntervalSince1970: time), thresholds: [.weightKg: bounds])
            XCTAssertEqual(invalid.classify(outcome: outcome(), history: [measurement(80)]), .unsafe)
        }
    }

    private func classifier(_ thresholds: Thresholds? = nil) -> OutcomeFeasibility {
        OutcomeFeasibility(now: now, thresholds: [.weightKg: thresholds ?? bounds])
    }

    private func outcome(target: Double = 76, date: String = "2027-02-26",
                         metric: DatedOutcome.Metric = .weightKg) -> DatedOutcome {
        DatedOutcome(outcome: .init(metric: metric, targetValue: target), outcomeDate: date)
    }

    private func measurement(_ value: Double, date: Date? = nil,
                             metric: DatedOutcome.Metric = .weightKg) -> Measurement {
        Measurement(date: date ?? now, metric: metric, value: value)
    }
}
