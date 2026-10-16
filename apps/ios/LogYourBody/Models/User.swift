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
        return ProfileBirthDatePolicy.age(from: dateOfBirth)
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

    var hasAppOwnedProfileData: Bool {
        if dateOfBirth != nil { return true }
        if let height, height > 0 { return true }
        if let gender, !gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let activityLevel, !activityLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let goalWeight, goalWeight > 0 { return true }
        if onboardingCompleted != nil { return true }
        return false
    }
}

/// Profile birthdays are Gregorian calendar dates encoded at UTC, not instants.
/// Preserve that day in editors and labels; compare age with the user's local day.
enum ProfileBirthDatePolicy {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    static func today(now: Date = Date(), localCalendar: Calendar = .current) -> Date {
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.timeZone = localCalendar.timeZone
        let components = localGregorian.dateComponents([.year, .month, .day], from: now)
        return calendar.date(from: components) ?? now
    }

    static func age(
        from dateOfBirth: Date,
        now: Date = Date(),
        localCalendar: Calendar = .current
    ) -> Int? {
        let birthday = calendar.startOfDay(for: dateOfBirth)
        return calendar.dateComponents(
            [.year], from: birthday, to: today(now: now, localCalendar: localCalendar)
        ).year
    }

    static func year(from dateOfBirth: Date) -> Int {
        calendar.component(.year, from: dateOfBirth)
    }

    static func date(year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: 1, day: 1))
    }

    static func formatted(
        _ dateOfBirth: Date,
        style: DateFormatter.Style = .medium,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: dateOfBirth)
    }
}
