//
//  BodyShapeCalibration.swift
//  LogYourBody
//
//  LYB-318. Shape parameters are not a body-fat percentage, and a picture
//  change is not week-to-week progress. Higher tiers stay closed until a
//  consented corpus meets the predeclared gates. FFMI is lineage only.
//

import Foundation

struct BodyShapeFamilyGate: Equatable {
    var ageMin: Double
    var ageMax: Double
    var heightMin: Double
    var heightMax: Double
    var massMin: Double
    var massMax: Double
    var bodyFatMin: Double
    var bodyFatMax: Double
    var fatMassIndexMin: Double
    var fatMassIndexMax: Double
    var skeletalMuscleIndexMin: Double
    var skeletalMuscleIndexMax: Double
    var leanIndexMin: Double
    var leanIndexMax: Double
}

struct BodyShapeObservation: Equatable {
    var family: String
    var ageYears: Double
    var heightM: Double?
    var bodyMassKg: Double?
    var bodyFatPercent: Double?
    var fatMassKg: Double?
    var fatFreeMassKg: Double?
    var leanSoftTissueKg: Double?
    var skeletalMuscleKg: Double?
    var boneMineralKg: Double?
    var ffmi: Double?
    var distribution: String?
    var frame: Double?
    var method: String
    var dxaDevice: String?
    var dxaSoftware: String?
    var dxaStudyDate: String?
    var modelVersion: String

    static func adultMale() -> BodyShapeObservation {
        BodyShapeObservation(
            family: "adult-male",
            ageYears: 30,
            heightM: 1.8,
            bodyMassKg: 80,
            bodyFatPercent: 20,
            fatMassKg: 16,
            fatFreeMassKg: 64,
            leanSoftTissueKg: 60.8,
            skeletalMuscleKg: 32,
            boneMineralKg: 3.2,
            ffmi: nil,
            distribution: "mixed",
            frame: nil,
            method: "dxa",
            dxaDevice: "synthetic-dxa",
            dxaSoftware: "synthetic-software",
            dxaStudyDate: "2026-04-01",
            modelVersion: BodyShapeCalibration.modelVersion
        )
    }
}

struct BodyShapeParameters: Equatable {
    var adiposity: Double?
    var muscularity: Double?
    var frame: Double?
    var distribution: String?
}

struct BodyShapeDecision: Equatable {
    var status: String
    var parameters: BodyShapeParameters
    var muscleSource: String?
    var skeletalMuscleKg: Double?
    var ffmiIgnored: Bool
    var derivedFfmi: Double?
    var uncertainty: Double?
    var provenanceComplete: Bool
    var dxaComparabilityKey: String?
    var reasons: [String]
}

struct BodyShapeModelComparison: Equatable {
    var adiposityDelta: Double
    var comparable: Bool
    var apparentProgress: String?
    var disclosure: String
}

struct BodyShapeWeeklyClaim: Equatable {
    var longitudinalPromoted: Bool
    var evidenceClass: String
    var intervalDays: Int
    var studySpanDays: Int
    var sameModel: Bool
    var sameDexa: Bool
}

enum BodyShapeCalibration {
    static let modelId = "lyb.body-shape-calibration"
    static let modelVersion = "1.0.0"
    static let shapeBadge = "Illustrative, not body fat"
    static let modelChangeDisclosure = "Shape model changed. The difference is not body change."
    static let sameModelDisclosure = "Same shape model. Weekly change is not a supported claim."
    static let massBalanceKg = 0.3
    static let bodyFatPercentagePoints = 0.15
    static let leanBalanceKg = 0.3
    static let skeletalMuscleAboveLeanKg = 0.3
    static let weeklyIntervalMinDays = 5
    static let weeklyIntervalMaxDays = 9
    static let minConsentedSubjectsPerSex = 30
    static let compositionMaePercentagePoints = 2.0
    static let minWithinPersonWeeklyPairs = 20

