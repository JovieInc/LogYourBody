import XCTest
@testable import LogYourBody

final class BodyScoreEngineTests: XCTestCase {
    func testCalculatorMatchesGoldenValuesAcrossBoundaryBandsAndUnits() throws {
        let calculator = BodyScoreCalculator()

        for testCase in bodyScoreGoldenCases {
            try XCTContext.runActivity(named: testCase.name) { _ in
                let result = try calculator.calculateScore(
                    context: BodyScoreCalculationContext(input: testCase.input)
                )

                assert(result, matches: testCase)
            }
        }
    }

    func testCalculatorRejectsIncompleteInput() {
        XCTAssertThrowsError(
            try BodyScoreCalculator().calculateScore(
                context: BodyScoreCalculationContext(input: BodyScoreInput())
            )
        ) { error in
            XCTAssertEqual(error as? BodyScoreCalculationError, .missingRequiredInputs)
        }
    }

    func testCachePersistsByUserKeyAndInvalidatesOnlyChangedUser() {
        let suiteName = "BodyScoreCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storageKey = "bodyScoreCache.tests.\(UUID().uuidString)"
        let cache = BodyScoreCache(userDefaults: defaults, storageKey: storageKey)
        let first = makeBodyScoreResult(score: 81)
        let second = makeBodyScoreResult(score: 68)

        cache.store(first, for: "user-a")
        cache.store(second, for: "user-b")
        cache.store(makeBodyScoreResult(score: 1), for: nil)

        XCTAssertEqual(cache.latestResult(for: "user-a"), first)
        XCTAssertEqual(cache.latestResult(for: "user-b"), second)
        XCTAssertNil(cache.latestResult(for: nil))

        let reloaded = BodyScoreCache(userDefaults: defaults, storageKey: storageKey)
        XCTAssertEqual(reloaded.latestResult(for: "user-a"), first)
        XCTAssertEqual(reloaded.latestResult(for: "user-b"), second)

        reloaded.invalidate(for: "user-a")

        XCTAssertNil(reloaded.latestResult(for: "user-a"))
        XCTAssertEqual(reloaded.latestResult(for: "user-b"), second)
        XCTAssertNil(
            BodyScoreCache(userDefaults: defaults, storageKey: storageKey)
                .latestResult(for: "user-a")
        )
    }

    func testRecalculationScheduleCoalescesRapidMetricChanges() {
        let service = BodyScoreRecalculationService(debounceInterval: 0.4)
        let firstChange = Date(timeIntervalSince1970: 1_783_100_000)

        XCTAssertTrue(service.scheduleRecalculation(now: firstChange, startTask: false))
        XCTAssertFalse(
            service.scheduleRecalculation(
                now: firstChange.addingTimeInterval(0.1),
                startTask: false
            )
        )
        XCTAssertTrue(
            service.scheduleRecalculation(
                now: firstChange.addingTimeInterval(1),
                startTask: false
            )
        )
        XCTAssertTrue(
            service.scheduleRecalculation(
                now: Date(timeIntervalSince1970: 1_783_100_002),
                startTask: false
            )
        )
    }

    private func assert(
        _ result: BodyScoreResult,
        matches testCase: BodyScoreGoldenCase
    ) {
        XCTAssertEqual(result.score, testCase.expectedScore, testCase.name)
        XCTAssertEqual(result.ffmi, testCase.expectedFFMI, accuracy: 0.05, testCase.name)
        XCTAssertEqual(
            result.leanPercentile,
            testCase.expectedLeanPercentile,
            accuracy: 0.05,
            testCase.name
        )
        XCTAssertEqual(result.ffmiStatus, testCase.expectedFFMIStatus, testCase.name)
        XCTAssertEqual(
            result.statusTagline,
            testCase.expectedStatusTagline,
            testCase.name
        )
        XCTAssertEqual(result.targetBodyFat.label, "Lean", testCase.name)
        XCTAssertEqual(
            result.targetBodyFat.lowerBound,
            testCase.targetBodyFatRange.lowerBound,
            accuracy: 0.001,
            testCase.name
        )
        XCTAssertEqual(
            result.targetBodyFat.upperBound,
            testCase.targetBodyFatRange.upperBound,
            accuracy: 0.001,
            testCase.name
        )
    }

    private func makeBodyScoreResult(score: Int) -> BodyScoreResult {
        BodyScoreResult(
            score: score,
            ffmi: Double(score) / 10,
            leanPercentile: Double(score),
            ffmiStatus: "Athletic",
            targetBodyFat: .init(lowerBound: 8, upperBound: 12, label: "Lean"),
            statusTagline: "Pinned cache fixture"
        )
    }
}

