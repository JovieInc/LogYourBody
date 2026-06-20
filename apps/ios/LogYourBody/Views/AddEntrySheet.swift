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
    private let includesGlp1Entry: Bool
    @State private var selectedDate = Date()
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem

    init(isPresented: Binding<Bool>, initialTab: Int = 0, includesGlp1Entry: Bool = false) {
        let resolvedInitialTab = initialTab == 3 && !includesGlp1Entry ? 0 : initialTab
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: resolvedInitialTab)
        self.includesGlp1Entry = includesGlp1Entry
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
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
    @State private var photoIdentifiers: [String] = []  // Store successfully uploaded PHAsset identifiers for deletion

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
    @State private var glp1IsRestDay = false
    @State private var glp1UserId: String?
    @State private var glp1DoseLogs: [Glp1DoseLog] = []
    @State private var glp1DoseNotes: String = ""
    @State private var editingGlp1DoseLogId: String?
    @State private var editingGlp1DoseCreatedAt: Date?
    @State private var pendingDeleteGlp1DoseLog: Glp1DoseLog?

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSavingEntry = false
    @State private var showDeletePhotosPrompt = false
    @AppStorage(Constants.deletePhotosAfterImportKey) private var deletePhotosAfterImport = false
    @AppStorage(Constants.hasPromptedDeletePhotosKey) private var hasPromptedDeletePhotos = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Entry Type", selection: $selectedTab) {
                    Label("Weight", systemImage: "scalemass").tag(0)
                    Label("Body Fat", systemImage: "percent").tag(1)
                    Label("Photos", systemImage: "photo.fill").tag(2)
                    if includesGlp1Entry {
                        Label("GLP-1", systemImage: "syringe").tag(3)
                    }
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

                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
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
                        if isProcessingPhotos || isSavingEntry {
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
                .disabled(!canSave || isProcessingPhotos || isSavingEntry)
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
            .standardErrorAlert(isPresented: $showError, message: errorMessage)
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

                loadGlp1MedicationsIfNeeded()
                AnalyticsService.shared.track(event: "add_entry_view")
            }
            .onChange(of: selectedTab) { _, _ in
                loadGlp1MedicationsIfNeeded()
            }
        }
    }

    // MARK: - GLP-1 Entry View

    private var glp1EntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingGlp1DoseLogId == nil ? "Log GLP-1 dose" : "Edit GLP-1 dose")
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
                            ForEach(glp1Medications, id: \.id) { medication in
                                let isSelected = selectedGlp1MedicationId == medication.id

                                Button {
                                    selectGlp1Medication(medication)
                                } label: {
                                    Text(medication.displayName)
                                        .font(.appBodySmall)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.appPrimary : Color.appCard
                                        )
                                        .foregroundColor(isSelected ? .black : .appText)
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
                                .background(Color.appCard)
                                .foregroundColor(.appText)
                                .cornerRadius(999)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if glp1SelectedMedication != nil {
                        let options = glp1DoseOptions
                        let unit = glp1UnitForSelectedMedication ?? glp1DoseUnit

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(editingGlp1DoseLogId == nil ? "Dose" : "Editing dose")
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)

                                Spacer()

                                if editingGlp1DoseLogId != nil {
                                    Button("Cancel") {
                                        resetGlp1DoseEditing()
                                    }
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)
                                }
                            }

                            Toggle("Rest day", isOn: $glp1IsRestDay)
                                .font(.appBodySmall)
                                .foregroundColor(.appTextSecondary)
                                .onChange(of: glp1IsRestDay) { _, isRestDay in
                                    if !isRestDay {
                                        updateGlp1DoseFromSelection()
                                    } else {
                                        glp1Error = nil
                                    }
                                }

                            if glp1IsRestDay {
                                Text("Record this date as a planned no-dose day.")
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextTertiary)
                            } else if !options.isEmpty {
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

                            if !glp1IsRestDay {
                                Toggle("Custom dose", isOn: $glp1UseCustomDose)
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)
                                    .onChange(of: glp1UseCustomDose) { _, isCustom in
                                        if !isCustom {
                                            updateGlp1DoseFromSelection()
                                        }
                                    }
                            }

                            if glp1UseCustomDose && !glp1IsRestDay {
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

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)

                                TextField("Optional context", text: $glp1DoseNotes)
                                    .font(.appBody)
                                    .modernTextFieldStyle()
                                    .accessibilityLabel("GLP-1 dose notes")
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

            glp1DoseHistorySection

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
        .confirmationDialog(
            "Delete dose?",
            isPresented: glp1DeleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let log = pendingDeleteGlp1DoseLog {
                Button("Delete dose", role: .destructive) {
                    deleteGlp1Dose(log)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            if let log = pendingDeleteGlp1DoseLog {
                Text("This removes \(Glp1DoseHistoryFormatter.doseText(log)) from your dose history.")
            }
        }
    }

    private var glp1DoseHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent doses")
                    .font(.appBodySmall)
                    .foregroundColor(.appTextSecondary)

                Spacer()

                if glp1DoseLogs.count > recentGlp1DoseLogs.count {
                    Text("\(glp1DoseLogs.count) total")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                }
            }

            if recentGlp1DoseLogs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No doses logged yet")
                        .font(.appBody)
                        .foregroundColor(.appText)

                    Text("Save a dose here and it will appear in your history.")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appCard)
                .cornerRadius(Constants.cornerRadius)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentGlp1DoseLogs) { log in
                        glp1DoseHistoryRow(log)

                        if log.id != recentGlp1DoseLogs.last?.id {
                            Divider()
                                .background(Color.appBorder)
                        }
                    }
                }
                .background(Color.appCard)
                .cornerRadius(Constants.cornerRadius)
            }
        }
        .accessibilityIdentifier("glp1DoseHistorySection")
    }

    private func glp1DoseHistoryRow(_ log: Glp1DoseLog) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.brand ?? "GLP-1")
                    .font(.appBody)
                    .foregroundColor(.appText)
                    .lineLimit(1)

                Text("\(Glp1DoseHistoryFormatter.doseText(log)) • \(Glp1DoseHistoryFormatter.dateText(log.takenAt))")
                    .font(.appBodySmall)
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)

                if let notes = log.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(.appBodySmall)
                        .foregroundColor(.appTextTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button("Edit") {
                editGlp1Dose(log)
            }
            .font(.appBodySmall)
            .foregroundColor(.appPrimary)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("glp1DoseHistoryEditButton")

            Button(role: .destructive) {
                pendingDeleteGlp1DoseLog = log
            } label: {
                Image(systemName: "trash")
                    .font(.appBodySmall)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete dose")
            .accessibilityIdentifier("glp1DoseHistoryDeleteButton")
        }
        .padding(14)
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
                    .onChange(of: weightUnit) { _, _ in
                        validateWeight(weight)
                    }
                }

                // Helper text
                if let error = weightError {
                    Text(error)
                        .font(.appBodySmall)
                        .foregroundColor(.error)
                        .accessibilityLabel("Weight validation error: \(error)")
                } else {
                    Text("Use today's scale weight.")
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
                    Text("Valid range: 3-60%")
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
            guard glp1SelectedMedication != nil else { return false }
            if glp1IsRestDay {
                return true
            }
            return !glp1Dose.isEmpty && Double(glp1Dose) != nil && glp1Error == nil
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
            return editingGlp1DoseLogId == nil ? "Save GLP-1" : "Save Changes"
        default:
            return "Save"
        }
    }

    // MARK: - Actions
    private func saveEntry() {
        guard let userId = authManager.currentUser?.id else { return }
        guard !isSavingEntry, !isProcessingPhotos else { return }

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

    private func saveBodyFat(userId: String) {
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

    private func saveGlp1Dose(userId: String) {
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

    private func savePhotos(userId: String) async {
        isProcessingPhotos = true
        photoProgress = 0
        processedCount = 0
        photoIdentifiers.removeAll()
        var successfulUploadCount = 0
        var successfulPhotoIdentifiers: [String] = []

        for (index, item) in selectedPhotos.enumerated() {
            do {
                defer {
                    processedCount = index + 1
                    photoProgress = Double(processedCount) / Double(selectedPhotos.count)
                }

                // Extract PHAsset identifier if available
                let itemIdentifier = item.itemIdentifier

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
            }
        }

        if successfulUploadCount == 0 {
            isProcessingPhotos = false
            errorMessage = "Photo upload failed. Please try again."
            showError = true
            return
        }

        photoIdentifiers = successfulPhotoIdentifiers

        // Delete photos from camera roll if enabled
        if deletePhotosAfterImport && !photoIdentifiers.isEmpty {
            await deletePhotosFromLibrary()
        }

        isProcessingPhotos = false
        RealtimeSyncManager.shared.syncIfNeeded()
        dismiss()

        trackEntrySaved(
            type: "photos",
            properties: [
                "count": String(successfulUploadCount)
            ]
        )
        HapticManager.shared.successAction()
    }

    private func trackEntrySaved(type: String, properties: [String: String] = [:]) {
        var eventProperties = properties
        eventProperties["type"] = type

        AnalyticsService.shared.track(
            event: "entry_saved",
            properties: eventProperties
        )
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
            let context = ErrorContext(
                feature: "photos",
                operation: "deleteImportedPhotos",
                screen: "AddEntrySheet",
                userId: nil
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
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

    private var recentGlp1DoseLogs: [Glp1DoseLog] {
        Array(glp1DoseLogs.sorted(by: { $0.takenAt > $1.takenAt }).prefix(5))
    }

    private var normalizedGlp1DoseNotes: String? {
        let trimmed = glp1DoseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func glp1DoseLogNotesForSave(isRestDay: Bool) -> String? {
        guard isRestDay else {
            return normalizedGlp1DoseNotes
        }

        guard let notes = normalizedGlp1DoseNotes else {
            return "Rest day"
        }

        return notes.localizedCaseInsensitiveContains("rest day") ? notes : "Rest day: \(notes)"
    }

    private var glp1DeleteConfirmationBinding: Binding<Bool> {
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
    private func loadGlp1Medications(userId: String) async {
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
            let medications = try await SupabaseManager.shared.fetchGlp1Medications(userId: userId)
            glp1Medications = medications.sorted(by: { $0.startedAt < $1.startedAt })
            CoreDataManager.shared.saveGlp1Medications(medications, userId: userId)

            let doseLogs = try await SupabaseManager.shared.fetchGlp1DoseLogs(userId: userId)
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
    private func loadGlp1DoseLogs(userId: String) async {
        glp1DoseLogs = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
    }

    private func loadGlp1MedicationsIfNeeded() {
        guard includesGlp1Entry, selectedTab == 3 else { return }
        guard let userId = authManager.currentUser?.id else { return }

        Task {
            await loadGlp1Medications(userId: userId)
        }
    }

    private func applyDefaultDoseConfig(for medication: Glp1Medication) {
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

    private func selectGlp1Medication(_ medication: Glp1Medication) {
        selectedGlp1MedicationId = medication.id
        applyDefaultDoseConfig(for: medication)
    }

    private func editGlp1Dose(_ log: Glp1DoseLog) {
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

    private func deleteGlp1Dose(_ log: Glp1DoseLog) {
        Task {
            let deleted = await CoreDataManager.shared.markGlp1DoseLogDeleted(id: log.id, userId: log.userId)
            guard deleted else { return }

            if editingGlp1DoseLogId == log.id {
                resetGlp1DoseEditing()
            }

            pendingDeleteGlp1DoseLog = nil
            await loadGlp1DoseLogs(userId: log.userId)
            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
            HapticManager.shared.successAction()
        }
    }

    private func resetGlp1DoseEditing() {
        editingGlp1DoseLogId = nil
        editingGlp1DoseCreatedAt = nil
        glp1DoseNotes = ""
        glp1IsRestDay = false

        if let medication = glp1SelectedMedication {
            applyDefaultDoseConfig(for: medication)
        } else {
            glp1Dose = ""
            glp1Error = nil
        }
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
    @State private var searchText: String = ""
    @State private var selectedPreset: Glp1MedicationPreset?
    @State private var activeFilters: Set<Glp1Filter> = []
    @State private var customCompoundName: String = ""
    @State private var customDoseUnit: String = "mg/week"
    @State private var customSchedule: Glp1CustomSchedule = .weekly
    @State private var customScheduleDays: String = ""

    private var presets: [Glp1MedicationPreset] {
        Glp1MedicationCatalog.allPresets
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select the medication you're currently using.")
                                .font(.appBodySmall)
                                .foregroundColor(.appTextSecondary)

                            SearchField(text: $searchText, placeholder: "Search brand or generic")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Glp1Filter.allCases) { filter in
                                        let isSelected = activeFilters.contains(filter)

                                        Button {
                                            toggleFilter(filter)
                                        } label: {
                                            Text(filter.label)
                                                .font(.appBodySmall)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.appPrimary : Color.appCard)
                                                .foregroundColor(isSelected ? .black : .appText)
                                                .cornerRadius(999)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    ForEach(groupedPresets, id: \.title) { group in
                        if !group.items.isEmpty {
                            Section(header: Text(group.title)
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                                .textCase(nil)
                            ) {
                                ForEach(group.items, id: \.displayName) { preset in
                                    let isSelected = selectedPreset?.displayName == preset.displayName

                                    Button {
                                        selectedPreset = preset
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                brandIcon(for: preset)

                                                Text(preset.displayName)
                                                    .font(.appBody)
                                                    .fontWeight(.semibold)

                                                if preset.isCompounded {
                                                    Text("Compounded")
                                                        .font(.appCaption)
                                                        .foregroundColor(.orange)
                                                }

                                                Spacer()

                                                HStack(spacing: 6) {
                                                    Image(
                                                        systemName: preset.route.lowercased() == "oral" ? "pills.fill" : "syringe"
                                                    )
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.appTextSecondary)

                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundColor(isSelected ? .appPrimary : .appBorder)
                                                }
                                            }

                                            Text(preset.genericName)
                                                .font(.appCaption)
                                                .foregroundColor(.appTextSecondary)

                                            HStack(spacing: 8) {
                                                Text("\(formattedRoute(for: preset)) • \(preset.frequency)")
                                                    .font(.appCaption)
                                                    .foregroundColor(.appTextSecondary)

                                                Spacer(minLength: 0)
                                            }
                                        }
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(isSelected ? Color.appCard.opacity(0.7) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSaving)
                                }
                            }
                        }
                    }

                    Section(header: Text("Custom compound")
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                        .textCase(nil)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                "For informational reference only. Log what you are already taking; " +
                                    "this does not provide dosing guidance."
                            )
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            TextField("Compound name", text: $customCompoundName)
                                .font(.appBody)
                                .modernTextFieldStyle()
                                .accessibilityLabel("Custom compound name")

                            Picker("Schedule", selection: $customSchedule) {
                                ForEach(Glp1CustomSchedule.allCases) { schedule in
                                    Text(schedule.label).tag(schedule)
                                }
                            }
                            .pickerStyle(.segmented)

                            if customSchedule == .custom {
                                TextField("Custom days, e.g. Mon/Wed/Fri", text: $customScheduleDays)
                                    .font(.appBody)
                                    .modernTextFieldStyle()
                                    .accessibilityLabel("Custom compound schedule days")
                            }

                            TextField("Dose unit", text: $customDoseUnit)
                                .font(.appBody)
                                .modernTextFieldStyle()
                                .accessibilityLabel("Custom compound dose unit")

                            Button {
                                createCustomMedication()
                            } label: {
                                Text("Use custom compound")
                                    .font(.appBodySmall)
                                    .fontWeight(.semibold)
                                    .frame(height: 40)
                                    .frame(maxWidth: .infinity)
                                    .background(customCompoundCanSave ? Color.appPrimary : Color.appBorder)
                                    .foregroundColor(customCompoundCanSave ? .black : .white)
                                    .cornerRadius(Constants.cornerRadius)
                            }
                            .disabled(!customCompoundCanSave || isSaving)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: searchText) { _, newValue in
                    if customCompoundName.isEmpty {
                        customCompoundName = newValue
                    }
                }

                VStack(spacing: 8) {
                    if errorMessage != nil {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.error)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Couldn't save. Check connection and try again.")
                                    .font(.appBodySmall)

                                HStack(spacing: 12) {
                                    Button("Try again") {
                                        if let preset = selectedPreset {
                                            createMedication(from: preset)
                                        }
                                    }
                                    .font(.appBodySmall)

                                    Button("Discard", role: .destructive) {
                                        errorMessage = nil
                                        isSaving = false
                                    }
                                    .font(.appBodySmall)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.9))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.error.opacity(0.3), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let preset = selectedPreset {
                                createMedication(from: preset)
                            }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text("Save medication")
                                        .font(.appBody)
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 44)
                        .background(selectedPreset != nil ? Color.appPrimary : Color.appBorder)
                        .foregroundColor(selectedPreset != nil ? .black : .white)
                        .cornerRadius(Constants.cornerRadius)
                        .disabled(selectedPreset == nil || isSaving)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(
                    Color.black.opacity(0.9)
                )
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

    private var filteredPresets: [Glp1MedicationPreset] {
        presets.filter { preset in
            matchesSearch(preset) && matchesFilters(preset)
        }
    }

    private var customCompoundCanSave: Bool {
        !trimmedCustomCompoundName.isEmpty
            && !trimmedCustomDoseUnit.isEmpty
            && (customSchedule != .custom || !trimmedCustomScheduleDays.isEmpty)
    }

    private var trimmedCustomCompoundName: String {
        customCompoundName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCustomDoseUnit: String {
        customDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCustomScheduleDays: String {
        customScheduleDays.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groupedPresets: [Glp1Group] {
        let commonBrands: Set<String> = ["Wegovy", "Zepbound", "Ozempic", "Mounjaro"]
        let oralBrands: Set<String> = ["Rybelsus"]
        let compoundedBrands: Set<String> = ["Compounded semaglutide", "Compounded tirzepatide"]

        let filtered = filteredPresets

        let newestCommon = filtered.filter { commonBrands.contains($0.brand) }
        let oral = filtered.filter { oralBrands.contains($0.brand) }
        let compounded = filtered.filter { compoundedBrands.contains($0.brand) }
        let other = filtered.filter { preset in
            !commonBrands.contains(preset.brand)
                && !oralBrands.contains(preset.brand)
                && !compoundedBrands.contains(preset.brand)
        }

        var groups: [Glp1Group] = []

        if !newestCommon.isEmpty {
            groups.append(Glp1Group(title: "Newest & most common", items: newestCommon))
        }

        if !other.isEmpty {
            groups.append(Glp1Group(title: "Other branded GLP-1s", items: other))
        }

        if !oral.isEmpty {
            groups.append(Glp1Group(title: "Oral (Rybelsus)", items: oral))
        }

        if !compounded.isEmpty {
            groups.append(Glp1Group(title: "Compounded (not FDA-approved)", items: compounded))
        }

        return groups
    }

    private func matchesSearch(_ preset: Glp1MedicationPreset) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let lowercased = query.lowercased()
        return preset.displayName.lowercased().contains(lowercased)
            || preset.genericName.lowercased().contains(lowercased)
            || preset.brand.lowercased().contains(lowercased)
    }

    private func matchesFilters(_ preset: Glp1MedicationPreset) -> Bool {
        guard !activeFilters.isEmpty else { return true }

        let generic = preset.genericName.lowercased()
        let route = preset.route.lowercased()
        let frequency = preset.frequency.lowercased()

        if hasDrugFilter(), !matchesDrugFilter(forGenericName: generic) {
            return false
        }

        if activeFilters.contains(.injectable) && route != "subcutaneous" {
            return false
        }

        if activeFilters.contains(.oral) && route != "oral" {
            return false
        }

        if activeFilters.contains(.weekly) && !frequency.contains("weekly") {
            return false
        }

        if activeFilters.contains(.daily) && !frequency.contains("daily") {
            return false
        }

        return true
    }

    private func hasDrugFilter() -> Bool {
        activeFilters.contains(.semaglutide)
            || activeFilters.contains(.tirzepatide)
            || activeFilters.contains(.liraglutide)
            || activeFilters.contains(.exenatide)
            || activeFilters.contains(.lixisenatide)
    }

    private func matchesDrugFilter(forGenericName generic: String) -> Bool {
        var matchesDrug = false

        if activeFilters.contains(.semaglutide) && generic.contains("semaglutide") {
            matchesDrug = true
        }

        if activeFilters.contains(.tirzepatide) && generic.contains("tirzepatide") {
            matchesDrug = true
        }

        if activeFilters.contains(.liraglutide) && generic.contains("liraglutide") {
            matchesDrug = true
        }

        if activeFilters.contains(.exenatide) && generic.contains("exenatide") {
            matchesDrug = true
        }

        if activeFilters.contains(.lixisenatide) && generic.contains("lixisenatide") {
            matchesDrug = true
        }

        return matchesDrug
    }

    private func toggleFilter(_ filter: Glp1Filter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    private func formattedRoute(for preset: Glp1MedicationPreset) -> String {
        let route = preset.route.lowercased()

        switch route {
        case "subcutaneous":
            return "Injection"
        case "oral":
            return "Oral"
        default:
            return preset.route
        }
    }

    @ViewBuilder
    private func brandIcon(for preset: Glp1MedicationPreset) -> some View {
        let brand = preset.brand
        let topBrands: Set<String> = ["Wegovy", "Ozempic", "Mounjaro", "Zepbound"]
        if topBrands.contains(brand) {
            let initial = String(brand.prefix(1))

            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.22))
                    .frame(width: 22, height: 22)

                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    private enum Glp1Filter: String, CaseIterable, Identifiable, Hashable {
        case semaglutide
        case tirzepatide
        case liraglutide
        case exenatide
        case lixisenatide
        case injectable
        case oral
        case weekly
        case daily

        var id: String { rawValue }

        var label: String {
            switch self {
            case .semaglutide:
                return "Semaglutide"
            case .tirzepatide:
                return "Tirzepatide"
            case .liraglutide:
                return "Liraglutide"
            case .exenatide:
                return "Exenatide"
            case .lixisenatide:
                return "Lixisenatide"
            case .injectable:
                return "Injectable"
            case .oral:
                return "Oral"
            case .weekly:
                return "Weekly"
            case .daily:
                return "Daily"
            }
        }
    }

    private enum Glp1CustomSchedule: String, CaseIterable, Identifiable {
        case weekly
        case daily
        case everyOtherDay
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .weekly:
                return "Weekly"
            case .daily:
                return "Daily"
            case .everyOtherDay:
                return "Every other"
            case .custom:
                return "Custom"
            }
        }

        func frequencyText(customDays: String) -> String {
            switch self {
            case .weekly:
                return "once weekly"
            case .daily:
                return "once daily"
            case .everyOtherDay:
                return "every other day"
            case .custom:
                return "custom: \(customDays)"
            }
        }
    }

    private struct Glp1Group {
        let title: String
        let items: [Glp1MedicationPreset]
    }

    private func createMedication(from preset: Glp1MedicationPreset) {
        guard !isSaving else { return }
        errorMessage = nil
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
            CoreDataManager.shared.endActiveGlp1Medications(for: userId, endedAt: now)
            CoreDataManager.shared.saveGlp1Medications([medication], userId: userId, markAsSynced: false)

            await MainActor.run {
                onCreated(medication)
                isSaving = false
                dismiss()
            }

            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
        }
    }

    private func createCustomMedication() {
        guard customCompoundCanSave, !isSaving else { return }
        errorMessage = nil
        isSaving = true

        let now = Date()
        let name = trimmedCustomCompoundName
        let medication = Glp1Medication(
            id: UUID().uuidString,
            userId: userId,
            displayName: name,
            genericName: name,
            drugClass: "GLP-1 receptor agonist",
            brand: name,
            route: "subcutaneous",
            frequency: customSchedule.frequencyText(customDays: trimmedCustomScheduleDays),
            doseUnit: trimmedCustomDoseUnit,
            isCompounded: true,
            hkIdentifier: nil,
            startedAt: now,
            endedAt: nil,
            notes: "For informational reference only",
            createdAt: now,
            updatedAt: now
        )

        Task {
            CoreDataManager.shared.endActiveGlp1Medications(for: userId, endedAt: now)
            CoreDataManager.shared.saveGlp1Medications([medication], userId: userId, markAsSynced: false)

            await MainActor.run {
                onCreated(medication)
                isSaving = false
                dismiss()
            }

            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
        }
    }
}

#Preview {
    AddEntrySheet(isPresented: .constant(true))
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
