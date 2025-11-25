//
// UnitConversion.swift
// LogYourBody
//
// Centralized unit conversion utilities
// Single source of truth for metric/imperial conversions
//

import Foundation

enum MeasurementSystem: String, Codable, CaseIterable {
    case imperial = "Imperial"
    case metric = "Metric"

    var weightUnit: String {
        switch self {
        case .imperial:
            return "lbs"
        case .metric:
            return "kg"
        }
    }

    var heightUnit: String {
        switch self {
        case .imperial:
            return "ft"
        case .metric:
            return "cm"
        }
    }

    var heightDisplay: String {
        switch self {
        case .imperial:
            return "feet & inches"
        case .metric:
            return "centimeters"
        }
    }
}

// MARK: - Unit Conversion Helper

struct UnitConversion {
    // MARK: - Weight Conversions

    /// Convert weight from kg to lbs
    static func kgToLbs(_ kg: Double) -> Double {
        return kg * 2.20462
    }

    /// Convert weight from lbs to kg
    static func lbsToKg(_ lbs: Double) -> Double {
        return lbs / 2.20462
    }

    /// Format weight for display based on unit preference
    /// - Parameters:
    ///   - weightKg: Weight in kilograms (stored value)
    ///   - useMetric: If true, display in kg; if false, display in lbs
    /// - Returns: Formatted string with value and unit
    static func formatWeight(_ weightKg: Double, useMetric: Bool) -> (value: String, unit: String) {
        if useMetric {
            return (String(format: "%.1f", weightKg), "kg")
        } else {
            let lbs = kgToLbs(weightKg)
            return (String(format: "%.1f", lbs), "lbs")
        }
    }

    /// Get display weight value only (no unit)
    static func displayWeight(_ weightKg: Double, useMetric: Bool) -> Double {
        return useMetric ? weightKg : kgToLbs(weightKg)
    }

    // MARK: - Height Conversions

