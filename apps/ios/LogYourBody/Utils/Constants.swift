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

    // MARK: - Feature Flags
    static let isBodySpecEnabled = true
    static let appleSignInEnabledFlagKey = "ios_apple_sign_in_enabled"
    // Legacy beta fallback; the intended post-MVP dashboard route is `ios_photo_timeline_hud`.
    static let fullBodyCompositionDashboardFlagKey = "ios_full_body_composition_dashboard"
    static let photoTimelineHUDFlagKey = "ios_photo_timeline_hud"
    static let phaseInsightFlagKey = "ios_phase_insight"
    static let glp1WeeklyCheckInFlagKey = "ios_glp1_weekly_checkin"
    static let bulkProgressPhotoImportFlagKey = "ios_bulk_progress_photo_import"
    static let photosTabFlagKey = "photos_tab"

    // MARK: - API Configuration (from Config.xcconfig via Info.plist)
    static var baseURL: String {
        Configuration.apiBaseURL
    }

    // MARK: - Clerk Configuration (from Config.xcconfig via Info.plist)
    static var clerkPublishableKey: String {
        Configuration.clerkPublishableKey
    }

    static var clerkFrontendAPI: String {
        Configuration.clerkFrontendAPI
    }

    #if DEBUG
    static let useMockAuth = false  // Set to true only for local mock testing in debug builds
    #else
    static let useMockAuth = false  // Always disabled in non-debug builds
    #endif

    static var isClerkConfigured: Bool {
        Configuration.isClerkConfigured
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
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let onboardingCompletedVersionKey = "onboardingCompletedVersion"

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

    // MARK: - Body Composition Ideal Ranges
    struct BodyComposition {
        // Body Fat Percentage
        struct BodyFat {
            static let maleOptimalRange: ClosedRange<Double> = 8...12
            static let maleIdealValue: Double = 10
            static let femaleOptimalRange: ClosedRange<Double> = 16...20
            static let femaleIdealValue: Double = 18
        }

        // Fat-Free Mass Index (FFMI)
        struct FFMI {
            static let maleOptimalRange: ClosedRange<Double> = 20...23
            static let maleIdealValue: Double = 22
            static let femaleOptimalRange: ClosedRange<Double> = 14...17
            static let femaleIdealValue: Double = 15
        }
    }
}

struct AuthSurfacePolicy {
    static let defaultShowsAppleSignIn = false
    static let primarySignInMethod = "email_otp"

    static func shouldShowAppleSignIn(gateEnabled: Bool) -> Bool {
        gateEnabled
    }
}

enum PhotoTimelineHUDPolicy {
    static let defaultShowsPhotoTimelineHUD = false

    static func shouldShowPhotoTimelineHUD(gateEnabled: Bool) -> Bool {
        gateEnabled
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

    static func shouldShowBulkImport(
        gateEnabled: Bool,
        existingProgressPhotoCount: Int
    ) -> Bool {
        gateEnabled || existingProgressPhotoCount >= activationProgressPhotoCount
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
