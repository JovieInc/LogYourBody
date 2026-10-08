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
    @State private var bodySpecHistoryFailed = false
    @State private var historyRefreshVersion = 0
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
        .alert(isDirectoryEnabled ? "Apple Health access" : "Apple Health access is needed", isPresented: $showHealthKitConnect) {
            if !isDirectoryEnabled {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(isDirectoryEnabled ? "Done" : "Not Now", role: .cancel) {}
        } message: {
            Text(isDirectoryEnabled
                ? "Review LogYourBody’s data access in the Health app on your iPhone or iPad."
                : "Allow Health access in Settings to sync weight and body-composition data.")
        }
        .task(id: "\(authManager.currentUser?.id ?? ""):\(historyRefreshVersion)") {
            healthKitManager.checkAuthorizationStatus()
            loadBulkPhotoImportActivationEvidence()
            await loadBodySpecLastSynced()
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
            featureGateRefreshToken = UUID()
        }
        .worldClassScreen(.integrations)
    }

    private var healthAndFitnessSection: some View {
        SettingsSection(
            header: isDirectoryEnabled ? "Connections" : "Health & Fitness",
            footer: "Control data connections and sync."
        ) {
            if isDirectoryEnabled {
                SettingsRow(
                    icon: "heart.fill",
                    title: ProductRegistry.Integrations.appleHealth.label,
                    subtitle: appleHealthPresentation.detail,
                    value: appleHealthPresentation.status
                )
                .accessibilityIdentifier("integrations_health_status")
            }
            if healthKitManager.isHealthKitAvailable {
                if !isDirectoryEnabled {
                    ViewThatFits(in: .horizontal) {
                        appleHealthConnectionRow
                        appleHealthConnectionStack
                    }
                } else if !healthKitManager.isAuthorized {
                    Button(isConnectingHealthKit ? "Requesting access…" : "Set up Apple Health") {
                        Task { @MainActor in await connectAppleHealth() }
                    }
                    .disabled(isConnectingHealthKit)
                    .accessibilityIdentifier("integrations_health_connect")
                }

                if healthKitManager.isAuthorized {
                    if isDirectoryEnabled {
                        DisclosureGroup("Sync and access") { healthSyncControls }
                            .accessibilityIdentifier("integrations_health_options")
                    } else {
                        healthSyncControls
                    }
                }
            } else if !isDirectoryEnabled {
                DataInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Apple Health isn’t available",
                    description: "This device doesn’t support Apple Health.",
                    iconColor: Color.appWarning
                )
            }

            if Constants.isBodySpecEnabled {
                NavigationLink(
                    destination: BodySpecIntegrationView()
                        .environmentObject(authManager)
                ) {
                    SettingsRow(
                        icon: "waveform.path.ecg",
                        title: isDirectoryEnabled ? ProductRegistry.Integrations.bodyspec.label : "BodySpec",
                        subtitle: isDirectoryEnabled ? bodySpecDirectoryDetail : "DEXA scans",
                        value: isDirectoryEnabled ? bodySpecConnectionStatus : bodySpecSyncStatusText,
                        showChevron: false
                    )
                }
                .accessibilityIdentifier("integrations_bodyspec_link")
                if isDirectoryEnabled, bodySpecHistoryFailed {
                    Button("Refresh scan history") { historyRefreshVersion += 1 }
                        .disabled(isLoadingBodySpecLastSynced)
                        .accessibilityIdentifier("integrations_bodyspec_refresh")
                }
            }
        }
    }

    private var healthSyncControls: some View {
        Group {
            if isDirectoryEnabled {
                Button("Manage Apple Health access") { showHealthKitConnect = true }
                    .accessibilityIdentifier("integrations_health_manage_access")
            }
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
                    subtitleColor: healthSyncStatusIsError ? Color.appError : nil,
                    showChevron: false
                )
            }
            .foregroundStyle(.primary)
            .disabled(isSyncingHealthKit)
            .accessibilityHint("Syncs your historical Apple Health data now.")
            .accessibilityIdentifier("integrations_health_sync_all_button")
        }
    }

    private var appleHealthConnectionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.appError)
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
                    .foregroundStyle(Color.appError)
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
                .foregroundStyle(Color.appSuccess)
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
    private var isDirectoryEnabled: Bool {
        _ = featureGateRefreshToken
        return IntegrationStatusPolicy.isEnabled(arguments: ProcessInfo.processInfo.arguments) {
            AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0)
        }
    }

    private var appleHealthPresentation: IntegrationStatusPolicy.HealthPresentation {
        IntegrationStatusPolicy.health(
            available: healthKitManager.isHealthKitAvailable,
            onMac: ProcessInfo.processInfo.isiOSAppOnMac,
            requestCompleted: healthKitManager.isAuthorized,
            syncEnabled: healthKitSyncEnabled
        )
    }

    private var bodySpecConnectionStatus: String {
        IntegrationStatusPolicy.bodySpecConnection(
            configured: BodySpecAuthManager.shared.isConfigured,
            connected: BodySpecAuthManager.shared.isConnected
        )
    }

    private var bodySpecDirectoryDetail: String {
        var lines = [ProductRegistry.Integrations.bodyspec.description]
        if BodySpecAuthManager.shared.isConnected { lines.append("Connection saved on this device") }
        lines.append(bodySpecSyncStatusText)
        if bodySpecHistoryFailed { lines.append("Couldn’t refresh scan history.") }
        return lines.joined(separator: "\n")
    }

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
            healthSyncStatusMessage = isDirectoryEnabled ? "Permission request finished" : "Apple Health sync is on"
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
            ? (isDirectoryEnabled ? "Sync request finished" : "Historical Apple Health data synced")
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
            bodySpecHistoryFailed = false
            return
        }

        isLoadingBodySpecLastSynced = true
        bodySpecHistoryFailed = false
        bodySpecLastSyncedText = nil

        let cachedResults = await CoreDataManager.shared.fetchDexaResults(for: userId, limit: isDirectoryEnabled ? 100 : 1)
        guard IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: userId, currentUserId: authManager.currentUser?.id, cancelled: Task.isCancelled
        ) else { return }
        let cached = isDirectoryEnabled ? IntegrationStatusPolicy.bodySpecHistory(cachedResults) : cachedResults
        if let latest = cached.first {
            let date = IntegrationStatusPolicy.scanDate(latest, directoryEnabled: isDirectoryEnabled)
            bodySpecLastSyncedText = formatBodySpecLastSynced(date: date)
        } else {
            bodySpecLastSyncedText = isDirectoryEnabled ? "No cached scans" : "Not synced yet"
        }

        do {
            let fetched = try await AppServicePorts.dexaResultRemoteDataProvider.fetchDexaResults(
                userId: userId, limit: isDirectoryEnabled ? 100 : 1
            )
            guard IntegrationStatusPolicy.mayApplyHistory(
                requestedUserId: userId, currentUserId: authManager.currentUser?.id, cancelled: Task.isCancelled
            ) else { return }
            let results = isDirectoryEnabled ? IntegrationStatusPolicy.bodySpecHistory(fetched) : fetched

            if let latest = results.first {
                let date = IntegrationStatusPolicy.scanDate(latest, directoryEnabled: isDirectoryEnabled)
                bodySpecLastSyncedText = formatBodySpecLastSynced(date: date)
            } else if !isDirectoryEnabled || cached.isEmpty {
                bodySpecLastSyncedText = isDirectoryEnabled ? "No scans in recent history" : "Not synced yet"
            }

            CoreDataManager.shared.saveDexaResults(fetched, userId: userId)
        } catch {
            guard authManager.currentUser?.id == userId, !Task.isCancelled else { return }
            bodySpecHistoryFailed = true
        }

        isLoadingBodySpecLastSynced = false
    }

    private func formatBodySpecLastSynced(date: Date?) -> String {
        guard let date else {
            return isDirectoryEnabled ? "Scan date unavailable" : "Not synced yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return isDirectoryEnabled ? "Latest scan · \(relative)" : "Last synced · \(relative)"
    }
}

