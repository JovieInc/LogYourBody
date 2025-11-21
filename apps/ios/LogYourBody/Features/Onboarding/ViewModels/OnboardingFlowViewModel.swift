import SwiftUI
import Combine

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
        case emailCapture
        case account
        case paywall
    }

    func startHealthKitImport() {
        guard !isRequestingHealthImport else { return }
        isRequestingHealthImport = true
        Task {
            await attemptHealthImport()
            await MainActor.run {
                self.isRequestingHealthImport = false
            }
        }
    }

    func skipHealthKit() {
        clearImportedMetricsForManualEntry()
        currentStep = .manualWeight
    }

    private func clearImportedMetricsForManualEntry() {
        bodyScoreInput.healthSnapshot = HealthImportSnapshot()
    }

    @Published var currentStep: Step = .hook {
        didSet { persistProgress() }
    }
    @Published var bodyScoreInput = BodyScoreInput() {
        didSet { persistProgress() }
    }
    @Published var canNavigateForward: Bool = false
    @Published var bodyScoreResult: BodyScoreResult?
    @Published var showEmailCaptureSheet = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var heightUnit: HeightUnit = .centimeters {
        didSet { persistProgress() }
    }
    @Published private(set) var weightUnit: WeightUnit = .pounds {
        didSet { persistProgress() }
    }
    @Published private(set) var heightCentimetersText: String = "" {
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
    @Published private(set) var didRequestHealthSync = false {
        didSet { persistProgress() }
    }
    @Published var emailAddress: String = "" {
        didSet { persistProgress() }
    }
    @Published var accountPassword: String = ""
    @Published var isCreatingAccount: Bool = false
    @Published var accountCreationError: String?
    @Published private(set) var accountCreationStage: AccountCreationStage = .idle

    private let healthKitManager: HealthKitManager
    private let calculator: BodyScoreCalculating
    private var hasMarkedOnboardingComplete = false
    private let progressStore = OnboardingProgressStore.shared
    private var isRestoringProgress = false

    private var hasWeightEntry: Bool {
        bodyScoreInput.weight.value != nil
    }

    private var hasBodyFatEntry: Bool {
        bodyScoreInput.bodyFat.percentage != nil
    }

    init(
        healthKitManager: HealthKitManager = .shared,
        calculator: BodyScoreCalculating = BodyScoreCalculator()
    ) {
        self.healthKitManager = healthKitManager
        self.calculator = calculator

        configureMeasurementPreference()
        hydrateHeightFields()
        hydrateWeightFields()

        if let bodyFat = bodyScoreInput.bodyFat.percentage {
            bodyFatPercentageText = Self.formatNumber(bodyFat)
        }

        restorePersistedProgressIfNeeded()
    }

    // MARK: - Flow Control

    func goToNextStep() {
        switch currentStep {
        case .hook: currentStep = .basics
        case .basics: currentStep = .height
        case .height: currentStep = .healthConnect
        case .healthConnect: currentStep = healthKitManager.isAuthorized ? .healthConfirmation : .manualWeight
        case .healthConfirmation: advanceAfterHealthConfirmation()
        case .manualWeight:
            currentStep = nextStepAfterWeightEntry()
        case .bodyFatChoice:
            switch bodyScoreInput.bodyFat.source {
            case .manualValue: currentStep = .bodyFatNumeric
            case .visualEstimate: currentStep = .bodyFatVisual
            default: currentStep = .loading
            }
        case .bodyFatNumeric, .bodyFatVisual: currentStep = .loading
        case .loading: currentStep = .bodyScore
        case .bodyScore: currentStep = .emailCapture
        case .emailCapture: currentStep = .account
        case .account:
            completeOnboardingIfNeeded()
            currentStep = .paywall
        case .paywall: break
        }
    }

    func goBack() {
        switch currentStep {
        case .hook: break
        case .basics: currentStep = .hook
        case .height: currentStep = .basics
        case .healthConnect: currentStep = .height
        case .healthConfirmation: currentStep = .healthConnect
        case .manualWeight: currentStep = .healthConnect
        case .bodyFatChoice: decideManualWeightBack()
        case .bodyFatNumeric, .bodyFatVisual: currentStep = .bodyFatChoice
        case .loading: currentStep = .bodyFatChoice
        case .bodyScore: currentStep = .bodyFatChoice
        case .emailCapture: currentStep = .bodyScore
        case .account: currentStep = .emailCapture
        case .paywall: currentStep = .account
        }
    }

    private func advanceAfterHealthConfirmation() {
        guard hasWeightEntry else {
            currentStep = .manualWeight
            return
        }

        if hasBodyFatEntry {
            currentStep = .loading
        } else {
            currentStep = .bodyFatChoice
        }
    }

    private func decideManualWeightBack() {
        if bodyScoreInput.weight.value == nil {
            currentStep = .manualWeight
        } else if healthKitManager.isAuthorized {
            currentStep = .healthConfirmation
        } else {
            currentStep = .manualWeight
        }
    }

    private func nextStepAfterWeightEntry() -> Step {
        hasBodyFatEntry ? .loading : .bodyFatChoice
    }

    // MARK: - HealthKit

    func attemptHealthImport() async {
        guard healthKitManager.isHealthKitAvailable else {
            currentStep = .manualWeight
            return
        }

        let granted = await healthKitManager.requestAuthorization()
        if granted {
            didRequestHealthSync = true
            currentStep = .healthConfirmation
            await fetchHealthMetrics()
        } else {
            currentStep = .manualWeight
        }
    }

    func fetchHealthMetrics() async {
        async let weightResult = healthKitManager.fetchLatestWeight()
        async let bodyFatResult = healthKitManager.fetchLatestBodyFatPercentage()
        async let heightResult = healthKitManager.fetchLatestHeight()

        do {
            let (weight, bodyFat, height) = try await (weightResult, bodyFatResult, heightResult)

            if let kg = weight.weight {
                let preferredUnit = weightUnit
                let value = preferredUnit == .kilograms ? kg : kg * 2.2046226218
                bodyScoreInput.weight = WeightValue(value: value, unit: preferredUnit)
                bodyScoreInput.healthSnapshot.weightKg = kg
                manualWeightText = Self.formatNumber(value)
            }

            if let bf = bodyFat.percentage {
                bodyScoreInput.bodyFat = BodyFatValue(percentage: bf, source: .healthKit)
                bodyScoreInput.healthSnapshot.bodyFatPercentage = bf
            }

            if let heightCm = height.value {
                bodyScoreInput.height = HeightValue(value: heightCm, unit: .centimeters)
                bodyScoreInput.healthSnapshot.heightCm = heightCm
                heightCentimetersText = Self.formatHeight(heightCm)
                if heightUnit == .inches {
                    updateImperialFields(fromCentimeters: heightCm)
                }
            }
        } catch {
            // Fail gracefully; user can continue manually
        }
    }

    // MARK: - Calculation

    func calculateScore() async {
        guard bodyScoreInput.isReadyForCalculation else {
            errorMessage = "Missing inputs for score calculation."
            return
        }

        isLoading = true
        currentStep = .loading

        do {
            let context = BodyScoreCalculationContext(input: bodyScoreInput)
            let result = try calculator.calculateScore(context: context)
            BodyScoreCache.shared.store(result, for: AuthManager.shared.currentUser?.id)
            await MainActor.run {
                self.bodyScoreResult = result
                self.currentStep = .bodyScore
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.currentStep = .bodyFatChoice
            }
        }
    }

    func calculateScoreIfNeeded() async {
        guard bodyScoreResult == nil else { return }
        if !isLoading {
            await calculateScore()
        }
    }

    // MARK: - Input Helpers

    var birthYearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 80)...(currentYear - 16)).reversed()
    }

    var defaultBirthYear: Int {
        birthYearOptions[birthYearOptions.count / 3]
    }

    var canContinueBasics: Bool {
        bodyScoreInput.sex != nil && bodyScoreInput.birthYear != nil
    }

    var canContinueHeight: Bool {
        switch heightUnit {
        case .centimeters:
            let numeric = Double(heightCentimetersText) ?? bodyScoreInput.height.inCentimeters ?? 0
            return numeric >= 100 // ~3'3"
        case .inches:
            let totalInches = Double((heightFeet * 12) + heightInches)
            return totalInches >= 48 // 4 feet minimum safeguard
        }
    }

    var canContinueWeight: Bool {
        let entered = Double(manualWeightText)
            ?? (weightUnit == .kilograms ? bodyScoreInput.weight.inKilograms : bodyScoreInput.weight.inPounds)
            ?? 0
        let poundsEquivalent = weightUnit == .kilograms ? entered * 2.2046226218 : entered
        return poundsEquivalent >= 70
    }

    var canContinueBodyFatChoice: Bool {
        bodyScoreInput.bodyFat.source != .unspecified
    }

    var canContinueBodyFatNumeric: Bool {
        let value = Double(bodyFatPercentageText) ?? 0
        return value >= 4 && value <= 60
    }

    var canContinueBodyFatVisual: Bool {
        selectedVisualBodyFat != nil
    }

    var canContinueEmailCapture: Bool {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    var canContinueAccountCreation: Bool {
        let password = accountPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return canContinueEmailCapture && password.count >= 8
    }

    func updateSex(_ sex: BiologicalSex) {
        bodyScoreInput.sex = sex
    }

    func updateBirthYear(_ year: Int) {
        bodyScoreInput.birthYear = year
    }

    func setHeightUnit(_ unit: HeightUnit) {
        guard heightUnit != unit else { return }

        convertHeightFields(to: unit)
        applyMeasurementSystem(unit.measurementSystem, skipHeight: true)
    }

    func updateHeightCentimetersText(_ text: String) {
        heightCentimetersText = text
    }

    func persistHeightEntry() {
        switch heightUnit {
        case .centimeters:
            if let value = Double(heightCentimetersText) {
                bodyScoreInput.height = HeightValue(value: value, unit: .centimeters)
            }
        case .inches:
            let total = Double((heightFeet * 12) + heightInches)
            guard total > 0 else { return }
            bodyScoreInput.height = HeightValue(value: total, unit: .inches)
            heightCentimetersText = Self.formatHeight(total * 2.54)
        }
    }

    func updateManualWeightText(_ text: String) {
        manualWeightText = text
    }

    func persistManualWeightEntry() {
        guard let value = Double(manualWeightText) else { return }
        bodyScoreInput.weight = WeightValue(value: value, unit: weightUnit)
    }

    func setWeightUnit(_ unit: WeightUnit) {
        guard weightUnit != unit else { return }

        convertWeightFields(to: unit)
        applyMeasurementSystem(unit.measurementSystem, skipWeight: true)
    }

    func updateBodyFatSource(_ source: BodyFatInputSource) {
        bodyScoreInput.bodyFat = BodyFatValue(percentage: bodyScoreInput.bodyFat.percentage, source: source)

        switch source {
        case .manualValue:
            if let existing = bodyScoreInput.bodyFat.percentage {
                bodyFatPercentageText = Self.formatNumber(existing)
            }
        case .visualEstimate:
            selectedVisualBodyFat = bodyScoreInput.bodyFat.percentage
        default:
            break
        }
    }

    func persistBodyFatPercentageEntry() {
        guard let value = Double(bodyFatPercentageText) else { return }
        bodyScoreInput.bodyFat = BodyFatValue(percentage: value, source: .manualValue)
    }

    func selectVisualBodyFat(_ value: Double) {
        selectedVisualBodyFat = value
        bodyScoreInput.bodyFat = BodyFatValue(percentage: value, source: .visualEstimate)
    }

    func persistEmailCapture() {
        emailAddress = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        // Placeholder for future analytics/backend hook
    }

    func createAccount(authManager: AuthManager) async {
        guard canContinueAccountCreation else { return }
        await MainActor.run {
            isCreatingAccount = true
            accountCreationError = nil
            accountCreationStage = .preparing
        }

        do {
            await MainActor.run {
                accountCreationStage = .creatingAccount
            }
            try await authManager.signUp(
                email: emailAddress,
                password: accountPassword,
                name: ""
            )

            await MainActor.run {
                accountCreationStage = .finalizing
            }

            await MainActor.run {
                self.accountCreationStage = .idle
                self.isCreatingAccount = false
                self.goToNextStep()
            }
        } catch {
            await MainActor.run {
                self.isCreatingAccount = false
                self.accountCreationStage = .idle
                self.accountCreationError = error.localizedDescription
            }
        }
    }

    var accountCreationStatusMessage: String? {
        accountCreationStage.statusMessage
    }

    func completeOnboardingIfNeeded() {
        guard !hasMarkedOnboardingComplete else { return }
        hasMarkedOnboardingComplete = true
        OnboardingStateManager.shared.markCompleted()
        Task {
            await AuthManager.shared.updateProfile(["onboardingCompleted": true])
        }
        clearPersistedProgress()

        if didRequestHealthSync {
            scheduleDeferredHealthSync()
        }
    }

    private func scheduleDeferredHealthSync() {
        Task.detached(priority: .background) {
            guard await MainActor.run(body: { self.didRequestHealthSync }) else { return }
            do {
                try await self.healthKitManager.syncWeightFromHealthKit()
            } catch {
                // Intentionally swallow errors; user can sync later from settings.
            }
        }
    }

    var weightFieldTitle: String {
        "Weight (\(weightUnit == .kilograms ? "kg" : "lbs"))"
    }

    var weightPlaceholder: String {
        weightUnit == .kilograms ? "80" : "175"
    }

    var weightHelperText: String {
        if weightUnit == .kilograms {
            return "Valid range: 32–300 kg • We'll store it in lbs too."
        }
        return "Valid range: 70–660 lbs • We'll store it in kg too."
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func updateImperialFields(fromCentimeters centimeters: Double) {
        let inches = centimeters / 2.54
        updateImperialFields(fromInches: inches)
    }

    private func updateImperialFields(fromInches inches: Double) {
        let totalInches = max(0, Int(round(inches)))
        heightFeet = max(3, min(8, totalInches / 12))
        heightInches = max(0, min(11, totalInches % 12))
    }

    private func configureMeasurementPreference() {
        let storedSystemRaw = UserDefaults.standard.string(forKey: Constants.preferredMeasurementSystemKey)
        let storedWeightUnitRaw = UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey)
        let localePrefersMetric = Locale.current.usesMetricSystem

        let measurementSystem: MeasurementSystem
        if let raw = storedSystemRaw, let system = MeasurementSystem(rawValue: raw) {
            measurementSystem = system
        } else if let weightRaw = storedWeightUnitRaw, let storedUnit = WeightUnit(rawValue: weightRaw) {
            measurementSystem = storedUnit.measurementSystem
        } else {
            measurementSystem = localePrefersMetric ? .metric : .imperial
        }

        applyMeasurementSystem(measurementSystem)
    }

    private func hydrateHeightFields() {
        if let centimeters = bodyScoreInput.height.inCentimeters {
            heightCentimetersText = Self.formatHeight(centimeters)
            if heightUnit == .inches {
                updateImperialFields(fromCentimeters: centimeters)
            }
        } else {
            heightCentimetersText = ""
        }
    }

    private func hydrateWeightFields() {
        if let existing = weightUnit == .kilograms ? bodyScoreInput.weight.inKilograms : bodyScoreInput.weight.inPounds {
            manualWeightText = Self.formatNumber(existing)
        } else {
            manualWeightText = ""
        }
    }

    private static func formatHeight(_ centimeters: Double) -> String {
        String(format: "%.1f", centimeters)
    }

    private func applyMeasurementSystem(_ system: MeasurementSystem, skipHeight: Bool = false, skipWeight: Bool = false) {
        let desiredHeightUnit: HeightUnit = system == .metric ? .centimeters : .inches
        let desiredWeightUnit: WeightUnit = system == .metric ? .kilograms : .pounds

        if !skipHeight {
            convertHeightFields(to: desiredHeightUnit)
        }

        if !skipWeight {
            convertWeightFields(to: desiredWeightUnit)
        }

        bodyScoreInput.measurementPreference = system
        persistMeasurementPreference(system)
    }

    private func convertHeightFields(to unit: HeightUnit) {
        guard heightUnit != unit else {
            heightUnit = unit
            return
        }

        switch unit {
        case .centimeters:
            let totalInches = Double((heightFeet * 12) + heightInches)
            if totalInches > 0 {
                let centimeters = totalInches * 2.54
                heightCentimetersText = Self.formatHeight(centimeters)
            } else if let centimeters = bodyScoreInput.height.inCentimeters {
                heightCentimetersText = Self.formatHeight(centimeters)
            }
        case .inches:
            let centimeters = Double(bodyScoreInput.height.inCentimeters ?? Double(heightCentimetersText) ?? 0)
            if centimeters > 0 {
                updateImperialFields(fromCentimeters: centimeters)
            }
        }

        heightUnit = unit
    }

    private func convertWeightFields(to unit: WeightUnit) {
        guard weightUnit != unit else { return }
        let previousUnit = weightUnit

        if let value = Double(manualWeightText) {
            let converted: Double
            if unit == .kilograms {
                converted = previousUnit == .kilograms ? value : value * 0.45359237
            } else {
                converted = previousUnit == .pounds ? value : value * 2.2046226218
            }
            manualWeightText = Self.formatNumber(converted)
        } else if let stored = unit == .kilograms ? bodyScoreInput.weight.inKilograms : bodyScoreInput.weight.inPounds {
            manualWeightText = Self.formatNumber(stored)
        }

        if let stored = unit == .kilograms ? bodyScoreInput.weight.inKilograms : bodyScoreInput.weight.inPounds {
            bodyScoreInput.weight = WeightValue(value: stored, unit: unit)
        } else if let value = Double(manualWeightText) {
            bodyScoreInput.weight = WeightValue(value: value, unit: unit)
        }

        weightUnit = unit
    }

    private func persistMeasurementPreference(_ system: MeasurementSystem) {
        UserDefaults.standard.set(system.rawValue, forKey: Constants.preferredMeasurementSystemKey)
        UserDefaults.standard.set(system.weightUnit, forKey: Constants.preferredWeightUnitKey)
    }

    // MARK: - Progress Persistence

    private func persistProgress() {
        guard !isRestoringProgress else { return }
        guard !OnboardingStateManager.shared.hasCompletedCurrentVersion else {
            clearPersistedProgress()
            return
        }
        guard let userId = AuthManager.shared.currentUser?.id else { return }

        let snapshot = OnboardingProgressSnapshot(
            version: OnboardingProgressStore.snapshotVersion,
            currentStep: currentStep,
            bodyScoreInput: bodyScoreInput,
            heightUnit: heightUnit,
            weightUnit: weightUnit,
            heightCentimetersText: heightCentimetersText,
            heightFeet: heightFeet,
            heightInches: heightInches,
            manualWeightText: manualWeightText,
            bodyFatPercentageText: bodyFatPercentageText,
            selectedVisualBodyFat: selectedVisualBodyFat,
            didRequestHealthSync: didRequestHealthSync,
            emailAddress: emailAddress,
            lastUpdated: Date()
        )

        progressStore.save(snapshot, for: userId)
    }

    private func restorePersistedProgressIfNeeded() {
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        guard !OnboardingStateManager.shared.hasCompletedCurrentVersion else {
            progressStore.clearProgress(for: userId)
            return
        }
        guard let snapshot = progressStore.loadProgress(for: userId), snapshot.currentStep != .paywall else {
            return
        }

        isRestoringProgress = true
        currentStep = snapshot.currentStep
        bodyScoreInput = snapshot.bodyScoreInput
        heightUnit = snapshot.heightUnit
        weightUnit = snapshot.weightUnit
        heightCentimetersText = snapshot.heightCentimetersText
        heightFeet = snapshot.heightFeet
        heightInches = snapshot.heightInches
        manualWeightText = snapshot.manualWeightText
        bodyFatPercentageText = snapshot.bodyFatPercentageText
        selectedVisualBodyFat = snapshot.selectedVisualBodyFat
        didRequestHealthSync = snapshot.didRequestHealthSync
        emailAddress = snapshot.emailAddress
        isRestoringProgress = false
    }

    private func clearPersistedProgress() {
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        progressStore.clearProgress(for: userId)
    }
}