    static let adultMale = BodyShapeFamilyGate(
        ageMin: 18, ageMax: 80,
        heightMin: 1.5, heightMax: 2.1,
        massMin: 45, massMax: 180,
        bodyFatMin: 5, bodyFatMax: 45,
        fatMassIndexMin: 1, fatMassIndexMax: 18,
        skeletalMuscleIndexMin: 6, skeletalMuscleIndexMax: 14,
        leanIndexMin: 12, leanIndexMax: 26
    )
    static let adultFemale = BodyShapeFamilyGate(
        ageMin: 18, ageMax: 80,
        heightMin: 1.4, heightMax: 2.0,
        massMin: 40, massMax: 160,
        bodyFatMin: 12, bodyFatMax: 55,
        fatMassIndexMin: 2, fatMassIndexMax: 22,
        skeletalMuscleIndexMin: 4, skeletalMuscleIndexMax: 11,
        leanIndexMin: 10, leanIndexMax: 22
    )

    /// Published pass/fail. Only the illustrative tier is promoted.
    static let tierPasses: [String: Bool] = [
        "illustrative-wireframe": true,
        "personalized-shape-estimate": false,
        "calibrated-composition-appearance": false,
        "longitudinal-interpretation": false
    ]

    static var compositionAppearancePromoted: Bool {
        tierPasses["calibrated-composition-appearance"] == true
    }

    static func wireframeAccessibilityLabel(presentation: String?) -> String {
        let body = presentation == "female" ? "female" : "male"
        return "Illustrative \(body) wireframe. Not a body-fat percentage."
    }

    static func shapeAccessibilityLabel(sexTitle: String) -> String {
        "Illustrative \(sexTitle.lowercased()) figure. Not a body-fat percentage."
    }

    static func family(named name: String) -> BodyShapeFamilyGate? {
        switch name {
        case "adult-male":
            return adultMale
        case "adult-female":
            return adultFemale
        default:
            return nil
        }
    }

    static func derivedFfmi(fatFreeMassKg: Double, heightM: Double) -> Double? {
        guard fatFreeMassKg.isFinite, heightM.isFinite, fatFreeMassKg > 0, heightM > 0 else { return nil }
        return fatFreeMassKg / (heightM * heightM) + 6.1 * (1.8 - heightM)
    }