enum IntegrationStatusPolicy {
    static let gateKey = "lyb_integrations_directory_v1"

    static func isEnabled(arguments: [String], checkGate: (String) -> Bool) -> Bool {
        #if DEBUG
        if arguments.contains("-lybUITestIntegrationsDirectoryFixture") { return true }
        #endif
        return checkGate(gateKey)
    }

    struct HealthPresentation: Equatable {
        let status: String
        let detail: String
    }

    static func health(available: Bool, onMac: Bool, requestCompleted: Bool, syncEnabled: Bool) -> HealthPresentation {
        guard available else {
            return HealthPresentation(
                status: onMac ? "Use on iPhone" : "Unavailable",
                detail: "Set up Apple Health in LogYourBody on a supported iPhone or iPad."
            )
        }
        return HealthPresentation(
            status: requestCompleted ? (syncEnabled ? "Sync enabled" : "Sync paused") : "Set up access",
            detail: "\(ProductRegistry.Integrations.appleHealth.description) Apple Health controls which data is shared."
        )
    }

    static func bodySpecConnection(configured: Bool, connected: Bool) -> String {
        guard configured else { return "Unavailable" }
        return connected ? "Connected" : "Not connected"
    }

    static func bodySpecHistory(_ results: [DexaResult]) -> [DexaResult] {
        results.filter { $0.externalSource.lowercased() == "bodyspec" }
            .sorted { ($0.acquireTime ?? .distantPast) > ($1.acquireTime ?? .distantPast) }
    }

    static func scanDate(_ result: DexaResult, directoryEnabled: Bool) -> Date? {
        directoryEnabled ? result.acquireTime : (result.acquireTime ?? result.updatedAt)
    }

    static func mayApplyHistory(requestedUserId: String, currentUserId: String?, cancelled: Bool) -> Bool {
        !cancelled && !requestedUserId.isEmpty && requestedUserId == currentUserId
    }
}
