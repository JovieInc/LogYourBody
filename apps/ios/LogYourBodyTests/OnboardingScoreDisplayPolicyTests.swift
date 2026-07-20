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

    func testPreferredHealthMetricsPreferSnapshotOverStoredEntries() {
        var input = BodyScoreInput(
            height: HeightValue(value: 178, unit: .centimeters),
            weight: WeightValue(value: 180, unit: .pounds),
            bodyFat: BodyFatValue(percentage: 18, source: .manualValue)
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

    // MARK: - Reveal presentation (BodyScoreRevealView)

    func testPercentileGroupLabelFollowsSexAtBirth() {
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: .male), "men your age and height")
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: .female), "women your age and height")
        XCTAssertEqual(BodyScoreRevealPolicy.percentileGroupLabel(for: nil), "people your age and height")
    }

    func testReferenceTextFollowsIndividualizedGoalsGate() {
        let range = BodyScoreResult.ReferenceRange(lowerBound: 10, upperBound: 15, label: "Lean")

        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceText(range: range, usesIndividualizedAestheticGoals: false),
            "Target: 10–15% (Lean)"
        )
        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceText(range: range, usesIndividualizedAestheticGoals: true),
            "Reference: 10–15% (Lean)"
        )
        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceAccessibilityText(range: range, usesIndividualizedAestheticGoals: false),
            "Target body fat: 10 to 15 percent. Lean."
        )
        XCTAssertEqual(
            BodyScoreRevealPolicy.referenceAccessibilityText(range: range, usesIndividualizedAestheticGoals: true),
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
}
