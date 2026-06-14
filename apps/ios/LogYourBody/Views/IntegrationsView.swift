//
// IntegrationsView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct IntegrationsView: View {
    @EnvironmentObject var authManager: AuthManager
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
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    healthAndFitnessSection
                    photoImportSection
                    dataExportSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
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
                            .foregroundColor(.red)
                            .font(.system(size: SettingsDesign.iconSize))
                            .frame(width: SettingsDesign.iconFrame)

                        Text("Apple Health")
                            .font(SettingsDesign.titleFont)

                        Spacer()

                        if healthKitManager.isAuthorized {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(SettingsDesign.valueFont)
                                .foregroundColor(.green)
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
                            .font(SettingsDesign.valueFont)
                            .foregroundColor(.appPrimary)
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)

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
                        iconColor: .orange
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
                                .foregroundColor(.blue)
                                .font(.system(size: SettingsDesign.iconSize))
                                .frame(width: SettingsDesign.iconFrame)

                            Text("BodySpec")
                                .font(SettingsDesign.titleFont)

                            Spacer()

                            if isLoadingBodySpecLastSynced {
                                Text("Checking…")
                                    .font(SettingsDesign.valueFont)
                                    .foregroundColor(.appTextSecondary)
                            } else if let bodySpecLastSyncedText {
                                Text(bodySpecLastSyncedText)
                                    .font(SettingsDesign.valueFont)
                                    .foregroundColor(.appTextSecondary)
                            } else {
                                Text("Not synced yet")
                                    .font(SettingsDesign.valueFont)
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)
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
                    tintColor: .appTextSecondary
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
    NavigationView {
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
            let results = try await SupabaseManager.shared.fetchDexaResults(userId: userId, limit: 1)

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
