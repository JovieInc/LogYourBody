// Compatibility copy still shared with the HomeV2 onboarding target fields.
// Settings presentation now lives in PreferencesView.
import Foundation

enum HomeV2SettingsCopy {
    static let notSet = "Not set"
    static let height = "Height"
    static let bodyFat = "Body fat"
    static let circumference = "Circumference"
    static let unitsNote = "Apple Health keeps its own units. LogYourBody converts when it reads."
    static let targetNote = "Your target is yours. It's used to show pace and to flag when a phase has likely gone on too long."
    static let removeTarget = "Remove target"
    static let days = "Days"
    static let everyDay = "Every day"
    static let remindersNote = "One notification, then quiet. No streaks, no nudges."
    static let included = "Included"
    static let included1 = "Unlimited progress photos and compare"
    static let included2 = "Body-fat, lean mass and FFMI trends"
    static let included3 = "Phase insights that tell you when to stop cutting"

    static func renews(on date: String, price: String?) -> String {
        guard let price else { return "Renews \(date)" }
        return "Renews \(date) for \(price)"
    }

    static func planText(isSubscribed: Bool, productIdentifier: String?) -> String {
        guard isSubscribed else { return "Free" }
        let lowercased = (productIdentifier ?? "").lowercased()
        if lowercased.contains("annual") || lowercased.contains("year") { return "Pro, annual" }
        if lowercased.contains("month") { return "Pro, monthly" }
        return "Pro"
    }

    static func unitsText(_ system: MeasurementSystem) -> String {
        "\(HomeV2Copy.displayUnit(system)), %"
    }

    static func heightUnitText(_ system: MeasurementSystem) -> String {
        system == .metric ? "cm" : "ft, in"
    }

    static func circumferenceUnitText(_ system: MeasurementSystem) -> String {
        system == .metric ? "cm" : "in"
    }
}

enum HomeV2SettingsRoute: String, Identifiable, Hashable {
    case profile
    case subscription
    case appleHealth
    case units
    case target
    case reminders
    case exportData
    case deleteAccount

    var id: String { rawValue }

    static let allRoutes: [HomeV2SettingsRoute] = [
        .profile, .subscription, .appleHealth, .units, .target, .reminders, .exportData, .deleteAccount
    ]
}
