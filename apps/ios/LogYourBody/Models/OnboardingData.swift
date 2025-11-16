//
// OnboardingData.swift
// LogYourBody
//
import Foundation

struct OnboardingData {
    var name: String = ""
    var dateOfBirth: Date?
    var heightFeet: Int = 5
    var heightInches: Int = 8
    var gender: Gender? = .male  // Default to male
    var bodyFatPercentage: Double?
    var notificationsEnabled: Bool = false
    var healthKitEnabled: Bool = false
    var hasUploadedPhotos: Bool = false
    
    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
        
        var icon: String {
            switch self {
            case .male: return "♂"
            case .female: return "♀"
            }
        }
    }
    
    var totalHeightInInches: Int {
        return (heightFeet * 12) + heightInches
    }
    
    var isProfileComplete: Bool {
        return !name.isEmpty && dateOfBirth != nil && gender != nil
    }

    var firstName: String {
        get {
            let parts = name.split(separator: " ")
            return parts.first.map { String($0) } ?? ""
        }
        set {
            let last = lastName
            let combined = [newValue, last]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            name = combined
        }
    }

    var lastName: String {
        get {
            let parts = name.split(separator: " ")
            guard parts.count > 1 else { return "" }
            return parts.dropFirst().joined(separator: " ")
        }
        set {
            let first = firstName
            let combined = [first, newValue]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            name = combined
        }
    }
}