private struct BodyScoreGoldenCase {
    let name: String
    let sex: BiologicalSex
    let age: Int
    let heightCm: Double
    let weightKg: Double
    let bodyFat: Double
    let units: BodyScoreFixtureUnits
    let expectedScore: Int
    let expectedFFMI: Double
    let expectedLeanPercentile: Double
    let expectedFFMIStatus: String
    let expectedStatusTagline: String

    var input: BodyScoreInput {
        BodyScoreInput(
            sex: sex,
            birthYear: Calendar.current.component(.year, from: Date()) - age,
            height: units.heightValue(fromCentimeters: heightCm),
            weight: units.weightValue(fromKilograms: weightKg),
            bodyFat: BodyFatValue(percentage: bodyFat, source: .manualValue),
            measurementPreference: units.measurementSystem
        )
    }

    var targetBodyFatRange: ClosedRange<Double> {
        sex == .male
            ? Constants.BodyComposition.BodyFat.maleOptimalRange
            : Constants.BodyComposition.BodyFat.femaleOptimalRange
    }
}

private enum BodyScoreFixtureUnits {
    case metric
    case imperial

    var measurementSystem: MeasurementSystem {
        switch self {
        case .metric: return .metric
        case .imperial: return .imperial
        }
    }

    func heightValue(fromCentimeters heightCm: Double) -> HeightValue {
        switch self {
        case .metric:
            return HeightValue(value: heightCm, unit: .centimeters)
        case .imperial:
            return HeightValue(value: heightCm / 2.54, unit: .inches)
        }
    }

    func weightValue(fromKilograms weightKg: Double) -> WeightValue {
        switch self {
        case .metric:
            return WeightValue(value: weightKg, unit: .kilograms)
        case .imperial:
            return WeightValue(value: weightKg / 0.45359237, unit: .pounds)
        }
    }
}

private struct BodyScoreGoldenCaseSeed {
    let name: String
    let sex: BiologicalSex
    let metrics: Metrics
    let expected: Expected

    struct Metrics {
        let age: Int
        let heightCm: Double
        let weightKg: Double
        let bodyFat: Double
        let units: BodyScoreFixtureUnits
    }

    struct Expected {
        let score: Int
        let ffmi: Double
        let leanPercentile: Double
        let ffmiStatus: String
        let tagline: String
    }
}

private let dialing = "Dialing it in."
private let solidBase = "Solid base. Room to tighten up."
private let earlyJourney = "Early in the journey. Huge upside."
private let goodStart = "Good starting point. Big upside."

