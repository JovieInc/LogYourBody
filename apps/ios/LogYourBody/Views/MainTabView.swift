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
            showFullBodyCompositionDashboard = AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.fullBodyCompositionDashboardFlagKey
            )

            if showFullBodyCompositionDashboard {
                HealthSyncCoordinator.shared.bootstrapIfNeeded(syncEnabled: healthKitSyncEnabled)
            }
        }
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
        weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
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
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("LogYourBody")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await authManager.logout()
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.appText)
                }
                .accessibilityLabel("Account")
            }
        }
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.appText)

            Text("Log today's weight. Your entries stay on this device and sync to your account.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var latestWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Latest", systemImage: "scalemass.fill")
                    .font(.system(size: 15, weight: .semibold))
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
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.appText)

                        Text(display.unit)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                    }

                    Text(latestWeight.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appTextSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No weight yet")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.appText)

                    Text("Add one entry to start the log.")
                        .font(.system(size: 15, weight: .medium))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appTextSecondary)
        }
        .accessibilityIdentifier("mvp_sync_status")
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add weight")
                .font(.system(size: 20, weight: .semibold))
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
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.appText)
                    .focused($isWeightFieldFocused)
                    .accessibilityIdentifier("mvp_weight_text_field")

                Text(currentSystem.weightUnit)
                    .font(.system(size: 20, weight: .semibold))
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

            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
            }

            Button(action: saveWeight) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.black)
                    }

                    Text(isSaving ? "Saving" : "Save weight")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundColor(.black)
                .background(isSaveDisabled ? Color.appBorder : Color.appPrimary)
                .cornerRadius(Constants.cornerRadiusLarge)
            }
            .disabled(isSaveDisabled)
            .accessibilityIdentifier("mvp_save_weight_button")
        }
        .padding(20)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cornerRadiusLarge)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .cornerRadius(Constants.cornerRadiusLarge)
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent entries")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.appText)

            HStack {
                Text("\(recentMetrics.count) saved")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.appTextSecondary)

                Spacer()

                exportControl
            }

            if recentMetrics.isEmpty && !isLoading {
                Text("Saved weights will appear here.")
                    .font(.system(size: 15, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
            }
            .disabled(recentMetrics.isEmpty)
        } else {
            Button(action: prepareCSVExport) {
                Label("CSV", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
            }
            .disabled(recentMetrics.isEmpty)
        }
    }

    private func recentMetricRow(_ metric: BodyMetrics) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appText)

                Text(metric.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            if let weight = metric.weight {
                let display = displayWeight(weight)
                Text("\(display.value) \(display.unit)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.appText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var syncStatusText: String {
        switch realtimeSyncManager.syncStatus {
        case .syncing:
            return "Syncing"
        case .success:
            return "Synced"
        case .error:
            return "Sync issue"
        case .offline:
            return "Offline"
        case .idle:
            return realtimeSyncManager.pendingSyncCount > 0 ? "Pending" : "Ready"
        }
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

            CoreDataManager.shared.saveBodyMetrics(metrics, userId: userId, markAsSynced: false)
            realtimeSyncManager.syncIfNeeded()
            AnalyticsService.shared.track(event: "mvp_weight_logged")

            weightText = ""
            savedMessage = "Saved"
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
