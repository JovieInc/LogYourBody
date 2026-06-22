import SwiftUI
import Combine

func defaultProfileDateOfBirth() -> Date {
    Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
}

@MainActor
final class OnboardingFlowViewModel: ObservableObject {
    enum AccountCreationStage {
        case idle
        case preparing
        case creatingAccount
        case finalizing

        var statusMessage: String? {
            switch self {
            case .idle:
                return nil
            case .preparing:
                return "Preparing secure connection…"
            case .creatingAccount:
                return "Creating your LogYourBody account…"
            case .finalizing:
                return "Finishing setup…"
            }
        }
    }
    enum Step: String, Hashable, Codable {
        case hook
        case basics
        case height
        case healthConnect
        case healthConfirmation
        case manualWeight
        case bodyFatChoice
        case bodyFatNumeric
        case bodyFatVisual
        case loading
        case bodyScore
        case defaultHomeMode
        case emailCapture
        case account
        case profileDetails
        case firstPhoto
        case paywall
    }

    enum EntryContext {
        case authenticated
        case preAuth

        var analyticsContext: String {
            switch self {
            case .authenticated:
                return "authenticated"
            case .preAuth:
                return "pre_auth"
            }
        }
    }

    enum ProfileDetailsSubstep: String, Codable {
        case firstName
        case lastName
        case dateOfBirth
        case sex
        case height
    }

    struct ProgressContext: Equatable {
        let currentIndex: Int
        let totalCount: Int
        let label: String

        var fractionComplete: Double {
            guard totalCount > 0 else { return 0 }
            return min(max(Double(currentIndex) / Double(totalCount), 0), 1)
        }
    }


    @Published var currentStep: Step = .hook {
        didSet { persistProgress() }
    }
    @Published var bodyScoreInput = BodyScoreInput() {
        didSet { persistProgress() }
    }
    @Published var canNavigateForward: Bool = false
    @Published var bodyScoreResult: BodyScoreResult?
    @Published var defaultHomeMode: DefaultHomeMode = .default {
        didSet {
            UserDefaults.standard.set(defaultHomeMode.rawValue, forKey: Constants.defaultHomeModeKey)
            persistProgress()
        }
    }
    @Published var showEmailCaptureSheet = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var heightUnit: HeightUnit = .centimeters {
        didSet { persistProgress() }
    }
    @Published var weightUnit: WeightUnit = .pounds {
        didSet { persistProgress() }
    }
    @Published var heightCentimetersText: String = "" {
        didSet { persistProgress() }
    }
    @Published var heightFeet: Int = 5 {
        didSet { persistProgress() }
    }
    @Published var heightInches: Int = 10 {
        didSet { persistProgress() }
    }
    @Published var isRequestingHealthImport = false
    @Published var manualWeightText: String = "" {
        didSet { persistProgress() }
    }
    @Published var bodyFatPercentageText: String = "" {
        didSet { persistProgress() }
    }
    @Published var selectedVisualBodyFat: Double? {
        didSet { persistProgress() }
    }
    @Published var didRequestHealthSync = false {
        didSet { persistProgress() }
    }
    @Published var emailAddress: String = "" {
        didSet { persistProgress() }
    }
    @Published var isCreatingAccount: Bool = false
    @Published var accountCreationError: String?
    @Published var accountCreationStage: AccountCreationStage = .idle
    @Published var onboardingFirstPhotoMetric: BodyMetrics?
    @Published var isPreparingFirstPhotoMetric = false
    @Published var isCompletingOnboarding = false
    @Published var firstPhotoErrorMessage: String?
    @Published var profileFirstName: String = "" {
        didSet { persistProgress() }
    }
    @Published var profileLastName: String = "" {
        didSet { persistProgress() }
    }
    @Published var profileDateOfBirth: Date = defaultProfileDateOfBirth() {
        didSet { persistProgress() }
    }
    @Published var profileBiologicalSex: BiologicalSex? {
        didSet { persistProgress() }
    }
    @Published var profileHeightUnit: HeightUnit = .centimeters {
        didSet { persistProgress() }
    }
    @Published var profileHeightCentimetersText: String = "" {
        didSet { persistProgress() }
    }
    @Published var profileHeightFeet: Int = 5 {
        didSet { persistProgress() }
    }
    @Published var profileHeightInches: Int = 10 {
        didSet { persistProgress() }
    }
    @Published var profileDetailsActiveSubstep: ProfileDetailsSubstep = .firstName {
        didSet { persistProgress() }
    }
    @Published var profileShouldAskSex: Bool = false {
        didSet { persistProgress() }
    }
    @Published var hasHydratedProfileDetailsDraft = false {
        didSet { persistProgress() }
    }