// MARK: - Onboarding Progress Store

private struct OnboardingProgressSnapshot: Codable {
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
    let didRequestHealthSync: Bool
    let emailAddress: String
    let lastUpdated: Date
}

@MainActor
final class OnboardingProgressStore {
    static let shared = OnboardingProgressStore()
    static let snapshotVersion = 1

    private let userDefaults: UserDefaults
    private let storageKey = "bodyScoreOnboardingProgress"
    private var snapshots: [String: OnboardingProgressSnapshot] = [:]

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDisk()
    }

    fileprivate func save(_ snapshot: OnboardingProgressSnapshot, for userId: String) {
        guard snapshot.version == Self.snapshotVersion else { return }
        snapshots[userId] = snapshot
        persistToDisk()
    }

    fileprivate func loadProgress(for userId: String) -> OnboardingProgressSnapshot? {
        guard let snapshot = snapshots[userId], snapshot.version == Self.snapshotVersion else { return nil }
        return snapshot
    }

    func clearProgress(for userId: String) {
        guard snapshots.removeValue(forKey: userId) != nil else { return }
        persistToDisk()
    }

    private func loadFromDisk() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: OnboardingProgressSnapshot].self, from: data) {
            snapshots = decoded.filter { $0.value.version == Self.snapshotVersion }
        }
    }

    private func persistToDisk() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(snapshots) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
