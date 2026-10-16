//
// LaunchAndBodyCompositionTests.swift
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


final class BodyCompositionMathGoldenTests: XCTestCase {
    private let calendar = Calendar.current

    func testFFMILeanMassAndFatMassMatchGoldenValues() throws {
        let ffmi = try XCTUnwrap(UnitConversion.calculateFFMI(
            weightKg: 80,
            bodyFatPercentage: 10,
            heightCm: 177.8
        ))
        XCTAssertEqual(ffmi, 22.9, accuracy: 0.05)

        let leanMassKg = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: true
        ))
        XCTAssertEqual(leanMassKg, 72, accuracy: 0.001)

        let leanMassLbs = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: false
        ))
        XCTAssertEqual(leanMassLbs, 158.733, accuracy: 0.001)

        let fatMassKg = try XCTUnwrap(UnitConversion.calculateFatMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: true
        ))
        XCTAssertEqual(fatMassKg, 8, accuracy: 0.001)

        let fatMassLbs = try XCTUnwrap(UnitConversion.calculateFatMass(
            weightKg: 80,
            bodyFatPercentage: 10,
            useMetric: false
        ))
        XCTAssertEqual(fatMassLbs, 17.637, accuracy: 0.001)
    }

    func testBodyCompositionCalculationsRejectInvalidInputsAndKeepExtremeValuesFinite() throws {
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 0, bodyFatPercentage: 10, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 0, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 100, heightCm: 180))
        XCTAssertNil(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 10, heightCm: 0))

        let extremeFFMI = try XCTUnwrap(UnitConversion.calculateFFMI(
            weightKg: 80,
            bodyFatPercentage: 99.9,
            heightCm: 180
        ))
        XCTAssertTrue(extremeFFMI.isFinite)
        XCTAssertGreaterThan(extremeFFMI, 0)

        let extremeLeanMass = try XCTUnwrap(UnitConversion.calculateLeanMass(
            weightKg: 80,
            bodyFatPercentage: 99.9,
            useMetric: true
        ))
        XCTAssertTrue(extremeLeanMass.isFinite)
        XCTAssertEqual(extremeLeanMass, 0.08, accuracy: 0.0001)
    }

    func testWeightConversionsRoundTripWithinHundredth() {
        for weightKg in [20.0, 80.0, 123.45, 300.0] {
            let roundTripped = UnitConversion.lbsToKg(UnitConversion.kgToLbs(weightKg))
            XCTAssertEqual(roundTripped, weightKg, accuracy: 0.01)
        }
    }

    func testMeasurementSystemDefaultsFollowLocaleUntilUserPreferenceExists() {
        XCTAssertEqual(
            MeasurementSystem.measurementSystem(for: Locale(identifier: "en_US")),
            .imperial
        )
        XCTAssertEqual(
            MeasurementSystem.measurementSystem(for: Locale(identifier: "de_DE")),
            .metric
        )
        XCTAssertEqual(MeasurementSystem.fromStored(rawValue: "Metric"), .metric)
        XCTAssertEqual(MeasurementSystem.fromStored(rawValue: "Imperial"), .imperial)
        XCTAssertEqual(WeightUnit.localeDefault.measurementSystem, MeasurementSystem.localeDefault)
        XCTAssertEqual(HeightUnit.localeDefault.measurementSystem, MeasurementSystem.localeDefault)
    }

    func testWeightGoalStoresKilogramsAndPresentsOncePerSelectedUnit() throws {
        let goal = try XCTUnwrap(WeightGoal(displayValue: 180, measurementSystem: .imperial))

        XCTAssertEqual(goal.kilograms, UnitConversion.lbsToKg(180), accuracy: 0.0001)
        XCTAssertEqual(goal.displayValue(in: .imperial), 180, accuracy: 0.0001)
        XCTAssertEqual(goal.displayValue(in: .metric), UnitConversion.lbsToKg(180), accuracy: 0.0001)
        XCTAssertEqual(goal.displayText(in: .imperial), "180.0 lbs")

        let migrated = try XCTUnwrap(WeightGoal.migrateLegacy(180, measurementSystem: .imperial))
        XCTAssertEqual(migrated, goal)
    }

    func testInterpolatedFFMIUsesTheCanonicalNormalizedFormula() throws {
        let date = date(daysAfterStart: 0)
        let metrics = [makeMetric(date: date, weight: 80, bodyFatPercentage: 10)]
        let result = try XCTUnwrap(
            MetricsInterpolationService.shared.estimateFFMI(
                for: date,
                metrics: metrics,
                heightInches: 70
            )
        )
        let expected = try XCTUnwrap(
            UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 10, heightCm: 177.8)
        )

        XCTAssertEqual(result.value, (expected * 10).rounded() / 10, accuracy: 0.001)
    }

    func testWeightSanityRangeMatchesLaunchValidationBounds() {
        XCTAssertFalse(UnitConversion.isValidWeight(31.9))
        XCTAssertTrue(UnitConversion.isValidWeight(32))
        XCTAssertTrue(UnitConversion.isValidWeight(300))
        XCTAssertFalse(UnitConversion.isValidWeight(300.1))
    }

    func testTrendWeightUsesHandComputedEMAReference() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 1, weight: 104),
            (dayOffset: 2, weight: 108)
        ])

        let dayTwoTrend = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 2)))

        XCTAssertEqual(dayTwoTrend.value, 102.8, accuracy: 0.001)
        XCTAssertFalse(dayTwoTrend.isInterpolated)
        XCTAssertFalse(dayTwoTrend.isLastKnown)
        XCTAssertNil(dayTwoTrend.confidenceLevel)
    }

    func testLaterTimestampedWeighInStaysObservedForTrendAndFFMI() throws {
        let first = date(daysAfterStart: 0).addingTimeInterval(12 * 60 * 60)
        let later = date(daysAfterStart: 7).addingTimeInterval(12 * 60 * 60)
        let metrics = [
            makeMetric(date: first, weight: 84.7, bodyFatPercentage: 17.4, bodyFatMethod: "manual"),
            makeMetric(date: later, weight: 82.1, bodyFatPercentage: 15.8, bodyFatMethod: "manual")
        ]
        let context = try XCTUnwrap(
            MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
        )
        let trend = try XCTUnwrap(context.trendWeight(for: later))
        XCTAssertFalse(trend.isInterpolated, "A weigh-in after midnight is still an observation")
        XCTAssertFalse(trend.isLastKnown)

        let ffmi = try XCTUnwrap(
            MetricsInterpolationService.shared.estimateFFMI(
                for: later, metrics: metrics, heightInches: 178 / 2.54
            )
        )
        XCTAssertFalse(ffmi.isInterpolated)
        XCTAssertFalse(ffmi.isLastKnown)
        XCTAssertEqual(
            fullScreenFFMIPresence(
                isLastKnown: ffmi.isLastKnown,
                isInterpolated: ffmi.isInterpolated,
                hasDirectBodyFat: true,
                directBodyFatMethod: "manual"
            ),
            .present
        )
    }

    func testTrendWeightIntradayQueriesMatchColdContextsInBothOrders() throws {
        let metrics = intradayMetrics([(0, 9, 80), (0, 18, 100)])
        let expected = [80.0, 100.0]
        for warmWithFuture in [false, true] {
            for order in [[0, 1, 0, 1], [1, 0, 1, 0]] {
                let context = try XCTUnwrap(
                    MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
                )
                if warmWithFuture {
                    let future = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 365 * 10)))
                    XCTAssertEqual(future.value, 100, accuracy: 0.001)
                    XCTAssertTrue(future.isLastKnown)
                }
                for index in order {
                    let query = metrics[index].date
                    let cold = try XCTUnwrap(
                        MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
                    )
                    let result = try XCTUnwrap(context.trendWeight(for: query))
                    XCTAssertEqual(result.value, expected[index], accuracy: 0.001)
                    XCTAssertEqual(result.value, try XCTUnwrap(cold.trendWeight(for: query)).value, accuracy: 0.001)
                    XCTAssertFalse(result.isInterpolated)
                    XCTAssertFalse(result.isLastKnown)
                }
                let midday = metrics[0].date.addingTimeInterval(3 * 60 * 60)
                XCTAssertEqual(try XCTUnwrap(context.trendWeight(for: midday)).value, 80, accuracy: 0.001)
                XCTAssertNil(context.trendWeight(for: metrics[0].date.addingTimeInterval(-1)))
            }
        }
    }

    func testPartialIntradayQueriesNeverSeedLaterEMACheckpoints() throws {
        let metrics = intradayMetrics([(0, 9, 80), (0, 18, 100), (1, 9, 120), (1, 18, 140), (2, 9, 160)])
        // Completed day0 seeds100; day1 early=0.25*120+0.75*100=105,
        // day1 late=110; day2=0.25*160+0.75*110=122.5.
        let expected = [80.0, 100.0, 105.0, 110.0, 122.5]
        for order in [[0, 2, 4, 3, 1, 2, 4], [4, 3, 2, 1, 0, 4, 2]] {
            let context = try XCTUnwrap(
                MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
            )
            for index in order {
                let cold = try XCTUnwrap(
                    MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
                )
                let result = try XCTUnwrap(context.trendWeight(for: metrics[index].date))
                let coldResult = try XCTUnwrap(cold.trendWeight(for: metrics[index].date))
                XCTAssertEqual(result.value, expected[index], accuracy: 0.001)
                XCTAssertEqual(result.value, coldResult.value, accuracy: 0.001)
                XCTAssertFalse(result.isInterpolated)
                XCTAssertFalse(result.isLastKnown)
            }
        }
    }

    func testFutureCheckpointCannotFillAnUnresolvedEarlierIntradayGap() throws {
        for gapDays in [31, 40] {
            let metrics = intradayMetrics([(0, 9, 80), (gapDays, 18, 100)])
            let context = try XCTUnwrap(
                MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
            )
            let laterDay = date(daysAfterStart: gapDays + 1).addingTimeInterval(9 * 60 * 60)
            // The gap skips missing days. The observed later day is85kg;
            // its next completed-day continuation is0.25*100+0.75*85=88.75.
            XCTAssertEqual(try XCTUnwrap(context.trendWeight(for: laterDay)).value, 88.8, accuracy: 0.001)
            let beforeObservation = date(daysAfterStart: gapDays).addingTimeInterval(9 * 60 * 60)
            let cold = try XCTUnwrap(
                MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics)
            )
            XCTAssertNil(cold.trendWeight(for: beforeObservation))
            XCTAssertNil(context.trendWeight(for: beforeObservation))
            let observed = try XCTUnwrap(context.trendWeight(for: metrics[1].date))
            XCTAssertEqual(observed.value, 85, accuracy: 0.001)
            XCTAssertFalse(observed.isInterpolated)
            XCTAssertFalse(observed.isLastKnown)
            XCTAssertNil(context.trendWeight(for: beforeObservation))
        }
    }

    func testFFMIAndActualHeroCachePreserveIntradayQueryIdentity() throws {
        let metrics = intradayMetrics([(0, 9, 80), (0, 18, 100)])
        // Independently: weight*0.8/1.8², normalized-height adjustment=0.
        let expected = [19.8, 24.7]
        for order in [[0, 1, 0, 1], [1, 0, 1, 0]] {
            let context = try XCTUnwrap(
                MetricsInterpolationService.shared.makeFFMIInterpolationContext(for: metrics, heightInches: 180 / 2.54)
            )
            let hero = HeroMetricInterpolationCache()
            for index in order {
                let result = try XCTUnwrap(context.estimate(for: metrics[index].date))
                let cached = hero.values(for: metrics[index], in: metrics, heightInches: 180 / 2.54)
                XCTAssertEqual(result.value, expected[index], accuracy: 0.001)
                XCTAssertEqual(try XCTUnwrap(cached.ffmi), expected[index], accuracy: 0.001)
                XCTAssertEqual(cached.weight, metrics[index].weight)
                XCTAssertEqual(cached.bodyFat, 20)
                XCTAssertFalse(result.isInterpolated)
                XCTAssertFalse(result.isLastKnown)
            }
        }
    }

    func testCurrentMonthShareFixtureHasObservedFFMIWithIndependentValue() throws {
        for hour in [0, 9, 12, 23] {
            let points: [(day: Int, hour: Int, weight: Double)] = [
                (0, hour, 84.7), (14, hour, 84.0), (21, hour, 83.4), (28, hour, 82.8), (35, hour, 82.1)
            ]
            let bodyFat: [Double?] = [17.4, 16.9, nil, 16.2, 15.8]
            let sources = ["manual", "bodyspec_dexa", "healthkit", "healthkit", "manual"]
            let metrics = intradayMetrics(points).enumerated().map { index, metric in
                makeMetric(
                    date: metric.date, weight: points[index].weight, bodyFatPercentage: bodyFat[index],
                    bodyFatMethod: bodyFat[index] == nil ? nil : sources[index], dataSource: sources[index]
                )
            }
            let context = try XCTUnwrap(
                MetricsInterpolationService.shared.makeFFMIInterpolationContext(for: metrics, heightInches: 178 / 2.54)
            )
            let latest = try XCTUnwrap(metrics.last)
            let result = try XCTUnwrap(context.estimate(for: latest.date))
            // Daily samples round to0.1kg before alpha0.25 EMA. Latest trend
            // is82.4..82.5kg; trend*0.842/1.78²+6.1*0.02 rounds to22.0.
            XCTAssertEqual(result.value, 22.0, accuracy: 0.001)
            XCTAssertFalse(result.isInterpolated)
            XCTAssertFalse(result.isLastKnown)
            XCTAssertEqual(
                fullScreenFFMIPresence(
                    isLastKnown: result.isLastKnown, isInterpolated: result.isInterpolated,
                    hasDirectBodyFat: true, directBodyFatMethod: "manual"
                ),
                .present
            )
        }
    }

    func testTrendWeightConfidenceDegradesWithInterpolationGap() throws {
        let cases: [(gapDays: Int, queryDay: Int, expected: InterpolatedMetric.ConfidenceLevel)] = [
            (7, 3, .high),
            (14, 7, .medium),
            (30, 15, .low)
        ]

        for testCase in cases {
            let context = try makeWeightContext([
                (dayOffset: 0, weight: 100),
                (dayOffset: testCase.gapDays, weight: 130)
            ])

            let trend = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: testCase.queryDay)))
            XCTAssertTrue(trend.isInterpolated)
            XCTAssertEqual(trend.confidenceLevel?.rawValue, testCase.expected.rawValue)
        }
    }

    func testTrendWeightReturnsNilWhenInterpolationGapExceedsThirtyDays() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 31, weight: 131)
        ])

        XCTAssertNil(context.trendWeight(for: date(daysAfterStart: 15)))
    }

    func testTrendWeightUsesFinalKnownTrendForFarFutureDates() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 1, weight: 104)
        ])

        let result = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 365 * 10)))

        // The EMA converges toward the final known weight without scanning
        // every day in the ten-year tail.
        XCTAssertEqual(result.value, 104, accuracy: 0.001)
        XCTAssertTrue(result.isLastKnown)
    }

    func testTrendWeightFarFutureOptimizationPreservesMixedQueryOrder() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 1, weight: 104)
        ])

        XCTAssertEqual(try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 365 * 10))).value, 104, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 1))).value, 101, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 2))).value, 101.8, accuracy: 0.001)
    }

    func testTrendWeightFarFutureTailUsesRoundedFinalKnownWeight() throws {
        let context = try makeWeightContext([
            (dayOffset: 0, weight: 100),
            (dayOffset: 1, weight: 104.04)
        ])

        let result = try XCTUnwrap(context.trendWeight(for: date(daysAfterStart: 4)))

        XCTAssertEqual(result.value, 102.7, accuracy: 0.001)
        XCTAssertTrue(result.isLastKnown)
    }

    // MARK: - DEXA-anchored body fat estimates

    func testBodyFatEstimateBetweenDexaScansFollowsScaleWeight() throws {
        var metrics = [
            makeMetric(
                date: date(daysAfterStart: 0),
                weight: 100,
                bodyFatPercentage: 20,
                bodyFatMethod: "dexa",
                dataSource: "bodyspec_dexa"
            ),
            makeMetric(
                date: date(daysAfterStart: 90),
                weight: 102,
                bodyFatPercentage: 22,
                bodyFatMethod: "dexa",
                dataSource: "bodyspec_dexa"
            )
        ]
        for day in stride(from: 1, to: 90, by: 1) {
            metrics.append(makeMetric(date: date(daysAfterStart: day), weight: 104))
        }

        let context = try XCTUnwrap(
            MetricsInterpolationService.shared.makeBodyFatInterpolationContext(for: metrics)
        )
        let estimate = try XCTUnwrap(context.estimate(for: date(daysAfterStart: 45)))

        // Trend weight converges to 104 kg; lean mass is linearly interpolated
        // between the scans: (100 * 0.8 + 102 * 0.78) / 2 = 79.78 kg.
        // Body fat = (104 - 79.78) / 104 = 23.3%.
        XCTAssertTrue(estimate.isInterpolated)
        XCTAssertFalse(estimate.isLastKnown)
        XCTAssertEqual(estimate.confidenceLevel?.rawValue, "low")
        XCTAssertEqual(estimate.value, 23.3, accuracy: 0.05)
    }

    func testBodyFatEstimateGapOverThirtyDaysWithoutDexaAnchorsReturnsNil() throws {
        var metrics = [
            makeMetric(
                date: date(daysAfterStart: 0),
                weight: 100,
                bodyFatPercentage: 20,
                dataSource: "smart_scale"
            ),
            makeMetric(
                date: date(daysAfterStart: 60),
                weight: 102,
                bodyFatPercentage: 22,
                dataSource: "smart_scale"
            )
        ]
        for day in stride(from: 1, to: 60, by: 1) {
            metrics.append(makeMetric(date: date(daysAfterStart: day), weight: 104))
        }

        let context = try XCTUnwrap(
            MetricsInterpolationService.shared.makeBodyFatInterpolationContext(for: metrics)
        )
        XCTAssertNil(context.estimate(for: date(daysAfterStart: 30)))
    }

    func testBodyFatEstimateBetweenDexaScansBeyondOneYearReturnsNil() throws {
        var metrics = [
            makeMetric(
                date: date(daysAfterStart: 0),
                weight: 100,
                bodyFatPercentage: 20,
                bodyFatMethod: "dexa",
                dataSource: "bodyspec_dexa"
            ),
            makeMetric(
                date: date(daysAfterStart: 400),
                weight: 102,
                bodyFatPercentage: 22,
                bodyFatMethod: "dexa",
                dataSource: "bodyspec_dexa"
            )
        ]
        for day in stride(from: 1, to: 400, by: 10) {
            metrics.append(makeMetric(date: date(daysAfterStart: day), weight: 104))
        }

        let context = try XCTUnwrap(
            MetricsInterpolationService.shared.makeBodyFatInterpolationContext(for: metrics)
        )
        XCTAssertNil(context.estimate(for: date(daysAfterStart: 200)))
    }

    private func intradayMetrics(_ points: [(day: Int, hour: Int, weight: Double)]) -> [BodyMetrics] {
        points.map { point in
            makeMetric(
                date: date(daysAfterStart: point.day).addingTimeInterval(Double(point.hour) * 60 * 60),
                weight: point.weight, bodyFatPercentage: 20, bodyFatMethod: "manual"
            )
        }
    }

    private func makeWeightContext(
        _ points: [(dayOffset: Int, weight: Double)]
    ) throws -> MetricsInterpolationService.WeightInterpolationContext {
        let metrics = points.map { point in
            makeMetric(
                date: date(daysAfterStart: point.dayOffset),
                weight: point.weight
            )
        }
        return try XCTUnwrap(MetricsInterpolationService.shared.makeWeightInterpolationContext(for: metrics))
    }

    private func makeMetric(
        date: Date,
        weight: Double,
        bodyFatPercentage: Double? = nil,
        bodyFatMethod: String? = nil,
        dataSource: String = "manual"
    ) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "body-comp-golden-tests",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: dataSource,
            createdAt: date,
            updatedAt: date
        )
    }

    private func date(daysAfterStart dayOffset: Int) -> Date {
        let start = calendar.date(from: DateComponents(
            year: 2_026,
            month: 1,
            day: 1
        ))!
        return calendar.date(byAdding: .day, value: dayOffset, to: start)!
    }
}