    let entryContext: EntryContext
    let includesFirstPhotoStep: Bool
    let healthKitManager: HealthKitManager
    let calculator: BodyScoreCalculating
    let profileUpdateHandler: @MainActor ([String: Any]) async throws -> Void
    var hasMarkedOnboardingComplete = false
    var isOnboardingCompletionInFlight = false
    let progressStore = OnboardingProgressStore.shared
    var isRestoringProgress = false


    init(
        entryContext: EntryContext = .authenticated,
        healthKitManager: HealthKitManager = .shared,
        calculator: BodyScoreCalculating = BodyScoreCalculator(),
        includesFirstPhotoStep: Bool? = nil,
        profileUpdateHandler: @escaping @MainActor ([String: Any]) async throws -> Void = {
            try await AuthManager.shared.updateProfileDurably($0)
        }
    ) {
        self.entryContext = entryContext
        self.healthKitManager = healthKitManager
        self.calculator = calculator
        self.includesFirstPhotoStep = includesFirstPhotoStep
            ?? (entryContext == .authenticated && PhotoTimelineHUDPolicy.shouldShowPhotoTimelineHUD())
        self.profileUpdateHandler = profileUpdateHandler

        isRestoringProgress = true
        configureMeasurementPreference()
        hydrateHeightFields()
        hydrateWeightFields()
        hydrateDefaultHomeMode()
        isRestoringProgress = false

        if let bodyFat = bodyScoreInput.bodyFat.percentage {
            bodyFatPercentageText = Self.formatNumber(bodyFat)
        }

        if entryContext == .authenticated {
            restorePersistedProgressIfNeeded()
        }

        applyFirstPhotoUITestFixtureIfNeeded()
    }
}

extension OnboardingFlowViewModel.Step {
    static var progressSequence: [Self] {
        [
            .hook,
            .basics,
            .height,
            .healthConnect,
            .healthConfirmation,
            .manualWeight,
            .bodyFatChoice,
            .bodyFatNumeric,
            .bodyFatVisual,
            .bodyScore,
            .defaultHomeMode,
            .emailCapture,
            .account,
            .profileDetails,
            .firstPhoto
        ]
    }

    var progressLabel: String {
        switch self {
        case .hook: return "Welcome"
        case .basics: return "Basics"
        case .height: return "Height"
        case .healthConnect: return "Health Sync"
        case .healthConfirmation: return "Review"
        case .manualWeight: return "Weight"
        case .bodyFatChoice, .bodyFatNumeric, .bodyFatVisual: return "Body Fat"
        case .bodyScore: return "Your Score"
        case .defaultHomeMode: return "Default View"
        case .emailCapture: return "Save Progress"
        case .account: return "Account"
        case .profileDetails: return "Profile"
        case .firstPhoto: return "Photo"
        case .loading: return "Loading"
        case .paywall: return "Upgrade"
        }
    }
}

// MARK: - Onboarding Progress Store

struct OnboardingProgressSnapshot: Codable {
    let version: Int
    let currentStep: OnboardingFlowViewModel.Step
    let bodyScoreInput: BodyScoreInput
    let heightUnit: HeightUnit
    let weightUnit: WeightUnit
    let heightCentimetersText: String
    let heightFeet: Int
    let heightInches: Int
    let manualWeightText: String
    let bodyFatPercentageText: String
    let selectedVisualBodyFat: Double?
    let defaultHomeMode: DefaultHomeMode
    let didRequestHealthSync: Bool
    let emailAddress: String
    let profileFirstName: String
    let profileLastName: String
    let profileDateOfBirth: Date
    let profileBiologicalSex: BiologicalSex?
    let profileHeightUnit: HeightUnit
    let profileHeightCentimetersText: String
    let profileHeightFeet: Int
    let profileHeightInches: Int
    let profileDetailsActiveSubstep: OnboardingFlowViewModel.ProfileDetailsSubstep
    let profileShouldAskSex: Bool
    let hasHydratedProfileDetailsDraft: Bool
    let lastUpdated: Date
}