private let bodyScoreGoldenCaseSeeds: [BodyScoreGoldenCaseSeed] = [
    seed(
        "male_underfat_peak", .male, metrics(23, 177.8, 80, 8, .metric),
        expected(100, 23.4, 99.0, "Advanced", dialing)
    ),
    seed("male_peak_9", .male, metrics(30, 177.8, 82, 9, .metric), expected(100, 23.7, 98.0, "Advanced", dialing)),
    seed("male_lean_11", .male, metrics(37, 180, 84, 11, .metric), expected(95, 23.1, 95.5, "Advanced", dialing)),
    seed("male_mid_13", .male, metrics(44, 180, 82, 13, .metric), expected(87, 22.0, 89.0, "Athletic", dialing)),
    seed("male_fit_15", .male, metrics(52, 175, 78, 15, .metric), expected(75, 22.0, 83.0, "Athletic", solidBase)),
    seed(
        "male_visible_18", .male, metrics(60, 175, 78, 18, .metric),
        expected(58, 21.2, 69.0, "Athletic", earlyJourney)
    ),
    seed("male_soft_20", .male, metrics(35, 175, 85, 20, .metric), expected(47, 22.5, 65.0, "Advanced", earlyJourney)),
    seed(
        "male_boundary_25", .male, metrics(35, 175, 90, 25, .metric),
        expected(30, 22.3, 40.0, "Athletic", earlyJourney)
    ),
    seed("male_high_30", .male, metrics(35, 175, 95, 30, .metric), expected(20, 22.0, 17.5, "Athletic", earlyJourney)),
    seed(
        "male_extreme_35", .male, metrics(35, 175, 100, 35, .metric),
        expected(1, 21.5, 4.8, "Athletic", earlyJourney)
    ),
    seed("male_low_6", .male, metrics(23, 180, 75, 6, .metric), expected(92, 21.8, 99.0, "Athletic", dialing)),
    seed("male_kg_metric", .male, metrics(40, 182, 88, 14, .metric), expected(81, 22.7, 87.0, "Advanced", solidBase)),
    seed(
        "male_lbs_inches_equiv", .male, metrics(40, 182, 88, 14, .imperial),
        expected(81, 22.7, 87.0, "Advanced", solidBase)
    ),
    seed("female_low_17", .female, metrics(23, 165, 58, 17, .metric), expected(85, 18.6, 99.0, "Advanced", dialing)),
    seed("female_18", .female, metrics(30, 165, 60, 18, .metric), expected(88, 19.0, 97.0, "Advanced", dialing)),
    seed("female_peak_19", .female, metrics(37, 165, 62, 19, .metric), expected(90, 19.4, 95.5, "Elite", dialing)),
    seed("female_peak_20", .female, metrics(44, 165, 62, 20, .metric), expected(90, 19.1, 91.0, "Elite", dialing)),
    seed("female_21", .female, metrics(52, 165, 63, 21, .metric), expected(85, 19.2, 89.0, "Elite", dialing)),
    seed("female_23", .female, metrics(60, 165, 64, 23, .metric), expected(75, 19.0, 80.0, "Elite", solidBase)),
    seed("female_25", .female, metrics(35, 165, 65, 25, .metric), expected(60, 18.8, 78.5, "Advanced", earlyJourney)),
    seed("female_28", .female, metrics(35, 165, 70, 28, .metric), expected(45, 19.4, 65.0, "Elite", earlyJourney)),
    seed("female_30", .female, metrics(35, 165, 74, 30, .metric), expected(35, 19.9, 55.0, "Elite", earlyJourney)),
    seed("female_35", .female, metrics(35, 165, 80, 35, .metric), expected(25, 20.0, 36.3, "Elite", earlyJourney)),
    seed("female_40", .female, metrics(35, 165, 86, 40, .metric), expected(15, 19.9, 17.5, "Elite", earlyJourney)),
    seed("female_45", .female, metrics(35, 165, 92, 45, .metric), expected(1, 19.5, 4.8, "Elite", earlyJourney)),
    seed("female_metric", .female, metrics(42, 170, 68, 24, .metric), expected(68, 18.5, 79.0, "Advanced", goodStart)),
    seed(
        "female_imperial_equiv", .female, metrics(42, 170, 68, 24, .imperial),
        expected(68, 18.5, 79.0, "Advanced", goodStart)
    )
]

private let bodyScoreGoldenCases: [BodyScoreGoldenCase] = bodyScoreGoldenCaseSeeds.map { seed in
    BodyScoreGoldenCase(
        name: seed.name,
        sex: seed.sex,
        age: seed.metrics.age,
        heightCm: seed.metrics.heightCm,
        weightKg: seed.metrics.weightKg,
        bodyFat: seed.metrics.bodyFat,
        units: seed.metrics.units,
        expectedScore: seed.expected.score,
        expectedFFMI: seed.expected.ffmi,
        expectedLeanPercentile: seed.expected.leanPercentile,
        expectedFFMIStatus: seed.expected.ffmiStatus,
        expectedStatusTagline: seed.expected.tagline
    )
}

private func seed(
    _ name: String,
    _ sex: BiologicalSex,
    _ metrics: BodyScoreGoldenCaseSeed.Metrics,
    _ expected: BodyScoreGoldenCaseSeed.Expected
) -> BodyScoreGoldenCaseSeed {
    BodyScoreGoldenCaseSeed(name: name, sex: sex, metrics: metrics, expected: expected)
}

private func metrics(
    _ age: Int,
    _ heightCm: Double,
    _ weightKg: Double,
    _ bodyFat: Double,
    _ units: BodyScoreFixtureUnits
) -> BodyScoreGoldenCaseSeed.Metrics {
    BodyScoreGoldenCaseSeed.Metrics(
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
        bodyFat: bodyFat,
        units: units
    )
}

private func expected(
    _ score: Int,
    _ ffmi: Double,
    _ leanPercentile: Double,
    _ ffmiStatus: String,
    _ tagline: String
) -> BodyScoreGoldenCaseSeed.Expected {
    BodyScoreGoldenCaseSeed.Expected(
        score: score,
        ffmi: ffmi,
        leanPercentile: leanPercentile,
        ffmiStatus: ffmiStatus,
        tagline: tagline
    )
}
