//
// HealthKitManager.swift
// LogYourBody
//
import Foundation
import HealthKit

enum HealthKitDefaultsKey: String {
    case authorizationConfirmed = "hasConfirmedHealthKitAuthorization"
    case readProbeRecord = "healthKitReadProbeRecord"
    case lastObserverSyncDate = "lastHealthKitObserverSyncDate"
    case fullSyncCompleted = "hasPerformedFullHealthKitSync"

    func scoped(with userId: String?) -> String {
        guard let userId = userId, !userId.isEmpty else {
            return rawValue
        }
        return "\(rawValue)_\(userId)"
    }
}

enum HealthKitSampleProbe: Equatable {
    case found
    case empty
    case failed
}

/// Read kinds the Apple Health prompt asks for. A sample confirms only its own kind.
enum HealthKitReadKind: String, Equatable, CaseIterable {
    case bodyMass
    case bodyFatPercentage
    case height
    case stepCount
    case dateOfBirth

    var displayName: String {
        switch self {
        case .bodyMass: return "weight"
        case .bodyFatPercentage: return "body fat"
        case .height: return "height"
        case .stepCount: return "steps"
        case .dateOfBirth: return "date of birth"
        }
    }
}

enum HealthKitReadProbeRecord: String, Equatable {
    case emptyNotDenial
    case writeOnly
    case partialSample
    case requestFailed
}

enum HealthKitConnectFollowUp: Equatable {
    case startSync
    case showRequestFailure
    case showInconclusiveRead
}

enum HealthKitOnboardingFollowUp: Equatable {
    case importHealth
    case manualAfterEmptyRead
    case manualAfterRequestFailure
}

struct HealthKitAuthorizationResolution: Equatable {
    let writeAuthorized: Bool
    let probes: [HealthKitReadKind: HealthKitSampleProbe]
    let requestSucceeded: Bool
    /// True only when the authorization sheet itself fails. An empty read leaves this false.
    let presentsAccessNeededAlert: Bool

    var confirmedReadKinds: Set<HealthKitReadKind> {
        Set(probes.compactMap { kind, probe in probe == .found ? kind : nil })
    }

    var grantsEveryRequestedReadKind: Bool {
        confirmedReadKinds == Set(HealthKitReadKind.allCases)
    }

    var canUseHealthKit: Bool {
        requestSucceeded && (writeAuthorized || !confirmedReadKinds.isEmpty)
    }

    var shouldPresentAccessNeededAlert: Bool { presentsAccessNeededAlert }

    /// An empty successful read is denial only when the request path treats it as one.
    var treatsEmptyReadAsDenial: Bool {
        requestSucceeded && probes.values.contains(.empty) && presentsAccessNeededAlert
    }

    var statusText: String {
        HealthKitAuthorizationPolicy.statusText(for: self)
    }

    var record: HealthKitReadProbeRecord {
        if !requestSucceeded { return .requestFailed }
        if confirmedReadKinds.isEmpty {
            return writeAuthorized ? .writeOnly : .emptyNotDenial
        }
        return .partialSample
    }
}

struct HealthKitAuthorizationPolicy {
    static func isAuthorized(
        writeStatus: HKAuthorizationStatus,
        hasConfirmedReadAccess: Bool
    ) -> Bool {
        writeStatus == .sharingAuthorized || hasConfirmedReadAccess
    }

    /// A finished prompt keeps the probe results as they are. Write sharing does not
    /// confirm unread kinds. An empty or failed probe does not raise a denial alert.
    static func resolve(
        writeAuthorized: Bool,
        probes: [HealthKitReadKind: HealthKitSampleProbe],
        requestSucceeded: Bool
    ) -> HealthKitAuthorizationResolution {
        HealthKitAuthorizationResolution(
            writeAuthorized: requestSucceeded && writeAuthorized,
            probes: probes,
            requestSucceeded: requestSucceeded,
            presentsAccessNeededAlert: !requestSucceeded
        )
    }

    static func statusText(for resolution: HealthKitAuthorizationResolution) -> String {
        if !resolution.requestSucceeded {
            return "Apple Health could not be opened. You can log manually and try again."
        }
        let names = resolution.confirmedReadKinds
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
        if names.isEmpty {
            if resolution.writeAuthorized {
                return "Apple Health writing is allowed. No samples were readable, so read access is not confirmed."
            }
            return "No Apple Health samples were readable. That is not a denial. You can log manually."
        }
        let list = names.joined(separator: ", ")
        if resolution.grantsEveryRequestedReadKind {
            return "Apple Health returned samples for \(list)."
        }
        return "Apple Health returned samples for \(list). Other requested types are not confirmed. "
            + "An empty read is not a denial."
    }