extension OnboardingProgressSnapshot {
    enum CodingKeys: String, CodingKey {
        case version
        case currentStep
        case bodyScoreInput
        case heightUnit
        case weightUnit
        case heightCentimetersText
        case heightFeet
        case heightInches
        case manualWeightText
        case bodyFatPercentageText
        case selectedVisualBodyFat
        case defaultHomeMode
        case didRequestHealthSync
        case emailAddress
        case profileFirstName
        case profileLastName
        case profileDateOfBirth
        case profileBiologicalSex
        case profileHeightUnit
        case profileHeightCentimetersText
        case profileHeightFeet
        case profileHeightInches
        case profileDetailsActiveSubstep
        case profileShouldAskSex
        case hasHydratedProfileDetailsDraft
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        currentStep = try container.decode(OnboardingFlowViewModel.Step.self, forKey: .currentStep)
        bodyScoreInput = try container.decode(BodyScoreInput.self, forKey: .bodyScoreInput)
        heightUnit = try container.decode(HeightUnit.self, forKey: .heightUnit)
        weightUnit = try container.decode(WeightUnit.self, forKey: .weightUnit)
        heightCentimetersText = try container.decode(String.self, forKey: .heightCentimetersText)
        heightFeet = try container.decode(Int.self, forKey: .heightFeet)
        heightInches = try container.decode(Int.self, forKey: .heightInches)
        manualWeightText = try container.decode(String.self, forKey: .manualWeightText)
        bodyFatPercentageText = try container.decode(String.self, forKey: .bodyFatPercentageText)
        selectedVisualBodyFat = try container.decodeIfPresent(Double.self, forKey: .selectedVisualBodyFat)
        defaultHomeMode = try container.decodeIfPresent(DefaultHomeMode.self, forKey: .defaultHomeMode) ?? .default
        didRequestHealthSync = try container.decode(Bool.self, forKey: .didRequestHealthSync)
        emailAddress = try container.decode(String.self, forKey: .emailAddress)
        profileFirstName = try container.decodeIfPresent(String.self, forKey: .profileFirstName) ?? ""
        profileLastName = try container.decodeIfPresent(String.self, forKey: .profileLastName) ?? ""
        profileDateOfBirth = try container.decodeIfPresent(Date.self, forKey: .profileDateOfBirth)
            ?? defaultProfileDateOfBirth()
        profileBiologicalSex = try container.decodeIfPresent(BiologicalSex.self, forKey: .profileBiologicalSex)
        profileHeightUnit = try container.decodeIfPresent(HeightUnit.self, forKey: .profileHeightUnit) ?? .centimeters
        profileHeightCentimetersText = try container.decodeIfPresent(
            String.self,
            forKey: .profileHeightCentimetersText
        ) ?? ""
        profileHeightFeet = try container.decodeIfPresent(Int.self, forKey: .profileHeightFeet) ?? 5
        profileHeightInches = try container.decodeIfPresent(Int.self, forKey: .profileHeightInches) ?? 10
        profileDetailsActiveSubstep = try container.decodeIfPresent(
            OnboardingFlowViewModel.ProfileDetailsSubstep.self,
            forKey: .profileDetailsActiveSubstep
        ) ?? .firstName
        profileShouldAskSex = try container.decodeIfPresent(Bool.self, forKey: .profileShouldAskSex) ?? false
        hasHydratedProfileDetailsDraft = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasHydratedProfileDetailsDraft
        ) ?? false
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(currentStep, forKey: .currentStep)
        try container.encode(bodyScoreInput, forKey: .bodyScoreInput)
        try container.encode(heightUnit, forKey: .heightUnit)
        try container.encode(weightUnit, forKey: .weightUnit)
        try container.encode(heightCentimetersText, forKey: .heightCentimetersText)
        try container.encode(heightFeet, forKey: .heightFeet)
        try container.encode(heightInches, forKey: .heightInches)
        try container.encode(manualWeightText, forKey: .manualWeightText)
        try container.encode(bodyFatPercentageText, forKey: .bodyFatPercentageText)
        try container.encodeIfPresent(selectedVisualBodyFat, forKey: .selectedVisualBodyFat)
        try container.encode(defaultHomeMode, forKey: .defaultHomeMode)
        try container.encode(didRequestHealthSync, forKey: .didRequestHealthSync)
        try container.encode(emailAddress, forKey: .emailAddress)
        try container.encode(profileFirstName, forKey: .profileFirstName)
        try container.encode(profileLastName, forKey: .profileLastName)
        try container.encode(profileDateOfBirth, forKey: .profileDateOfBirth)
        try container.encodeIfPresent(profileBiologicalSex, forKey: .profileBiologicalSex)
        try container.encode(profileHeightUnit, forKey: .profileHeightUnit)
        try container.encode(profileHeightCentimetersText, forKey: .profileHeightCentimetersText)
        try container.encode(profileHeightFeet, forKey: .profileHeightFeet)
        try container.encode(profileHeightInches, forKey: .profileHeightInches)
        try container.encode(profileDetailsActiveSubstep, forKey: .profileDetailsActiveSubstep)
        try container.encode(profileShouldAskSex, forKey: .profileShouldAskSex)
        try container.encode(hasHydratedProfileDetailsDraft, forKey: .hasHydratedProfileDetailsDraft)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

struct OnboardingProfileUpdateBuilder {
    static func buildUpdates(
        bodyScoreInput: BodyScoreInput,
        heightUnit: HeightUnit
    ) -> [String: Any] {
        var updates: [String: Any] = [:]

        if let sex = bodyScoreInput.sex {
            updates["gender"] = sex.description
        }

        if let birthYear = bodyScoreInput.birthYear,
           let dateOfBirth = Calendar.current.date(from: DateComponents(year: birthYear, month: 1, day: 1)) {
            updates["dateOfBirth"] = dateOfBirth
        }

        if let heightCm = bodyScoreInput.height.inCentimeters {
            updates["height"] = heightCm

            let preferredHeightUnit: String
            switch heightUnit {
            case .centimeters:
                preferredHeightUnit = "cm"
            case .inches:
                preferredHeightUnit = "in"
            }

            updates["heightUnit"] = preferredHeightUnit
        }

        updates["onboardingCompleted"] = true

        return updates
    }
}

final class OnboardingProgressStore {
    static let shared = OnboardingProgressStore()
    static let snapshotVersion = 1

