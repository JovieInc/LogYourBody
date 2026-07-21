import SwiftUI
import Combine

extension OnboardingFlowViewModel {
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

func applyFirstPhotoUITestFixtureIfNeeded() {
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
            bodyFatReferenceRange: .init(lowerBound: 10, upperBound: 15, label: "Athletic"),
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

@discardableResult
    func completeOnboardingIfNeeded() async -> Bool {
        guard entryContext == .authenticated else { return true }
        guard !hasMarkedOnboardingComplete else { return true }
        guard !isOnboardingCompletionInFlight else { return false }
        isOnboardingCompletionInFlight = true
        isCompletingOnboarding = true
        defer {
            isOnboardingCompletionInFlight = false
            isCompletingOnboarding = false
        }

        let updates = buildOnboardingProfileUpdates()
        do {
            try await profileUpdateHandler(updates)
        } catch {
            let message = "We couldn't save your setup. Check your connection and try again."
            errorMessage = message
            firstPhotoErrorMessage = message
            return false
        }

        hasMarkedOnboardingComplete = true
        applyCompletedOnboardingLocally(with: updates)
        OnboardingStateManager.shared.markCompleted(userId: AuthManager.shared.currentUser?.id)
        UserDefaults.standard.set(defaultHomeMode.rawValue, forKey: Constants.defaultHomeModeKey)
        clearPersistedProgress()
        PreAuthOnboardingStore.shared.clear()

        if didRequestHealthSync, UserDefaults.standard.bool(forKey: Constants.healthKitSyncEnabledKey) {
            scheduleDeferredHealthSync()
        }

        return true
    }

func completeFirstPhotoStep() async {
        await finishOnboardingAndShowPaywall(from: currentStep)
    }

func finishOnboardingAndShowPaywall() async {
        await finishOnboardingAndShowPaywall(from: currentStep)
    }

func finishOnboardingAndShowPaywall(from previousStep: Step) async {
        guard await completeOnboardingIfNeeded() else { return }
        currentStep = .paywall
        trackStepTransition(from: previousStep, to: currentStep)
    }

func applyCompletedOnboardingLocally(with updates: [String: Any]) {
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

var firstPhotoBaselineDataSource: String {
        if didRequestHealthSync || bodyScoreInput.bodyFat.source == .healthKit {
            return BodyMetricSource.healthKit.rawValue
        }

        return BodyMetricSource.manual.rawValue
    }

func scheduleDeferredHealthSync() {
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

static func formatNumber(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

func updateImperialFields(fromCentimeters centimeters: Double) {
        let inches = centimeters / 2.54
        updateImperialFields(fromInches: inches)
    }

func updateImperialFields(fromInches inches: Double) {
        let totalInches = max(0, Int(round(inches)))
        heightFeet = max(3, min(8, totalInches / 12))
        heightInches = max(0, min(11, totalInches % 12))
    }

func configureMeasurementPreference() {
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

func hydrateHeightFields() {
        if let centimeters = bodyScoreInput.height.inCentimeters {
            heightCentimetersText = Self.formatHeight(centimeters)
            if heightUnit == .inches {
                updateImperialFields(fromCentimeters: centimeters)
            }
        } else {
            heightCentimetersText = ""
        }
    }

func hydrateWeightFields() {
        if let existing = weightUnit == .kilograms ? bodyScoreInput.weight.inKilograms : bodyScoreInput.weight.inPounds {
            manualWeightText = Self.formatNumber(existing)
        } else {
            manualWeightText = ""
        }
    }

static func formatHeight(_ centimeters: Double) -> String {
        String(format: "%.1f", centimeters)
    }

static func biologicalSex(from gender: String) -> BiologicalSex? {
        let normalized = gender.lowercased()
        if normalized.contains("female") || normalized.contains("woman") {
            return .female
        }
        if normalized.contains("male") || normalized.contains("man") {
            return .male
        }
        return nil
    }

func hydrateProfileName(from user: User) {
        let baseName = user.profile?.fullName ?? user.name ?? ""
        let components = baseName.split(separator: " ")
        guard !components.isEmpty else { return }

        profileFirstName = String(components.first ?? "")
        if components.count > 1 {
            profileLastName = components.dropFirst().joined(separator: " ")
        }
    }

func hydrateProfileHeight(centimeters: Double, storedUnit: String?) {
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

var profileHeightInCentimeters: Double? {
        switch profileHeightUnit {
        case .centimeters:
            return Double(profileHeightCentimetersText)
        case .inches:
            let totalInches = Double((profileHeightFeet * 12) + profileHeightInches)
            return totalInches > 0 ? totalInches * 2.54 : nil
        }
    }

var profileHeightUnitStorageValue: String {
        switch profileHeightUnit {
        case .centimeters:
            return "cm"
        case .inches:
            return "in"
        }
    }

func recomputeProfileDetailsActiveSubstep() {
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

func applyMeasurementSystem(_ system: MeasurementSystem, skipHeight: Bool = false, skipWeight: Bool = false) {
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

func convertHeightFields(to unit: HeightUnit) {
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

func convertWeightFields(to unit: WeightUnit) {
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

func persistMeasurementPreference(_ system: MeasurementSystem) {
        UserDefaults.standard.set(system.rawValue, forKey: Constants.preferredMeasurementSystemKey)
        UserDefaults.standard.set(system.weightUnit, forKey: Constants.preferredWeightUnitKey)
    }

func hydrateDefaultHomeMode() {
        let storedValue = UserDefaults.standard.string(forKey: Constants.defaultHomeModeKey) ?? DefaultHomeMode.default.rawValue
        defaultHomeMode = DefaultHomeMode(storedValue: storedValue)
    }

// MARK: - Progress Persistence

    func persistProgress() {
        guard entryContext == .authenticated else { return }
        guard !isRestoringProgress else { return }
        guard !OnboardingStateManager.shared.hasCompletedCurrentVersion(for: AuthManager.shared.currentUser?.id) else {
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

func restorePersistedProgressIfNeeded() {
        guard entryContext == .authenticated else { return }
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        guard !OnboardingStateManager.shared.hasCompletedCurrentVersion(for: AuthManager.shared.currentUser?.id) else {
            progressStore.clearProgress(for: userId)
            return
        }

        if let snapshot = progressStore.loadProgress(for: userId), snapshot.currentStep != .paywall {
            restore(snapshot)
            return
        }

        restorePreAuthSnapshotIfNeeded(for: userId)
    }

func restore(_ snapshot: OnboardingProgressSnapshot) {
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

func restorePreAuthSnapshotIfNeeded(for userId: String) {
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

func clearPersistedProgress() {
        guard entryContext == .authenticated else { return }
        guard let userId = AuthManager.shared.currentUser?.id else { return }
        progressStore.clearProgress(for: userId)
    }
}
