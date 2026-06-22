//
// AddEntrySheet.swift
// LogYourBody
//
import SwiftUI

struct PhotoUploadBatchPolicy {
    static func progress(completedCount: Int, totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    static func progressText(processedCount: Int, totalCount: Int) -> String {
        guard totalCount > 0 else { return "Processing photos" }
        let currentIndex = min(processedCount + 1, totalCount)
        return "Processing \(currentIndex) of \(totalCount)"
    }

    static func canChangeSelection(isProcessing: Bool) -> Bool {
        !isProcessing
    }

    static func canStartUpload(selectedCount: Int, isSaving: Bool, isProcessing: Bool) -> Bool {
        selectedCount > 0 && !isSaving && !isProcessing
    }

    static func canDismiss(isSaving: Bool, isProcessing: Bool) -> Bool {
        !isSaving && !isProcessing
    }

    static func shouldDismissAfterUpload(successfulCount: Int, totalCount: Int) -> Bool {
        totalCount > 0 && successfulCount == totalCount
    }

    static func uploadFailureMessage(successfulCount: Int, totalCount: Int) -> String {
        guard successfulCount > 0 else {
            return "Photo upload failed. Please try again."
        }

        let failedCount = max(totalCount - successfulCount, 0)
        let noun = failedCount == 1 ? "photo" : "photos"
        return "Uploaded \(successfulCount) of \(totalCount) photos. \(failedCount) \(noun) failed. Try again."
    }
}

struct AddEntrySheet: View {
    @Environment(\.dismiss)
    var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    @State var selectedTab: Int
    let includesGlp1Entry: Bool
    @State var selectedDate = Date()
    @AppStorage(Constants.preferredMeasurementSystemKey) var measurementSystem = PreferencesView.defaultMeasurementSystem

    init(isPresented: Binding<Bool>, initialTab: Int = 0, includesGlp1Entry: Bool = false) {
        let resolvedInitialTab = initialTab == 3 && !includesGlp1Entry ? 0 : initialTab
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: resolvedInitialTab)
        self.includesGlp1Entry = includesGlp1Entry
    }


    // Weight entry
    @State var weight: String = ""
    @State var weightUnit: String = ""
    @State var weightError: String?

    // Body fat entry
    @State var bodyFat: String = ""
    @State var bodyFatMethod = "Visual"
    @State var bodyFatError: String?

    // Photo entry
    @State var selectedPhotos: [AppPhotoAsset] = []
    @State var isProcessingPhotos = false
    @State var photoProgress: Double = 0
    @State var processedCount = 0
    @State var processingPhotoCount = 0
    @State var photoIdentifiers: [String] = []  // Store successfully uploaded photo identifiers for deletion

    // GLP-1 entry
    @State var glp1Dose: String = ""
    @State var glp1DoseUnit: String = "mg/week"
    @State var glp1Error: String?
    @State var glp1Medications: [Glp1Medication] = []
    @State var selectedGlp1MedicationId: String?
    @State var selectedGlp1DoseIndex: Int = 0
    @State var glp1IsLoadingMedications = false
    @State var isPresentingGlp1AddMedication = false
    @State var glp1UseCustomDose = false
    @State var glp1IsRestDay = false
    @State var glp1UserId: String?
    @State var glp1DoseLogs: [Glp1DoseLog] = []
    @State var glp1DoseNotes: String = ""
    @State var editingGlp1DoseLogId: String?
    @State var editingGlp1DoseCreatedAt: Date?
    @State var pendingDeleteGlp1DoseLog: Glp1DoseLog?

    @State var showError = false
    @State var errorMessage = ""
    @State var isSavingEntry = false
    @State var showDeletePhotosPrompt = false
    @AppStorage(Constants.deletePhotosAfterImportKey) var deletePhotosAfterImport = false
    @AppStorage(Constants.hasPromptedDeletePhotosKey) var hasPromptedDeletePhotos = false


    // MARK: - Validation Functions

    enum InputField {
        case weight
        case bodyFat
    }
}

struct Glp1AddMedicationView: View {
    let userId: String
    let onCreated: (Glp1Medication) -> Void

    @Environment(\.dismiss) var dismiss
    @State var isSaving = false
    @State var errorMessage: String?
    @State var searchText: String = ""
    @State var selectedPreset: Glp1MedicationPreset?
    @State var activeFilters: Set<Glp1Filter> = []
    @State var customCompoundName: String = ""
    @State var customDoseUnit: String = "mg/week"
    @State var customSchedule: Glp1CustomSchedule = .weekly
    @State var customScheduleDays: String = ""

    var presets: [Glp1MedicationPreset] {
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

    var filteredPresets: [Glp1MedicationPreset] {
        presets.filter { preset in
            matchesSearch(preset) && matchesFilters(preset)
        }
    }

    var customCompoundCanSave: Bool {
        !trimmedCustomCompoundName.isEmpty
            && !trimmedCustomDoseUnit.isEmpty
            && (customSchedule != .custom || !trimmedCustomScheduleDays.isEmpty)
    }

    var trimmedCustomCompoundName: String {
        customCompoundName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCustomDoseUnit: String {
        customDoseUnit.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCustomScheduleDays: String {
        customScheduleDays.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var groupedPresets: [Glp1Group] {
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

    func matchesSearch(_ preset: Glp1MedicationPreset) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let lowercased = query.lowercased()
        return preset.displayName.lowercased().contains(lowercased)
            || preset.genericName.lowercased().contains(lowercased)
            || preset.brand.lowercased().contains(lowercased)
    }

    func matchesFilters(_ preset: Glp1MedicationPreset) -> Bool {
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

    func hasDrugFilter() -> Bool {
        activeFilters.contains(.semaglutide)
            || activeFilters.contains(.tirzepatide)
            || activeFilters.contains(.liraglutide)
            || activeFilters.contains(.exenatide)
            || activeFilters.contains(.lixisenatide)
    }

    func matchesDrugFilter(forGenericName generic: String) -> Bool {
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

    func toggleFilter(_ filter: Glp1Filter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    func formattedRoute(for preset: Glp1MedicationPreset) -> String {
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
    func brandIcon(for preset: Glp1MedicationPreset) -> some View {
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

    enum Glp1Filter: String, CaseIterable, Identifiable, Hashable {
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

    enum Glp1CustomSchedule: String, CaseIterable, Identifiable {
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

    struct Glp1Group {
        let title: String
        let items: [Glp1MedicationPreset]
    }

    func createMedication(from preset: Glp1MedicationPreset) {
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

    func createCustomMedication() {
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
