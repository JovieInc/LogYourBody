//
// IntegrationsView.swift
// LogYourBody
//
import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @State private var showHealthKitConnect = false
    @State private var bodySpecLastSyncedText: String?
    @State private var isLoadingBodySpecLastSynced = false
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
                    developerAccessSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHealthKitConnect) {
            // HealthKit authorization handled inline
            Text("")
                .onAppear {
                    Task {
                        _ = await healthKitManager.requestAuthorization()
                        showHealthKitConnect = false
                    }
                }
        }
        .onAppear {
            // Check HealthKit authorization status
            healthKitManager.checkAuthorizationStatus()

            Task { @MainActor in
                await loadBodySpecLastSynced()
            }
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
                                    if !authorized {
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
                                        await HealthSyncCoordinator.shared.configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync()
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

                Divider()

                // Google Fit (Coming Soon)
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundColor(.green)
                        .font(.system(size: SettingsDesign.iconSize))
                        .frame(width: SettingsDesign.iconFrame)

                    Text("Google Fit")
                        .font(SettingsDesign.titleFont)

                    Spacer()

                    Text("Coming Soon")
                        .font(SettingsDesign.valueFont)
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, SettingsDesign.horizontalPadding)
                .padding(.vertical, SettingsDesign.verticalPadding)
                .opacity(0.6)

                Divider()

                if Constants.isBodySpecEnabled {
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
                } else {
                    // BodySpec (Coming Soon)
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.blue)
                            .font(.system(size: SettingsDesign.iconSize))
                            .frame(width: SettingsDesign.iconFrame)

                        Text("BodySpec")
                            .font(SettingsDesign.titleFont)

                        Spacer()

                        Text("Coming Soon")
                            .font(SettingsDesign.valueFont)
                            .foregroundColor(.appTextSecondary)
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)
                    .opacity(0.6)
                }
            }
        }
    }

    private var photoImportSection: some View {
        SettingsSection(
            header: "Photo Import",
            footer: "Import progress photos from your photo library"
        ) {
            NavigationLink(destination: BulkPhotoImportView().environmentObject(authManager)) {
                SettingsRow(
                    icon: "photo.stack",
                    title: "Import Progress Photos",
                    value: "Scan library",
                    showChevron: true
                )
            }
        }
    }

    private var dataExportSection: some View {
        SettingsSection(
            header: "Data Export",
            footer: "Export your data to other platforms"
        ) {
            VStack(spacing: 0) {
                // CSV Export
                NavigationLink(destination: ExportDataView()) {
                    SettingsRow(
                        icon: "doc.text",
                        title: "Export as CSV",
                        showChevron: true
                    )
                }

                Divider()

                // JSON Export (Coming Soon)
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                        .foregroundColor(.appTextSecondary)
                        .font(.system(size: SettingsDesign.iconSize))
                        .frame(width: SettingsDesign.iconFrame)

                    Text("Export as JSON")
                        .font(SettingsDesign.titleFont)

                    Spacer()

                    Text("Coming Soon")
                        .font(SettingsDesign.valueFont)
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, SettingsDesign.horizontalPadding)
                .padding(.vertical, SettingsDesign.verticalPadding)
                .opacity(0.6)
            }
        }
    }

    private var developerAccessSection: some View {
        SettingsSection(
            header: "Developer Access",
            footer: "API access for third-party developers will be available in the future"
        ) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.appTextSecondary)
                    .font(.system(size: SettingsDesign.iconSize))
                    .frame(width: SettingsDesign.iconFrame)

                Text("API Access")
                    .font(SettingsDesign.titleFont)

                Spacer()

                Text("Coming Soon")
                    .font(SettingsDesign.valueFont)
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, SettingsDesign.horizontalPadding)
            .padding(.vertical, SettingsDesign.verticalPadding)
            .opacity(0.6)
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
