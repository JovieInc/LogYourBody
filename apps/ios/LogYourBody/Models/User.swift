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
    let firstName: String? = nil
    let lastName: String? = nil

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
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

enum ProfileHeightStorage {
    static func storedHeightValue(heightCm: Double, preferredUnit: String?) -> Double {
        switch preferredUnit?.lowercased() {
        case "in":
            return UnitConversion.cmToInches(heightCm)
        default:
            return heightCm
        }
    }

    static func heightCentimeters(storedHeight: Double?, preferredUnit: String?) -> Double? {
        guard let storedHeight, storedHeight > 0 else {
            return nil
        }

        switch preferredUnit?.lowercased() {
        case "in":
            return storedHeight >= 100 ? storedHeight : UnitConversion.inchesToCm(storedHeight)
        case "cm":
            return storedHeight < 100 ? UnitConversion.inchesToCm(storedHeight) : storedHeight
        default:
            return storedHeight >= 100 ? storedHeight : UnitConversion.inchesToCm(storedHeight)
        }
    }
}

enum ProfileUpdateMerge {
    static func updatedUser(_ user: User, updates: [String: Any]) -> User {
        var updatedUser = user
        let existingProfile = user.profile

        let updatedName = nonEmptyString(
            from: updates,
            keys: ["name", "fullName", "full_name"]
        ) ?? user.name
        let updatedOnboardingCompleted = bool(
            from: updates,
            keys: ["onboardingCompleted", "onboarding_completed"]
        ) ?? existingProfile?.onboardingCompleted

        let mergedProfile = UserProfile(
            id: existingProfile?.id ?? user.id,
            email: existingProfile?.email ?? user.email,
            username: string(from: updates, keys: ["username"]) ?? existingProfile?.username,
            fullName: nonEmptyString(
                from: updates,
                keys: ["fullName", "full_name", "name"]
            ) ?? existingProfile?.fullName ?? updatedName,
            dateOfBirth: date(
                from: updates,
                keys: ["dateOfBirth", "date_of_birth"]
            ) ?? existingProfile?.dateOfBirth,
            height: double(from: updates, keys: ["height"]) ?? existingProfile?.height,
            heightUnit: string(
                from: updates,
                keys: ["heightUnit", "height_unit"]
            ) ?? existingProfile?.heightUnit,
            gender: string(from: updates, keys: ["gender"]) ?? existingProfile?.gender,
            activityLevel: string(
                from: updates,
                keys: ["activityLevel", "activity_level"]
            ) ?? existingProfile?.activityLevel,
            goalWeight: double(
                from: updates,
                keys: ["goalWeight", "goal_weight"]
            ) ?? existingProfile?.goalWeight,
            goalWeightUnit: string(
                from: updates,
                keys: ["goalWeightUnit", "goal_weight_unit"]
            ) ?? existingProfile?.goalWeightUnit,
            onboardingCompleted: updatedOnboardingCompleted
        )

        updatedUser.name = updatedName
        updatedUser.profile = mergedProfile

        if let updatedOnboardingCompleted {
            updatedUser.onboardingCompleted = updatedOnboardingCompleted
        }

        return updatedUser
    }

    private static func string(from updates: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = updates[key] as? String {
                return value
            }
        }

        return nil
    }

    private static func nonEmptyString(from updates: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = updates[key] as? String else {
                continue
            }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func date(from updates: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = updates[key] as? Date {
                return value
            }
        }

        return nil
    }

    private static func bool(from updates: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = updates[key] as? Bool {
                return value
            }
        }

        return nil
    }

    private static func double(from updates: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = updates[key] as? Double {
                return value
            }

            if let value = updates[key] as? NSNumber {
                return value.doubleValue
            }
        }

        return nil
    }
}
