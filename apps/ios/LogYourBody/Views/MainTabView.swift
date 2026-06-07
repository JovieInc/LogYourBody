//
// MainTabView.swift
// LogYourBody
//
import SwiftUI
import CoreData

struct MainTabView: View {
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @State private var showFullBodyCompositionDashboard = false

    var body: some View {
        NavigationStack {
            if showFullBodyCompositionDashboard {
                DashboardViewLiquid()
            } else {
                PaidWeightLoggerMVPView()
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-lybUITestFullDashboardFixture") {
                showFullBodyCompositionDashboard = true
                return
            }
            #endif

            showFullBodyCompositionDashboard = AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.fullBodyCompositionDashboardFlagKey
            )

            if showFullBodyCompositionDashboard {
                HealthSyncCoordinator.shared.bootstrapIfNeeded(syncEnabled: healthKitSyncEnabled)
            }
        }
    }
}

enum PaidWeightLoggerMVPPolicy {
    static func validationMessage(weightText: String, unit: String) -> String? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            _ = try ValidationService.shared.validateWeight(trimmed, unit: unit)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func canSaveWeight(weightText: String, unit: String, isSaving: Bool) -> Bool {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return false }
        return validationMessage(weightText: trimmed, unit: unit) == nil
    }

    static func syncStatusText(status: RealtimeSyncManager.SyncStatus, pendingCount: Int) -> String {
        switch status {
        case .syncing:
            return "Syncing now"
        case .success:
            return "Synced"
        case .error:
            return "Sync needs retry"
        case .offline:
            return pendingCount > 0 ? "Saved offline" : "Offline"
        case .idle:
            return pendingCount > 0 ? "Sync queued" : "Ready"
        }
    }

    static func savedConfirmationText(isOnline: Bool) -> String {
        isOnline ? "Saved locally. Sync queued." : "Saved locally. Will sync when online."
    }
}

