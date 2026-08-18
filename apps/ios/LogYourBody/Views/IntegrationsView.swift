//
// IntegrationsView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct IntegrationsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @AppStorage(Constants.healthKitSyncEnabledKey) private var healthKitSyncEnabled = true
    @State private var showHealthKitConnect = false
    @State private var isConnectingHealthKit = false
    @State private var isSyncingHealthKit = false
    @State private var healthSyncStatusMessage: String?
    @State private var healthSyncStatusIsError = false
    @State private var bodySpecLastSyncedText: String?
    @State private var isLoadingBodySpecLastSynced = false
    @State private var progressPhotoCount = 0
    @State private var featureGateRefreshToken = UUID()
    var body: some View {
        List {
            healthAndFitnessSection
            if isBulkProgressPhotoImportEnabled {
                photoImportSection
            }
            dataExportSection
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Apple Health access is needed", isPresented: $showHealthKitConnect) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Allow Health access in Settings to sync weight and body-composition data.")
        }
        .onAppear {
            // Check HealthKit authorization status
            healthKitManager.checkAuthorizationStatus()

            Task { @MainActor in
                await loadBodySpecLastSynced()
            }

            loadBulkPhotoImportActivationEvidence()
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
            featureGateRefreshToken = UUID()
        }
        .worldClassScreen(.integrations)
    }

    private var healthAndFitnessSection: some View {
        SettingsSection(
            header: "Health & Fitness",
            footer: "Control data connections and sync."
        ) {
            if healthKitManager.isHealthKitAvailable {
                ViewThatFits(in: .horizontal) {
                    appleHealthConnectionRow
                    appleHealthConnectionStack
                }

                if healthKitManager.isAuthorized {
                    SettingsToggleRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Enable Sync",
                        isOn: $healthKitSyncEnabled,
                        subtitle: "Keep weight and steps up to date"
                    )
                    .onChange(of: healthKitSyncEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let authorized = await healthKitManager.requestAuthorization()
                                if authorized {
                                    await HealthSyncCoordinator.shared
                                        .configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
                                } else {
                                    await MainActor.run {
                                        healthKitSyncEnabled = false
                                        showHealthKitConnect = true
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        Task { @MainActor in
                            await syncAllHealthData()
                        }
                    } label: {
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: isSyncingHealthKit ? "Syncing historical data" : "Sync all historical data",
                            subtitle: healthSyncStatusMessage,
                            subtitleColor: healthSyncStatusIsError ? .red : nil,
                            showChevron: false
                        )
                    }
                    .foregroundStyle(.primary)
                    .disabled(isSyncingHealthKit)
                    .accessibilityHint("Syncs your historical Apple Health data now.")
                    .accessibilityIdentifier("integrations_health_sync_all_button")
                }
            } else {
                DataInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Apple Health isn’t available",
                    description: "This device doesn’t support Apple Health.",
                    iconColor: .orange
                )
            }

            if Constants.isBodySpecEnabled {
                NavigationLink(
                    destination: BodySpecIntegrationView()
                        .environmentObject(authManager)
                ) {
                    SettingsRow(
                        icon: "waveform.path.ecg",
                        title: "BodySpec",
                        subtitle: "DEXA scans",
                        value: bodySpecSyncStatusText,
                        showChevron: false
                    )
                }
                .accessibilityIdentifier("integrations_bodyspec_link")
            }
        }
    }

    private var appleHealthConnectionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text("Apple Health")

            Spacer()

            healthConnectionStatus
        }
    }

    private var appleHealthConnectionStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text("Apple Health")
            }

            healthConnectionStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var healthConnectionStatus: some View {
        if healthKitManager.isAuthorized {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Apple Health connected")
        } else {
            Button {
                Task { @MainActor in
                    await connectAppleHealth()
                }
            } label: {
                if isConnectingHealthKit {
                    ProgressView()
                } else {
                    Text("Connect")
                }
            }
            .disabled(isConnectingHealthKit)
            .accessibilityLabel("Connect Apple Health")
            .accessibilityHint("Requests Apple Health access to sync your data.")
        }
    }

    private var photoImportSection: some View {
        SettingsSection(
            header: "Photo Import",
            footer: BulkProgressPhotoImportPolicy.footerText(
                isEnabled: true,
                existingProgressPhotoCount: progressPhotoCount
            )
        ) {
            NavigationLink(destination: BulkPhotoImportView().environmentObject(authManager)) {
                SettingsRow(
                    icon: "photo.stack",
                    title: "Import Progress Photos",
                    subtitle: "Choose photos from your library",
                    value: "Scan library",
                    showChevron: false
                )
                .accessibilityIdentifier("integrations_bulk_photo_import_link")
            }
        }
    }

    private var dataExportSection: some View {
        SettingsSection(
            header: "Data Export",
            footer: "Download a copy of your LogYourBody data as a CSV file."
        ) {
            NavigationLink(destination: ExportDataView()) {
                SettingsRow(
                    icon: "doc.text",
                    title: "Export Data",
                    value: "CSV",
                    showChevron: false
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        IntegrationsView()
            .environmentObject(AuthManager.shared)
    }
}

// MARK: - BodySpec Helpers

extension IntegrationsView {
    private var bodySpecSyncStatusText: String {
        if isLoadingBodySpecLastSynced {
            return "Checking"
        }

        return bodySpecLastSyncedText ?? "Not synced yet"
    }

    @MainActor
    private func connectAppleHealth() async {
        guard !isConnectingHealthKit else { return }

        isConnectingHealthKit = true
        healthSyncStatusMessage = nil
        healthSyncStatusIsError = false

        let authorized = await healthKitManager.requestAuthorization()
        if authorized {
            await HealthSyncCoordinator.shared
                .configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
            healthSyncStatusMessage = "Apple Health sync is on"
        } else {
            showHealthKitConnect = true
        }

        isConnectingHealthKit = false
    }

    @MainActor
    private func syncAllHealthData() async {
        guard !isSyncingHealthKit else { return }

        isSyncingHealthKit = true
        healthSyncStatusMessage = nil
        healthSyncStatusIsError = false
        let didSucceed = await HealthSyncCoordinator.shared.forceFullHealthKitSync()
        healthSyncStatusMessage = didSucceed
            ? "Historical Apple Health data synced"
            : "Historical sync failed. Try again."
        healthSyncStatusIsError = !didSucceed
        isSyncingHealthKit = false
    }

    private var isBulkProgressPhotoImportEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestBulkPhotoImportEnabledFixture") {
            return true
        }
        #endif

        return BulkProgressPhotoImportPolicy.shouldShowBulkImport(
            existingProgressPhotoCount: progressPhotoCount
        )
    }

    private func loadBulkPhotoImportActivationEvidence() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestBulkPhotoImportActivationFixture") {
            progressPhotoCount = BulkProgressPhotoImportPolicy.activationProgressPhotoCount
            return
        }
        #endif

        guard let userId = authManager.currentUser?.id else {
            progressPhotoCount = 0
            return
        }

        Task {
            let metrics = await CoreDataManager.shared.fetchVisibleBodyMetrics(for: userId)
            let photoCount = metrics.filter { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }.count

            await MainActor.run {
                progressPhotoCount = photoCount
            }
        }
    }

    @MainActor
    private func loadBodySpecLastSynced() async {
        guard Constants.isBodySpecEnabled,
              let userId = authManager.currentUser?.id else {
            bodySpecLastSyncedText = nil
            isLoadingBodySpecLastSynced = false
            return
        }

        isLoadingBodySpecLastSynced = true

        let cached = await CoreDataManager.shared.fetchDexaResults(for: userId, limit: 1)
        if let latest = cached.first {
            let date = latest.acquireTime ?? latest.updatedAt
            bodySpecLastSyncedText = formatBodySpecLastSynced(date: date)
        } else {
            bodySpecLastSyncedText = "Not synced yet"
        }

        do {
            let results = try await AppServicePorts.dexaResultRemoteDataProvider.fetchDexaResults(userId: userId, limit: 1)

            if let latest = results.first {
                let date = latest.acquireTime ?? latest.updatedAt
                bodySpecLastSyncedText = formatBodySpecLastSynced(date: date)
            } else {
                bodySpecLastSyncedText = "Not synced yet"
            }

            CoreDataManager.shared.saveDexaResults(results, userId: userId)
        } catch {
        }

        isLoadingBodySpecLastSynced = false
    }

    private func formatBodySpecLastSynced(date: Date?) -> String {
        guard let date else {
            return "Not synced yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Last synced · \(relative)"
    }
}
