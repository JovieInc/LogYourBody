import Foundation

protocol BodyScoreCalculating {
    func calculateScore(context: BodyScoreCalculationContext) throws -> BodyScoreResult
}

struct BodyScoreCalculator: BodyScoreCalculating {
    func calculateScore(context: BodyScoreCalculationContext) throws -> BodyScoreResult {
        guard context.input.isReadyForCalculation,
              let heightCm = context.input.height.inCentimeters,
              let weightKg = context.input.weight.inKilograms,
              let bodyFat = context.input.bodyFat.percentage,
              let sex = context.input.sex else {
            throw BodyScoreCalculationError.missingRequiredInputs
        }

        let ffmi = calculateFFMI(weightKg: weightKg, bodyFatPercentage: bodyFat, heightCm: heightCm)
        let percentile = clamp(calculateLeanPercentile(sex: sex, age: context.input.age, bodyFat: bodyFat), min: 1, max: 99)
        let targetRange = idealBodyFatRange(for: sex)
        let ffmiStatus = descriptiveFFMIStatus(ffmi, sex: sex)
        let config = config(for: sex)

        let leannessScore = leannessScore(for: bodyFat, config: config)
        let muscleBonus = muscleBonus(ffmi: ffmi, bodyFat: bodyFat, config: config)
        let aggregate = leannessScore + muscleBonus
        let finalScore = Int(round(clamp(aggregate, min: 1, max: 100)))

        return BodyScoreResult(
            score: finalScore,
            ffmi: round(ffmi * 10) / 10,
            leanPercentile: round(percentile * 10) / 10,
            ffmiStatus: ffmiStatus,
            targetBodyFat: targetRange,
            statusTagline: statusTagline(for: finalScore)
        )
    }

    private func calculateFFMI(weightKg: Double, bodyFatPercentage: Double, heightCm: Double) -> Double {
        let heightM = heightCm / 100.0
        let leanMassKg = weightKg * (1 - bodyFatPercentage / 100)
        return (leanMassKg / (heightM * heightM)) + 6.1 * (1.8 - heightM)
    }

    private func idealBodyFatRange(for sex: BiologicalSex) -> BodyScoreResult.TargetRange {
        switch sex {
        case .male:
            let range = Constants.BodyComposition.BodyFat.maleOptimalRange
            return .init(lowerBound: range.lowerBound, upperBound: range.upperBound, label: "Lean")
        case .female:
            let range = Constants.BodyComposition.BodyFat.femaleOptimalRange
            return .init(lowerBound: range.lowerBound, upperBound: range.upperBound, label: "Lean")
        }
    }

    private func leannessScore(for bodyFat: Double, config: BodyScoreConfig) -> Double {
        interpolatedValue(for: bodyFat, points: config.leannessPoints.map { ($0.bodyFat, $0.score) })
    }

    private func muscleBonus(ffmi: Double, bodyFat: Double, config: BodyScoreConfig) -> Double {
        guard config.ffmiGoal > config.ffmiBaseline else { return 0 }

        let clampedFFMI = clamp(ffmi, min: config.ffmiBaseline, max: config.ffmiCeiling)
        let normalized = (clampedFFMI - config.ffmiBaseline) / (config.ffmiGoal - config.ffmiBaseline)
        let boundedNormalized = clamp(normalized, min: 0, max: 1)

        let ffmiExponent: Double = 0.7
        let muscleFraction = pow(boundedNormalized, ffmiExponent)
        let muscleMaxBonus: Double = 10
        let rawBonus = muscleMaxBonus * muscleFraction

        let gate = visibilityGate(for: bodyFat, config: config)
        return rawBonus * gate
    }

    private func visibilityGate(for bodyFat: Double, config: BodyScoreConfig) -> Double {
        interpolatedValue(for: bodyFat, points: config.visibilityPoints.map { ($0.bodyFat, $0.gate) })
    }

    private func interpolatedValue(for bodyFat: Double, points: [(bodyFat: Double, value: Double)]) -> Double {
        let sortedPoints = points.sorted { $0.bodyFat < $1.bodyFat }

        guard let first = sortedPoints.first, let last = sortedPoints.last else {
            return 0
        }

        if bodyFat <= first.bodyFat {
            return first.value
        }

        if bodyFat >= last.bodyFat {
            return last.value
        }

        for index in 0..<(sortedPoints.count - 1) {
            let start = sortedPoints[index]
            let end = sortedPoints[index + 1]
            if bodyFat >= start.bodyFat, bodyFat <= end.bodyFat {
                let fraction = (bodyFat - start.bodyFat) / (end.bodyFat - start.bodyFat)
                return start.value + fraction * (end.value - start.value)
            }
        }

        return last.value
    }

