//
// ValidationService.swift
// LogYourBody
//
import Foundation

enum ValidationError: LocalizedError {
    case invalidWeight(String)
    case invalidBodyFat(String)
    case invalidHeight(String)

    var errorDescription: String? {
        switch self {
        case .invalidWeight(let message):
            return message
        case .invalidBodyFat(let message):
            return message
        case .invalidHeight(let message):
            return message
        }
    }
}

final class ValidationService {
    static let shared = ValidationService()

    private init() {}

    func validateWeight(_ value: String, unit: String) throws -> Double {
        let sanitized = sanitizeNumericValue(value)

        guard !sanitized.isEmpty, let weight = Double(sanitized) else {
            throw ValidationError.invalidWeight("Please enter a valid number")
        }

        let range = weightRange(for: unit)
        guard range.contains(weight) else {
            throw ValidationError.invalidWeight("Weight must be between \(Int(range.lowerBound))-\(Int(range.upperBound)) \(unit)")
        }

        return roundedToOneDecimal(weight)
    }

    func validateBodyFat(_ value: String) throws -> Double {
        let sanitized = sanitizeNumericValue(value)

        guard !sanitized.isEmpty, let bodyFat = Double(sanitized) else {
            throw ValidationError.invalidBodyFat("Please enter a valid percentage")
        }

        let range = 3.0...50.0
        guard range.contains(bodyFat) else {
            throw ValidationError.invalidBodyFat("Body fat must be between \(Int(range.lowerBound))-\(Int(range.upperBound))%")
        }

        return roundedToOneDecimal(bodyFat)
    }

    func validateHeight(_ value: String, unit: String) throws -> Double {
        let sanitized = sanitizeNumericValue(value)

        guard !sanitized.isEmpty, let height = Double(sanitized) else {
            throw ValidationError.invalidHeight("Please enter a valid height")
        }

        let range = heightRange(for: unit)
        guard range.contains(height) else {
            throw ValidationError.invalidHeight("Height must be between \(Int(range.lowerBound))-\(Int(range.upperBound)) \(unit)")
        }

        return roundedToOneDecimal(height)
    }

    // MARK: - Helpers

    private func sanitizeNumericValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: "[^0-9.]",
            with: "",
            options: .regularExpression,
            range: nil
        )
    }

    private func weightRange(for unit: String) -> ClosedRange<Double> {
        switch unit.lowercased() {
        case "lbs":
            return 44...1_100
        default:
            return 20...500
        }
    }

    private func heightRange(for unit: String) -> ClosedRange<Double> {
        switch unit.lowercased() {
        case "ft":
            return 3...8
        default:
            return 90...250
        }
    }

    private func roundedToOneDecimal(_ value: Double) -> Double {
        round(value * 10) / 10
    }
}
