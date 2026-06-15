import SwiftUI
import Combine

private func defaultProfileDateOfBirth() -> Date {
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
    @Published var defaultHomeMode: DefaultHomeMode = .default {
        didSet {
            UserDefaults.standard.set(defaultHomeMode.rawValue, forKey: Constants.defaultHomeModeKey)
            persistProgress()
        }
    }
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
    @Published var isCreatingAccount: Bool = false
    @Published var accountCreationError: String?
    @Published private(set) var accountCreationStage: AccountCreationStage = .idle
    @Published private(set) var onboardingFirstPhotoMetric: BodyMetrics?
    @Published private(set) var isPreparingFirstPhotoMetric = false
    @Published private(set) var isCompletingOnboarding = false
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
    @Published private(set) var hasHydratedProfileDetailsDraft = false {
        didSet { persistProgress() }
    }

    let entryContext: EntryContext
    let includesFirstPhotoStep: Bool
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

    private var hasAuthenticatedAccountEmail: Bool {
        guard entryContext == .authenticated else { return false }
        guard let email = AuthManager.shared.currentUser?.email else { return false }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        entryContext: EntryContext = .authenticated,
        healthKitManager: HealthKitManager = .shared,
        calculator: BodyScoreCalculating = BodyScoreCalculator(),
        includesFirstPhotoStep: Bool? = nil
    ) {
        self.entryContext = entryContext
        self.healthKitManager = healthKitManager
        self.calculator = calculator
        self.includesFirstPhotoStep = includesFirstPhotoStep
            ?? (entryContext == .authenticated && PhotoTimelineHUDPolicy.shouldShowPhotoTimelineHUD())

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

    func goToNextStep() {
        let previousStep = currentStep

        switch currentStep {
        case .hook:
            currentStep = .basics
        case .basics:
            currentStep = .height
        case .height:
            currentStep = .healthConnect
        case .healthConnect:
            currentStep = healthKitManager.isAuthorized ? .healthConfirmation : .manualWeight
        case .healthConfirmation:
            advanceAfterHealthConfirmation()
        case .manualWeight:
            currentStep = nextStepAfterWeightEntry()
        case .bodyFatChoice:
            advanceFromBodyFatChoice()
        case .bodyFatNumeric, .bodyFatVisual:
            currentStep = .loading
        case .loading:
            currentStep = .bodyScore
        case .bodyScore:
            currentStep = .defaultHomeMode
        case .defaultHomeMode:
            advanceFromDefaultHomeMode()
        case .emailCapture:
            advanceFromEmailCapture()
        case .account:
            if entryContext == .preAuth {
                AnalyticsService.shared.track(
                    event: "onboarding_pre_auth_completed"
                )

                NotificationCenter.default.post(
                    name: .preAuthOnboardingCompleted,
                    object: nil
                )
            } else {
                currentStep = .profileDetails
            }
        case .profileDetails:
            if includesFirstPhotoStep {
                currentStep = .firstPhoto
            } else {
                Task {
                    await finishOnboardingAndShowPaywall(from: previousStep)
                }
                return
            }
        case .firstPhoto:
            Task {
                await finishOnboardingAndShowPaywall(from: previousStep)
            }
            return
        case .paywall:
            break
        }

        let newStep = currentStep
        trackStepTransition(from: previousStep, to: newStep)
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
        case .loading:
            bodyScoreResult = nil
            isLoading = false
            errorMessage = nil
            currentStep = .bodyFatChoice
        case .bodyScore:
            bodyScoreResult = nil
            isLoading = false
            errorMessage = nil
            currentStep = .bodyFatChoice
        case .defaultHomeMode:
            currentStep = .bodyScore
        case .emailCapture:
            currentStep = .defaultHomeMode
        case .account:
            currentStep = hasAuthenticatedAccountEmail ? .bodyScore : .emailCapture
        case .profileDetails:
            currentStep = hasAuthenticatedAccountEmail ? .defaultHomeMode : .account
        case .firstPhoto: currentStep = .profileDetails
        case .paywall: currentStep = includesFirstPhotoStep ? .firstPhoto : .profileDetails
        }
    }

    private func advanceFromBodyFatChoice() {
        switch bodyScoreInput.bodyFat.source {
        case .manualValue: currentStep = .bodyFatNumeric
        case .visualEstimate: currentStep = .bodyFatVisual
        default: currentStep = hasBodyFatEntry ? .loading : .bodyFatChoice
        }
    }

    private func advanceFromDefaultHomeMode() {
        UserDefaults.standard.set(defaultHomeMode.rawValue, forKey: Constants.defaultHomeModeKey)

        if entryContext == .preAuth {
            if let result = bodyScoreResult {
                PreAuthOnboardingStore.shared.save(
                    input: bodyScoreInput,
                    result: result,
                    defaultHomeMode: defaultHomeMode
                )
            }
            currentStep = .emailCapture
        } else {
            if hasAuthenticatedAccountEmail {
                if emailAddress.isEmpty {
                    emailAddress = AuthManager.shared.currentUser?.email ?? ""
                }
                currentStep = .profileDetails
            } else {
                currentStep = .emailCapture
            }
        }
    }

    private func advanceFromEmailCapture() {
        if entryContext == .preAuth {
            currentStep = .account
        } else if hasAuthenticatedAccountEmail {
            if emailAddress.isEmpty {
                emailAddress = AuthManager.shared.currentUser?.email ?? ""
            }
            currentStep = .profileDetails
        } else {
            currentStep = .account
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

    private func firstMissingInputStep() -> Step {
        if bodyScoreInput.sex == nil {
            return .basics
        }

        if bodyScoreInput.height.inCentimeters == nil {
            return .height
        }

        if bodyScoreInput.weight.inKilograms == nil {
            return healthKitManager.isAuthorized ? .healthConfirmation : .manualWeight
        }

        if bodyScoreInput.bodyFat.percentage == nil {
            return .bodyFatChoice
        }

        return .bodyFatChoice
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

    private func trackStepTransition(from: Step, to: Step) {
        guard from != to else { return }

        AnalyticsService.shared.track(
            event: "onboarding_step_advanced",
            properties: [
                "from_step": from.rawValue,
                "to_step": to.rawValue,
                "entry_context": entryContext.analyticsContext
            ]
        )
    }

    func progress(for step: Step) -> ProgressContext? {
        let steps = activeProgressSteps
        guard let index = steps.firstIndex(of: step) else { return nil }
        return ProgressContext(
            currentIndex: index + 1,
            totalCount: steps.count,
            label: step.progressLabel
        )
    }

    private var activeProgressSteps: [Step] {
        Step.progressSequence.filter { shouldIncludeInProgress($0) }
    }

    private func shouldIncludeInProgress(_ step: Step) -> Bool {
        switch step {
        case .hook, .basics, .height, .healthConnect, .bodyScore, .defaultHomeMode, .profileDetails:
            return true
        case .firstPhoto:
            return includesFirstPhotoStep
        case .emailCapture, .account:
            return !hasAuthenticatedAccountEmail
        case .healthConfirmation:
            return healthKitManager.isAuthorized
        case .manualWeight:
            return !hasWeightEntry
        case .bodyFatChoice:
            return !hasBodyFatEntry
        case .bodyFatNumeric:
            return bodyScoreInput.bodyFat.source == .manualValue
        case .bodyFatVisual:
            return bodyScoreInput.bodyFat.source == .visualEstimate
        case .loading, .paywall:
            return false
        }
    }

    // MARK: - HealthKit

    func attemptHealthImport() async {
        AnalyticsService.shared.track(
            event: "onboarding_health_import_attempt"
        )

        guard healthKitManager.isHealthKitAvailable else {
            AnalyticsService.shared.track(
                event: "onboarding_health_import_unavailable"
            )
            currentStep = .manualWeight
            return
        }

        let granted = await healthKitManager.requestAuthorization()
        if granted {
            didRequestHealthSync = true
            AnalyticsService.shared.track(
                event: "onboarding_health_import_authorized"
            )
            currentStep = .healthConfirmation
            await fetchHealthMetrics()
        } else {
            AnalyticsService.shared.track(
                event: "onboarding_health_import_denied"
            )
            currentStep = .manualWeight
        }
    }

    func fetchHealthMetrics() async {
        async let weightResult = healthKitManager.fetchLatestWeight()
        async let bodyFatResult = healthKitManager.fetchLatestBodyFatPercentage()
        async let heightResult = healthKitManager.fetchLatestHeight()

        do {
            let (weight, bodyFat, height) = try await (weightResult, bodyFatResult, heightResult)

            if let pounds = weight.weight {
                // HealthKitManager returns pounds; convert once so manual entry stays accurate
                let weightInKilograms = pounds * 0.45359237
                let preferredUnit = weightUnit
                let value = preferredUnit == .kilograms ? weightInKilograms : pounds
                bodyScoreInput.weight = WeightValue(value: value, unit: preferredUnit)
                bodyScoreInput.healthSnapshot.weightKg = weightInKilograms
                bodyScoreInput.healthSnapshot.weightDate = weight.date
                manualWeightText = Self.formatNumber(value)
            }

            if let bf = bodyFat.percentage {
                bodyScoreInput.bodyFat = BodyFatValue(percentage: bf, source: .healthKit)
                bodyScoreInput.healthSnapshot.bodyFatPercentage = bf
                bodyScoreInput.healthSnapshot.bodyFatDate = bodyFat.date
            }

            if let heightCm = height.value {
                bodyScoreInput.height = HeightValue(value: heightCm, unit: .centimeters)
                bodyScoreInput.healthSnapshot.heightCm = heightCm
                bodyScoreInput.healthSnapshot.heightDate = height.date
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
            isLoading = false
            currentStep = firstMissingInputStep()
            return
        }

        AnalyticsService.shared.track(
            event: "onboarding_body_score_calculation_attempt",
            properties: [
                "entry_context": entryContext.analyticsContext
            ]
        )

        isLoading = true
        currentStep = .loading

        do {
            let context = BodyScoreCalculationContext(input: bodyScoreInput)
            let result = try calculator.calculateScore(context: context)
            BodyScoreCache.shared.store(result, for: AuthManager.shared.currentUser?.id)

            AnalyticsService.shared.track(
                event: "onboarding_body_score_calculation_succeeded",
                properties: [
                    "entry_context": entryContext.analyticsContext
                ]
            )

            await MainActor.run {
                self.bodyScoreResult = result
                self.currentStep = .bodyScore
                self.isLoading = false
                self.errorMessage = nil
            }
        } catch {
            AnalyticsService.shared.track(
                event: "onboarding_body_score_calculation_failed",
                properties: [
                    "entry_context": entryContext.analyticsContext
                ]
            )

            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.currentStep = .bodyFatChoice
            }
        }
    }

    func calculateScoreIfNeeded() async {
        guard !isLoading else { return }
        await calculateScore()
    }

    // MARK: - Input Helpers

    var canContinueBasics: Bool {
        bodyScoreInput.sex != nil
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

    var canContinueDefaultHomeMode: Bool {
        true
    }

    private var trimmedEmailAddress: String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    var canContinueEmailCapture: Bool {
        let trimmed = trimmedEmailAddress
        guard !trimmed.isEmpty else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    var canContinueAccountCreation: Bool {
        canContinueEmailCapture
    }

    func updateSex(_ sex: BiologicalSex) {
        bodyScoreInput.sex = sex
    }

    func updateDefaultHomeMode(_ mode: DefaultHomeMode) {
        defaultHomeMode = mode
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
        emailAddress = trimmedEmailAddress
        AnalyticsService.shared.track(
            event: "onboarding_email_captured",
            properties: [
                "entry_context": entryContext.analyticsContext
            ]
        )
    }

    func createAccount(authManager: AuthManager) async {
        guard canContinueAccountCreation else { return }

        await MainActor.run {
            isCreatingAccount = true
            accountCreationError = nil
            accountCreationStage = .preparing
        }

        if authManager.isAuthenticated {
            await MainActor.run {
                accountCreationStage = .finalizing
                accountCreationStage = .idle
                isCreatingAccount = false
                goToNextStep()
            }
            return
        }

        do {
            await MainActor.run {
                accountCreationStage = .creatingAccount
            }
            try await authManager.signUp(
                email: trimmedEmailAddress,
                password: "",
                name: ""
            )

            AnalyticsService.shared.track(
                event: "onboarding_account_created",
                properties: [
                    "entry_context": entryContext.analyticsContext,
                    "method": "email_otp"
                ]
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
            AnalyticsService.shared.track(
                event: "onboarding_account_creation_failed",
                properties: [
                    "entry_context": entryContext.analyticsContext
                ]
            )

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

    func hydrateProfileDetailsDraftIfNeeded(from user: User?) {
        guard !hasHydratedProfileDetailsDraft else { return }

        isRestoringProgress = true

        guard let user else {
            if profileBiologicalSex == nil {
                profileBiologicalSex = bodyScoreInput.sex
            }

            profileShouldAskSex = profileBiologicalSex == nil
            recomputeProfileDetailsActiveSubstep()
            isRestoringProgress = false
            persistProgress()
            return
        }

        hydrateProfileName(from: user)

        if let existingDob = user.profile?.dateOfBirth {
            profileDateOfBirth = existingDob
        }

        if let existingGender = user.profile?.gender {
            profileBiologicalSex = Self.biologicalSex(from: existingGender)
        }

        if let existingHeight = user.profile?.height, existingHeight > 0 {
            hydrateProfileHeight(
                centimeters: existingHeight,
                storedUnit: user.profile?.heightUnit
            )
        }

        if profileBiologicalSex == nil {
            profileBiologicalSex = bodyScoreInput.sex
        }

        profileShouldAskSex = profileBiologicalSex == nil
        recomputeProfileDetailsActiveSubstep()
        hasHydratedProfileDetailsDraft = true

        isRestoringProgress = false
        persistProgress()
    }

    func updateProfileBiologicalSex(_ sex: BiologicalSex) {
        profileBiologicalSex = sex
        updateSex(sex)
    }

    private func applyFirstPhotoUITestFixtureIfNeeded() {
        guard entryContext == .authenticated else { return }
        guard ProcessInfo.processInfo.arguments.contains("-lybUITestBodyScoreFirstPhotoFixture") else { return }

        isRestoringProgress = true
        bodyScoreInput = BodyScoreInput(
            sex: .male,
            birthYear: 1_990,
            height: HeightValue(value: 178, unit: .centimeters),
            weight: WeightValue(value: 185, unit: .pounds),
            bodyFat: BodyFatValue(percentage: 18, source: .manualValue)
        )
        bodyScoreResult = BodyScoreResult(
            score: 82,
            ffmi: 21.4,
            leanPercentile: 0.72,
            ffmiStatus: "Strong",
            targetBodyFat: .init(lowerBound: 10, upperBound: 15, label: "Athletic"),
            statusTagline: "Strong base"
        )
        defaultHomeMode = .photo
        profileFirstName = "Onboarding"
        profileLastName = "UI"
        profileDateOfBirth = Calendar.current.date(from: DateComponents(year: 1_990, month: 1, day: 1))
            ?? defaultProfileDateOfBirth()
        profileBiologicalSex = .male
        profileHeightUnit = .centimeters
        profileHeightCentimetersText = "178"
        profileShouldAskSex = false
        hasHydratedProfileDetailsDraft = true
        currentStep = .firstPhoto
        isRestoringProgress = false
        persistProgress()
    }

    func completeOnboardingIfNeeded() async {
        guard entryContext == .authenticated else { return }
        guard !hasMarkedOnboardingComplete else { return }
        hasMarkedOnboardingComplete = true
        isCompletingOnboarding = true
        defer { isCompletingOnboarding = false }

        let updates = buildOnboardingProfileUpdates()
        await AuthManager.shared.updateProfile(updates)
        applyCompletedOnboardingLocally(with: updates)
        OnboardingStateManager.shared.markCompleted()
        UserDefaults.standard.set(defaultHomeMode.rawValue, forKey: Constants.defaultHomeModeKey)
        clearPersistedProgress()
        PreAuthOnboardingStore.shared.clear()

        if didRequestHealthSync, UserDefaults.standard.bool(forKey: "healthKitSyncEnabled") {
            scheduleDeferredHealthSync()
        }
    }

    func completeFirstPhotoStep() async {
        await finishOnboardingAndShowPaywall(from: currentStep)
    }

    func finishOnboardingAndShowPaywall() async {
        await finishOnboardingAndShowPaywall(from: currentStep)
    }

    private func finishOnboardingAndShowPaywall(from previousStep: Step) async {
        await completeOnboardingIfNeeded()
        currentStep = .paywall
        trackStepTransition(from: previousStep, to: currentStep)
    }

    private func applyCompletedOnboardingLocally(with updates: [String: Any]) {
        guard var currentUser = AuthManager.shared.currentUser else { return }

        let existingProfile = currentUser.profile
        let updatedProfile = UserProfile(
            id: existingProfile?.id ?? currentUser.id,
            email: existingProfile?.email ?? currentUser.email,
            username: existingProfile?.username,
            fullName: existingProfile?.fullName ?? currentUser.name,
            dateOfBirth: updates["dateOfBirth"] as? Date ?? existingProfile?.dateOfBirth,
            height: updates["height"] as? Double ?? existingProfile?.height,
            heightUnit: updates["heightUnit"] as? String ?? existingProfile?.heightUnit,
            gender: updates["gender"] as? String ?? existingProfile?.gender,
            activityLevel: existingProfile?.activityLevel,
            goalWeight: existingProfile?.goalWeight,
            goalWeightUnit: existingProfile?.goalWeightUnit,
            onboardingCompleted: true
        )

        currentUser.profile = updatedProfile
        currentUser.onboardingCompleted = true
        AuthManager.shared.currentUser = currentUser
    }

    func prepareFirstPhotoBaselineMetric() async -> BodyMetrics? {
        guard entryContext == .authenticated else { return nil }
        if let onboardingFirstPhotoMetric {
            return onboardingFirstPhotoMetric
        }

        guard let userId = AuthManager.shared.currentUser?.id else {
            firstPhotoErrorMessage = "Sign in again to add a progress photo."
            return nil
        }

        isPreparingFirstPhotoMetric = true
        firstPhotoErrorMessage = nil
        defer { isPreparingFirstPhotoMetric = false }

        let metric = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: Date(),
            weight: bodyScoreInput.weight.inKilograms,
            bodyFatPercentage: bodyScoreInput.bodyFat.percentage,
            userId: userId,
            dataSource: firstPhotoBaselineDataSource,
            preserveExistingMeasurements: true
        )
        onboardingFirstPhotoMetric = metric
        return metric
    }

    private var firstPhotoBaselineDataSource: String {
        if didRequestHealthSync || bodyScoreInput.bodyFat.source == .healthKit {
            return BodyMetricSource.healthKit.rawValue
        }

        return BodyMetricSource.manual.rawValue
    }

    private func scheduleDeferredHealthSync() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            let shouldSync = await MainActor.run {
                self.didRequestHealthSync
            }

            guard shouldSync else { return }

            await HealthSyncCoordinator.shared.runDeferredOnboardingWeightSync()
        }
    }

    func buildOnboardingProfileUpdates() -> [String: Any] {
        var updates = OnboardingProfileUpdateBuilder.buildUpdates(
            bodyScoreInput: bodyScoreInput,
            heightUnit: heightUnit
        )

        guard hasHydratedProfileDetailsDraft else {
            return updates
        }

        if let profileBiologicalSex {
            updates["gender"] = profileBiologicalSex.description
        }

        updates["dateOfBirth"] = profileDateOfBirth

        if let profileHeightInCentimeters {
            updates["height"] = profileHeightInCentimeters
            updates["heightUnit"] = profileHeightUnitStorageValue
        }

        return updates
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

    var isHealthKitConnected: Bool {
        healthKitManager.isAuthorized
    }

    var latestHealthSampleDate: Date? {
        let dates = [
            healthKitManager.latestWeightDate,
            healthKitManager.latestBodyFatDate,
            healthKitManager.latestStepCountDate
        ]
        return dates.compactMap { $0 }.max()
    }

    var healthKitConnectionStatusText: String? {
        guard isHealthKitConnected else { return nil }
        guard let date = latestHealthSampleDate else {
            return "Connected to Apple Health"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Connected • Last synced \(relative)"
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
        let localePrefersMetric = Locale.current.measurementSystem == .metric

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

    private static func biologicalSex(from gender: String) -> BiologicalSex? {
        let normalized = gender.lowercased()
        if normalized.contains("female") || normalized.contains("woman") {
            return .female
        }
        if normalized.contains("male") || normalized.contains("man") {
            return .male
        }
        return nil
    }

    private func hydrateProfileName(from user: User) {
        let baseName = user.profile?.fullName ?? user.name ?? ""
        let components = baseName.split(separator: " ")
        guard !components.isEmpty else { return }

        profileFirstName = String(components.first ?? "")
        if components.count > 1 {
            profileLastName = components.dropFirst().joined(separator: " ")
        }
    }

    private func hydrateProfileHeight(centimeters: Double, storedUnit: String?) {
        if storedUnit?.lowercased() == "in" {
            profileHeightUnit = .inches
            let totalInches = Int((centimeters / 2.54).rounded())
            profileHeightFeet = max(3, min(8, totalInches / 12))
            profileHeightInches = max(0, min(11, totalInches % 12))
        } else {
            profileHeightUnit = .centimeters
        }

        profileHeightCentimetersText = String(format: "%.0f", centimeters)
    }

    private var profileHeightInCentimeters: Double? {
        switch profileHeightUnit {
        case .centimeters:
            return Double(profileHeightCentimetersText)
        case .inches:
            let totalInches = Double((profileHeightFeet * 12) + profileHeightInches)
            return totalInches > 0 ? totalInches * 2.54 : nil
        }
    }

    private var profileHeightUnitStorageValue: String {
        switch profileHeightUnit {
        case .centimeters:
            return "cm"
        case .inches:
            return "in"
        }
    }

    private func recomputeProfileDetailsActiveSubstep() {
        let trimmedFirstName = profileFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = profileLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let age = Calendar.current.dateComponents([.year], from: profileDateOfBirth, to: Date()).year

        if trimmedFirstName.isEmpty {
            profileDetailsActiveSubstep = .firstName
        } else if trimmedLastName.isEmpty {
            profileDetailsActiveSubstep = .lastName
        } else if (age ?? 0) < 16 || (age ?? 0) > 80 {
            profileDetailsActiveSubstep = .dateOfBirth
        } else if profileShouldAskSex && profileBiologicalSex == nil {
            profileDetailsActiveSubstep = .sex
        } else {
            profileDetailsActiveSubstep = .height
        }
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

    private func hydrateDefaultHomeMode() {
        let storedValue = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey) ?? DefaultHomeMode.default.rawValue
        defaultHomeMode = DefaultHomeMode(storedValue: storedValue)
    }

    // MARK: - Progress Persistence

    private func persistProgress() {
        guard entryContext == .authenticated else { return }
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
            defaultHomeMode: defaultHomeMode,
            didRequestHealthSync: didRequestHealthSync,
            emailAddress: emailAddress,
            profileFirstName: profileFirstName,
            profileLastName: profileLastName,
            profileDateOfBirth: profileDateOfBirth,
            profileBiologicalSex: profileBiologicalSex,
            profileHeightUnit: profileHeightUnit,
            profileHeightCentimetersText: profileHeightCentimetersText,
            profileHeightFeet: profileHeightFeet,
            profileHeightInches: profileHeightInches,
            profileDetailsActiveSubstep: profileDetailsActiveSubstep,
            profileShouldAskSex: profileShouldAskSex,
            hasHydratedProfileDetailsDraft: hasHydratedProfileDetailsDraft,
            lastUpdated: Date()
        )

        progressStore.save(snapshot, for: userId)
    }

    private func restorePersistedProgressIfNeeded() {
        guard entryContext == .authenticated else { return }
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        guard !OnboardingStateManager.shared.hasCompletedCurrentVersion else {
            progressStore.clearProgress(for: userId)
            return
        }

        if let snapshot = progressStore.loadProgress(for: userId), snapshot.currentStep != .paywall {
            restore(snapshot)
            return
        }

        restorePreAuthSnapshotIfNeeded(for: userId)
    }

    private func restore(_ snapshot: OnboardingProgressSnapshot) {
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
        defaultHomeMode = snapshot.defaultHomeMode
        didRequestHealthSync = snapshot.didRequestHealthSync
        emailAddress = snapshot.emailAddress
        profileFirstName = snapshot.profileFirstName
        profileLastName = snapshot.profileLastName
        profileDateOfBirth = snapshot.profileDateOfBirth
        profileBiologicalSex = snapshot.profileBiologicalSex
        profileHeightUnit = snapshot.profileHeightUnit
        profileHeightCentimetersText = snapshot.profileHeightCentimetersText
        profileHeightFeet = snapshot.profileHeightFeet
        profileHeightInches = snapshot.profileHeightInches
        profileDetailsActiveSubstep = snapshot.profileDetailsActiveSubstep
        profileShouldAskSex = snapshot.profileShouldAskSex
        hasHydratedProfileDetailsDraft = snapshot.hasHydratedProfileDetailsDraft
        if hasAuthenticatedAccountEmail,
           currentStep == .emailCapture || currentStep == .account {
            currentStep = .profileDetails
        }
        if currentStep == .firstPhoto, !includesFirstPhotoStep {
            currentStep = .profileDetails
        }
        isRestoringProgress = false
    }

    private func restorePreAuthSnapshotIfNeeded(for userId: String) {
        guard let snapshot = PreAuthOnboardingStore.shared.load() else { return }

        isRestoringProgress = true
        bodyScoreInput = snapshot.input
        bodyScoreResult = snapshot.result
        defaultHomeMode = snapshot.defaultHomeMode
        if emailAddress.isEmpty {
            emailAddress = AuthManager.shared.currentUser?.email ?? ""
        }
        currentStep = hasAuthenticatedAccountEmail ? .profileDetails : .emailCapture
        isRestoringProgress = false

        BodyScoreCache.shared.store(snapshot.result, for: userId)
        persistProgress()
        PreAuthOnboardingStore.shared.clear()
    }

    private func clearPersistedProgress() {
        guard entryContext == .authenticated else { return }
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        progressStore.clearProgress(for: userId)
    }
}

private extension OnboardingFlowViewModel.Step {
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

private extension OnboardingProgressSnapshot {
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

    private let userDefaults: UserDefaults
    private let storageKey = "bodyScoreOnboardingProgress"
    private var snapshots: [String: OnboardingProgressSnapshot] = [:]
    private let queue = DispatchQueue(label: "com.logyourbody.onboarding.progressStore", qos: .utility)

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDisk()
    }

    fileprivate func save(_ snapshot: OnboardingProgressSnapshot, for userId: String) {
        queue.sync {
            guard snapshot.version == Self.snapshotVersion else { return }
            snapshots[userId] = snapshot
            persistToDiskLocked()
        }
    }

    fileprivate func loadProgress(for userId: String) -> OnboardingProgressSnapshot? {
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

    private func loadFromDisk() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([String: OnboardingProgressSnapshot].self, from: data) {
            snapshots = decoded.filter { $0.value.version == Self.snapshotVersion }
        }
    }

    private func persistToDiskLocked() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(snapshots) {
            userDefaults.set(data, forKey: storageKey)
        }
    }
}
