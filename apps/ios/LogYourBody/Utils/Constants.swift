//
// Constants.swift
// LogYourBody
//
import SwiftUI

extension Notification.Name {
    static let profileUpdated = Notification.Name("profileUpdated")
}

struct Constants {
    // MARK: - App Info
    static let appName = "LogYourBody"
    static let appVersion = "1.0.0"
    static let buildNumber = "1"
    
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

    static let useMockAuth = false  // Clerk authentication enabled

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
    static let preferredTimeFormatKey = "preferredTimeFormat"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

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
