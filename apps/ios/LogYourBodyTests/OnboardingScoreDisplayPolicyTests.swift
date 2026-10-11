//
// OnboardingScoreDisplayPolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

@MainActor
final class OnboardingScoreDisplayPolicyTests: XCTestCase {
    private func makeResult() -> BodyScoreResult {
        BodyScoreResult(
            score: 82,
            ffmi: 21.4,
            leanPercentile: 72,
            ffmiStatus: "Strong",
            bodyFatReferenceRange: .init(lowerBound: 10, upperBound: 15, label: "Lean"),
            statusTagline: "Strong base"
        )
    }

    // MARK: - Health confirmation display (BodyScoreHealthConfirmationView)

    func testHeightDisplayConvertsAndOrdersPerMeasurementSystem() {
        XCTAssertEqual(HealthConfirmationDisplayPolicy.imperialHeightString(fromCentimeters: 178), "5' 10\"")
        XCTAssertEqual(HealthConfirmationDisplayPolicy.imperialHeightString(fromCentimeters: 152.4), "5' 0\"")
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.formattedHeight(centimeters: 178, system: .metric),
            "178 cm (5' 10\")"
        )
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.formattedHeight(centimeters: 178, system: .imperial),
            "5' 10\" (178 cm)"
        )
    }

    func testWeightDisplayRoundsAndConvertsPerUnit() {
        XCTAssertEqual(HealthConfirmationDisplayPolicy.formatWeight(value: 80.4, unit: .kilograms), "80 kg")
        XCTAssertEqual(HealthConfirmationDisplayPolicy.formatWeight(value: 80.5, unit: .kilograms), "81 kg")
        XCTAssertEqual(HealthConfirmationDisplayPolicy.formatWeight(fromKilograms: 80, unit: .pounds), "176 lbs")
        XCTAssertEqual(HealthConfirmationDisplayPolicy.formatWeight(fromKilograms: 80, unit: .kilograms), "80 kg")
    }

    func testLegacyHealthMetricsPreferSnapshotOverUnspecifiedEntries() {
        var input = BodyScoreInput(
            height: HeightValue(value: 178, unit: .centimeters),
            weight: WeightValue(value: 180, unit: .pounds),
            bodyFat: BodyFatValue(percentage: 18, source: .unspecified)
        )
        input.healthSnapshot.heightCm = 190
        input.healthSnapshot.weightKg = 90
        input.healthSnapshot.bodyFatPercentage = 21

        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .kilograms),
            "90 kg"
        )
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredHeightString(input: input, system: .metric),
            "190 cm (6' 3\")"
        )
        XCTAssertEqual(HealthConfirmationDisplayPolicy.preferredBodyFatString(input: input), "21.0%")

        input.healthSnapshot = HealthImportSnapshot()
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .pounds),
            "180 lbs"
        )
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredHeightString(input: input, system: .imperial),
            "5' 10\" (178 cm)"
        )
        XCTAssertEqual(HealthConfirmationDisplayPolicy.preferredBodyFatString(input: input), "18.0%")

        let emptyInput = BodyScoreInput()
        XCTAssertNil(HealthConfirmationDisplayPolicy.preferredWeightString(input: emptyInput, preferredUnit: .pounds))
        XCTAssertNil(HealthConfirmationDisplayPolicy.preferredHeightString(input: emptyInput, system: .metric))
        XCTAssertNil(HealthConfirmationDisplayPolicy.preferredBodyFatString(input: emptyInput))
    }

    func testExplicitManualWeightOverridesOlderHealthSnapshot() {
        var input = BodyScoreInput(
            weight: WeightValue(value: 80, unit: .kilograms),
            weightSource: .manual
        )
        input.healthSnapshot.weightKg = 90

        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .kilograms),
            "80 kg"
        )
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .pounds),
            "176 lbs"
        )
        input.weight = WeightValue(value: 180.5, unit: .pounds)
        input.healthSnapshot = HealthImportSnapshot()
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .pounds),
            "181 lbs"
        )
    }

    func testExplicitScanWeightOverridesOlderHealthSnapshot() {
        var input = BodyScoreInput(
            weight: WeightValue(value: 80, unit: .kilograms),
            weightSource: .scan
        )
        input.healthSnapshot.weightKg = 90

        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.preferredWeightString(input: input, preferredUnit: .kilograms),
            "80 kg"
        )
    }

    func testExplicitManualBodyFatOverridesOlderHealthSnapshot() {
        var input = BodyScoreInput(bodyFat: BodyFatValue(percentage: 18, source: .manualValue))
        input.healthSnapshot.bodyFatPercentage = 21

        XCTAssertEqual(HealthConfirmationDisplayPolicy.preferredBodyFatString(input: input), "18.0%")
    }

    func testExplicitScanAndVisualBodyFatOverrideOlderHealthSnapshot() {
        for source in [BodyFatInputSource.scan, .visualEstimate] {
            var input = BodyScoreInput(bodyFat: BodyFatValue(percentage: 20, source: source))
            input.healthSnapshot.bodyFatPercentage = 21

            XCTAssertEqual(
                HealthConfirmationDisplayPolicy.preferredBodyFatString(input: input),
                "20.0%",
                "An explicit \(source) value must survive an older Health snapshot"
            )
        }
    }


    func testExplicitHealthReviewValuesKeepTheirOwnProvenance() throws {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let weightCases: [(OnboardingWeightSource, HealthConfirmationDisplayPolicy.Source)] = [
            (.manual, .entered), (.scan, .scan)
        ]
        for (source, expectedSource) in weightCases {
            var input = BodyScoreInput(weight: WeightValue(value: 80, unit: .kilograms), weightSource: source)
            input.healthSnapshot.weightKg = 90
            input.healthSnapshot.weightDate = oldDate

            let resolved = try XCTUnwrap(HealthConfirmationDisplayPolicy.weight(input: input))
            XCTAssertEqual(resolved.value, 80)
            XCTAssertEqual(resolved.source, expectedSource)
            XCTAssertNil(resolved.date, "An override must not inherit the old Health measurement date")
        }
        let bodyFatCases: [(BodyFatInputSource, HealthConfirmationDisplayPolicy.Source)] = [
            (.manualValue, .entered), (.scan, .scan), (.visualEstimate, .visualEstimate)
        ]
        for (source, expectedSource) in bodyFatCases {
            var input = BodyScoreInput(bodyFat: BodyFatValue(percentage: 18, source: source))
            input.healthSnapshot.bodyFatPercentage = 21
            input.healthSnapshot.bodyFatDate = oldDate

            let resolved = try XCTUnwrap(HealthConfirmationDisplayPolicy.bodyFat(input: input))
            XCTAssertEqual(resolved.value, 18)
            XCTAssertEqual(resolved.source, expectedSource)
            XCTAssertNil(resolved.date)
        }
    }

    func testPartialHealthReadPreservesRetainedScanProvenance() throws {
        var input = BodyScoreInput(
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 20, source: .scan),
            weightSource: .scan
        )
        input.healthSnapshot.heightCm = 180

        let weight = try XCTUnwrap(HealthConfirmationDisplayPolicy.weight(input: input))
        let bodyFat = try XCTUnwrap(HealthConfirmationDisplayPolicy.bodyFat(input: input))
        XCTAssertEqual(weight.value, 80)
        XCTAssertEqual(bodyFat.value, 20)
        XCTAssertEqual(weight.source, .scan)
        XCTAssertEqual(bodyFat.source, .scan)
        XCTAssertNil(weight.date)
        XCTAssertNil(bodyFat.date)
    }

    func testMissingExplicitValuesFallBackToHealthWithItsDate() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var input = BodyScoreInput(bodyFat: BodyFatValue(source: .scan), weightSource: .manual)
        input.healthSnapshot.weightKg = 90
        input.healthSnapshot.weightDate = date
        input.healthSnapshot.bodyFatPercentage = 21
        input.healthSnapshot.bodyFatDate = date

        let weight = try XCTUnwrap(HealthConfirmationDisplayPolicy.weight(input: input))
        let bodyFat = try XCTUnwrap(HealthConfirmationDisplayPolicy.bodyFat(input: input))
        XCTAssertEqual(weight.value, 90)
        XCTAssertEqual(bodyFat.value, 21)
        XCTAssertEqual(weight.source, .healthKit)
        XCTAssertEqual(bodyFat.source, .healthKit)
        XCTAssertEqual(weight.date, date)
        XCTAssertEqual(bodyFat.date, date)
    }

    func testLegacyFallbackAndUnknownProvenanceRemainDistinct() throws {
        var input = BodyScoreInput(
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 18)
        )
        input.healthSnapshot.weightKg = 90
        input.healthSnapshot.bodyFatPercentage = 21

        XCTAssertEqual(HealthConfirmationDisplayPolicy.weight(input: input)?.source, .healthKit)
        XCTAssertEqual(HealthConfirmationDisplayPolicy.bodyFat(input: input)?.source, .healthKit)
        input.healthSnapshot = HealthImportSnapshot()

        let weight = try XCTUnwrap(HealthConfirmationDisplayPolicy.weight(input: input))
        let bodyFat = try XCTUnwrap(HealthConfirmationDisplayPolicy.bodyFat(input: input))
        XCTAssertEqual(weight.value, 80)
        XCTAssertEqual(bodyFat.value, 18)
        XCTAssertEqual(weight.source, .unknown)
        XCTAssertEqual(bodyFat.source, .unknown)
        XCTAssertNil(weight.date)
        XCTAssertNil(bodyFat.date)
    }

    func testHealthOriginWithoutSnapshotDoesNotReuseOrphanedDates() throws {
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        var input = BodyScoreInput(
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 18, source: .healthKit),
            weightSource: .healthKit
        )
        input.healthSnapshot.weightDate = oldDate
        input.healthSnapshot.bodyFatDate = oldDate

        let weight = try XCTUnwrap(HealthConfirmationDisplayPolicy.weight(input: input))
        let bodyFat = try XCTUnwrap(HealthConfirmationDisplayPolicy.bodyFat(input: input))
        XCTAssertEqual(weight.source, .healthKit)
        XCTAssertEqual(bodyFat.source, .healthKit)
        XCTAssertNil(weight.date)
        XCTAssertNil(bodyFat.date)
        XCTAssertNil(HealthConfirmationDisplayPolicy.weight(input: BodyScoreInput()))
        XCTAssertNil(HealthConfirmationDisplayPolicy.bodyFat(input: BodyScoreInput()))
    }


    // MARK: - Reveal presentation (BodyScoreRevealView)

    func testPercentileGroupLabelFollowsSexAtBirth() {
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: .male), "men your age and height")
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: .female), "women your age and height")
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: nil), "people your age and height")
    }

    func testPopulationRangeIsAlwaysLabeledAsReference() {
        let range = BodyScoreResult.ReferenceRange(lowerBound: 10, upperBound: 15, label: "Lean")

        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceText(range: range),
            "Reference: 10–15% (Lean)"
        )
        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceAccessibilityText(range: range),
            "Reference body fat: 10 to 15 percent. Lean."
        )
    }

    func testSharePayloadConvertsWeightIntoPreferredSystem() {
        let result = makeResult()
        let metricInput = BodyScoreInput(
            sex: .male,
            height: HeightValue(value: 178, unit: .centimeters),
            weight: WeightValue(value: 80, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 18, source: .manualValue),
            measurementPreference: .metric
        )

        let metricPayload = BodyScoreRevealPolicy.makeSharePayload(input: metricInput, result: result)
        XCTAssertEqual(metricPayload.weightValue, "80.0")
        XCTAssertEqual(metricPayload.weightCaption, "kg")
        XCTAssertEqual(metricPayload.bodyFatValue, "18.0")
        XCTAssertEqual(metricPayload.scoreText, "82")
        XCTAssertEqual(metricPayload.ffmiValue, "21.4")
        XCTAssertEqual(metricPayload.gender, "male")

        var imperialInput = metricInput
        imperialInput.measurementPreference = .imperial
        let imperialPayload = BodyScoreRevealPolicy.makeSharePayload(input: imperialInput, result: result)
        XCTAssertEqual(imperialPayload.weightValue, "176.4")
        XCTAssertEqual(imperialPayload.weightCaption, "lbs")
    }

    func testSharePayloadFallsBackWhenMetricsAreMissing() {
        let result = makeResult()
        let input = BodyScoreInput(measurementPreference: .imperial)

        let payload = BodyScoreRevealPolicy.makeSharePayload(input: input, result: result)
        XCTAssertEqual(payload.weightValue, "--")
        XCTAssertEqual(payload.weightCaption, "lbs")
        XCTAssertEqual(payload.bodyFatValue, "--")
        XCTAssertNil(payload.bodyFatPercentage)
        XCTAssertNil(payload.gender)
    }

    func testHeightDisplayCarriesRoundedInchesAcrossTheFootBoundary() {
        XCTAssertEqual(HealthConfirmationDisplayPolicy.imperialHeightString(fromCentimeters: 182.8), "6' 0\"")
        XCTAssertEqual(
            HealthConfirmationDisplayPolicy.formattedHeight(centimeters: 182.8, system: .metric),
            "183 cm (6' 0\")"
        )
    }

    func testHealthHeightFormattingRejectsUnsafeSnapshotsWithoutCrashing() {
        for height in [Double.infinity, -.infinity, .nan, Double.greatestFiniteMagnitude] {
            var input = BodyScoreInput(height: HeightValue(value: 178, unit: .centimeters))
            input.healthSnapshot.heightCm = height
            XCTAssertNil(HealthConfirmationDisplayPolicy.preferredHeightString(input: input, system: .metric))
            XCTAssertEqual(HealthConfirmationDisplayPolicy.imperialHeightString(fromCentimeters: height), "—")
            XCTAssertEqual(HealthConfirmationDisplayPolicy.formattedHeight(centimeters: height, system: .metric), "—")
        }
    }
}
