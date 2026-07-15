import SwiftUI

extension AddEntrySheet {
var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

var resolvedWeightUnit: String {
        weightUnit.isEmpty ? currentSystem.weightUnit : weightUnit
    }

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
                        guard PhotoUploadBatchPolicy.canDismiss(
                            isSaving: isSavingEntry,
                            isProcessing: isProcessingPhotos
                        ) else { return }
                        dismiss()
                    }
                    .disabled(!PhotoUploadBatchPolicy.canDismiss(
                        isSaving: isSavingEntry,
                        isProcessing: isProcessingPhotos
                    ))
                }
            }
            .interactiveDismissDisabled(!PhotoUploadBatchPolicy.canDismiss(
                isSaving: isSavingEntry,
                isProcessing: isProcessingPhotos
            ))
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
                AppServicePorts.analyticsTracker.track(event: "add_entry_view")
            }
            .onChange(of: selectedTab) { _, _ in
                loadGlp1MedicationsIfNeeded()
            }
        }
    }

// MARK: - GLP-1 Entry View

    var glp1EntryView: some View {
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
                        let unit = glp1DoseUnit.isEmpty
                            ? (glp1UnitForSelectedMedication ?? "mg")
                            : glp1DoseUnit

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
                            } else if !glp1UseCustomDose && !options.isEmpty {
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
                                .accessibilityLabel("GLP-1 dose")
                                .accessibilityValue(glp1SelectedDoseAccessibilityValue)
                                .accessibilityHint("Selected dose for this log.")
                                .accessibilityIdentifier("glp1_dose_picker")

                                HStack {
                                    Text(unit)
                                        .font(.appBodySmall)
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                }
                            }

                            if let lastLoggedDoseText = glp1LastLoggedDoseText {
                                Text("Last logged: \(lastLoggedDoseText)")
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)
                                    .accessibilityLabel("Last logged dose: \(lastLoggedDoseText)")
                                    .accessibilityIdentifier("glp1_last_logged_dose_status")
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
                                        .accessibilityIdentifier("glp1_custom_dose_field")
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
                                glp1DoseUnit = unit
                            }
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
                        applyResolvedGlp1DoseDraft(for: medication)
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

var glp1DoseHistorySection: some View {
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

func glp1DoseHistoryRow(_ log: Glp1DoseLog) -> some View {
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
    var weightEntryView: some View {
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
    var bodyFatEntryView: some View {
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
}
