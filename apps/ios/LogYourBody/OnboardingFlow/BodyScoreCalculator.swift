import Foundation

/// Calculates the Body Score using light-weight heuristics so the app can deliver
/// an instant dopamine hit before account creation. The formulas intentionally lean
/// optimistic while still respecting FFMI math and known body fat ranges.
struct BodyScoreCalculator {
    struct Input {
        enum Sex: String, CaseIterable, Identifiable {
            case male = "Male"
            case female = "Female"
            case other = "Other"

            var id: String { rawValue }
        }

        var sex: Sex
        var birthYear: Int
        var heightInches: Double
        var weightPounds: Double
        var bodyFatPercentage: Double
    }

    struct Result: Equatable {
        let score: Int
        let leanPercentile: Int
        let ffmi: Double
        let ffmiStatus: String
        let targetBodyFatRange: String
        let targetLabel: String
        let tagline: String

        var scoreDisplay: String { "\(score) / 100" }
    }

    func calculate(input: Input) -> Result {
        let ffmiValue = computeFFMI(heightInches: input.heightInches, weightPounds: input.weightPounds, bodyFat: input.bodyFatPercentage)
        let ffmiStatus = describeFFMI(ffmiValue, sex: input.sex)

        // Normalize leanness percentile. Younger users and lower BF push percentile up.
        let age = max(18, min(70, currentYear - input.birthYear))
        let leanPercentile = percentile(for: input.bodyFatPercentage, sex: input.sex, age: age)

        // Blend FFMI and leanness into a single 0-100 score.
        let leannessScore = Double(leanPercentile)
        let ffmiScore = normalizeFFMIScore(ffmiValue, sex: input.sex)
        let composite = (leannessScore * 0.55) + (ffmiScore * 0.45)
        let clampedScore = max(40, min(99, Int(round(composite))))

        let (targetRange, targetLabel) = targetBodyFat(for: input.sex, current: input.bodyFatPercentage)
        let tagline = tagline(for: clampedScore)

        return Result(
            score: clampedScore,
            leanPercentile: leanPercentile,
            ffmi: ffmiValue,
            ffmiStatus: ffmiStatus,
            targetBodyFatRange: targetRange,
            targetLabel: targetLabel,
            tagline: tagline
        )
    }

    // MARK: - Private helpers

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func computeFFMI(heightInches: Double, weightPounds: Double, bodyFat: Double) -> Double {
        let heightCm = heightInches * 2.54
        let weightKg = weightPounds * 0.453592
        guard heightCm > 0 else { return 0 }
        let leanMassKg = weightKg * (1 - (bodyFat / 100))
        let heightMeters = heightCm / 100
        guard heightMeters > 0 else { return 0 }
        let ffmi = leanMassKg / (heightMeters * heightMeters)
        return (ffmi + (6.1 * (1.8 - heightMeters))).rounded(toPlaces: 1)
    }

    private func describeFFMI(_ ffmi: Double, sex: Input.Sex) -> String {
        let thresholds: [Double]
        switch sex {
        case .female:
            thresholds = [15.5, 17.5, 18.5, 20.0, 21.5]
        case .male, .other:
            thresholds = [17.5, 19.0, 20.5, 22.0, 24.0]
        }

        switch ffmi {
        case ..<thresholds[0]: return "Below average for your height"
        case ..<thresholds[1]: return "Starting to build a base"
        case ..<thresholds[2]: return "Solid development"
        case ..<thresholds[3]: return "Athletic frame"
        case ..<thresholds[4]: return "Dialed-in musculature"
        default: return "Elite FFMI for natural lifters"
        }
    }

    private func percentile(for bodyFat: Double, sex: Input.Sex, age: Int) -> Int {
        // Base percentile by BF%. Lower BF => higher percentile.
        let normalizedBF = max(4, min(50, bodyFat))
        let base: Double
        switch sex {
        case .female:
            base = 100 - ((normalizedBF - 12) * 2.1)
        case .male:
            base = 100 - ((normalizedBF - 6) * 2.6)
        case .other:
            base = 100 - ((normalizedBF - 8) * 2.3)
        }

        // Age adjustments. Older users get a slight boost for the same BF.
        let ageAdjustment = Double(max(0, age - 30)) * 0.25
        let percentile = max(1, min(99, Int(round(base + ageAdjustment))))
        return percentile
    }

    private func normalizeFFMIScore(_ ffmi: Double, sex: Input.Sex) -> Double {
        // Map FFMI roughly onto a 40-100 range.
        let minFFMI: Double
        let idealFFMI: Double
        let eliteFFMI: Double

        switch sex {
        case .female:
            minFFMI = 14
            idealFFMI = 18.5
            eliteFFMI = 21.5
        case .male, .other:
            minFFMI = 16
            idealFFMI = 21.0
            eliteFFMI = 24.5
        }

        if ffmi <= minFFMI { return 40 }
        if ffmi >= eliteFFMI { return 100 }

        if ffmi <= idealFFMI {
            let progress = (ffmi - minFFMI) / (idealFFMI - minFFMI)
            return 60 + (progress * 25)
        } else {
            let progress = (ffmi - idealFFMI) / (eliteFFMI - idealFFMI)
            return 85 + (progress * 15)
        }
    }

    private func targetBodyFat(for sex: Input.Sex, current: Double) -> (range: String, label: String) {
        switch sex {
        case .female:
            if current <= 18 { return ("15–18%", "cover model lean") }
            if current <= 24 { return ("18–22%", "fit and defined") }
            if current <= 30 { return ("22–26%", "athletic shape") }
            return ("24–28%", "toned silhouette")
        case .male, .other:
            if current <= 10 { return ("8–11%", "stage-sharp") }
            if current <= 15 { return ("10–13%", "photo-ready") }
            if current <= 22 { return ("12–16%", "dialed-in") }
            return ("14–18%", "lean and aesthetic")
        }
    }

    private func tagline(for score: Int) -> String {
        switch score {
        case 90...: return "Borderline superhero." 
        case 80..<90: return "Dialing it in."
        case 70..<80: return "Solid base. Room to tighten up."
        case 60..<70: return "Good starting point. Big upside."
        default: return "You’re earlier in the journey, but the upside is huge."
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
