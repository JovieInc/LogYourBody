import SwiftUI

extension AddEntrySheet {
// MARK: - Photo Entry View
    var photoEntryView: some View {
        VStack(spacing: 16) {
            if selectedPhotos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.appTextTertiary)

                    Text("Select progress photos")
                        .font(.appHeadline)

                    Text(
                        "Photos will be automatically dated based on when they were taken. " +
                            "You can select multiple photos for bulk upload."
                    )
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                    AppPhotosPicker(maxSelectionCount: 10) { assets in
                        await MainActor.run {
                            selectedPhotos = assets
                            if !assets.isEmpty && !hasPromptedDeletePhotos {
                                showDeletePhotosPrompt = true
                            }
                        }
                    } label: {
                        Label("Choose Photos", systemImage: "photo.fill")
                            .frame(height: 48)
                            .frame(maxWidth: .infinity)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(Constants.cornerRadius)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(selectedPhotos.count) photo\(selectedPhotos.count == 1 ? "" : "s") selected")
                            .font(.appHeadline)

                        Spacer()

                        Button("Change") {
                            selectedPhotos = []
                        }
                        .foregroundColor(.appPrimary)
                        .disabled(!PhotoUploadBatchPolicy.canChangeSelection(isProcessing: isProcessingPhotos))
                    }

                    if isProcessingPhotos {
                        VStack(spacing: 12) {
                            ProgressView(value: photoProgress)
                                .tint(.appPrimary)

                            Text(
                                PhotoUploadBatchPolicy.progressText(
                                    processedCount: processedCount,
                                    totalCount: processingPhotoCount
                                )
                            )
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
            }

            Spacer()
        }
    }

// MARK: - Computed Properties
    var canSave: Bool {
        switch selectedTab {
        case 0:
            return !weight.isEmpty && Double(weight) != nil && weightError == nil
        case 1:
            return !bodyFat.isEmpty && Double(bodyFat) != nil && bodyFatError == nil
        case 2:
            return !selectedPhotos.isEmpty
        case 3:
            guard glp1SelectedMedication != nil else { return false }
            if glp1IsRestDay {
                return true
            }
            return !glp1Dose.isEmpty && Double(glp1Dose) != nil && glp1Error == nil
        default:
            return false
        }
    }

var saveButtonText: String {
        switch selectedTab {
        case 0:
            return "Save Weight"
        case 1:
            return "Save Body Fat"
        case 2:
            return selectedPhotos.count > 1 ? "Upload \(selectedPhotos.count) Photos" : "Upload Photo"
        case 3:
            return editingGlp1DoseLogId == nil ? "Save GLP-1" : "Save Changes"
        default:
            return "Save"
        }
    }

// MARK: - Actions
    func saveEntry() {
        guard let userId = authManager.currentUser?.id else { return }
        guard !isSavingEntry, !isProcessingPhotos else { return }

        switch selectedTab {
        case 0:
            saveWeight(userId: userId)
        case 1:
            saveBodyFat(userId: userId)
        case 2:
            let photosToSave = selectedPhotos
            guard PhotoUploadBatchPolicy.canStartUpload(
                selectedCount: photosToSave.count,
                isSaving: isSavingEntry,
                isProcessing: isProcessingPhotos
            ) else { return }

            isProcessingPhotos = true
            photoProgress = 0
            processedCount = 0
            processingPhotoCount = photosToSave.count
            photoIdentifiers.removeAll()

            Task {
                await savePhotos(userId: userId, selectedPhotos: photosToSave)
            }
        case 3:
            saveGlp1Dose(userId: userId)
        default:
            break
        }
    }

func saveWeight(userId: String) {
        do {
            let validatedWeight = try ValidationService.shared.validateWeight(weight, unit: resolvedWeightUnit)
            let weightInKg = resolvedWeightUnit == "lbs" ? validatedWeight.lbsToKg : validatedWeight

            weightError = nil
            isSavingEntry = true

            Task {
                defer { isSavingEntry = false }

                _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: selectedDate,
                    weight: weightInKg,
                    userId: userId
                )
                RealtimeSyncManager.shared.syncIfNeeded()

                BodyScoreRecalculationService.shared.scheduleRecalculation()

                trackEntrySaved(
                    type: "weight",
                    properties: [
                        "unit": resolvedWeightUnit
                    ]
                )
                HapticManager.shared.successAction()

                dismiss()
            }
        } catch let error as ValidationError {
            handleValidationError(error, for: .weight)
        } catch {
            handleValidationError(.invalidWeight("Please enter a valid number"), for: .weight)
        }
    }

