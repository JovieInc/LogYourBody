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

    static var localeDefault: WeightUnit {
        MeasurementSystem.localeDefault == .metric ? .kilograms : .pounds
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

    static var localeDefault: HeightUnit {
        MeasurementSystem.localeDefault == .metric ? .centimeters : .inches
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
    /// A DEXA or InBody report imported during onboarding.
    case scan
    case unspecified

    var id: String { rawValue }
}

struct HeightValue: Codable, Equatable {
    var value: Double?
    var unit: HeightUnit

    init(value: Double? = nil, unit: HeightUnit = .localeDefault) {
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

    init(value: Double? = nil, unit: WeightUnit = .localeDefault) {
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
        measurementPreference: MeasurementSystem = .localeDefault,
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
    struct ReferenceRange: Equatable {
        let lowerBound: Double
        let upperBound: Double
        let label: String
    }

    let score: Int
    let ffmi: Double
    let leanPercentile: Double
    let ffmiStatus: String
    let bodyFatReferenceRange: ReferenceRange
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


/// The DEXA or InBody scans imported during onboarding, reduced to what the
/// first-run reveal needs: the latest reading, plus the scan before it so the
/// reveal can say whether fat or lean mass changed.
struct OnboardingScanImport: Equatable {
    struct Reading: Equatable {
        let date: Date
        let weightKg: Double
        let bodyFatPercentage: Double?

        var fatKg: Double? {
            bodyFatPercentage.map { weightKg * $0 / 100 }
        }

        var leanKg: Double? {
            fatKg.map { weightKg - $0 }
        }
    }

    let latest: Reading
    /// The most recent earlier scan that has body fat, when the latest one does too.
    let previous: Reading?

    init?(scans: [DexaPDFScan]) {
        let readings = scans.compactMap(Self.reading(from:)).sorted { $0.date < $1.date }
        guard let latest = readings.last else { return nil }
        self.latest = latest
        previous = latest.bodyFatPercentage == nil
            ? nil
            : readings.dropLast().last { $0.bodyFatPercentage != nil }
    }

    init(latest: Reading, previous: Reading?) {
        self.latest = latest
        self.previous = previous
    }

    private static func reading(from scan: DexaPDFScan) -> Reading? {
        guard let date = scanDateFormatter.date(from: scan.date),
              let weightKg = weightInKilograms(scan.weight, unit: scan.weightUnit),
              weightKg > 0 else {
            return nil
        }
        let bodyFat = scan.bodyFatPercentage.flatMap { $0 > 0 && $0 < 100 ? $0 : nil }
        return Reading(date: date, weightKg: weightKg, bodyFatPercentage: bodyFat)
    }

    static func weightInKilograms(_ value: Double, unit: String) -> Double? {
        switch unit.lowercased().trimmingCharacters(in: .whitespaces) {
        case "kg", "kgs", "kilograms":
            return value
        case "lb", "lbs", "pounds":
            return value * 0.45359237
        default:
            return nil
        }
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// "Since Mar 3: 4 lb less fat, 1 lb more lean mass." The answer to "am I
/// losing fat or muscle?" for someone who brings two scans.
enum ScanChangePolicy {
    static func changeText(for scanImport: OnboardingScanImport, system: MeasurementSystem) -> String? {
        guard let previous = scanImport.previous,
              let previousFat = previous.fatKg, let previousLean = previous.leanKg,
              let latestFat = scanImport.latest.fatKg, let latestLean = scanImport.latest.leanKg else {
            return nil
        }
        let factor = system == .metric ? 1 : 2.20462
        let unit = system == .metric ? "kg" : "lb"
        let fatChange = ((latestFat - previousFat) * factor).rounded()
        let leanChange = ((latestLean - previousLean) * factor).rounded()

        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let since = dateFormatter.string(from: previous.date)

        return "Since \(since): \(phrase(fatChange, unit: unit, noun: "fat")), "
            + "\(phrase(leanChange, unit: unit, noun: "lean mass"))."
    }

    private static func phrase(_ change: Double, unit: String, noun: String) -> String {
        if change == 0 { return "\(noun) about the same" }
        let amount = String(format: "%.0f", abs(change))
        return "\(amount) \(unit) \(change < 0 ? "less" : "more") \(noun)"
    }
}
