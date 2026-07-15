//
// Constants.swift
// LogYourBody
//
import SwiftUI

extension Notification.Name {
    static let profileUpdated = Notification.Name("profileUpdated")
    static let bodyScoreUpdated = Notification.Name("bodyScoreUpdated")
    static let featureGatesDidChange = Notification.Name("featureGatesDidChange")
}

struct Constants {
    // MARK: - App Info
    static let appName = "LogYourBody"
    static let appVersion = "1.0.0"
    static let buildNumber = "1"

    // MARK: - Product Capabilities
    static let isBodySpecEnabled = true

    // MARK: - API Configuration (from Config.xcconfig via Info.plist)
    static var baseURL: String {
        Configuration.apiBaseURL
    }

    #if DEBUG
    static let useMockAuth = false  // Set to true only for local mock testing in debug builds
    #else
    static let useMockAuth = false  // Always disabled in non-debug builds
    #endif

    static var isAuthConfigured: Bool {
        Configuration.isAuthConfigured
    }

    // MARK: - Supabase Configuration (from Config.xcconfig via Info.plist)
    static var supabaseURL: String {
        Configuration.supabaseURL
    }

    static var supabaseAnonKey: String {
        Configuration.supabaseAnonKey
    }

    // MARK: - RevenueCat Configuration (from Config.xcconfig via Info.plist)
    static var revenueCatAPIKey: String {
        Configuration.revenueCatAPIKey
    }

    // RevenueCat Entitlement ID (must match RevenueCat dashboard)
    static let proEntitlementID = "Premium"

    // MARK: - UserDefaults Keys
    static let authTokenKey = "authToken"
    static let currentUserKey = "currentUser"
    static let preferredWeightUnitKey = "preferredWeightUnit"
    static let preferredMeasurementSystemKey = "preferredMeasurementSystem"
    static let defaultHomeModeKey = "defaultHomeMode"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let onboardingCompletedVersionKey = "onboardingCompletedVersion"
    static let onboardingCompletedUserIdKey = "onboardingCompletedUserId"
    static let dailyWeighInReminderEnabledKey = "dailyWeighInReminderEnabled"
    static let dailyWeighInReminderHourKey = "dailyWeighInReminderHour"
    static let dailyWeighInReminderMinuteKey = "dailyWeighInReminderMinute"
    static let dailyWeighInReminderPromptCompletedKey = "dailyWeighInReminderPromptCompleted"

    // Goal Keys
    static let goalBodyFatPercentageKey = "goalBodyFatPercentage"
    static let goalFFMIKey = "goalFFMI"
    static let goalWeightKey = "goalWeight"

    // Timeline Keys
    static let timelineModeKey = "timelineMode"

    // Photo Management Keys
    static let deletePhotosAfterImportKey = "deletePhotosAfterImportKey"
    static let hasPromptedDeletePhotosKey = "hasPromptedDeletePhotosKey"

    // MARK: - Units
    static let weightUnits = ["kg", "lbs"]
    static let heightUnits = ["cm", "ft"]

    // MARK: - Layout
    static let cornerRadius: CGFloat = 8  // More modern, Linear-inspired
    static let cornerRadiusLarge: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 6
    static let padding: CGFloat = 20
    static let paddingSmall: CGFloat = 12
    static let paddingLarge: CGFloat = 24
    static let spacing: CGFloat = 12
    static let spacingSmall: CGFloat = 8
    static let spacingLarge: CGFloat = 16

    // MARK: - Animation
    static let animationDuration: Double = 0.3
    static let springAnimation = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let smoothAnimation = SwiftUI.Animation.easeInOut(duration: 0.3)

    // MARK: - Body Composition Reference Ranges
    struct BodyComposition {
        // Body Fat Percentage
        struct BodyFat {
            static let maleReferenceRange: ClosedRange<Double> = 8...12
            static let maleReferenceMidpoint: Double = 10
            static let femaleReferenceRange: ClosedRange<Double> = 16...20
            static let femaleReferenceMidpoint: Double = 18
        }

        // Fat-Free Mass Index (FFMI)
        struct FFMI {
            static let maleReferenceRange: ClosedRange<Double> = 20...23
            static let maleReferenceMidpoint: Double = 22
            static let femaleReferenceRange: ClosedRange<Double> = 14...17
            static let femaleReferenceMidpoint: Double = 15
        }
    }
}

enum AppFeatureGate {
    static let individualizedAestheticGoals = "individualized_aesthetic_goals"
}

enum AestheticGoalPolicy {
    static func resolvedGoal(
        explicitGoal: Double?,
        legacyReferenceMidpoint: Double,
        individualizedGoalsEnabled: Bool
    ) -> Double? {
        if individualizedGoalsEnabled {
            return explicitGoal
        }

        return explicitGoal ?? legacyReferenceMidpoint
    }
}

struct AuthSurfacePolicy {
    static let primarySignInMethod = "sms_otp"
}

enum PhotoTimelineHUDPolicy {
    static let defaultShowsPhotoTimelineHUD = true

    static func shouldShowPhotoTimelineHUD() -> Bool {
        true
    }

    static func stateText(
        presence: MetricPresence,
        confidence: GlobalTimelineMetricConfidence? = nil
    ) -> String {
        switch presence {
        case .present:
            return "Measured"
        case .interpolated:
            if let confidence {
                return "Interpolated - \(confidence.rawValue) confidence"
            }
            return "Interpolated"
        case .lastKnown:
            return "Last known"
        case .missing:
            return "Missing"
        }
    }

    static func hasUsablePhoto(_ metric: BodyMetrics?) -> Bool {
        guard let photoUrl = metric?.photoUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !photoUrl.isEmpty
    }
}

enum BulkProgressPhotoImportPolicy {
    static let defaultShowsBulkImport = false
    static let activationProgressPhotoCount = 2

    static func shouldShowBulkImport(existingProgressPhotoCount: Int) -> Bool {
        existingProgressPhotoCount >= activationProgressPhotoCount
    }

    static func footerText(
        isEnabled: Bool,
        existingProgressPhotoCount: Int
    ) -> String {
        if isEnabled {
            return "Import progress photos from your photo library."
        }

        if existingProgressPhotoCount == 1 {
            return "Bulk import unlocks after one more added progress photo or migration access."
        }

        return "Bulk import unlocks after you have added progress photos or request migration access."
    }
}
