//
// User.swift
// LogYourBody
//
import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    var name: String?
    var avatarUrl: String?
    var profile: UserProfile?
    var onboardingCompleted: Bool = false

    var displayName: String {
        name ?? email.components(separatedBy: "@").first ?? "User"
    }
}

struct UserProfile: Codable {
    let id: String?
    let email: String?
    let username: String?
    let fullName: String?
    let dateOfBirth: Date?
    let height: Double?
    let heightUnit: String?
    let gender: String?
    let activityLevel: String?
    let goalWeight: Double?
    let goalWeightUnit: String?
    let onboardingCompleted: Bool?

    var age: Int? {
        guard let dateOfBirth = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case height
        case heightUnit = "height_unit"
        case gender
        case activityLevel = "activity_level"
        case goalWeight = "goal_weight"
        case goalWeightUnit = "goal_weight_unit"
        case onboardingCompleted = "onboarding_completed"
    }
}
