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
    @State private var bodySpecLastSyncedText: String?
    @State private var isLoadingBodySpecLastSynced = false
    @State private var progressPhotoCount = 0
    @State private var featureGateRefreshToken = UUID()
    @Environment(\.dismiss)

    var dismiss
    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

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
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Apple Health Permission Needed", isPresented: $showHealthKitConnect) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Enable Apple Health access in Settings to sync weight and body-composition data.")
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
            footer: "Connect your favorite health apps to sync data automatically"
        ) {
            VStack(spacing: 0) {
                // Apple Health
                if healthKitManager.isHealthKitAvailable {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(theme.colors.error)
                            .font(theme.typography.headlineSmall)
                            .frame(width: 24)

                        Text("Apple Health")
                            .font(theme.typography.labelLarge)
                            .foregroundColor(theme.colors.text)

                        Spacer()

                        if healthKitManager.isAuthorized {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.success)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Connect") {
                                Task {
                                    let authorized = await healthKitManager.requestAuthorization()
                                    if authorized {
                                        await HealthSyncCoordinator.shared
                                            .configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
                                    } else {
                                        showHealthKitConnect = true
                                    }
                                }
                            }
                            .font(theme.typography.captionLarge)
                            .foregroundColor(theme.colors.primary)
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)

                    if healthKitManager.isAuthorized {
                        Divider()

                        // Enable Sync Toggle
                        SettingsToggleRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Enable Sync",
                            isOn: $healthKitSyncEnabled
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

                        // Manual Sync Button
                        SettingsButtonRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Sync All Historical Data",
                            action: {
                                Task {
                                    await HealthSyncCoordinator.shared.forceFullHealthKitSync()
                                }
                            }
                        )
                    }
                } else {
                    // HealthKit Not Available
                    DataInfoRow(
                        icon: "exclamationmark.triangle",
                        title: "Apple Health Not Available",
                        description: "Apple Health is not available on this device",
                        iconColor: theme.colors.warning
                    )
                }

                if Constants.isBodySpecEnabled {
                    Divider()

                    NavigationLink(
                        destination: BodySpecIntegrationView()
                            .environmentObject(authManager)
                    ) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(theme.colors.info)
                                .font(theme.typography.headlineSmall)
                                .frame(width: 24)

                            Text("BodySpec")
                                .font(theme.typography.labelLarge)
                                .foregroundColor(theme.colors.text)

                            Spacer()

                            if isLoadingBodySpecLastSynced {
                                Text("Checking…")
                                    .font(theme.typography.captionLarge)
                                    .foregroundColor(theme.colors.textSecondary)
                            } else if let bodySpecLastSyncedText {
                                Text(bodySpecLastSyncedText)
                                    .font(theme.typography.captionLarge)
                                    .foregroundColor(theme.colors.textSecondary)
                            } else {
                                Text("Not synced yet")
                                    .font(theme.typography.captionLarge)
                                    .foregroundColor(theme.colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
                }
            }
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
                        value: "Scan library",
                        showChevron: true
                    )
                    .accessibilityIdentifier("integrations_bulk_photo_import_link")
                }
            } else {
                SettingsRow(
                    icon: "photo.stack",
                    title: "Import Progress Photos",
                    value: "Locked",
                    tintColor: theme.colors.textSecondary
                )
                .opacity(0.6)
                .accessibilityIdentifier("integrations_bulk_photo_import_locked")
            }
        }
    }

    private var dataExportSection: some View {
        SettingsSection(
            header: "Data Export",
            footer: "Export your data in available formats"
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
