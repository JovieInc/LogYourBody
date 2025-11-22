import Foundation

// Note: MeasurementSystem is defined globally in PreferencesView.swift

enum WeightUnit: String, Codable, CaseIterable, CustomStringConvertible {
    case kilograms = "kg"
    case pounds = "lbs"

    var measurementSystem: MeasurementSystem {
        switch self {
        case .kilograms:
            return .metric
        case .pounds:
            return .imperial
        }
    }

    var description: String {
        switch self {
        case .kilograms:
            return "KG"
        case .pounds:
            return "LBS"
        }
    }
}

enum HeightUnit: String, Codable, CaseIterable, CustomStringConvertible {
    case centimeters = "cm"
    case inches = "in" // Stored as total inches for simplicity

    var measurementSystem: MeasurementSystem {
        switch self {
        case .centimeters:
            return .metric
        case .inches:
            return .imperial
        }
    }

    var description: String {
        switch self {
        case .centimeters:
            return "CM"
        case .inches:
            return "FT/IN"
        }
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable, CustomStringConvertible {
    case male
    case female

    var id: String { rawValue }

    var description: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

enum BodyFatInputSource: String, Codable, CaseIterable, Identifiable {
    case healthKit
    case manualValue
    case visualEstimate
    case unspecified

    var id: String { rawValue }
}

struct HeightValue: Codable, Equatable {
    var value: Double?
    var unit: HeightUnit

    init(value: Double? = nil, unit: HeightUnit = .inches) {
        self.value = value
        self.unit = unit
    }

    var inCentimeters: Double? {
        guard let value else { return nil }
        switch unit {
        case .centimeters:
            return value
        case .inches:
            return value * 2.54
        }
    }

    var inInches: Double? {
        guard let value else { return nil }
        switch unit {
        case .centimeters:
            return value / 2.54
        case .inches:
            return value
        }
    }
}

struct WeightValue: Codable, Equatable {
    var value: Double?
    var unit: WeightUnit

    init(value: Double? = nil, unit: WeightUnit = .pounds) {
        self.value = value
        self.unit = unit
    }

    var inKilograms: Double? {
        guard let value else { return nil }
        switch unit {
        case .kilograms:
            return value
        case .pounds:
            return value * 0.45359237
        }
    }

    var inPounds: Double? {
        guard let value else { return nil }
        switch unit {
        case .kilograms:
            return value * 2.2046226218
        case .pounds:
            return value
        }
    }
}

struct BodyFatValue: Codable, Equatable {
    var percentage: Double?
    var source: BodyFatInputSource

    init(percentage: Double? = nil, source: BodyFatInputSource = .unspecified) {
        self.percentage = percentage
        self.source = source
    }
}

struct HealthImportSnapshot: Codable, Equatable {
    var heightCm: Double?
    var weightKg: Double?
    var bodyFatPercentage: Double?
    var birthYear: Int?
    var heightDate: Date?
    var weightDate: Date?
    var bodyFatDate: Date?

    var hasAnyValue: Bool {
        heightCm != nil || weightKg != nil || bodyFatPercentage != nil || birthYear != nil
    }
}

struct BodyScoreInput: Codable, Equatable {
    var sex: BiologicalSex?
    var birthYear: Int?
    var height: HeightValue
    var weight: WeightValue
    var bodyFat: BodyFatValue
    var measurementPreference: MeasurementSystem
    var healthSnapshot: HealthImportSnapshot

    init(
        sex: BiologicalSex? = nil,
        birthYear: Int? = nil,
        height: HeightValue = HeightValue(),
        weight: WeightValue = WeightValue(),
        bodyFat: BodyFatValue = BodyFatValue(),
        measurementPreference: MeasurementSystem = .imperial,
        healthSnapshot: HealthImportSnapshot = HealthImportSnapshot()
    ) {
        self.sex = sex
        self.birthYear = birthYear
        self.height = height
        self.weight = weight
        self.bodyFat = bodyFat
        self.measurementPreference = measurementPreference
        self.healthSnapshot = healthSnapshot
    }

    var age: Int? {
        guard let birthYear else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        return max(0, currentYear - birthYear)
    }

    var isReadyForCalculation: Bool {
        sex != nil && height.inCentimeters != nil && weight.inKilograms != nil && bodyFat.percentage != nil
    }
}

struct BodyScoreResult: Equatable {
    struct TargetRange: Equatable {
        let lowerBound: Double
        let upperBound: Double
        let label: String
    }

    let score: Int
    let ffmi: Double
    let leanPercentile: Double
    let ffmiStatus: String
    let targetBodyFat: TargetRange
    let statusTagline: String
}

struct BodyScoreCalculationContext {
    let input: BodyScoreInput
    let calculationDate: Date

    init(input: BodyScoreInput, calculationDate: Date = Date()) {
        self.input = input
        self.calculationDate = calculationDate
    }
}

enum BodyScoreCalculationError: LocalizedError {
    case missingRequiredInputs

    var errorDescription: String? {
        switch self {
        case .missingRequiredInputs:
            return "Missing required metrics to calculate Body Score."
        }
    }
}
