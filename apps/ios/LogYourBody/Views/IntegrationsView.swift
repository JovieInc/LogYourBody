//
// IntegrationsView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct IntegrationsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.theme)
    private var theme
    @StateObject private var healthKitManager = HealthKitManager.shared
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @State private var showHealthKitConnect = false
    @State private var isConnectingHealthKit = false
    @State private var isSyncingHealthKit = false
    @State private var healthSyncStatusMessage: String?
    @State private var bodySpecLastSyncedText: String?
    @State private var isLoadingBodySpecLastSynced = false
    @State private var progressPhotoCount = 0
    @State private var featureGateRefreshToken = UUID()
    @Environment(\.dismiss)

    var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.sectionSpacing) {
                healthAndFitnessSection
                photoImportSection
                dataExportSection
            }
            .padding(.horizontal, theme.spacing.screenPadding)
            .padding(.top, theme.spacing.md)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .settingsBackground()
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
    }

    private var healthAndFitnessSection: some View {
        SettingsSection(
            header: "Health & Fitness",
            footer: "Control data connections and sync."
        ) {
            VStack(spacing: 0) {
                // Apple Health
                if healthKitManager.isHealthKitAvailable {
                    ViewThatFits(in: .horizontal) {
                        appleHealthConnectionRow
                        appleHealthConnectionStack
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .frame(minHeight: JovieTokens.minimumHitTarget)

                    if healthKitManager.isAuthorized {
                        Divider()

                        // Enable Sync Toggle
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

                        Divider()

                        Button {
                            Task { @MainActor in
                                await syncAllHealthData()
                            }
                        } label: {
                            SettingsRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: isSyncingHealthKit ? "Syncing historical data" : "Sync all historical data",
                                subtitle: healthSyncStatusMessage,
                                showChevron: false
                            )
                        }
                        .disabled(isSyncingHealthKit)
                        .accessibilityHint("Syncs your historical Apple Health data now.")
                    }
                } else {
                    DataInfoRow(
                        icon: "exclamationmark.triangle",
                        title: "Apple Health isn’t available",
                        description: "This device doesn’t support Apple Health.",
                        iconColor: theme.colors.warning
                    )
                }

                if Constants.isBodySpecEnabled {
                    Divider()

                    NavigationLink(
                        destination: BodySpecIntegrationView()
                            .environmentObject(authManager)
                    ) {
                        SettingsRow(
                            icon: "waveform.path.ecg",
                            title: "BodySpec",
                            subtitle: "DEXA scans",
                            value: bodySpecSyncStatusText,
                            showChevron: true,
                            tintColor: theme.colors.text
                        )
                    }
                    .accessibilityIdentifier("integrations_bodyspec_link")
                }
            }
        }
    }

    private var appleHealthConnectionRow: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "heart.fill")
                .foregroundColor(theme.colors.error)
                .font(theme.typography.headlineSmall)
                .frame(width: 24)

            Text("Apple Health")
                .font(theme.typography.labelLarge)
                .foregroundColor(theme.colors.text)

            Spacer()

            healthConnectionStatus
        }
    }

    private var appleHealthConnectionStack: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundColor(theme.colors.error)
                    .font(theme.typography.headlineSmall)
                    .frame(width: 24)

                Text("Apple Health")
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)
            }

            healthConnectionStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var healthConnectionStatus: some View {
        if healthKitManager.isAuthorized {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.success)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Apple Health connected")
        } else {
            Button {
                Task { @MainActor in
                    await connectAppleHealth()
                }
            } label: {
                HStack(spacing: theme.spacing.xs) {
                    if isConnectingHealthKit {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.jovieActionText)
                    }

                    Text(isConnectingHealthKit ? "Connecting" : "Connect")
                        .font(theme.typography.labelMedium.weight(.semibold))
                }
                .foregroundColor(.jovieActionText)
                .padding(.horizontal, theme.spacing.md)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .background(Color.jovieAction, in: Capsule())
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
                isEnabled: isBulkProgressPhotoImportEnabled,
                existingProgressPhotoCount: progressPhotoCount
            )
        ) {
            if isBulkProgressPhotoImportEnabled {
                NavigationLink(destination: BulkPhotoImportView().environmentObject(authManager)) {
                    SettingsRow(
                        icon: "photo.stack",
                        title: "Import Progress Photos",
                        subtitle: "Choose photos from your library",
                        value: "Scan library",
                        showChevron: true
                    )
                    .accessibilityIdentifier("integrations_bulk_photo_import_link")
                }
            } else {
                SettingsRow(
                    icon: "photo.stack",
                    title: "Import Progress Photos",
                    subtitle: "Add progress photos to unlock",
                    value: "Locked",
                    tintColor: theme.colors.textSecondary
                )
                .accessibilityIdentifier("integrations_bulk_photo_import_locked")
                .accessibilityHint("Add progress photos or request migration access to unlock bulk import.")
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
                    showChevron: true
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

        let authorized = await healthKitManager.requestAuthorization()
        if authorized {
            await HealthSyncCoordinator.shared
                .configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
            healthSyncStatusMessage = "Apple Health sync is set up"
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
        await HealthSyncCoordinator.shared.forceFullHealthKitSync()
        healthSyncStatusMessage = "Historical Apple Health data synced"
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