    let userDefaults: UserDefaults
    let storageKey = "bodyScoreOnboardingProgress"
    var snapshots: [String: OnboardingProgressSnapshot] = [:]
    let queue = DispatchQueue(label: "com.logyourbody.onboarding.progressStore", qos: .utility)

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDisk()
    }

    func save(_ snapshot: OnboardingProgressSnapshot, for userId: String) {
        queue.sync {
            guard snapshot.version == Self.snapshotVersion else { return }
            snapshots[userId] = snapshot
            persistToDiskLocked()
        }
    }

    func loadProgress(for userId: String) -> OnboardingProgressSnapshot? {
        queue.sync {
            guard let snapshot = snapshots[userId], snapshot.version == Self.snapshotVersion else { return nil }
            return snapshot
        }
    }

    #if DEBUG
    func snapshotForTesting(for userId: String) -> (
        currentStep: OnboardingFlowViewModel.Step,
        defaultHomeMode: DefaultHomeMode,
        profileFirstName: String,
        profileLastName: String,
        profileDateOfBirth: Date,
        profileBiologicalSex: BiologicalSex?,
        profileHeightUnit: HeightUnit,
        profileHeightCentimetersText: String,
        profileHeightFeet: Int,
        profileHeightInches: Int,
        profileDetailsActiveSubstep: OnboardingFlowViewModel.ProfileDetailsSubstep
    )? {
        queue.sync {
            guard let snapshot = snapshots[userId], snapshot.version == Self.snapshotVersion else { return nil }
            return (
                snapshot.currentStep,
                snapshot.defaultHomeMode,
                snapshot.profileFirstName,
                snapshot.profileLastName,
                snapshot.profileDateOfBirth,
                snapshot.profileBiologicalSex,
                snapshot.profileHeightUnit,
                snapshot.profileHeightCentimetersText,
                snapshot.profileHeightFeet,
                snapshot.profileHeightInches,
                snapshot.profileDetailsActiveSubstep
            )
        }
    }
    #endif

    func clearProgress(for userId: String) {
        queue.sync {
            guard snapshots.removeValue(forKey: userId) != nil else { return }
            persistToDiskLocked()
        }
    }

    func loadFromDisk() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: OnboardingProgressSnapshot].self, from: data) {
            snapshots = decoded.filter { $0.value.version == Self.snapshotVersion }
        }
    }

    func persistToDiskLocked() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(snapshots) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
