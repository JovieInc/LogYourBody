import SwiftUI

struct BodySpecIntegrationView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var isConfigured = false
    @State private var isConnected = false
    @State private var connectedEmail: String?
    @State private var isConnecting = false
    @State private var isSyncing = false
    @State private var lastSyncSummary: String?
    @State private var errorMessage: String?
    @State private var recoveryAction: RecoveryAction?
    @State private var isLoadingScans = false
    @State private var recentScans: [DexaResult] = []
    @State private var recentScansError: String?

    private enum RecoveryAction {
        case connect
    }

    var body: some View {
        SettingsDetailScreen(title: "BodySpec") {
            introductionSection
            connectionSection
            syncSection
            recentScansSection

            if let errorMessage {
                errorRecoverySection(message: errorMessage)
            }
        }
        .onAppear {
            Task { @MainActor in
                await handleOnAppear()
            }
        }
    }

    private var introductionSection: some View {
        SettingsSection(header: "About") {
            DataInfoRow(
                icon: "waveform.path.ecg",
                title: "DEXA scan import",
                description: "Connect BodySpec to bring your DEXA scan history into LogYourBody.",
                iconColor: .accentColor
            )
        }
    }

    private var connectionSection: some View {
        SettingsSection(
            header: "Connection",
            footer: isConfigured
                ? "You can disconnect at any time."
                : "BodySpec is not available in this version of the app."
        ) {
            SettingsRow(
                icon: connectionIcon,
                title: connectionTitle,
                subtitle: connectionDescription,
                tintColor: connectionTint
            )

            if isConfigured {
                Button {
                    connectTapped()
                } label: {
                    Label(
                        isConnected ? "Reconnect BodySpec" : "Connect BodySpec",
                        systemImage: "link"
                    )
                }
                .disabled(isConnecting)
                .accessibilityHint("Connects your BodySpec account.")

                if isConnected {
                    Button("Disconnect BodySpec", role: .destructive) {
                        disconnectTapped()
                    }
                    .disabled(isConnecting)
                    .accessibilityHint("Disconnects your BodySpec account from LogYourBody.")
                }
            }
        }
    }

    private var syncSection: some View {
        SettingsSection(
            header: "DEXA sync",
            footer: "New scans are added to your body metrics."
        ) {
            if isConfigured, isConnected {
                Button {
                    syncTapped()
                } label: {
                    if isSyncing {
                        Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Sync DEXA scans", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing)
                .accessibilityHint("Checks BodySpec for new DEXA scans now.")
            } else {
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync unavailable",
                    subtitle: syncUnavailableDescription,
                    tintColor: .secondary
                )
            }

            if let lastSyncSummary {
                DataInfoRow(
                    icon: "checkmark.circle",
                    title: "Sync complete",
                    description: lastSyncSummary,
                    iconColor: Color.appSuccess
                )
            }
        }
    }

    private var recentScansSection: some View {
        SettingsSection(
            header: "Recent scans",
            footer: "Your five most recent BodySpec DEXA scans appear here."
        ) {
            if isLoadingScans {
                DataInfoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading scans",
                    description: "Checking your BodySpec history…",
                    iconColor: .secondary
                )
            } else if let recentScansError {
                DataInfoRow(
                    icon: "exclamationmark.triangle",
                    title: "Couldn’t load scans",
                    description: recentScansError,
                    iconColor: Color.appWarning
                )

                Button {
                    reloadRecentScans()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            } else if recentScans.isEmpty {
                DataInfoRow(
                    icon: "doc.text.magnifyingglass",
                    title: "No DEXA scans yet",
                    description: isConnected
                        ? "New scans from BodySpec will appear here after syncing."
                        : "Connect BodySpec to see your DEXA scan history.",
                    iconColor: .secondary
                )
            } else {
                ForEach(recentScans.prefix(5)) { scan in
                    SettingsRow(
                        icon: "calendar",
                        title: formattedDate(scan.acquireTime),
                        subtitle: scan.locationName?.isEmpty == false ? scan.locationName : "BodySpec DEXA scan"
                    )
                }
            }
        }
    }

    private func errorRecoverySection(message: String) -> some View {
        SettingsSection(header: "Needs attention") {
            DataInfoRow(
                icon: "exclamationmark.triangle",
                title: "BodySpec couldn’t finish",
                description: message,
                iconColor: Color.appError
            )

            if recoveryAction != nil {
                Button {
                    retryLastAction()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var connectionIcon: String {
        if !isConfigured { return "exclamationmark.triangle" }
        return isConnected ? "checkmark.circle.fill" : "link"
    }

    private var connectionTint: Color {
        if !isConfigured { return Color.appWarning }
        return isConnected ? Color.appSuccess : .secondary
    }

    private var connectionTitle: String {
        if !isConfigured { return "BodySpec isn’t available" }
        return isConnected ? "Connected" : "Not connected"
    }

    private var connectionDescription: String {
        if !isConfigured {
            return "This build can’t connect to BodySpec."
        }
        return connectedEmail ?? (isConnected
            ? "Your BodySpec account is ready to sync."
            : "Connect your account to import DEXA scans.")
    }

    private var syncUnavailableDescription: String {
        if !isConfigured {
            return "BodySpec isn’t available in this build."
        }
        return "Connect BodySpec before syncing your scans."
    }

    @MainActor
    private func handleOnAppear() async {
        refreshConnectionState()
        await loadRecentScansIfNeeded()
    }

    private func refreshConnectionState() {
        let manager = BodySpecAuthManager.shared
        isConfigured = manager.isConfigured
        isConnected = manager.isConnected
        connectedEmail = manager.connectedEmail
    }

    @MainActor
    private func loadRecentScansIfNeeded() async {
        guard isConfigured,
              isConnected,
              let userId = authManager.currentUser?.id else {
            recentScans = []
            recentScansError = nil
            return
        }

        isLoadingScans = true
        recentScansError = nil

        let cached = await CoreDataManager.shared.fetchDexaResults(for: userId, limit: 10)
        if !cached.isEmpty {
            recentScans = cached
        }

        do {
            let scans = try await AppServicePorts.dexaResultRemoteDataProvider.fetchDexaResults(userId: userId, limit: 10)
            recentScans = scans
            CoreDataManager.shared.saveDexaResults(scans, userId: userId)
        } catch {
            if recentScans.isEmpty {
                recentScansError = "Check your connection and try again."
            }
        }

        isLoadingScans = false
    }

    private func reloadRecentScans() {
        Task { @MainActor in
            await loadRecentScansIfNeeded()
        }
    }

    private func connectTapped() {
        errorMessage = nil
        recoveryAction = nil
        isConnecting = true

        Task { @MainActor in
            do {
                try await BodySpecAuthManager.shared.connect()
                refreshConnectionState()
                await loadRecentScansIfNeeded()
            } catch {
                errorMessage = "We couldn’t connect BodySpec. Check your connection and try again."
                recoveryAction = .connect
            }

            isConnecting = false
        }
    }

    private func disconnectTapped() {
        errorMessage = nil
        recoveryAction = nil

        Task { @MainActor in
            BodySpecAuthManager.shared.disconnect()
            refreshConnectionState()
            await loadRecentScansIfNeeded()
        }
    }

    private func syncTapped() {
        guard isConfigured else {
            errorMessage = "BodySpec isn’t available in this build."
            recoveryAction = nil
            return
        }

        guard isConnected else {
            errorMessage = "Connect BodySpec before syncing your scans."
            recoveryAction = .connect
            return
        }

        errorMessage = nil
        recoveryAction = nil
        lastSyncSummary = nil
        isSyncing = true

        Task { @MainActor in
            let result = await BodySpecDexaImporter.shared.importDexaResults()
            isSyncing = false
            lastSyncSummary = syncSummary(for: result)
            await loadRecentScansIfNeeded()
        }
    }

    private func retryLastAction() {
        switch recoveryAction {
        case .connect:
            connectTapped()
        case nil:
            break
        }
    }

    private func syncSummary(for result: BodySpecDexaImporter.ImportResult) -> String {
        if result.importedCount == 0, result.skippedCount == 0 {
            return "No new DEXA scans found."
        }

        let importedUnit = result.importedCount == 1 ? "scan" : "scans"
        let skippedUnit = result.skippedCount == 1 ? "scan" : "scans"
        return "Imported \(result.importedCount) new \(importedUnit) and skipped \(result.skippedCount) \(skippedUnit)."
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown date"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        BodySpecIntegrationView()
            .environmentObject(AuthManager.shared)
    }
}