    static func map(_ observation: BodyShapeObservation) -> BodyShapeDecision {
        var reasons: [String] = []
        let ffmiIgnored = observation.ffmi != nil
        let key = dxaKey(observation)
        let empty = BodyShapeParameters(adiposity: nil, muscularity: nil, frame: nil, distribution: nil)

        func finish(
            status: String,
            parameters: BodyShapeParameters,
            muscleSource: String?,
            extra: [String] = []
        ) -> BodyShapeDecision {
            let allReasons = reasons + extra
            let provenanceComplete = key != nil
            let uncertainty: Double?
            if let _ = parameters.adiposity {
                var value = 0.2
                if parameters.distribution == nil { value += 0.1 }
                if !provenanceComplete { value += 0.1 }
                uncertainty = min(1, value)
            } else {
                uncertainty = nil
            }
            let balanced = !allReasons.contains("mass-balance")
            let derived: Double?
            if balanced, let ffm = observation.fatFreeMassKg, let height = observation.heightM {
                derived = derivedFfmi(fatFreeMassKg: ffm, heightM: height)
            } else {
                derived = nil
            }
            return BodyShapeDecision(
                status: status,
                parameters: parameters,
                muscleSource: muscleSource,
                skeletalMuscleKg: muscleSource == "skeletal-muscle" ? observation.skeletalMuscleKg : nil,
                ffmiIgnored: ffmiIgnored,
                derivedFfmi: derived,
                uncertainty: uncertainty,
                provenanceComplete: provenanceComplete,
                dxaComparabilityKey: key,
                reasons: allReasons
            )
        }

        guard let gate = family(named: observation.family) else {
            return finish(status: "abstained", parameters: empty, muscleSource: nil, extra: ["unsupported-family"])
        }
        if hasNonFinite(observation) {
            return finish(status: "abstained", parameters: empty, muscleSource: nil, extra: ["non-finite"])
        }
        if !inside(observation.ageYears, min: gate.ageMin, max: gate.ageMax) {
            return finish(status: "abstained", parameters: empty, muscleSource: nil, extra: ["unsupported-age"])
        }
        guard let height = observation.heightM, inside(height, min: gate.heightMin, max: gate.heightMax) else {
            return finish(status: "abstained", parameters: empty, muscleSource: nil, extra: ["unsupported-height"])
        }
        guard let mass = observation.bodyMassKg, inside(mass, min: gate.massMin, max: gate.massMax) else {
            return finish(status: "abstained", parameters: empty, muscleSource: nil, extra: ["unsupported-mass"])
        }

        var fat = observation.fatMassKg
        if let percent = observation.bodyFatPercent, !inside(percent, min: gate.bodyFatMin, max: gate.bodyFatMax) {
            reasons.append("unsupported-body-fat")
        }
        if fat == nil, let percent = observation.bodyFatPercent, !reasons.contains("unsupported-body-fat") {
            fat = mass * (percent / 100)
        }
        if let fat, let percent = observation.bodyFatPercent,
           abs(percent - (fat / mass) * 100) > bodyFatPercentagePoints {
            reasons.append("body-fat-conflict")
        }
        if let fat, let ffm = observation.fatFreeMassKg, abs(fat + ffm - mass) > massBalanceKg {
            reasons.append("mass-balance")
        }
        if reasons.contains("mass-balance") || reasons.contains("body-fat-conflict") || reasons.contains("unsupported-body-fat") {
            return finish(status: "abstained", parameters: empty, muscleSource: nil)
        }

        var parameters = BodyShapeParameters(
            adiposity: nil,
            muscularity: nil,
            frame: nil,
            distribution: observation.distribution
        )
        if let fat {
            parameters.adiposity = unit(
                fat / (height * height),
                min: gate.fatMassIndexMin,
                max: gate.fatMassIndexMax
            )
            if parameters.adiposity == nil { reasons.append("unsupported-fat-mass-index") }
        } else {
            reasons.append("missing-fat")
        }

        var muscleSource: String?
        let sm = observation.skeletalMuscleKg
        let lst = observation.leanSoftTissueKg
        let bone = observation.boneMineralKg
        let ffm = observation.fatFreeMassKg
        if let lst, let bone, let ffm, abs(lst + bone - ffm) > leanBalanceKg {
            reasons.append("lean-balance")
        } else if let sm, let lst, sm > lst + skeletalMuscleAboveLeanKg {
            reasons.append("skeletal-muscle-exceeds-lean")
        } else if let sm {
            parameters.muscularity = unit(
                sm / (height * height),
                min: gate.skeletalMuscleIndexMin,
                max: gate.skeletalMuscleIndexMax
            )
            muscleSource = parameters.muscularity == nil ? nil : "skeletal-muscle"
            if parameters.muscularity == nil { reasons.append("unsupported-muscle-index") }
        } else if let lst {
            parameters.muscularity = unit(
                lst / (height * height),
                min: gate.leanIndexMin,
                max: gate.leanIndexMax
            )
            muscleSource = parameters.muscularity == nil ? nil : "lean-soft-tissue"
            if parameters.muscularity == nil { reasons.append("unsupported-muscle-index") }
        } else if let ffm, let bone {
            let derivedLean = ffm - bone
            parameters.muscularity = unit(
                derivedLean / (height * height),
                min: gate.leanIndexMin,
                max: gate.leanIndexMax
            )
            muscleSource = parameters.muscularity == nil ? nil : "fat-free-mass-minus-bone"
            if parameters.muscularity == nil { reasons.append("unsupported-muscle-index") }
        } else {
            reasons.append("missing-muscle")
        }

        if let frame = observation.frame {
            if frame < 0 || frame > 1 {
                reasons.append("unsupported-frame")
            } else {
                parameters.frame = frame
            }
        } else {
            reasons.append("missing-frame")
        }

        let status: String
        if parameters.adiposity != nil && parameters.muscularity != nil && parameters.frame != nil {
            status = "estimated"
        } else if parameters.adiposity != nil || parameters.muscularity != nil || parameters.frame != nil {
            status = "partial"
        } else {
            status = "abstained"
        }
        return finish(status: status, parameters: parameters, muscleSource: muscleSource)
    }

