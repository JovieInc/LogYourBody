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
