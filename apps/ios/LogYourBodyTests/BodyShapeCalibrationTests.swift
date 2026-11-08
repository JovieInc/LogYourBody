//
//  BodyShapeCalibrationTests.swift
//  LogYourBodyTests
//

import XCTest
@testable import LogYourBody

final class BodyShapeCalibrationTests: XCTestCase {
    func testPublishedReportKeepsHigherTiersClosed() {
        XCTAssertEqual(BodyShapeCalibration.tierPasses["illustrative-wireframe"], true)
        XCTAssertEqual(BodyShapeCalibration.tierPasses["personalized-shape-estimate"], false)
        XCTAssertEqual(BodyShapeCalibration.tierPasses["calibrated-composition-appearance"], false)
        XCTAssertEqual(BodyShapeCalibration.tierPasses["longitudinal-interpretation"], false)
        XCTAssertFalse(BodyShapeCalibration.compositionAppearancePromoted)
        XCTAssertEqual(BodyShapeCalibration.minConsentedSubjectsPerSex, 30)
        XCTAssertEqual(BodyShapeCalibration.compositionMaePercentagePoints, 2, accuracy: 0.0001)
        XCTAssertEqual(BodyShapeCalibration.minWithinPersonWeeklyPairs, 20)
        XCTAssertEqual(BodyShapeCalibration.weeklyIntervalMinDays, 5)
        XCTAssertEqual(BodyShapeCalibration.weeklyIntervalMaxDays, 9)
    }