    static func statusText(for record: HealthKitReadProbeRecord) -> String {
        switch record {
        case .emptyNotDenial:
            return "No Apple Health samples were readable. That is not a denial. You can log manually."
        case .writeOnly:
            return "Apple Health writing is allowed. No samples were readable, so read access is not confirmed."
        case .partialSample:
            return "Some Apple Health types returned samples. Other requested types are not confirmed. "
                + "An empty read is not a denial."
        case .requestFailed:
            return "Apple Health could not be opened. You can log manually and try again."
        }
    }

    static func connectFollowUp(
        _ resolution: HealthKitAuthorizationResolution
    ) -> HealthKitConnectFollowUp {
        if resolution.canUseHealthKit { return .startSync }
        if resolution.shouldPresentAccessNeededAlert { return .showRequestFailure }
        return .showInconclusiveRead
    }

    static func onboardingFollowUp(
        _ resolution: HealthKitAuthorizationResolution?
    ) -> HealthKitOnboardingFollowUp {
        guard let resolution else { return .manualAfterRequestFailure }
        if resolution.canUseHealthKit { return .importHealth }
        if resolution.requestSucceeded { return .manualAfterEmptyRead }
        return .manualAfterRequestFailure
    }

    static func onboardingAnalyticsEvent(_ followUp: HealthKitOnboardingFollowUp) -> String {
        switch followUp {
        case .importHealth: return "onboarding_health_import_authorized"
        case .manualAfterEmptyRead: return "onboarding_health_import_no_samples"
        case .manualAfterRequestFailure: return "onboarding_health_import_unavailable"
        }
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
    let userDefaults: UserDefaults
    let importAuthManager: AuthManager?
    let importCoreDataManager: CoreDataManager?
    let weightImportQuery: ((Date, Date) async throws -> [HealthKitWeightImportSample])?
    let bodyFatImportQuery: ((Date) async throws -> [HealthKitBodyFatImportSample])?
    let stepHistoryQuery: ((Int) async throws -> [(stepCount: Int, date: Date)])?
    let earliestImportDateQuery: (() async throws -> Date?)?
    let importSyncTrigger: (@MainActor () -> Void)?
    let importCompletion: (@MainActor (String) -> Void)?
    let bodyScoreRecalculationTrigger: (@MainActor () -> Void)?
    let metricImportStore: ((BodyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void)?
    let rawImportStore: (([HKRawSample]) async -> Void)?

    init(
        userDefaults: UserDefaults = .standard,
        authManager: AuthManager? = nil,
        coreDataManager: CoreDataManager? = nil,
        weightImportQuery: ((Date, Date) async throws -> [HealthKitWeightImportSample])? = nil,
        bodyFatImportQuery: ((Date) async throws -> [HealthKitBodyFatImportSample])? = nil,
        stepHistoryQuery: ((Int) async throws -> [(stepCount: Int, date: Date)])? = nil,
        earliestImportDateQuery: (() async throws -> Date?)? = nil,
        syncTrigger: (@MainActor () -> Void)? = nil,
        importCompletion: (@MainActor (String) -> Void)? = nil,
        bodyScoreRecalculationTrigger: (@MainActor () -> Void)? = nil,
        metricImportStore: ((BodyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void)? = nil,
        rawImportStore: (([HKRawSample]) async -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        importAuthManager = authManager
        importCoreDataManager = coreDataManager
        self.weightImportQuery = weightImportQuery
        self.bodyFatImportQuery = bodyFatImportQuery
        self.stepHistoryQuery = stepHistoryQuery
        self.earliestImportDateQuery = earliestImportDateQuery
        importSyncTrigger = syncTrigger
        self.importCompletion = importCompletion
        self.bodyScoreRecalculationTrigger = bodyScoreRecalculationTrigger
        self.metricImportStore = metricImportStore
        self.rawImportStore = rawImportStore
    }

    @Published var isAuthorized = false
    /// Truthful Apple Health status. Empty means the screen may use its legacy connected/not connected label.
    @Published var authorizationStatusText = ""
    var lastAuthorizationResolution: HealthKitAuthorizationResolution?
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
    @MainActor var historicalImportOperation: UUID?

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

/// The queued CoreData block has no originating Swift task. Carry cancellation explicitly.
final class HealthKitImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
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