func saveBodyFat(userId: String) {
        do {
            let validatedBodyFat = try ValidationService.shared.validateBodyFat(bodyFat)
            bodyFatError = nil
            isSavingEntry = true

            Task {
                defer { isSavingEntry = false }

                _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: selectedDate,
                    bodyFatPercentage: validatedBodyFat,
                    userId: userId
                )
                RealtimeSyncManager.shared.syncIfNeeded()

                BodyScoreRecalculationService.shared.scheduleRecalculation()

                trackEntrySaved(type: "body_fat")
                HapticManager.shared.successAction()
                dismiss()
            }
        } catch let error as ValidationError {
            handleValidationError(error, for: .bodyFat)
        } catch {
            handleValidationError(.invalidBodyFat("Please enter a valid percentage"), for: .bodyFat)
        }
    }

func saveGlp1Dose(userId: String) {
        do {
            guard let medication = glp1SelectedMedication else {
                glp1Error = "Select a medication first"
                return
            }

            let dose: Double?
            if glp1IsRestDay {
                dose = nil
            } else {
                guard let resolvedDose = Double(glp1Dose) else {
                    glp1Error = "Please enter a valid number"
                    return
                }

                if resolvedDose <= 0 {
                    glp1Error = "Dose must be greater than zero"
                    return
                }

                dose = resolvedDose
            }

            glp1Error = nil
            isSavingEntry = true

            let now = Date()
            let calendar = Calendar.current
            let takenDate = calendar.startOfDay(for: selectedDate)
            let log = Glp1DoseLog(
                id: editingGlp1DoseLogId ?? UUID().uuidString,
                userId: userId,
                takenAt: takenDate,
                medicationId: medication.id,
                doseAmount: dose,
                doseUnit: glp1IsRestDay ? nil : medication.doseUnit ?? glp1DoseUnit,
                drugClass: medication.drugClass,
                brand: medication.brand ?? medication.displayName,
                isCompounded: medication.isCompounded,
                supplierType: nil,
                supplierName: nil,
                notes: glp1DoseLogNotesForSave(isRestDay: glp1IsRestDay),
                createdAt: editingGlp1DoseCreatedAt ?? now,
                updatedAt: now
            )

            Task {
                defer { isSavingEntry = false }

                CoreDataManager.shared.saveGlp1DoseLogs([log], userId: userId, markAsSynced: false)
                await loadGlp1DoseLogs(userId: userId)
                RealtimeSyncManager.shared.updatePendingSyncCount()
                RealtimeSyncManager.shared.syncIfNeeded()

                trackEntrySaved(
                    type: "glp1",
                    properties: [
                        "medication_id": medication.id,
                        "dose_unit": medication.doseUnit ?? glp1DoseUnit
                    ]
                )
                dismiss()
            }
        }
    }

