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

        let bodyFatScore = scaledBodyFatScore(bodyFat, targetRange: targetRange)
        let ffmiScore = scaledFFMIScore(ffmi, sex: sex)
        let percentileScore = percentile

        let aggregate = (0.45 * bodyFatScore) + (0.4 * ffmiScore) + (0.15 * Double(percentileScore))
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
            return .init(lowerBound: 10, upperBound: 15, label: "Lean")
        case .female:
            return .init(lowerBound: 18, upperBound: 23, label: "Lean")
        case .other:
            return .init(lowerBound: 14, upperBound: 24, label: "Balanced")
        }
    }

    private func scaledBodyFatScore(_ value: Double, targetRange: BodyScoreResult.TargetRange) -> Double {
        let midpoint = (targetRange.lowerBound + targetRange.upperBound) / 2
        let deviation = abs(value - midpoint)
        let penalty = deviation * 4 // 0.5% deviation ≈ 2 points
        return clamp(100 - penalty, min: 0, max: 100)
    }

    private func scaledFFMIScore(_ ffmi: Double, sex: BiologicalSex) -> Double {
        let idealRange: ClosedRange<Double>
        switch sex {
        case .male:
            idealRange = 20...23
        case .female:
            idealRange = 14...17
        case .other:
            idealRange = 16...20
        }

        if ffmi >= idealRange.upperBound {
            return 100
        } else if ffmi <= idealRange.lowerBound - 4 {
            return 30
        }

        let span = idealRange.upperBound - (idealRange.lowerBound - 4)
        let normalized = (ffmi - (idealRange.lowerBound - 4)) / span
        return clamp(normalized * 100, min: 0, max: 100)
    }

    private func calculateLeanPercentile(sex: BiologicalSex, age: Int?, bodyFat: Double) -> Double {
        let baseline = sex == .male ? 12.0 : 20.0
        let diff = baseline - bodyFat
        let basePercentile = 50 + diff * 2.2
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
        case .other:
            switch ffmi {
            case ..<15: return "Developing"
            case 15..<17: return "Solid base"
            case 17..<19: return "Athletic"
            case 19..<21: return "Advanced"
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
