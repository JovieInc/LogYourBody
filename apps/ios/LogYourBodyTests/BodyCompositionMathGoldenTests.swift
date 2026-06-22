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

    private func makeMetric(date: Date, weight: Double) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "body-comp-golden-tests",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
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