    private func config(for sex: BiologicalSex) -> BodyScoreConfig {
        switch sex {
        case .male:
            return BodyScoreConfig(
                leannessPoints: [
                    .init(bodyFat: 35, score: 0),
                    .init(bodyFat: 30, score: 20),
                    .init(bodyFat: 25, score: 30),
                    .init(bodyFat: 20, score: 45),
                    .init(bodyFat: 18, score: 55),
                    .init(bodyFat: 15, score: 70),
                    .init(bodyFat: 13, score: 80),
                    .init(bodyFat: 11, score: 86),
                    .init(bodyFat: 9, score: 90),
                    .init(bodyFat: 8, score: 90),
                    .init(bodyFat: 7, score: 88),
                    .init(bodyFat: 6, score: 85)
                ],
                visibilityPoints: [
                    .init(bodyFat: 35, gate: 0),
                    .init(bodyFat: 30, gate: 0),
                    .init(bodyFat: 25, gate: 0),
                    .init(bodyFat: 20, gate: 0.2),
                    .init(bodyFat: 17, gate: 0.4),
                    .init(bodyFat: 15, gate: 0.5),
                    .init(bodyFat: 13, gate: 0.7),
                    .init(bodyFat: 11, gate: 0.85),
                    .init(bodyFat: 9, gate: 1),
                    .init(bodyFat: 8, gate: 1),
                    .init(bodyFat: 7, gate: 0.9),
                    .init(bodyFat: 6, gate: 0.7)
                ],
                ffmiBaseline: 17,
                ffmiGoal: Constants.BodyComposition.FFMI.maleIdealValue,
                ffmiCeiling: Constants.BodyComposition.FFMI.maleOptimalRange.upperBound + 1
            )
        case .female:
            return BodyScoreConfig(
                leannessPoints: [
                    .init(bodyFat: 45, score: 0),
                    .init(bodyFat: 40, score: 15),
                    .init(bodyFat: 35, score: 25),
                    .init(bodyFat: 30, score: 35),
                    .init(bodyFat: 28, score: 45),
                    .init(bodyFat: 25, score: 60),
                    .init(bodyFat: 23, score: 75),
                    .init(bodyFat: 21, score: 85),
                    .init(bodyFat: 20, score: 90),
                    .init(bodyFat: 19, score: 90),
                    .init(bodyFat: 18, score: 88),
                    .init(bodyFat: 17, score: 85)
                ],
                visibilityPoints: [
                    .init(bodyFat: 45, gate: 0),
                    .init(bodyFat: 40, gate: 0),
                    .init(bodyFat: 35, gate: 0),
                    .init(bodyFat: 30, gate: 0.2),
                    .init(bodyFat: 28, gate: 0.3),
                    .init(bodyFat: 26, gate: 0.5),
                    .init(bodyFat: 24, gate: 0.7),
                    .init(bodyFat: 22, gate: 0.85),
                    .init(bodyFat: 20, gate: 1),
                    .init(bodyFat: 19, gate: 1),
                    .init(bodyFat: 18, gate: 0.9),
                    .init(bodyFat: 17, gate: 0.7)
                ],
                ffmiBaseline: 15,
                ffmiGoal: Constants.BodyComposition.FFMI.femaleIdealValue,
                ffmiCeiling: Constants.BodyComposition.FFMI.femaleOptimalRange.upperBound + 1
            )
        }
    }

    private struct BodyScoreConfig {
        struct LeannessPoint {
            let bodyFat: Double
            let score: Double
        }

        struct VisibilityPoint {
            let bodyFat: Double
            let gate: Double
        }

        let leannessPoints: [LeannessPoint]
        let visibilityPoints: [VisibilityPoint]
        let ffmiBaseline: Double
        let ffmiGoal: Double
        let ffmiCeiling: Double
    }

    private func calculateLeanPercentile(sex: BiologicalSex, age: Int?, bodyFat: Double) -> Double {
        let malePoints: [(bodyFat: Double, value: Double)] = [
            (8, 99),
            (10, 97),
            (12, 94),
            (14, 90),
            (16, 82),
            (18, 75),
            (20, 65),
            (22, 55),
            (25, 40),
            (28, 25),
            (32, 10),
            (36, 3)
        ]

        let femalePoints: [(bodyFat: Double, value: Double)] = [
            (16, 99),
            (18, 97),
            (20, 94),
            (22, 90),
            (24, 82),
            (26, 75),
            (28, 65),
            (30, 55),
            (34, 40),
            (38, 25),
            (42, 10),
            (46, 3)
        ]

        let points = sex == .male ? malePoints : femalePoints
        let basePercentile = interpolatedValue(for: bodyFat, points: points)
        let ageAdjustment: Double

        if let age {
            switch age {
            case ..<25:
                ageAdjustment = 4
            case 25..<40:
                ageAdjustment = 0
            case 40..<55:
                ageAdjustment = -3
            default:
                ageAdjustment = -6
            }
        } else {
            ageAdjustment = 0
        }

        return clamp(basePercentile + ageAdjustment, min: 1, max: 99)
    }

    private func descriptiveFFMIStatus(_ ffmi: Double, sex: BiologicalSex) -> String {
        switch sex {
        case .male:
            switch ffmi {
            case ..<18: return "Developing"
            case 18..<20: return "Solid base"
            case 20..<22.5: return "Athletic"
            case 22.5..<25: return "Advanced"
            default: return "Elite"
            }
        case .female:
            switch ffmi {
            case ..<13: return "Developing"
            case 13..<15: return "Solid base"
            case 15..<17: return "Athletic"
            case 17..<19: return "Advanced"
            default: return "Elite"
            }
        }
    }

    private func statusTagline(for score: Int) -> String {
        switch score {
        case 85...100: return "Dialing it in."
        case 75..<85: return "Solid base. Room to tighten up."
        case 65..<75: return "Good starting point. Big upside."
        default: return "Early in the journey. Huge upside."
        }
    }

    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