func savePhotos(userId: String, selectedPhotos photosToUpload: [AppPhotoAsset]) async {
        guard !photosToUpload.isEmpty else { return }

        isProcessingPhotos = true
        photoProgress = 0
        processedCount = 0
        processingPhotoCount = photosToUpload.count
        photoIdentifiers.removeAll()
        var successfulUploadCount = 0
        var successfulPhotoIdentifiers: [String] = []
        var failedPhotos: [AppPhotoAsset] = []

        defer {
            isProcessingPhotos = false
            processingPhotoCount = 0
        }

        for (index, item) in photosToUpload.enumerated() {
            var placeholderMetricId: String?

            do {
                defer {
                    processedCount = index + 1
                    photoProgress = PhotoUploadBatchPolicy.progress(
                        completedCount: processedCount,
                        totalCount: photosToUpload.count
                    )
                }

                let itemIdentifier = item.localIdentifier
                let data = item.data
                let image = item.image

                // Extract date from metadata
                let photoDate = PhotoMetadataService.shared.extractDate(from: data) ?? selectedDate

                // Create or get metrics for this date
                let metricsResult = try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
                    for: photoDate,
                    userId: userId
                )
                let metrics = metricsResult.metrics
                placeholderMetricId = metrics.id

                // Upload the photo
                _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                    for: metrics,
                    image: image
                )

                successfulUploadCount += 1
                if let itemIdentifier {
                    successfulPhotoIdentifiers.append(itemIdentifier)
                }
            } catch {
                let context = ErrorContext(
                    feature: "photos",
                    operation: "savePhotos",
                    screen: "AddEntrySheet",
                    userId: userId
                )
                ErrorReporter.shared.captureNonFatal(error, context: context)
                if let placeholderMetricId {
                    _ = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
                        id: placeholderMetricId,
                        userId: userId
                    )
                }
                failedPhotos.append(item)
            }
        }

        photoIdentifiers = successfulPhotoIdentifiers

        // Delete successfully imported originals even if a later item failed.
        if deletePhotosAfterImport && !photoIdentifiers.isEmpty {
            await deletePhotosFromLibrary()
        }

        RealtimeSyncManager.shared.syncIfNeeded()

        if !PhotoUploadBatchPolicy.shouldDismissAfterUpload(
            successfulCount: successfulUploadCount,
            totalCount: photosToUpload.count
        ) {
            selectedPhotos = failedPhotos
            errorMessage = PhotoUploadBatchPolicy.uploadFailureMessage(
                successfulCount: successfulUploadCount,
                totalCount: photosToUpload.count
            )
            showError = true
            return
        }

        dismiss()

        trackEntrySaved(
            type: "photos",
            properties: [
                "count": String(successfulUploadCount)
            ]
        )
        HapticManager.shared.successAction()
    }

func trackEntrySaved(type: String, properties: [String: String] = [:]) {
        var eventProperties = properties
        eventProperties["type"] = type

        AppServicePorts.analyticsTracker.track(
            event: "entry_saved",
            properties: eventProperties
        )
    }

func deletePhotosFromLibrary() async {
        guard !photoIdentifiers.isEmpty else { return }

        do {
            try await LivePhotoLibraryAdapter.shared.deleteAssets(localIdentifiers: photoIdentifiers)
        } catch {
            let context = ErrorContext(
                feature: "photos",
                operation: "deleteImportedPhotos",
                screen: "AddEntrySheet",
                userId: nil
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

func handleValidationError(_ error: ValidationError, for field: InputField) {
        switch field {
        case .weight:
            weightError = error.errorDescription
        case .bodyFat:
            bodyFatError = error.errorDescription
        }
    }

func validateWeight(_ value: String) {
        guard !value.isEmpty else {
            weightError = nil
            return
        }

        do {
            _ = try ValidationService.shared.validateWeight(value, unit: resolvedWeightUnit)
            weightError = nil
        } catch let error as ValidationError {
            weightError = error.errorDescription
        } catch {
            weightError = "Please enter a valid number"
        }
    }

func validateBodyFat(_ value: String) {
        guard !value.isEmpty else {
            bodyFatError = nil
            return
        }

        do {
            _ = try ValidationService.shared.validateBodyFat(value)
            bodyFatError = nil
        } catch let error as ValidationError {
            bodyFatError = error.errorDescription
        } catch {
            bodyFatError = "Please enter a valid number"
        }
    }

func validateGlp1Dose(_ value: String) {
        guard !value.isEmpty else {
            glp1Error = nil
            return
        }

        guard let dose = Double(value) else {
            glp1Error = "Please enter a valid number"
            return
        }

        if dose <= 0 {
            glp1Error = "Dose must be greater than zero"
        } else {
            glp1Error = nil
        }
    }

// MARK: - GLP-1 Helpers

    var glp1SelectedMedication: Glp1Medication? {
        guard let id = selectedGlp1MedicationId else { return nil }
        return glp1Medications.first(where: { $0.id == id })
    }

var glp1DoseOptions: [Double] {
        guard let medication = glp1SelectedMedication else { return [] }
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        return config.doses
    }

var glp1UnitForSelectedMedication: String? {
        guard let medication = glp1SelectedMedication else { return nil }
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        return config.unit
    }

var recentGlp1DoseLogs: [Glp1DoseLog] {
        Array(glp1DoseLogs.sorted(by: { $0.takenAt > $1.takenAt }).prefix(5))
    }

var normalizedGlp1DoseNotes: String? {
        let trimmed = glp1DoseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

func glp1DoseLogNotesForSave(isRestDay: Bool) -> String? {
        guard isRestDay else {
            return normalizedGlp1DoseNotes
        }

        guard let notes = normalizedGlp1DoseNotes else {
            return "Rest day"
        }

        return notes.localizedCaseInsensitiveContains("rest day") ? notes : "Rest day: \(notes)"
    }

var glp1DeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteGlp1DoseLog != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteGlp1DoseLog = nil
                }
            }
        )
    }

