//
// DashboardView+Calculations.swift
// LogYourBody
//
import Foundation
import SwiftUI

extension DashboardView {
    // MARK: - Weight Conversions

    private var currentMeasurementSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }

    func convertWeight(_ weight: Double?, to system: MeasurementSystem) -> Double? {
        guard let weight = weight else { return nil }

        // Weight is ALWAYS stored in kg in the database
        switch system {
        case .metric:
            // Already in kg
            return weight
        case .imperial:
            // Convert kg to lbs
            return weight * 2.20462
        }
    }

    func formatWeight(_ weight: Double?) -> String {
        guard let weight = weight else { return "N/A" }

        let system = currentMeasurementSystem
        let convertedWeight = convertWeight(weight, to: system) ?? weight
        let unit = system.weightUnit

        return String(format: "%.1f %@", convertedWeight, unit)
    }

    // MARK: - Body Composition Calculations

    /// Convert height to inches regardless of stored unit
    func convertHeightToInches(height: Double?, heightUnit: String?) -> Double? {
        guard let height = height else { return nil }

        if heightUnit == "cm" {
            return height / 2.54  // Convert cm to inches
        } else {
            return height  // Already in inches
        }
    }

    func calculateLeanMass(weight: Double?, bodyFat: Double?) -> Double? {
        guard let weight = weight, let bodyFat = bodyFat else { return nil }
        return weight * (1 - bodyFat / 100)
    }

    func calculateFFMI(weight: Double?, bodyFat: Double?, heightInches: Double?) -> Double? {
        guard let weight = weight,
              let bodyFat = bodyFat,
              let heightInches = heightInches else {
            return nil
        }

        // Weight is already in kg from database
        let heightMeters = heightInches * 0.0254
        let leanMassKg = weight * (1 - bodyFat / 100)

        // FFMI = lean mass (kg) / height (m)^2
        return leanMassKg / (heightMeters * heightMeters)
    }

    // MARK: - Health Ranges

    func getBodyFatColor(bodyFat: Double?, gender: String?) -> Color {
        guard let bodyFat = bodyFat else { return .gray }

        // Gender-specific body fat % ranges
        let isMale = gender?.lowercased() == "male"

        if isMale {
            switch bodyFat {
            case ..<6: return .blue // Essential fat
            case 6..<14: return .green // Athletes
            case 14..<18: return .cyan // Fitness
            case 18..<25: return .yellow // Average
            default: return .red // Above average
            }
        } else {
            switch bodyFat {
            case ..<14: return .blue // Essential fat
            case 14..<21: return .green // Athletes
            case 21..<25: return .cyan // Fitness
            case 25..<32: return .yellow // Average
            default: return .red // Above average
            }
        }
    }

    func getOptimalBodyFatRange(gender: String?) -> String {
        let isMale = gender?.lowercased() == "male"
        return isMale ? "14-18%" : "21-25%"
    }

    func isInHealthyWeightRange(weight: Double?, heightInches: Double?) -> Bool {
        guard let weight = weight, let heightInches = heightInches else {
            return false
        }

        // Calculate BMI - weight is already in kg from database
        let heightMeters = heightInches * 0.0254
        let bmi = weight / (heightMeters * heightMeters)

        // Healthy BMI range: 18.5 - 24.9
        return bmi >= 18.5 && bmi <= 24.9
    }

    // MARK: - Formatting Helpers

    func formatHeightToFeetInches(_ heightInches: Double?) -> String {
        guard let heightInches = heightInches else { return "N/A" }

        let system = currentMeasurementSystem

        if system == .metric {
            let cm = heightInches * 2.54
            return String(format: "%.0f cm", cm)
        } else {
            let feet = Int(heightInches / 12)
            let inches = Int(heightInches.truncatingRemainder(dividingBy: 12))
            return "\(feet)'\(inches)\""
        }
    }
}
