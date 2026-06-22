//
// HealthKitManager.swift
// LogYourBody
//
import Foundation
import HealthKit

enum HealthKitDefaultsKey: String {
    case authorizationConfirmed = "hasConfirmedHealthKitAuthorization"
    case lastObserverSyncDate = "lastHealthKitObserverSyncDate"
    case fullSyncCompleted = "hasPerformedFullHealthKitSync"

    func scoped(with userId: String?) -> String {
        guard let userId = userId, !userId.isEmpty else {
            return rawValue
        }
        return "\(rawValue)_\(userId)"
    }
}

struct HealthKitAuthorizationPolicy {
    static func isAuthorized(
        writeStatus: HKAuthorizationStatus,
        hasConfirmedReadAccess: Bool
    ) -> Bool {
        writeStatus == .sharingAuthorized || hasConfirmedReadAccess
    }
}

struct HealthKitFullSyncCompletionPolicy {
    static func shouldMarkCompleted(importSucceeded: Bool) -> Bool {
        importSucceeded
    }
}

struct HealthKitWeightImportSample: Equatable {
    let weight: Double
    let date: Date
    let sourceMetadata: BodyMetricSourceMetadata?

    init(weight: Double, date: Date, sourceMetadata: BodyMetricSourceMetadata? = nil) {
        self.weight = weight
        self.date = date
        self.sourceMetadata = sourceMetadata
    }
}

struct HealthKitBodyFatImportSample: Equatable {
    let percentage: Double
    let date: Date
    let sourceMetadata: BodyMetricSourceMetadata?

    init(percentage: Double, date: Date, sourceMetadata: BodyMetricSourceMetadata? = nil) {
        self.percentage = percentage
        self.date = date
        self.sourceMetadata = sourceMetadata
    }
}

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let healthStore = HKHealthStore()
    let userDefaults = UserDefaults.standard

    @Published var isAuthorized = false
    @Published var latestWeight: Double?
    @Published var latestWeightDate: Date?
    @Published var latestBodyFatPercentage: Double?
    @Published var latestBodyFatDate: Date?
    @Published var todayStepCount: Int = 0
    @Published var latestStepCount: Int?
    @Published var latestStepCountDate: Date?

    // Import progress tracking
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0  // 0.0 to 1.0
    @Published var importStatus: String = ""
    @Published var importedCount: Int = 0
    @Published var totalToImport: Int = 0

    // Health types - using computed properties to avoid crashes if HealthKit types fail to initialize

    // Sync management
    let syncStateQueue = DispatchQueue(label: "com.logyourbody.healthkit.sync.state")
    var isSyncingWeight = false
    var syncDebounceTimer: Timer?
    var weightObserverQuery: HKObserverQuery?
    var bodyFatObserverQuery: HKObserverQuery?
    var stepObserverQuery: HKObserverQuery?
    var activeQueries: [HKQuery] = []
    var activeUserId: String?


    // Check if HealthKit is available


    // MARK: - Bootstrap & Authorization

    // Check authorization status

    // Fetch latest height from HealthKit


    // Request authorization


    // Save weight to HealthKit

    // Fetch latest weight from HealthKit

    // Fetch weight history

    // New function to fetch weight history in a specific date range


    // Fetch latest body fat percentage from HealthKit

    // Fetch body fat percentage history


    // Save body fat percentage to HealthKit

    // Setup background delivery for weight and body fat changes


    // Fetch user's height from HealthKit

    // Fetch user's date of birth from HealthKit

    // Fetch user's biological sex from HealthKit

    // Fetch today's step count

    // Fetch step count for a specific date

    // Sync ALL weight and body fat data from HealthKit to app


    // Background incremental sync for longer time periods (30 days at a time)

    // Sync ALL historical HealthKit data efficiently


    // Get the earliest weight entry date from HealthKit

    // Process a batch of HealthKit data and return (imported, skipped) counts


    // Helper function to save body metrics

    // Sync step count data from HealthKit to app


    // Setup observer for new weight entries in HealthKit

    // Setup observer for new body fat entries in HealthKit


    // Setup observer for new step count entries in HealthKit

    // Enable background delivery for steps

    // Fetch step count history

    // Setup background delivery for step count changes


    // Sync historical step data
}

// MARK: - GLP-1 HealthKit Mapping

extension HealthKitManager {
    /// Returns the app's canonical HealthKit identifier string for a given GLP-1 medication, if known.
    /// This does not perform any HealthKit writes on its own; it simply exposes mapping metadata
    /// so future HealthKit medication integrations can align with our GLP-1 catalog.
    func glp1HealthKitIdentifier(for medication: Glp1Medication) -> String? {
        if let identifier = medication.hkIdentifier {
            return identifier
        }

        if let brand = medication.brand,
           let preset = Glp1MedicationCatalog.preset(forBrand: brand) {
            return preset.hkIdentifier
        }

        return nil
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAuthorized
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .syncFailed:
            return "Failed to sync weight data"
        }
    }
}