private struct PaidWeightLoggerMVPView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var realtimeSyncManager: RealtimeSyncManager
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @State private var weightText = ""
    @State private var recentMetrics: [BodyMetrics] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var exportFileURL: URL?
    @FocusState private var isWeightFieldFocused: Bool

    private var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    private var latestWeight: BodyMetrics? {
        recentMetrics.first
    }

    private var isSaveDisabled: Bool {
        !PaidWeightLoggerMVPPolicy.canSaveWeight(
            weightText: weightText,
            unit: currentSystem.weightUnit,
            isSaving: isSaving
        )
    }

    private var weightValidationMessage: String? {
        PaidWeightLoggerMVPPolicy.validationMessage(
            weightText: weightText,
            unit: currentSystem.weightUnit
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                latestWeightCard
                entryCard
                recentHistorySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("LogYourBody")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    PreferencesView()
                        .environmentObject(authManager)
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens account and subscription settings.")
                .accessibilityIdentifier("mvp_settings_button")

                Menu {
                    Button(role: .destructive) {
                        Task {
                            await authManager.logout()
                        }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("mvp_sign_out_button")
                } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Account")
                .accessibilityIdentifier("mvp_account_menu_button")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Button("Done") {
                    isWeightFieldFocused = false
                }
                .accessibilityIdentifier("mvp_keyboard_done_button")

                Spacer()

                Button(isSaving ? "Saving" : "Save weight") {
                    saveWeight()
                }
                .disabled(isSaveDisabled)
                .accessibilityIdentifier("mvp_keyboard_save_weight_button")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isWeightFieldFocused {
                keyboardSaveBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isWeightFieldFocused)
        .task {
            await loadRecentMetrics()
        }
        .onChange(of: measurementSystem) { _, _ in
            exportFileURL = nil
            savedMessage = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
            Task {
                await loadRecentMetrics()
            }
        }
        .alert("Could not save weight", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight log")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.appText)

            Text("Log today's weight. Your entries stay on this device and sync to your account.")
                .font(.body.weight(.medium))
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var latestWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latest", systemImage: "scalemass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                syncStatusLabel
            }

            if isLoading {
                ProgressView()
                    .tint(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else if let latestWeight, let weight = latestWeight.weight {
                let display = displayWeight(weight)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(display.value)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundColor(.appText)

                        Text(display.unit)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.appTextSecondary)
                    }

                    Text(latestWeight.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.appTextSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No weight yet")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.appText)

                    Text("Add one entry to start the log.")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.appTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(Constants.cornerRadiusLarge)
    }

    private var syncStatusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 7, height: 7)

            Text(syncStatusText)
                .font(.caption.weight(.semibold))
                .foregroundColor(.appTextSecondary)
        }
        .accessibilityIdentifier("mvp_sync_status")
    }

    private var keyboardSaveBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.appBorder)

            HStack(spacing: 12) {
                Button("Done") {
                    isWeightFieldFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.appTextSecondary)
                .accessibilityIdentifier("mvp_keyboard_bottom_done_button")

                Button(action: saveWeight) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        }

                        Text(isSaving ? "Saving" : "Save weight")
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundColor(.black)
                    .background(isSaveDisabled ? Color.appBorder : Color.appPrimary)
                    .cornerRadius(Constants.cornerRadiusLarge)
                }
                .disabled(isSaveDisabled)
                .accessibilityIdentifier("mvp_keyboard_save_weight_bar_button")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.appCard)
        }
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add weight")
                .font(.title3.weight(.semibold))
                .foregroundColor(.appText)

            Picker("Units", selection: $measurementSystem) {
                Text("lb").tag(MeasurementSystem.imperial.rawValue)
                Text("kg").tag(MeasurementSystem.metric.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("mvp_weight_unit_picker")

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("0.0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(.appText)
                    .focused($isWeightFieldFocused)
                    .accessibilityIdentifier("mvp_weight_text_field")

                Text(currentSystem.weightUnit)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.appBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                    .stroke(isWeightFieldFocused ? Color.appPrimary : Color.appBorder, lineWidth: 1)
            )
            .cornerRadius(Constants.cornerRadiusLarge)

            if let weightValidationMessage {
                Label(weightValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.orange)
                    .accessibilityIdentifier("mvp_weight_validation_message")
            }

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.green)
                    .accessibilityIdentifier("mvp_weight_saved_message")
            }

            saveWeightButton
        }
        .padding(20)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(Constants.cornerRadiusLarge)
    }

    private var saveWeightButton: some View {
        Button(action: saveWeight) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                }

                Text(isSaving ? "Saving" : "Save weight")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundColor(.black)
            .background(isSaveDisabled ? Color.appBorder : Color.appPrimary)
            .cornerRadius(Constants.cornerRadiusLarge)
        }
        .disabled(isSaveDisabled)
        .accessibilityIdentifier("mvp_save_weight_button")
        .accessibilityHint(saveButtonAccessibilityHint)
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent entries")
                .font(.title3.weight(.semibold))
                .foregroundColor(.appText)

            HStack {
                Text("\(recentMetrics.count) saved")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                exportControl
            }

            if recentMetrics.isEmpty && !isLoading {
                Text("Saved weights will appear here.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.appCard)
                    .cornerRadius(Constants.cornerRadiusLarge)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentMetrics.prefix(10)) { metric in
                        recentMetricRow(metric)

                        if metric.id != recentMetrics.prefix(10).last?.id {
                            Divider()
                                .background(Color.appBorder)
                        }
                    }
                }
                .background(Color.appCard)
                .cornerRadius(Constants.cornerRadiusLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var exportControl: some View {
        if let exportFileURL {
            ShareLink(item: exportFileURL) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .disabled(recentMetrics.isEmpty)
        } else {
            Button(action: prepareCSVExport) {
                Label("CSV", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
            }
            .disabled(recentMetrics.isEmpty)
        }
    }

    private func recentMetricRow(_ metric: BodyMetrics) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appText)

                Text(metric.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            if let weight = metric.weight {
                let display = displayWeight(weight)
                Text("\(display.value) \(display.unit)")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.appText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var syncStatusText: String {
        PaidWeightLoggerMVPPolicy.syncStatusText(
            status: realtimeSyncManager.syncStatus,
            pendingCount: realtimeSyncManager.pendingSyncCount
        )
    }

    private var syncStatusColor: Color {
        switch realtimeSyncManager.syncStatus {
        case .success:
            return .green
        case .syncing:
            return .appPrimary
        case .error:
            return .orange
        case .offline:
            return .gray
        case .idle:
            return realtimeSyncManager.pendingSyncCount > 0 ? .orange : .green
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private var saveButtonAccessibilityHint: String {
        if isSaving {
            return "Saving your weight."
        }

        if weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a weight before saving."
        }

        if let weightValidationMessage {
            return weightValidationMessage
        }

        return "Saves this weight locally and queues account sync."
    }

    private func displayWeight(_ weightKg: Double) -> (value: String, unit: String) {
        let useMetric = currentSystem == .metric
        let value = UnitConversion.displayWeight(weightKg, useMetric: useMetric)
        return (String(format: "%.1f", value), currentSystem.weightUnit)
    }

    private func saveWeight() {
        guard !isSaveDisabled else { return }

        Task {
            await saveWeightEntry()
        }
    }

    @MainActor
    private func saveWeightEntry() async {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "Sign in again before logging weight."
            return
        }

        isSaving = true
        savedMessage = nil

        do {
            let validatedWeight = try ValidationService.shared.validateWeight(
                weightText,
                unit: currentSystem.weightUnit
            )
            let weightInKilograms = currentSystem == .imperial ? validatedWeight.lbsToKg : validatedWeight
            let now = Date()

            let metrics = BodyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: now,
                weight: weightInKilograms,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: now,
                updatedAt: now
            )

            try await CoreDataManager.shared.saveBodyMetricsAndWait(metrics, userId: userId, markAsSynced: false)
            realtimeSyncManager.updatePendingSyncCount()
            realtimeSyncManager.syncIfNeeded()
            AnalyticsService.shared.track(event: "mvp_weight_logged")

            isWeightFieldFocused = false
            weightText = ""
            savedMessage = PaidWeightLoggerMVPPolicy.savedConfirmationText(isOnline: realtimeSyncManager.isOnline)
            exportFileURL = nil

            try? await Task.sleep(nanoseconds: 150_000_000)
            await loadRecentMetrics()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    @MainActor
    private func loadRecentMetrics() async {
        guard let userId = authManager.currentUser?.id else {
            recentMetrics = []
            isLoading = false
            return
        }

        isLoading = true
        let cachedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        recentMetrics = cachedMetrics
            .compactMap { $0.toBodyMetrics() }
            .filter { $0.weight != nil }
            .sorted { $0.date > $1.date }
        exportFileURL = nil
        if savedMessage == "CSV ready" {
            savedMessage = nil
        }
        isLoading = false
    }

    private func prepareCSVExport() {
        do {
            exportFileURL = try writeWeightCSV(metrics: recentMetrics)
            savedMessage = "CSV ready"
        } catch {
            errorMessage = "Could not prepare CSV export."
        }
    }

    private func writeWeightCSV(metrics: [BodyMetrics]) throws -> URL {
        var csv = "Date,Weight,Unit\n"
        let formatter = ISO8601DateFormatter()

        for metric in metrics.sorted(by: { $0.date < $1.date }) {
            guard let weight = metric.weight else { continue }
            let display = displayWeight(weight)
            csv += "\(formatter.string(from: metric.date)),\(display.value),\(display.unit)\n"
        }

        let fileName = "LogYourBody_weight_log_\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

#Preview {
    NavigationStack {
        MainTabView()
            .environmentObject(AuthManager())
            .environmentObject(RealtimeSyncManager.shared)
    }
}