    func testBodyFatPercentageDoesNotSelectAnAvatarBucket() {
        let male = AvatarBodyFatCatalog.Sex.male
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male").bucket,
            male.defaultBucket
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 80, gender: "male").bucket,
            male.defaultBucket
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male").assetName,
            AvatarBodyFatCatalog.match(bodyFatPercentage: 30, gender: "male").assetName
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 72, gender: "f").bucket,
            AvatarBodyFatCatalog.Sex.female.defaultBucket
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male").badgeText,
            "Illustrative, not body fat"
        )
        XCTAssertFalse(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male").badgeText.contains("%")
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male").accessibilityLabel,
            "Illustrative male figure. Not a body-fat percentage."
        )
    }

    func testPromotedInRangeBucketStaysInsideTheFamilyAndOutOfRangeAbstains() {
        let male = AvatarBodyFatCatalog.Sex.male
        let maleRange = male.supportedBodyFatPercent
        XCTAssertEqual(
            BodyShapeCalibration.displayedBucket(
                bodyFatPercentage: 16.4,
                supported: maleRange,
                buckets: male.buckets,
                fallback: male.defaultBucket,
                compositionPromoted: true
            ),
            15
        )
        XCTAssertEqual(
            BodyShapeCalibration.displayedBucket(
                bodyFatPercentage: 80,
                supported: maleRange,
                buckets: male.buckets,
                fallback: male.defaultBucket,
                compositionPromoted: true
            ),
            male.defaultBucket
        )
        XCTAssertEqual(
            BodyShapeCalibration.displayedBucket(
                bodyFatPercentage: 20.2,
                supported: maleRange,
                buckets: male.buckets,
                fallback: male.defaultBucket,
                compositionPromoted: false
            ),
            male.defaultBucket
        )
    }

    func testSameBodyFatDoesNotForceOneShapeAndIgnoresFFMI() {
        var light = BodyShapeObservation.adultMale()
        var heavy = light
        heavy.bodyMassKg = 100
        heavy.heightM = 1.7
        heavy.bodyFatPercent = 20
        heavy.fatMassKg = 20
        heavy.fatFreeMassKg = 80
        heavy.leanSoftTissueKg = 76
        heavy.skeletalMuscleKg = 36
        heavy.boneMineralKg = 4
        heavy.distribution = "central"
        light.ffmi = 99

        let lightDecision = BodyShapeCalibration.map(light)
        let heavyDecision = BodyShapeCalibration.map(heavy)
        let lightFatIndex = 16 / (1.8 * 1.8)
        let heavyFatIndex = 20 / (1.7 * 1.7)

        XCTAssertEqual(lightDecision.parameters.adiposity ?? -1, (lightFatIndex - 1) / 17, accuracy: 1e-9)
        XCTAssertEqual(heavyDecision.parameters.adiposity ?? -1, (heavyFatIndex - 1) / 17, accuracy: 1e-9)
        XCTAssertNotEqual(lightDecision.parameters.adiposity, heavyDecision.parameters.adiposity)
        XCTAssertNotEqual(lightDecision.parameters.distribution, heavyDecision.parameters.distribution)
        XCTAssertEqual(lightDecision.muscleSource, "skeletal-muscle")
        XCTAssertTrue(lightDecision.ffmiIgnored)
        XCTAssertEqual(lightDecision.derivedFfmi ?? -1, 64 / (1.8 * 1.8), accuracy: 1e-9)
        XCTAssertNotEqual(lightDecision.derivedFfmi, 99)
        XCTAssertEqual(lightDecision.skeletalMuscleKg, 32)
    }

    func testCompartmentsStayDistinctAndConflictsAbstain() {
        var leanOnly = BodyShapeObservation.adultMale()
        leanOnly.skeletalMuscleKg = nil
        let lean = BodyShapeCalibration.map(leanOnly)
        XCTAssertEqual(lean.muscleSource, "lean-soft-tissue")
        XCTAssertNil(lean.skeletalMuscleKg)

        var fatFreeOnly = BodyShapeObservation.adultMale()
        fatFreeOnly.skeletalMuscleKg = nil
        fatFreeOnly.leanSoftTissueKg = nil
        fatFreeOnly.boneMineralKg = nil
        let fatFree = BodyShapeCalibration.map(fatFreeOnly)
        XCTAssertNil(fatFree.parameters.muscularity)
        XCTAssertNil(fatFree.muscleSource)
        XCTAssertTrue(fatFree.reasons.contains("missing-muscle"))

        var derived = BodyShapeObservation.adultMale()
        derived.skeletalMuscleKg = nil
        derived.leanSoftTissueKg = nil
        let fromBone = BodyShapeCalibration.map(derived)
        XCTAssertEqual(fromBone.muscleSource, "fat-free-mass-minus-bone")
        XCTAssertNil(fromBone.skeletalMuscleKg)

        var conflict = BodyShapeObservation.adultMale()
        conflict.fatFreeMassKg = 50
        XCTAssertEqual(BodyShapeCalibration.map(conflict).status, "abstained")
        XCTAssertNil(BodyShapeCalibration.map(conflict).parameters.adiposity)
        XCTAssertNil(BodyShapeCalibration.map(conflict).derivedFfmi)

        var tooMuchMuscle = BodyShapeObservation.adultMale()
        tooMuchMuscle.skeletalMuscleKg = 70
        let rejected = BodyShapeCalibration.map(tooMuchMuscle)
        XCTAssertNil(rejected.parameters.muscularity)
        XCTAssertTrue(rejected.reasons.contains("skeletal-muscle-exceeds-lean"))

        var percentOnly = BodyShapeObservation.adultMale()
        percentOnly.fatMassKg = nil
        percentOnly.fatFreeMassKg = nil
        percentOnly.leanSoftTissueKg = nil
        percentOnly.skeletalMuscleKg = nil
        percentOnly.boneMineralKg = nil
        percentOnly.distribution = nil
        percentOnly.frame = nil
        let partial = BodyShapeCalibration.map(percentOnly)
        XCTAssertNotNil(partial.parameters.adiposity)
        XCTAssertNil(partial.parameters.muscularity)
        XCTAssertNil(partial.parameters.frame)
        XCTAssertEqual(partial.status, "partial")
    }

    func testUnsupportedInputsAbstainInsteadOfClamping() {
        var child = BodyShapeObservation.adultMale()
        child.ageYears = 16
        XCTAssertEqual(BodyShapeCalibration.map(child).status, "abstained")
        XCTAssertTrue(BodyShapeCalibration.map(child).reasons.contains("unsupported-age"))

        var unknown = BodyShapeObservation.adultMale()
        unknown.family = "unspecified"
        XCTAssertTrue(BodyShapeCalibration.map(unknown).reasons.contains("unsupported-family"))

        var highFat = BodyShapeObservation.adultMale()
        highFat.bodyFatPercent = 60
        highFat.fatMassKg = 48
        highFat.fatFreeMassKg = 32
        XCTAssertEqual(BodyShapeCalibration.map(highFat).status, "abstained")
        XCTAssertNil(BodyShapeCalibration.map(highFat).parameters.adiposity)

        var wildFrame = BodyShapeObservation.adultMale()
        wildFrame.frame = 4
        XCTAssertNil(BodyShapeCalibration.map(wildFrame).parameters.frame)
        XCTAssertTrue(BodyShapeCalibration.map(wildFrame).reasons.contains("unsupported-frame"))

        var broken = BodyShapeObservation.adultMale()
        broken.bodyMassKg = .infinity
        XCTAssertTrue(BodyShapeCalibration.map(broken).reasons.contains("non-finite"))
    }

    func testDexaProvenanceAndModelUpdatesDoNotInventProgress() {
        var missing = BodyShapeObservation.adultMale()
        missing.dxaSoftware = nil
        let incomplete = BodyShapeCalibration.map(missing)
        let complete = BodyShapeCalibration.map(.adultMale())
        XCTAssertFalse(incomplete.provenanceComplete)
        XCTAssertNil(incomplete.dxaComparabilityKey)
        XCTAssertGreaterThan(incomplete.uncertainty ?? 0, complete.uncertainty ?? 1)

        let upgrade = BodyShapeCalibration.compareModels(
            fromVersion: "1.0.0",
            toVersion: "1.1.0",
            fromAdiposity: 0.42,
            toAdiposity: 0.30
        )
        XCTAssertEqual(upgrade.adiposityDelta, -0.12, accuracy: 1e-9)
        XCTAssertFalse(upgrade.comparable)
        XCTAssertNil(upgrade.apparentProgress)
        XCTAssertEqual(upgrade.disclosure, BodyShapeCalibration.modelChangeDisclosure)

        let same = BodyShapeCalibration.compareModels(
            fromVersion: "1.0.0",
            toVersion: "1.0.0",
            fromAdiposity: 0.42,
            toAdiposity: 0.30
        )
        XCTAssertTrue(same.comparable)
        XCTAssertNil(same.apparentProgress)
    }

    func testWeeklyChangeRequiresWithinPersonEvidenceInsideOneWeek() {
        XCTAssertFalse(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: false,
            evidenceClass: "consented-human",
            intervalDays: 7,
            studySpanDays: 7,
            sameModel: true,
            sameDexa: true
        )))
        XCTAssertFalse(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: true,
            evidenceClass: "synthetic-regression",
            intervalDays: 7,
            studySpanDays: 7,
            sameModel: true,
            sameDexa: true
        )))
        XCTAssertFalse(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: true,
            evidenceClass: "consented-human",
            intervalDays: 7,
            studySpanDays: 151,
            sameModel: true,
            sameDexa: true
        )))
        XCTAssertFalse(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: true,
            evidenceClass: "consented-human",
            intervalDays: 151,
            studySpanDays: 151,
            sameModel: true,
            sameDexa: true
        )))
        XCTAssertFalse(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: true,
            evidenceClass: "consented-human",
            intervalDays: 7,
            studySpanDays: 7,
            sameModel: false,
            sameDexa: true
        )))
        XCTAssertTrue(BodyShapeCalibration.weeklyClaimAllowed(BodyShapeWeeklyClaim(
            longitudinalPromoted: true,
            evidenceClass: "consented-human",
            intervalDays: 7,
            studySpanDays: 7,
            sameModel: true,
            sameDexa: true
        )))
    }

    func testMappingIsDeterministic() {
        XCTAssertEqual(
            BodyShapeCalibration.map(.adultMale()),
            BodyShapeCalibration.map(.adultMale())
        )
    }
}