    /// Convert height from cm to feet and inches
    static func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Double) {
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = totalInches.truncatingRemainder(dividingBy: 12)
        return (feet, inches)
    }

    /// Convert feet and inches to cm
    static func feetInchesToCm(feet: Int, inches: Double) -> Double {
        let totalInches = Double(feet * 12) + inches
        return totalInches * 2.54
    }

    /// Format height for display based on unit preference
    /// - Parameters:
    ///   - heightCm: Height in centimeters (stored value)
    ///   - useMetric: If true, display in cm; if false, display in ft/in
    /// - Returns: Formatted string
    static func formatHeight(_ heightCm: Double, useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.1f cm", heightCm)
        } else {
            let (feet, inches) = cmToFeetInches(heightCm)
            return String(format: "%d'%.1f\"", feet, inches)
        }
    }

    // MARK: - Waist Conversions

    /// Convert waist from cm to inches
    static func cmToInches(_ cm: Double) -> Double {
        return cm / 2.54
    }

    /// Convert waist from inches to cm
    static func inchesToCm(_ inches: Double) -> Double {
        return inches * 2.54
    }

    /// Format waist for display based on unit preference
    /// - Parameters:
    ///   - waistCm: Waist in centimeters (stored value)
    ///   - useMetric: If true, display in cm; if false, display in inches
    /// - Returns: Formatted string with value and unit
    static func formatWaist(_ waistCm: Double, useMetric: Bool) -> (value: String, unit: String) {
        if useMetric {
            return (String(format: "%.1f", waistCm), "cm")
        } else {
            let inches = cmToInches(waistCm)
            return (String(format: "%.1f", inches), "in")
        }
    }

    /// Get display waist value only (no unit)
    static func displayWaist(_ waistCm: Double, useMetric: Bool) -> Double {
        return useMetric ? waistCm : cmToInches(waistCm)
    }

    // MARK: - Body Composition Calculations

    /// Calculate Fat Free Mass Index (FFMI)
    /// Formula: FFMI = (weight × (1 - body fat %)) / height² + 6.1 × (1.8 - height)
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - bodyFatPercentage: Body fat as percentage (0-100)
    ///   - heightCm: Height in centimeters
    /// - Returns: FFMI value, or nil if invalid inputs
    static func calculateFFMI(weightKg: Double, bodyFatPercentage: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, bodyFatPercentage > 0, bodyFatPercentage < 100, heightCm > 0 else {
            return nil
        }

        let heightM = heightCm / 100.0
        let fatFreeMassKg = weightKg * (1 - bodyFatPercentage / 100)
        let ffmi = (fatFreeMassKg / (heightM * heightM)) + 6.1 * (1.8 - heightM)
        return ffmi
    }

    /// Calculate lean body mass (fat-free mass)
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - bodyFatPercentage: Body fat as percentage (0-100)
    ///   - useMetric: If true, return kg; if false, return lbs
    /// - Returns: Lean mass in specified unit
    static func calculateLeanMass(weightKg: Double, bodyFatPercentage: Double, useMetric: Bool) -> Double? {
        guard weightKg > 0, bodyFatPercentage > 0, bodyFatPercentage < 100 else {
            return nil
        }

        let leanMassKg = weightKg * (1 - bodyFatPercentage / 100)
        return useMetric ? leanMassKg : kgToLbs(leanMassKg)
    }

    /// Calculate fat mass
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - bodyFatPercentage: Body fat as percentage (0-100)
    ///   - useMetric: If true, return kg; if false, return lbs
    /// - Returns: Fat mass in specified unit
    static func calculateFatMass(weightKg: Double, bodyFatPercentage: Double, useMetric: Bool) -> Double? {
        guard weightKg > 0, bodyFatPercentage > 0, bodyFatPercentage < 100 else {
            return nil
        }

        let fatMassKg = weightKg * (bodyFatPercentage / 100)
        return useMetric ? fatMassKg : kgToLbs(fatMassKg)
    }

    /// Calculate Body Mass Index (BMI)
    /// Formula: BMI = weight(kg) / height(m)²
    /// - Parameters:
    ///   - weightKg: Weight in kilograms
    ///   - heightCm: Height in centimeters
    /// - Returns: BMI value, or nil if invalid inputs
    static func calculateBMI(weightKg: Double, heightCm: Double) -> Double? {
        guard weightKg > 0, heightCm > 0 else {
            return nil
        }

        let heightM = heightCm / 100.0
        return weightKg / (heightM * heightM)
    }

    // MARK: - Number Formatting

    /// Format a numeric value with thousands separator
    /// - Parameter value: Integer value to format
    /// - Returns: Formatted string (e.g., "10,234")
    static func formatWithThousandsSeparator(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Format percentage value
    /// - Parameter percentage: Percentage value (0-100)
    /// - Returns: Formatted string with % symbol
    static func formatPercentage(_ percentage: Double) -> String {
        return String(format: "%.1f%%", percentage)
    }

    // MARK: - Unit String Helpers

    /// Get weight unit string based on preference
    static func weightUnit(useMetric: Bool) -> String {
        return useMetric ? "kg" : "lbs"
    }

    /// Get height unit string based on preference
    static func heightUnit(useMetric: Bool) -> String {
        return useMetric ? "cm" : "ft/in"
    }

    /// Get waist unit string based on preference
    static func waistUnit(useMetric: Bool) -> String {
        return useMetric ? "cm" : "in"
    }

    // MARK: - Validation

    /// Validate weight value is within reasonable range
    /// - Parameter weightKg: Weight in kilograms
    /// - Returns: True if valid (20-300 kg)
    static func isValidWeight(_ weightKg: Double) -> Bool {
        return weightKg >= 20 && weightKg <= 300
    }

    /// Validate height value is within reasonable range
    /// - Parameter heightCm: Height in centimeters
    /// - Returns: True if valid (100-250 cm)
    static func isValidHeight(_ heightCm: Double) -> Bool {
        return heightCm >= 100 && heightCm <= 250
    }

    /// Validate body fat percentage is within reasonable range
    /// - Parameter percentage: Body fat percentage (0-100)
    /// - Returns: True if valid (3-60%)
    static func isValidBodyFat(_ percentage: Double) -> Bool {
        return percentage >= 3 && percentage <= 60
    }

    /// Validate waist measurement is within reasonable range
    /// - Parameter waistCm: Waist in centimeters
    /// - Returns: True if valid (40-200 cm)
    static func isValidWaist(_ waistCm: Double) -> Bool {
        return waistCm >= 40 && waistCm <= 200
    }
}

// MARK: - Extensions for Convenience

extension MeasurementSystem {
    static func fromStored(rawValue: String?) -> MeasurementSystem {
        if let rawValue, let system = MeasurementSystem(rawValue: rawValue) {
            return system
        }
        return .imperial
    }

    static var preferredFromDefaults: MeasurementSystem {
        let rawValue = UserDefaults.standard.string(forKey: Constants.preferredMeasurementSystemKey)
        return fromStored(rawValue: rawValue)
    }
}

extension Double {
    /// Convert this value from kg to lbs
    var kgToLbs: Double {
        UnitConversion.kgToLbs(self)
    }

    /// Convert this value from lbs to kg
    var lbsToKg: Double {
        UnitConversion.lbsToKg(self)
    }

    /// Convert this value from cm to inches
    var cmToInches: Double {
        UnitConversion.cmToInches(self)
    }

    /// Convert this value from inches to cm
    var inchesToCm: Double {
        UnitConversion.inchesToCm(self)
    }
}
