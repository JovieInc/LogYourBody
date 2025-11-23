//
// AddEntrySheet.swift
// LogYourBody
//
import SwiftUI
import PhotosUI

struct AddEntrySheet: View {
    @Environment(\.dismiss)
    var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    @State private var selectedTab: Int
    @State private var selectedDate = Date()
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem

    init(isPresented: Binding<Bool>, initialTab: Int = 0) {
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }

    private var resolvedWeightUnit: String {
        weightUnit.isEmpty ? currentSystem.weightUnit : weightUnit
    }

    // Weight entry
    @State private var weight: String = ""
    @State private var weightUnit: String = ""
    @State private var weightError: String?

    // Body fat entry
    @State private var bodyFat: String = ""
    @State private var bodyFatMethod = "Visual"
    @State private var bodyFatError: String?

    // Photo entry
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isProcessingPhotos = false
    @State private var photoProgress: Double = 0
    @State private var processedCount = 0
    @State private var photoIdentifiers: [String] = []  // Store PHAsset identifiers for deletion

    // GLP-1 entry
    @State private var glp1Dose: String = ""
    @State private var glp1DoseUnit: String = "mg/week"
    @State private var glp1Error: String?
    @State private var glp1Medications: [Glp1Medication] = []
    @State private var selectedGlp1MedicationId: String?
    @State private var selectedGlp1DoseIndex: Int = 0
    @State private var glp1IsLoadingMedications = false
    @State private var isPresentingGlp1AddMedication = false
    @State private var glp1UseCustomDose = false
    @State private var glp1UserId: String?

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeletePhotosPrompt = false
    @AppStorage(Constants.deletePhotosAfterImportKey) private var deletePhotosAfterImport = false
    @AppStorage(Constants.hasPromptedDeletePhotosKey) private var hasPromptedDeletePhotos = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Entry Type", selection: $selectedTab) {
                    Label("Weight", systemImage: "scalemass").tag(0)
                    Label("Body Fat", systemImage: "percent").tag(1)
                    Label("Photos", systemImage: "photo.fill").tag(2)
                    Label("GLP-1", systemImage: "syringe").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.vertical, 12)
                .accessibilityLabel("Entry type selector")
                .accessibilityHint("Select the type of entry you want to add")

                // Date picker (common for all tabs)
                HStack {
                    Text("Date")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    Spacer()

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case 0:
                        weightEntryView
                    case 1:
                        bodyFatEntryView
                    case 2:
                        photoEntryView
                    case 3:
                        glp1EntryView
                    default:
                        EmptyView()
                    }
                }

                // Save button
                Button(action: saveEntry) {
                    HStack {
                        if isProcessingPhotos {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Text(saveButtonText)
                                .font(.appBody)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(canSave ? Color.white : Color.appBorder)
                    .foregroundColor(canSave ? .black : .white)
                    .cornerRadius(Constants.cornerRadius)
                }
                .disabled(!canSave || isProcessingPhotos)
                .padding()
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Delete Photos After Import?", isPresented: $showDeletePhotosPrompt) {
                Button("Keep Photos", role: .cancel) {
                    deletePhotosAfterImport = false
                    hasPromptedDeletePhotos = true
                }
                Button("Delete After Import") {
                    deletePhotosAfterImport = true
                    hasPromptedDeletePhotos = true
                }
            } message: {
                Text(
                    "Would you like to automatically delete photos from your camera roll after importing them into the app? " +
                        "You can change this later in Settings."
                )
            }
            .onAppear {
                // Set default weight unit based on user preference
                if weightUnit.isEmpty {
                    weightUnit = currentSystem.weightUnit
                }

                glp1UserId = authManager.currentUser?.id
                if let userId = glp1UserId {
                    Task {
                        await loadGlp1Medications(userId: userId)
                    }
                }
            }
        }
    }

    // MARK: - GLP-1 Entry View

    private var glp1EntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log GLP-1 dose")
                .font(.appHeadline)
                .padding(.top)

            if glp1IsLoadingMedications {
                HStack {
                    ProgressView()
                        .tint(.appPrimary)
                    Text("Loading medications…")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.top, 8)
            } else if glp1Medications.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add your GLP-1 medication")
                        .font(.appBody)

                    Text("Select the medication you're taking so logging is just a quick dose pick.")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    Button {
                        isPresentingGlp1AddMedication = true
                    } label: {
                        Text("Add medication")
                            .font(.appBody)
                            .fontWeight(.semibold)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(Constants.cornerRadius)
                    }
                    .padding(.top, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Medication")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(glp1Medications) { medication in
                                let isSelected = medication.id == selectedGlp1MedicationId

                                Button {
                                    selectGlp1Medication(medication)
                                } label: {
                                    Text(medication.displayName)
                                        .font(.appBodySmall)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.appPrimary : Color.appSurfaceSecondary
                                        )
                                        .foregroundColor(isSelected ? .black : .appTextPrimary)
                                        .cornerRadius(999)
                                }
                            }

                            Button {
                                isPresentingGlp1AddMedication = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(.appBodySmall)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.appSurfaceSecondary)
                                .foregroundColor(.appTextPrimary)
                                .cornerRadius(999)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let medication = glp1SelectedMedication {
                        let options = glp1DoseOptions
                        let unit = glp1UnitForSelectedMedication ?? glp1DoseUnit

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dose")
                                .font(.appBodySmall)
                                .foregroundColor(.appTextSecondary)

                            if !options.isEmpty {
                                Picker("Dose", selection: $selectedGlp1DoseIndex) {
                                    ForEach(options.indices, id: \.self) { index in
                                        Text(String(format: "%.2f", options[index]))
                                            .tag(index)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                                .clipped()
                                .onChange(of: selectedGlp1DoseIndex) { _, _ in
                                    updateGlp1DoseFromSelection()
                                }

                                HStack {
                                    Text(unit)
                                        .font(.appBodySmall)
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                }
                            }

                            Toggle("Custom dose", isOn: $glp1UseCustomDose)
                                .font(.appBodySmall)
                                .foregroundColor(.appTextSecondary)
                                .onChange(of: glp1UseCustomDose) { _, isCustom in
                                    if !isCustom {
                                        updateGlp1DoseFromSelection()
                                    }
                                }

                            if glp1UseCustomDose {
                                HStack(spacing: 12) {
                                    TextField("0.0", text: $glp1Dose)
                                        .keyboardType(.decimalPad)
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .modernTextFieldStyle()
                                        .accessibilityLabel("GLP-1 custom dose value")
                                        .submitLabel(.done)
                                        .onChange(of: glp1Dose) { _, newValue in
                                            validateGlp1Dose(newValue)
                                        }

                                    Text(unit)
                                        .font(.appBodySmall)
                                        .foregroundColor(.appTextSecondary)
                                }
                            }

                            if let error = glp1Error {
                                Text(error)
                                    .font(.appBodySmall)
                                    .foregroundColor(.error)
                            } else {
                                Text("Pick your dose from the wheel or enter a custom dose if needed.")
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextTertiary)
                            }
                        }
                        .onAppear {
                            if glp1Dose.isEmpty {
                                updateGlp1DoseFromSelection()
                            }
                            glp1DoseUnit = unit
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .sheet(isPresented: $isPresentingGlp1AddMedication) {
            if let userId = glp1UserId {
                Glp1AddMedicationView(userId: userId) { medication in
                    glp1Medications.append(medication)
                    selectedGlp1MedicationId = medication.id
                    applyDefaultDoseConfig(for: medication)
                }
            }
        }
    }

    // MARK: - Weight Entry View
    private var weightEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter your weight")
                .font(.appHeadline)
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("0.0", text: $weight)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .modernTextFieldStyle()
                        .accessibilityLabel("Weight value")
                        .accessibilityHint("Enter your weight")
                        .submitLabel(.done)
                        .onChange(of: weight) { _, newValue in
                            validateWeight(newValue)
                        }

                    Picker("Unit", selection: $weightUnit) {
                        Text("kg").tag("kg")
                        Text("lbs").tag("lbs")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                    .accessibilityLabel("Weight unit")
                }

                // Helper text
                if let error = weightError {
                    Text(error)
                        .font(.appBodySmall)
                        .foregroundColor(.error)
                        .accessibilityLabel("Weight validation error: \(error)")
                } else {
                    Text(resolvedWeightUnit == "kg" ? "Valid range: 20-500 kg" : "Valid range: 44-1100 lbs")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Body Fat Entry View
    private var bodyFatEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter body fat percentage")
                .font(.appHeadline)
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("0.0", text: $bodyFat)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .modernTextFieldStyle()
                        .accessibilityLabel("Body fat percentage value")
                        .accessibilityHint("Enter your body fat percentage")
                        .submitLabel(.done)
                        .onChange(of: bodyFat) { _, newValue in
                            validateBodyFat(newValue)
                        }

                    Text("%")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }

                // Helper text
                if let error = bodyFatError {
                    Text(error)
                        .font(.appBodySmall)
                        .foregroundColor(.error)
                        .accessibilityLabel("Body fat validation error: \(error)")
                } else {
                    Text("Valid range: 3-50%")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Measurement Method")
                    .font(.appBodySmall)
                    .foregroundColor(.appTextSecondary)

                Picker("Method", selection: $bodyFatMethod) {
                    Text("Visual Estimate").tag("Visual")
                    Text("Body Scan").tag("Scan")
                    Text("Calipers").tag("Calipers")
                    Text("Bioelectrical").tag("BIA")
                    Text("DEXA").tag("DEXA")
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Body fat measurement method")
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Photo Entry View
    private var photoEntryView: some View {
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

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Choose Photos", systemImage: "photo.fill")
                            .frame(height: 48)
                            .frame(maxWidth: .infinity)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(Constants.cornerRadius)
                    }
                    .padding(.horizontal)
                    .onChange(of: selectedPhotos) { _, newPhotos in
                        if !newPhotos.isEmpty && !hasPromptedDeletePhotos {
                            showDeletePhotosPrompt = true
                        }
                    }
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
                    }

                    if isProcessingPhotos {
                        VStack(spacing: 12) {
                            ProgressView(value: photoProgress)
                                .tint(.appPrimary)

                            Text("Processing \(processedCount + 1) of \(selectedPhotos.count)")
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
    private var canSave: Bool {
        switch selectedTab {
        case 0:
            return !weight.isEmpty && Double(weight) != nil && weightError == nil
        case 1:
            return !bodyFat.isEmpty && Double(bodyFat) != nil && bodyFatError == nil
        case 2:
            return !selectedPhotos.isEmpty
        case 3:
            return glp1SelectedMedication != nil && !glp1Dose.isEmpty && Double(glp1Dose) != nil && glp1Error == nil
        default:
            return false
        }
    }

    private var saveButtonText: String {
        switch selectedTab {
        case 0:
            return "Save Weight"
        case 1:
            return "Save Body Fat"
        case 2:
            return selectedPhotos.count > 1 ? "Upload \(selectedPhotos.count) Photos" : "Upload Photo"
        case 3:
            return "Save GLP-1"
        default:
            return "Save"
        }
    }

    // MARK: - Actions
    private func saveEntry() {
        guard let userId = authManager.currentUser?.id else { return }

        switch selectedTab {
        case 0:
            saveWeight(userId: userId)
        case 1:
            saveBodyFat(userId: userId)
        case 2:
            Task {
                await savePhotos(userId: userId)
            }
        case 3:
            saveGlp1Dose(userId: userId)
        default:
            break
        }
    }

    private func saveWeight(userId: String) {
        do {
            let validatedWeight = try ValidationService.shared.validateWeight(weight, unit: resolvedWeightUnit)
            let weightInKg = resolvedWeightUnit == "lbs" ? validatedWeight * 0.453592 : validatedWeight

            weightError = nil

            Task {
                _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: selectedDate,
                    weight: weightInKg,
                    userId: userId
                )

                // Update widget data
                await WidgetDataManager.shared.updateWidgetData()

                RealtimeSyncManager.shared.syncIfNeeded()

                BodyScoreRecalculationService.shared.scheduleRecalculation()
            }

            dismiss()
        } catch let error as ValidationError {
            handleValidationError(error, for: .weight)
        } catch {
            handleValidationError(.invalidWeight("Please enter a valid number"), for: .weight)
        }
    }

    private func saveBodyFat(userId: String) {
        do {
            let validatedBodyFat = try ValidationService.shared.validateBodyFat(bodyFat)
            bodyFatError = nil

            Task {
                _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: selectedDate,
                    bodyFatPercentage: validatedBodyFat,
                    userId: userId
                )

                // Update widget data
                await WidgetDataManager.shared.updateWidgetData()

                RealtimeSyncManager.shared.syncIfNeeded()

                BodyScoreRecalculationService.shared.scheduleRecalculation()
            }

            dismiss()
        } catch let error as ValidationError {
            handleValidationError(error, for: .bodyFat)
        } catch {
            handleValidationError(.invalidBodyFat("Please enter a valid percentage"), for: .bodyFat)
        }
    }

    private func saveGlp1Dose(userId: String) {
        do {
            guard let medication = glp1SelectedMedication else {
                glp1Error = "Select a medication first"
                return
            }

            guard let dose = Double(glp1Dose) else {
                glp1Error = "Please enter a valid number"
                return
            }

            if dose <= 0 {
                glp1Error = "Dose must be greater than zero"
                return
            }

            glp1Error = nil

            let now = Date()
            let calendar = Calendar.current
            let takenDate = calendar.startOfDay(for: selectedDate)
            let log = Glp1DoseLog(
                id: UUID().uuidString,
                userId: userId,
                takenAt: takenDate,
                medicationId: medication.id,
                doseAmount: dose,
                doseUnit: medication.doseUnit ?? glp1DoseUnit,
                drugClass: medication.drugClass,
                brand: medication.brand ?? medication.displayName,
                isCompounded: medication.isCompounded,
                supplierType: nil,
                supplierName: nil,
                notes: nil,
                createdAt: now,
                updatedAt: now
            )

            Task {
                do {
                    try await SupabaseManager.shared.saveGlp1DoseLog(log)
                    RealtimeSyncManager.shared.syncIfNeeded()
                    dismiss()
                } catch {
                    errorMessage = "Unable to save GLP-1 entry. Please try again."
                    showError = true
                }
            }
        }
    }

    private func savePhotos(userId: String) async {
        isProcessingPhotos = true
        photoProgress = 0
        processedCount = 0
        photoIdentifiers.removeAll()

        for (index, item) in selectedPhotos.enumerated() {
            do {
                // Extract PHAsset identifier if available
                if let identifier = item.itemIdentifier {
                    photoIdentifiers.append(identifier)
                }

                // Load the photo data
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }

                // Extract date from metadata
                let photoDate = PhotoMetadataService.shared.extractDate(from: data) ?? selectedDate

                // Create or get metrics for this date
                let metrics = await PhotoMetadataService.shared.createOrUpdateMetrics(
                    for: photoDate,
                    userId: userId
                )

                // Upload the photo
                _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                    for: metrics,
                    image: image
                )

                processedCount = index + 1
                photoProgress = Double(processedCount) / Double(selectedPhotos.count)
            } catch {
                // print("Failed to process photo \(index): \(error)")
            }
        }

        // Delete photos from camera roll if enabled
        if deletePhotosAfterImport && !photoIdentifiers.isEmpty {
            await deletePhotosFromLibrary()
        }

        isProcessingPhotos = false
        RealtimeSyncManager.shared.syncIfNeeded()
        dismiss()
    }

    private func deletePhotosFromLibrary() async {
        guard !photoIdentifiers.isEmpty else { return }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: photoIdentifiers, options: nil)

        guard fetchResult.firstObject != nil else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
        } catch {
            // Silently fail - don't interrupt the user flow if deletion fails
            // print("Failed to delete photos: \(error)")
        }
    }

    // MARK: - Validation Functions

    private enum InputField {
        case weight
        case bodyFat
    }

    private func handleValidationError(_ error: ValidationError, for field: InputField) {
        switch field {
        case .weight:
            weightError = error.errorDescription
        case .bodyFat:
            bodyFatError = error.errorDescription
        }
    }

    private func validateWeight(_ value: String) {
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

    private func validateBodyFat(_ value: String) {
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

    private func validateGlp1Dose(_ value: String) {
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

    private var glp1SelectedMedication: Glp1Medication? {
        guard let id = selectedGlp1MedicationId else { return nil }
        return glp1Medications.first(where: { $0.id == id })
    }

    private var glp1DoseOptions: [Double] {
        guard let medication = glp1SelectedMedication else { return [] }
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        return config.doses
    }

    private var glp1UnitForSelectedMedication: String? {
        guard let medication = glp1SelectedMedication else { return nil }
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        return config.unit
    }

    @MainActor
    private func loadGlp1Medications(userId: String) async {
        glp1IsLoadingMedications = true

        do {
            let medications = try await SupabaseManager.shared.fetchGlp1Medications(userId: userId)
            glp1Medications = medications.sorted(by: { $0.startedAt < $1.startedAt })

            if selectedGlp1MedicationId == nil,
               let active = glp1Medications.last(where: { $0.endedAt == nil }) ?? glp1Medications.last {
                selectedGlp1MedicationId = active.id
                applyDefaultDoseConfig(for: active)
            }
        } catch {
            // Ignore errors for now; GLP-1 is optional
        }

        glp1IsLoadingMedications = false
    }

    private func applyDefaultDoseConfig(for medication: Glp1Medication) {
        let config = Glp1MedicationCatalog.doseConfig(for: medication)
        glp1DoseUnit = config.unit
        selectedGlp1DoseIndex = 0
        glp1UseCustomDose = false

        if let first = config.doses.first {
            glp1Dose = String(first)
        } else {
            glp1Dose = ""
        }

        glp1Error = nil
    }

    private func selectGlp1Medication(_ medication: Glp1Medication) {
        selectedGlp1MedicationId = medication.id
        applyDefaultDoseConfig(for: medication)
    }

    private func updateGlp1DoseFromSelection() {
        guard !glp1UseCustomDose else { return }
        let options = glp1DoseOptions

        guard selectedGlp1DoseIndex >= 0,
              selectedGlp1DoseIndex < options.count else { return }

        glp1Dose = String(options[selectedGlp1DoseIndex])
        glp1Error = nil
    }
}

private struct Glp1AddMedicationView: View {
    let userId: String
    let onCreated: (Glp1Medication) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var presets: [Glp1MedicationPreset] {
        Glp1MedicationCatalog.allPresets
    }

    var body: some View {
        NavigationView {
            List {
                Section("Choose medication") {
                    ForEach(presets, id: \.displayName) { preset in
                        Button {
                            createMedication(from: preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.displayName)
                                    .font(.appBody)
                                Text("\(preset.genericName) • \(preset.frequency)")
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.appBodySmall)
                            .foregroundColor(.error)
                    }
                }
            }
            .navigationTitle("Select GLP-1")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func createMedication(from preset: Glp1MedicationPreset) {
        guard !isSaving else { return }
        isSaving = true

        let now = Date()
        let medication = Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: preset.displayName,
            genericName: preset.genericName,
            drugClass: preset.drugClass,
            brand: preset.brand,
            route: preset.route,
            frequency: preset.frequency,
            doseUnit: preset.doseUnit,
            isCompounded: preset.isCompounded,
            hkIdentifier: preset.hkIdentifier,
            startedAt: now,
            endedAt: nil,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                let manager = SupabaseManager.shared
                // End any active GLP-1 courses for this user before starting a new one.
                try await manager.endActiveGlp1Medications(userId: userId, endedAt: now)
                try await manager.saveGlp1Medication(medication)
                await MainActor.run {
                    onCreated(medication)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Unable to save medication. Please try again."
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    AddEntrySheet(isPresented: .constant(true))
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
