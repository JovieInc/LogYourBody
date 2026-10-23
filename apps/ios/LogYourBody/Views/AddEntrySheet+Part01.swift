import SwiftUI

extension AddEntrySheet {
var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

var resolvedWeightUnit: String {
        weightUnit.isEmpty ? currentSystem.weightUnit : weightUnit
    }

var entryTitle: String {
        switch selectedTab {
        case 0: "Weight"
        case 1: "Body fat"
        case 2: "Progress photo"
        case 3: "Weekly check-in"
        default: "Add entry"
        }
    }

var entryScreen: WorldClassScreen {
        switch selectedTab {
        case 0: .logWeight
        case 1: .logBodyFat
        case 2: .addProgressPhoto
        case 3: .glp1CheckIn
        default: .logWeight
        }
    }

var isHomeV2WeightEntry: Bool {
        isHomeV2LogEntry && selectedTab == 0
    }

var usesAccessibleBodyFatLayout: Bool {
        isHomeV2LogEntry && selectedTab == 1 && dynamicTypeSize.isAccessibilitySize
    }

var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isHomeV2WeightEntry && !usesAccessibleBodyFatLayout {
                    entryDateDescription
                }

                Picker("Entry Type", selection: $selectedTab) {
                    Label("Weight", systemImage: "scalemass").tag(0)
                    Label("Body Fat", systemImage: "percent").tag(1)
                    Label("Photos", systemImage: "photo.fill").tag(2)
                    if includesGlp1Entry {
                        Label("GLP-1", systemImage: "syringe").tag(3)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, 12)
                .accessibilityLabel("Entry type selector")
                .accessibilityHint("Select the type of entry you want to add")

                if !usesAccessibleBodyFatLayout {
                    entryDatePicker
                }

                Divider()

                // Tab content
                if usesAccessibleBodyFatLayout {
                    accessibleBodyFatScrollView
                } else {
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
                    .accessibilityIdentifier(isHomeV2WeightEntry ? "home_v2_log_sheet_content" : "add_entry_content")
                    .clipped()
                }

                entrySaveButton
                .accessibilityIdentifier(isHomeV2LogEntry ? "home_v2_log_sheet_save" : "add_entry_save_button")
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, 12)
            }
            .worldClassScreen(entryScreen)
            .navigationTitle(isHomeV2LogEntry ? "" : entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isHomeV2LogEntry {
                    ToolbarItem(placement: .principal) {
                        Text(selectedTab == 0 ? "Log weight" : entryTitle)
                            .font(.headline)
                            .accessibilityIdentifier("home_v2_log_sheet")
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button("Cancel") {
                        guard NativeSheetPresentationPolicy.canDismissAddEntry(
                            isSaving: isSavingEntry,
                            isProcessing: isProcessingPhotos
                        ) else { return }
                        dismiss()
                    }
                    .disabled(!NativeSheetPresentationPolicy.canDismissAddEntry(
                        isSaving: isSavingEntry,
                        isProcessing: isProcessingPhotos
                    ))
                }
            }
            .interactiveDismissDisabled(!NativeSheetPresentationPolicy.canDismissAddEntry(
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
        .nativeSheetChrome(for: .addEntry, detent: $sheetDetent)
    }

    private var bodyFatValueScrollID: String { "body-fat-value-control" }

    private var accessibleBodyFatScrollView: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        entryDateDescription
                        entryDatePicker
                        bodyFatEntryView
                    }
                }
                .accessibilityIdentifier("add_entry_content")
                .onChange(of: isBodyFatFieldEditing) { _, _ in
                    revealBodyFatField(using: proxy, viewportHeight: viewport.size.height)
                }
                .onChange(of: viewport.size.height) { _, height in
                    revealBodyFatField(using: proxy, viewportHeight: height)
                }
            }
        }
    }

    private func revealBodyFatField(using proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard isBodyFatFieldEditing, viewportHeight.isFinite, viewportHeight > 0 else { return }
        proxy.scrollTo(bodyFatValueScrollID, anchor: .center)
    }

    private var entryDateDescription: some View {
        Text(selectedDate.formatted(date: .complete, time: .shortened))
            .font(.subheadline)
            .foregroundStyle(Color.jovieTextSecondary)
            .fixedSize(horizontal: false, vertical: usesAccessibleBodyFatLayout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.top, 8)
            .accessibilityIdentifier(isHomeV2LogEntry ? "home_v2_log_sheet_date" : "add_entry_date")
    }

    private var entryDatePicker: some View {
        Group {
            if isHomeV2WeightEntry {
                // Compact only. A graphical calendar draws over the value.
                DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(.appBodySmall)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .tint(.jovieText)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                    .accessibilityIdentifier("home_v2_log_sheet_date")
            } else if usesAccessibleBodyFatLayout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)
                    DatePicker("Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                }
            } else {
                HStack {
                    Text("Date")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    Spacer()

                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, JovieTokens.screenInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var entrySaveButton: some View {
        let configuration = ButtonConfiguration(
            style: .custom(background: .jovieAction, foreground: .jovieActionText),
            size: .large,
            isLoading: isProcessingPhotos || isSavingEntry,
            isEnabled: canSave && !isProcessingPhotos && !isSavingEntry,
            fullWidth: true,
            cornerRadius: 9_999
        )
        if usesAccessibleBodyFatLayout {
            BaseButton(configuration: configuration, action: saveEntry) {
                Text(saveButtonText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if isHomeV2WeightEntry {
            BaseButton(saveButtonText, configuration: configuration, action: saveEntry)
                .keyboardShortcut(.defaultAction)
        } else {
            BaseButton(saveButtonText, configuration: configuration, action: saveEntry)
        }
    }

// MARK: - GLP-1 Entry View

    var glp1EntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingGlp1DoseLogId == nil ? "Log GLP-1 dose" : "Edit GLP-1 dose")
                .font(.appHeadline)
                .padding(.top)

            Text(Glp1DoseLogCopy.trackingNotice)
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

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

                    Text("Choose the medication you track to make logging and reminders easier.")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)

                    Button("Add medication") {
                        isPresentingGlp1AddMedication = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
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
                                HStack(spacing: 8) {
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
                                Text(Glp1DoseLogCopy.noDoseTaken)
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

                            if !glp1IsRestDay && !options.isEmpty {
                                Toggle("Custom dose", isOn: $glp1UseCustomDose)
                                    .font(.appBodySmall)
                                    .foregroundColor(.appTextSecondary)
                                    .onChange(of: glp1UseCustomDose) { _, isCustom in
                                        if !isCustom {
                                            updateGlp1DoseFromSelection()
                                        }
                                    }
                            }

                            if (glp1UseCustomDose || options.isEmpty) && !glp1IsRestDay {
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
                                Text(options.isEmpty ? Glp1DoseLogCopy.enterRecordedDose : Glp1DoseLogCopy.usePreviousDose)
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
        // The confirmation-dialog Cancel button measured 36 points wide.
        .alert(
            "Delete dose?",
            isPresented: glp1DeleteConfirmationBinding
        ) {
            if let log = pendingDeleteGlp1DoseLog {
                Button("Delete dose", role: .destructive) {
                    deleteGlp1Dose(log)
                }
                .accessibilityIdentifier("glp1_dose_delete_confirm")
            }
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("glp1_dose_delete_cancel")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("No doses logged yet")
                        .font(.appBody)
                        .foregroundColor(.appText)

                    Text("Save a dose here and it will appear in your history.")
                        .font(.appBodySmall)
                        .foregroundColor(.appTextSecondary)
                }
                .padding(16)
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
        .padding(16)
    }

// MARK: - Weight Entry View
    @ViewBuilder
    var weightEntryView: some View {
        if isHomeV2LogEntry {
            homeV2WeightEntryView
        } else {
            standardWeightEntryView
        }
    }

    private var homeV2WeightEntryView: some View {
        VStack(spacing: 24) {
            // Value and unit share one row so the reading cannot paint over the unit.
            HStack(alignment: .center, spacing: 12) {
                TextField("0.0", text: $weight)
                    .keyboardType(.decimalPad)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.jovieText)
                    .tint(.jovieText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                    .accessibilityLabel("Weight value")
                    .accessibilityHint("Enter your weight")
                    .accessibilityIdentifier("home_v2_log_sheet_value")
                    .submitLabel(.done)
                    .onChange(of: weight) { _, newValue in
                        validateWeight(newValue)
                    }

                Picker("Weight unit", selection: $weightUnit) {
                    Text("kg").tag("kg")
                    Text("lbs").tag("lbs")
                }
                .pickerStyle(.menu)
                .tint(.jovieTextSecondary)
                .frame(minWidth: 72, minHeight: JovieTokens.minimumHitTarget)
                .layoutPriority(1)
                .accessibilityValue(weightUnit)
                .accessibilityIdentifier("home_v2_log_sheet_unit")
                .onChange(of: weightUnit) { previous, current in
                    updateWeightUnit(from: previous, to: current)
                }
            }

            HStack(spacing: 24) {
                homeV2WeightStepButton(direction: -1, symbol: "minus", label: "Decrease weight")
                homeV2WeightStepButton(direction: 1, symbol: "plus", label: "Increase weight")
            }

            Group {
                if let error = weightError {
                    Text(error)
                        .foregroundStyle(Color.error)
                        .accessibilityLabel("Weight validation error: \(error)")
                } else {
                    Text("Use your scale reading for this date.")
                        .foregroundStyle(Color.jovieTextSecondary)
                }
            }
            .font(.appBodySmall)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                selectedTab = 1
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add body fat")
                            .font(.body)
                            .foregroundStyle(Color.jovieText)
                        Text("Optional estimate or measurement")
                            .font(.caption)
                            .foregroundStyle(Color.jovieTextSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(Color.jovieTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_log_sheet_details")
        }
        .padding(.horizontal, JovieTokens.screenInset)
        .padding(.vertical, 24)
    }

    private func homeV2WeightStepButton(direction: Int, symbol: String, label: String) -> some View {
        Button { stepWeight(by: direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.jovieText)
                .frame(width: 48, height: 48)
                .background(Color.jovieText.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(direction < 0 ? "home_v2_log_sheet_minus" : "home_v2_log_sheet_plus")
    }

    private var standardWeightEntryView: some View {
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
                    .onChange(of: weightUnit) { previous, current in
                        updateWeightUnit(from: previous, to: current)
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
                    TextField("0.0", text: $bodyFat, onEditingChanged: { isBodyFatFieldEditing = $0 })
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
                .id(bodyFatValueScrollID)

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

                Group {
                    if usesAccessibleBodyFatLayout {
                        accessibleBodyFatMethodSummary
                    } else {
                        bodyFatMethodPicker
                            .pickerStyle(MenuPickerStyle())
                            .accessibilityLabel("Body fat measurement method")
                            .accessibilityValue(BodyFatEntryMethod.selectionTitle(bodyFatMethod))
                            .accessibilityIdentifier("home_v2_body_fat_method")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // A Menu around the picker draws only the current value at the
                // largest text size, so DEXA is not a visible choice. List every
                // method in the sheet, which already scrolls above Save.
                if usesAccessibleBodyFatLayout {
                    accessibleBodyFatMethodChoices
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private var accessibleBodyFatMethodSummary: some View {
        Button {
            // The rows below change the method. This row reports the current one.
        } label: {
            Text(BodyFatEntryMethod.selectionTitle(bodyFatMethod))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Body fat measurement method")
        .accessibilityValue(BodyFatEntryMethod.selectionTitle(bodyFatMethod))
        .accessibilityHint("Measurement choices are listed below")
        .accessibilityIdentifier("home_v2_body_fat_method")
    }

    private var accessibleBodyFatMethodChoices: some View {
        ForEach(BodyFatEntryMethod.accessibleChoices(selected: bodyFatMethod)) { choice in
            Button {
                bodyFatMethod = choice.value
            } label: {
                HStack(spacing: 12) {
                    Text(choice.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if BodyFatEntryMethod.selectionTitle(bodyFatMethod) == choice.title {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(choice.title)
        }
    }

    private var bodyFatMethodPicker: some View {
        Picker("Method", selection: $bodyFatMethod) {
            if BodyFatEntryMethod.needsPreservedOption(bodyFatMethod) {
                Text(BodyFatEntryMethod.selectionTitle(bodyFatMethod)).tag(bodyFatMethod)
            }
            ForEach(BodyFatEntryMethod.allCases, id: \.rawValue) { method in
                Text(method.title).tag(Optional(method.rawValue))
            }
        }
    }
}
