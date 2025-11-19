import SwiftUI
import Combine

@MainActor
final class OnboardingFlowViewModel: ObservableObject {
    enum Step: Hashable {
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
        currentStep = .manualWeight
    }

    @Published var currentStep: Step = .hook
    @Published var bodyScoreInput = BodyScoreInput()
    @Published var canNavigateForward: Bool = false
    @Published var bodyScoreResult: BodyScoreResult?
    @Published var showEmailCaptureSheet = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var heightUnit: HeightUnit = .centimeters
    @Published private(set) var heightCentimetersText: String = ""
    @Published var heightFeet: Int = 5
    @Published var heightInches: Int = 10
    @Published var isRequestingHealthImport = false
    @Published var manualWeightText: String = ""
    @Published var bodyFatPercentageText: String = ""
    @Published var selectedVisualBodyFat: Double?
    @Published var emailAddress: String = ""
    @Published var accountPassword: String = ""
    @Published var isCreatingAccount: Bool = false
    @Published var accountCreationError: String?

    private let healthKitManager: HealthKitManager
    private let calculator: BodyScoreCalculating
    private var hasMarkedOnboardingComplete = false

    init(
        healthKitManager: HealthKitManager = .shared,
        calculator: BodyScoreCalculating = BodyScoreCalculator()
    ) {
        self.healthKitManager = healthKitManager
        self.calculator = calculator

        if let existingHeightCm = bodyScoreInput.height.inCentimeters {
            heightUnit = .centimeters
            heightCentimetersText = Self.formatHeight(existingHeightCm)
            updateImperialFields(fromCentimeters: existingHeightCm)
        } else if let existingInches = bodyScoreInput.height.inInches {
            heightUnit = .inches
            updateImperialFields(fromInches: existingInches)
            heightCentimetersText = Self.formatHeight(existingInches * 2.54)
        }

        if let pounds = bodyScoreInput.weight.inPounds {
            manualWeightText = Self.formatNumber(pounds)
        }

        if let bodyFat = bodyScoreInput.bodyFat.percentage {
            bodyFatPercentageText = Self.formatNumber(bodyFat)
        }
    }

    // MARK: - Flow Control

    func goToNextStep() {
        switch currentStep {
        case .hook: currentStep = .basics
        case .basics: currentStep = .height
        case .height: currentStep = .healthConnect
        case .healthConnect: currentStep = healthKitManager.isAuthorized ? .healthConfirmation : .manualWeight
        case .healthConfirmation: advanceAfterHealthConfirmation()
        case .manualWeight: currentStep = .bodyFatChoice
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
        if bodyScoreInput.weight.value != nil {
            currentStep = .bodyFatChoice
        } else {
            currentStep = .manualWeight
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

    // MARK: - HealthKit

    func attemptHealthImport() async {
        guard healthKitManager.isHealthKitAvailable else {
            currentStep = .manualWeight
            return
        }

        let granted = await healthKitManager.requestAuthorization()
        if granted {
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
                bodyScoreInput.weight = WeightValue(value: kg * 2.2046226218, unit: .pounds)
                bodyScoreInput.healthSnapshot.weightKg = kg
            }

            if let bf = bodyFat.percentage {
                bodyScoreInput.bodyFat = BodyFatValue(percentage: bf, source: .healthKit)
                bodyScoreInput.healthSnapshot.bodyFatPercentage = bf
            }

            if let heightCm = height.value {
                bodyScoreInput.height = HeightValue(value: heightCm, unit: .centimeters)
                bodyScoreInput.healthSnapshot.heightCm = heightCm
                await MainActor.run {
                    self.heightUnit = .centimeters
                    self.heightCentimetersText = Self.formatHeight(heightCm)
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
            try await Task.sleep(nanoseconds: 1_000_000_000 / 2)
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
        let pounds = Double(manualWeightText) ?? bodyScoreInput.weight.inPounds ?? 0
        return pounds >= 70
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

        switch unit {
        case .centimeters:
            let totalInches = Double((heightFeet * 12) + heightInches)
            let centimeters = totalInches * 2.54
            heightCentimetersText = Self.formatHeight(centimeters)
        case .inches:
            let centimeters = Double(bodyScoreInput.height.inCentimeters ?? Double(heightCentimetersText) ?? 0)
            if centimeters > 0 {
                updateImperialFields(fromCentimeters: centimeters)
            }
        }

        heightUnit = unit
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

    func persistManualWeightEntry(unit: WeightUnit = .pounds) {
        guard let value = Double(manualWeightText) else { return }
        bodyScoreInput.weight = WeightValue(value: value, unit: unit)
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
        }

        do {
            try await authManager.signUp(
                email: emailAddress,
                password: accountPassword,
                name: ""
            )

            await MainActor.run {
                self.isCreatingAccount = false
                self.goToNextStep()
            }
        } catch {
            await MainActor.run {
                self.isCreatingAccount = false
                self.accountCreationError = error.localizedDescription
            }
        }
    }

    func completeOnboardingIfNeeded() {
        guard !hasMarkedOnboardingComplete else { return }
        hasMarkedOnboardingComplete = true
        OnboardingStateManager.shared.markCompleted()
    }

    private static func formatHeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
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
}