    static func displayedBucket(
        bodyFatPercentage: Double?,
        supported: ClosedRange<Double>,
        buckets: [Int],
        fallback: Int,
        compositionPromoted: Bool
    ) -> Int {
        guard compositionPromoted, let bodyFatPercentage,
              bodyFatPercentage >= supported.lowerBound,
              bodyFatPercentage <= supported.upperBound else {
            return fallback
        }
        let eligible = buckets.filter { supported.contains(Double($0)) }
        guard !eligible.isEmpty else { return fallback }
        return eligible.min { lhs, rhs in
            let leftDistance = abs(Double(lhs) - bodyFatPercentage)
            let rightDistance = abs(Double(rhs) - bodyFatPercentage)
            if leftDistance == rightDistance { return lhs < rhs }
            return leftDistance < rightDistance
        } ?? fallback
    }

    static func compareModels(
        fromVersion: String,
        toVersion: String,
        fromAdiposity: Double,
        toAdiposity: Double
    ) -> BodyShapeModelComparison {
        let delta = toAdiposity - fromAdiposity
        if fromVersion != toVersion {
            return BodyShapeModelComparison(
                adiposityDelta: delta,
                comparable: false,
                apparentProgress: nil,
                disclosure: modelChangeDisclosure
            )
        }
        return BodyShapeModelComparison(
            adiposityDelta: delta,
            comparable: true,
            apparentProgress: nil,
            disclosure: sameModelDisclosure
        )
    }

    static func weeklyClaimAllowed(_ claim: BodyShapeWeeklyClaim) -> Bool {
        claim.longitudinalPromoted
            && claim.evidenceClass == "consented-human"
            && claim.sameModel
            && claim.sameDexa
            && claim.intervalDays >= weeklyIntervalMinDays
            && claim.intervalDays <= weeklyIntervalMaxDays
            && claim.studySpanDays >= weeklyIntervalMinDays
            && claim.studySpanDays <= weeklyIntervalMaxDays
    }

    private static func inside(_ value: Double, min lower: Double, max upper: Double) -> Bool {
        value.isFinite && value >= lower && value <= upper
    }

    private static func unit(_ value: Double, min lower: Double, max upper: Double) -> Double? {
        guard inside(value, min: lower, max: upper), upper > lower else { return nil }
        return (value - lower) / (upper - lower)
    }

    private static func dxaKey(_ observation: BodyShapeObservation) -> String? {
        guard observation.method == "dxa",
              let device = observation.dxaDevice, !device.isEmpty,
              let software = observation.dxaSoftware, !software.isEmpty,
              let studyDate = observation.dxaStudyDate, !studyDate.isEmpty else {
            return nil
        }
        return "\(device)|\(software)|\(studyDate)"
    }

    private static func hasNonFinite(_ observation: BodyShapeObservation) -> Bool {
        if !observation.ageYears.isFinite { return true }
        let values = [
            observation.heightM,
            observation.bodyMassKg,
            observation.bodyFatPercent,
            observation.fatMassKg,
            observation.fatFreeMassKg,
            observation.leanSoftTissueKg,
            observation.skeletalMuscleKg,
            observation.boneMineralKg,
            observation.frame,
            observation.ffmi
        ]
        return values.contains { value in
            guard let value else { return false }
            return !value.isFinite
        }
    }
}