@MainActor
    func loadGlp1Medications(userId: String) async {
        glp1IsLoadingMedications = true
        let cached = await CoreDataManager.shared.fetchGlp1Medications(for: userId)
        await loadGlp1DoseLogs(userId: userId)

        if !cached.isEmpty {
            glp1Medications = cached.sorted { $0.startedAt < $1.startedAt }

            if selectedGlp1MedicationId == nil,
               let active = glp1Medications.last(where: { $0.endedAt == nil }) ?? glp1Medications.last {
                selectedGlp1MedicationId = active.id
                applyDefaultDoseConfig(for: active)
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
            glp1IsLoadingMedications = false
            return
        }
        #endif

        do {
            let medications = try await AppServicePorts.glp1RemoteDataProvider.fetchGlp1Medications(userId: userId)
            glp1Medications = medications.sorted(by: { $0.startedAt < $1.startedAt })
            CoreDataManager.shared.saveGlp1Medications(medications, userId: userId)

            let doseLogs = try await AppServicePorts.glp1RemoteDataProvider.fetchGlp1DoseLogs(userId: userId)
            CoreDataManager.shared.saveGlp1DoseLogs(doseLogs, userId: userId)
            glp1DoseLogs = doseLogs.sorted(by: { $0.takenAt < $1.takenAt })

            if selectedGlp1MedicationId == nil,
               let active = glp1Medications.last(where: { $0.endedAt == nil }) ?? glp1Medications.last {
                selectedGlp1MedicationId = active.id
                applyDefaultDoseConfig(for: active)
            }
        } catch {
        }

        glp1IsLoadingMedications = false
    }

@MainActor
    func loadGlp1DoseLogs(userId: String) async {
        glp1DoseLogs = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
    }

func loadGlp1MedicationsIfNeeded() {
        guard includesGlp1Entry, selectedTab == 3 else { return }
        guard let userId = authManager.currentUser?.id else { return }

        glp1UserId = userId

        Task {
            await loadGlp1Medications(userId: userId)
        }
    }

func applyDefaultDoseConfig(for medication: Glp1Medication) {
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        glp1DoseUnit = config.unit
        selectedGlp1DoseIndex = 0
        glp1UseCustomDose = false
        glp1IsRestDay = false

        if let first = config.doses.first {
            glp1Dose = String(first)
        } else {
            glp1Dose = ""
        }

        glp1Error = nil
    }

func selectGlp1Medication(_ medication: Glp1Medication) {
        selectedGlp1MedicationId = medication.id
        applyDefaultDoseConfig(for: medication)
    }

func editGlp1Dose(_ log: Glp1DoseLog) {
        editingGlp1DoseLogId = log.id
        editingGlp1DoseCreatedAt = log.createdAt
        selectedDate = log.takenAt
        glp1DoseNotes = log.notes ?? ""
        glp1IsRestDay = Glp1DoseHistoryFormatter.isRestDay(log)

        if let medicationId = log.medicationId,
           glp1Medications.contains(where: { $0.id == medicationId }) {
            selectedGlp1MedicationId = medicationId
        } else if let brand = log.brand,
                  let medication = glp1Medications.first(where: { $0.displayName == brand || $0.brand == brand }) {
            selectedGlp1MedicationId = medication.id
        }

        glp1DoseUnit = log.doseUnit ?? glp1UnitForSelectedMedication ?? glp1DoseUnit

        guard let amount = log.doseAmount else {
            glp1Dose = ""
            glp1UseCustomDose = true
            glp1Error = nil
            return
        }

        if let matchingIndex = glp1DoseOptions.firstIndex(where: { abs($0 - amount) < 0.0001 }) {
            selectedGlp1DoseIndex = matchingIndex
            glp1UseCustomDose = false
            glp1Dose = String(glp1DoseOptions[matchingIndex])
        } else {
            glp1UseCustomDose = true
            glp1Dose = Glp1DoseHistoryFormatter.numberText(amount)
        }

        validateGlp1Dose(glp1Dose)
    }
}
