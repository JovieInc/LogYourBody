import SwiftUI
import Combine

extension OnboardingFlowViewModel {
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

func clearImportedMetricsForManualEntry() {
        bodyScoreInput.healthSnapshot = HealthImportSnapshot()
    }

var hasWeightEntry: Bool {
        bodyScoreInput.weight.value != nil
    }

var hasBodyFatEntry: Bool {
        bodyScoreInput.bodyFat.percentage != nil
    }

var hasAuthenticatedAccountEmail: Bool {
        guard entryContext == .authenticated else { return false }
        guard let email = AuthManager.shared.currentUser?.email else { return false }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                AppServicePorts.analyticsTracker.track(
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

func advanceFromBodyFatChoice() {
        switch bodyScoreInput.bodyFat.source {
        case .manualValue: currentStep = .bodyFatNumeric
        case .visualEstimate: currentStep = .bodyFatVisual
        default: currentStep = hasBodyFatEntry ? .loading : .bodyFatChoice
        }
    }

func advanceFromDefaultHomeMode() {
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

func advanceFromEmailCapture() {
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

func advanceAfterHealthConfirmation() {
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

func firstMissingInputStep() -> Step {
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

func decideManualWeightBack() {
        if bodyScoreInput.weight.value == nil {
            currentStep = .manualWeight
        } else if healthKitManager.isAuthorized {
            currentStep = .healthConfirmation
        } else {
            currentStep = .manualWeight
        }
    }

func nextStepAfterWeightEntry() -> Step {
        hasBodyFatEntry ? .loading : .bodyFatChoice
    }

func trackStepTransition(from: Step, to: Step) {
        guard from != to else { return }

        AppServicePorts.analyticsTracker.track(
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

var activeProgressSteps: [Step] {
        Step.progressSequence.filter { shouldIncludeInProgress($0) }
    }

func shouldIncludeInProgress(_ step: Step) -> Bool {
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
        AppServicePorts.analyticsTracker.track(
            event: "onboarding_health_import_attempt"
        )

        guard healthKitManager.isHealthKitAvailable else {
            AppServicePorts.analyticsTracker.track(
                event: "onboarding_health_import_unavailable"
            )
            currentStep = .manualWeight
            return
        }

        let granted = await healthKitManager.requestAuthorization()
        if granted {
            didRequestHealthSync = true
            AppServicePorts.analyticsTracker.track(
                event: "onboarding_health_import_authorized"
            )
            currentStep = .healthConfirmation
            await fetchHealthMetrics()
        } else {
            AppServicePorts.analyticsTracker.track(
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

        AppServicePorts.analyticsTracker.track(
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

            AppServicePorts.analyticsTracker.track(
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
            AppServicePorts.analyticsTracker.track(
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

var trimmedEmailAddress: String {
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
        AppServicePorts.analyticsTracker.track(
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
            try await authManager.signInWithPhone()

            AppServicePorts.analyticsTracker.track(
                event: "onboarding_account_created",
                properties: [
                    "entry_context": entryContext.analyticsContext,
                    "method": "sms_otp"
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
            AppServicePorts.analyticsTracker.track(
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
}
