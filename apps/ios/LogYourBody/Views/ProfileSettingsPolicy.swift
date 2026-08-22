//
// ProfileSettingsPolicy.swift
// LogYourBody
//
import Foundation

/// Shared profile-name, height, and age formatting used by settings tests
/// and any remaining profile-editor surfaces.
///
/// Production profile editing lives in `PreferencesView` sheets. The old
/// `ProfileSettingsViewV2` screen was unused and has been removed.
enum ProfileSettingsPolicy {
    /// Joins first/last names into a display name, trimming blanks and dropping empty parts.
    static func joinedDisplayName(first: String, last: String) -> String {
        let trimmedFirst = first.trimmingCharacters(in: .whitespaces)
        let trimmedLast = last.trimmingCharacters(in: .whitespaces)
        return [trimmedFirst, trimmedLast]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Base string used to prefill the name fields: the stored display name, or the email local-part.
    static func displayNameBase(name: String, email: String) -> String {
        if !name.isEmpty {
            return name
        }
        return email.components(separatedBy: "@").first ?? ""
    }

    /// Splits a display name into (first, last); everything after the first word becomes the last name.
    static func splitDisplayName(_ base: String) -> (first: String, last: String) {
        let parts = base.split(separator: " ")
        let first = parts.first.map { String($0) } ?? ""
        let last = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        return (first, last)
    }

    /// Formats a height stored in cm for the profile row and picker sheet display.
    static func formattedHeight(heightCm: Int, useMetric: Bool) -> String {
        if useMetric {
            return "\(heightCm) cm"
        }
        let totalInches = Int(Double(heightCm) / 2.54)
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }

    /// Formats the age row label from a date of birth.
    static func formattedAge(dateOfBirth: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let age = calendar.dateComponents([.year], from: dateOfBirth, to: now).year ?? 0
        return age > 0 ? "\(age) years" : "Not set"
    }

    /// Imperial wheel components for a height stored in cm.
    static func imperialHeightComponents(heightCm: Int) -> (feet: Int, inches: Int) {
        let totalInches = Double(heightCm) / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        return (feet, inches)
    }

    /// Height in cm from imperial wheel components.
    static func heightCm(feet: Int, inches: Int) -> Int {
        Int((Double(feet) * 12 + Double(inches)) * 2.54)
    }
}
