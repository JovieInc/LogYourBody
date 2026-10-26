import XCTest
@testable import LogYourBody

final class MeasurementValueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_929_600)

    func testCurrentDailyWeightNeverAsksRegardlessOfQualityOrImpact() {
        for age in [0.0, 86_399, 86_400] {
            for reliability in [0.0, 0.5, 1] {
                for noise in [0.0, 0.5, 1] {
                    for impact in [0.0, 0.5, 1] {
                        let result = evaluate(age: age, reliability: reliability, noise: noise, impact: impact)
                        XCTAssertEqual(result.status, .current)
                        XCTAssertEqual(result.decisionValue, 0)
                    }
                }
            }
        }
    }

    func testWeightFreshnessBoundary() {
        let threshold = MeasurementValueConstants.weightFreshness
        XCTAssertEqual(evaluate(age: threshold - 1).status, .current)
        XCTAssertEqual(evaluate(age: threshold).status, .current)
        XCTAssertEqual(evaluate(age: threshold + 1).status, .usefulToAsk)
    }

    func testPhotoIsNotMissingUntilMoreThanSevenDaysHaveElapsed() {
        for age in [0.0, 604_799, 604_800] {
            XCTAssertEqual(evaluate(.photo, age: age).status, .current)
            XCTAssertEqual(evaluate(.photo, age: age, reliability: 0, noise: 1).status, .current)
        }
        XCTAssertEqual(evaluate(.photo, age: 604_801).status, .usefulToAsk)
        XCTAssertEqual(evaluate(.photo, age: nil).status, .usefulToAsk)
    }

    func testPhotoFreshnessBoundary() {
        let threshold = MeasurementValueConstants.photoFreshness
        XCTAssertEqual(evaluate(.photo, age: threshold - 1).status, .current)
        XCTAssertEqual(evaluate(.photo, age: threshold).status, .current)
        XCTAssertEqual(evaluate(.photo, age: threshold + 1).status, .usefulToAsk)
    }

    func testMissingReadingHasNoConfidenceEvenWhenAskingIsUseful() {
        for metric in MeasurementValue.MetricKind.allCases {
            let result = evaluate(metric, age: nil)
            XCTAssertEqual(result.status, .usefulToAsk)
            XCTAssertEqual(result.confidence, 0)
            XCTAssertEqual(result.confidenceReasons, [.missingMeasurement])
            XCTAssertEqual(result.decisionValue, 1)
        }
    }

    func testMissingOrStaleReadingDoesNotJustifyAskingWithoutDecisionImpact() {
        for metric in MeasurementValue.MetricKind.allCases {
            for age: Double? in [nil, metric.freshnessInterval + 1] {
                let result = evaluate(metric, age: age, impact: 0)
                XCTAssertEqual(result.status, .notWorthAsking)
                XCTAssertEqual(result.decisionValue, 0)
                XCTAssertFalse(result.confidenceReasons.isEmpty)
            }
        }
    }

    func testDecisionValueBoundaryForMissingAndStaleReadings() {
        let threshold = MeasurementValueConstants.minimumDecisionValueToAsk
        for metric in MeasurementValue.MetricKind.allCases {
            for age: Double? in [nil, metric.freshnessInterval + 1] {
                XCTAssertEqual(evaluate(metric, age: age, impact: threshold.nextDown).status, .notWorthAsking)
                XCTAssertEqual(evaluate(metric, age: age, impact: threshold).status, .usefulToAsk)
                XCTAssertEqual(evaluate(metric, age: age, impact: threshold.nextUp).status, .usefulToAsk)
            }
        }
    }

    func testUnreliableSourceLowersConfidenceAndIsReportedEvenWhenCurrent() {
        let reliable = evaluate(age: 0)
        let unreliable = evaluate(age: 0, reliability: 0.5)
        XCTAssertEqual(unreliable.status, .current)
        XCTAssertLessThan(unreliable.confidence, reliable.confidence)
        XCTAssertEqual(unreliable.confidence, 0.5)
        XCTAssertEqual(unreliable.confidenceReasons, [.unreliableSource])
    }

    func testNoiseLowersConfidenceAndIsReportedEvenWhenCurrent() {
        let quiet = evaluate(age: 0)
        let noisy = evaluate(age: 0, noise: 0.5)
        XCTAssertEqual(noisy.status, .current)
        XCTAssertLessThan(noisy.confidence, quiet.confidence)
        XCTAssertEqual(noisy.confidence, 0.5)
        XCTAssertEqual(noisy.confidenceReasons, [.measurementNoise])
    }

    func testSourceReliabilityEndpointsAndReportingBoundary() {
        XCTAssertEqual(evaluate(age: 0, reliability: 0).confidence, 0)
        XCTAssertTrue(evaluate(age: 0, reliability: 0).confidenceReasons.contains(.unreliableSource))
        XCTAssertTrue(evaluate(age: 0, reliability: Double(1).nextDown).confidenceReasons.contains(.unreliableSource))
        XCTAssertEqual(evaluate(age: 0, reliability: 1).confidence, 1)
        XCTAssertTrue(evaluate(age: 0, reliability: 1).confidenceReasons.isEmpty)
    }

    func testNoiseEndpointsAndReportingBoundary() {
        XCTAssertEqual(evaluate(age: 0, noise: 0).confidence, 1)
        XCTAssertTrue(evaluate(age: 0, noise: 0).confidenceReasons.isEmpty)
        XCTAssertTrue(evaluate(age: 0, noise: Double(0).nextUp).confidenceReasons.contains(.measurementNoise))
        XCTAssertEqual(evaluate(age: 0, noise: 1).confidence, 0)
        XCTAssertTrue(evaluate(age: 0, noise: 1).confidenceReasons.contains(.measurementNoise))
    }

    func testStalenessLowersConfidenceAtEachMetricBoundary() {
        for metric in MeasurementValue.MetricKind.allCases {
            let current = evaluate(metric, age: metric.freshnessInterval)
            let stale = evaluate(metric, age: metric.freshnessInterval + 1)
            XCTAssertEqual(current.confidence, 1)
            XCTAssertTrue(current.confidenceReasons.isEmpty)
            XCTAssertLessThan(stale.confidence, current.confidence)
            XCTAssertEqual(stale.confidence, MeasurementValueConstants.staleConfidenceMultiplier)
            XCTAssertEqual(stale.confidenceReasons, [.staleMeasurement])
        }
    }

    func testAllConfidenceReductionsAreRetainedTogether() {
        let result = evaluate(age: 86_401, reliability: 0.5, noise: 0.5, impact: 0.8)
        XCTAssertEqual(result.status, .usefulToAsk)
        XCTAssertEqual(result.confidence, 0.25 * MeasurementValueConstants.staleConfidenceMultiplier)
        XCTAssertEqual(result.decisionValue, 0.2, accuracy: 0.000001)
        XCTAssertEqual(result.confidenceReasons, [.staleMeasurement, .unreliableSource, .measurementNoise])
    }

    func testLowQualityCanMakeAnotherHighImpactReadingNotWorthAskingFor() {
        for age: Double? in [nil, 86_401] {
            XCTAssertEqual(evaluate(age: age, reliability: 0).status, .notWorthAsking)
            XCTAssertEqual(evaluate(age: age, noise: 1).status, .notWorthAsking)
            XCTAssertEqual(evaluate(age: age, reliability: 0.1).status, .notWorthAsking)
            XCTAssertEqual(evaluate(age: age, noise: 0.9).status, .notWorthAsking)
        }
    }

    func testInvalidScoresNeverGenerateAnAskOrHideUncertainty() {
        let invalidScores: [Double] = [-0.01, 1.01, .nan, .infinity, -.infinity]
        for metric in MeasurementValue.MetricKind.allCases {
            for age: Double? in [nil, 0, metric.freshnessInterval + 1] {
                for invalid in invalidScores {
                    let results = [
                        evaluate(metric, age: age, reliability: invalid),
                        evaluate(metric, age: age, noise: invalid),
                        evaluate(metric, age: age, impact: invalid)
                    ]
                    for result in results {
                        XCTAssertEqual(result.status, age == 0 ? .current : .notWorthAsking)
                        XCTAssertEqual(result.confidence, 0)
                        XCTAssertEqual(result.decisionValue, 0)
                        XCTAssertTrue(result.confidenceReasons.contains(.invalidInput))
                    }
                }
            }
        }
    }

    func testFutureEffectiveDateIsReportedWithoutTriggeringARepeatAsk() {
        for metric in MeasurementValue.MetricKind.allCases {
            let future = evaluate(metric, age: -1)
            XCTAssertEqual(future.status, .notWorthAsking)
            XCTAssertEqual(future.confidence, 0)
            XCTAssertEqual(future.confidenceReasons, [.futureEffectiveDate])
            XCTAssertEqual(evaluate(metric, age: 0).status, .current)
        }
    }

    func testInvalidDatesAreReportedWithNoConfidenceOrAsk() {
        for interval: Double in [.nan, .infinity, -.infinity] {
            let invalidDate = Date(timeIntervalSince1970: interval)
            let results = [
                MeasurementValue.evaluate(
                    metric: .weight, lastEffectiveDate: invalidDate,
                    sourceReliability: 1, noise: 0, decisionImpact: 1, now: now
                ),
                MeasurementValue.evaluate(
                    metric: .photo, lastEffectiveDate: nil,
                    sourceReliability: 1, noise: 0, decisionImpact: 1, now: invalidDate
                )
            ]
            for result in results {
                XCTAssertEqual(result.status, .notWorthAsking)
                XCTAssertEqual(result.confidence, 0)
                XCTAssertTrue(result.confidenceReasons.contains(.invalidInput))
            }
        }
    }

    private func evaluate(
        _ metric: MeasurementValue.MetricKind = .weight,
        age: TimeInterval?,
        reliability: Double = 1,
        noise: Double = 0,
        impact: Double = 1
    ) -> MeasurementValue.Assessment {
        MeasurementValue.evaluate(
            metric: metric, lastEffectiveDate: age.map { now.addingTimeInterval(-$0) },
            sourceReliability: reliability, noise: noise, decisionImpact: impact, now: now
        )
    }
}
