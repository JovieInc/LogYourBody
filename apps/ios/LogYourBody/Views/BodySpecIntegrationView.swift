import SwiftUI
import UniformTypeIdentifiers

struct BodySpecIntegrationView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var isConfigured = false
    @State private var sessionState = BodySpecIntegrationState()
    @State private var isSelectingPDF = false
    @State private var selectedPDF: DexaPDFFileSelection?

    var body: some View {
        SettingsDetailScreen(title: "DEXA and InBody") {
            introductionSection
            pdfImportSection
            connectionSection
            syncSection
            recentScansSection

            if let errorMessage = sessionState.errorMessage {
                errorRecoverySection(message: errorMessage)
            }
        }
        .task(id: authManager.captureAccountSession()) { @MainActor in
            sessionState.reset(for: authManager.captureAccountSession())
            selectedPDF = nil
            isSelectingPDF = false
            await handleOnAppear()
        }
        .fileImporter(
            isPresented: $isSelectingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedPDF = DexaPDFFileSelection(url: url)
                }
            case .failure:
                sessionState.errorMessage = "Choose a readable DEXA or InBody PDF and try again."
            }
        }
        .sheet(item: $selectedPDF, onDismiss: reloadRecentScans) { selection in
            DexaPDFImportSheet(fileURL: selection.url)
                .environmentObject(authManager)
        }
    }

    private var introductionSection: some View {
        SettingsSection(header: "About") {
            DataInfoRow(
                icon: "waveform.path.ecg",
                title: "DEXA scan import",
                description: "Import DEXA or InBody reports and keep your dated scan history together.",
                iconColor: .accentColor
            )
        }
    }

    private var pdfImportSection: some View {
        SettingsSection(
            header: "Import from PDF",
            footer: "Choose a report from Files or use the iOS share sheet to open a PDF in LogYourBody."
        ) {
            Button {
                isSelectingPDF = true
            } label: {
                Label("Import DEXA or InBody PDF", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("body_spec_pdf_import")
            .accessibilityHint("Choose a scan report PDF to add its dated measurements to your timeline.")
        }
    }

    private var connectionSection: some View {
        SettingsSection(
            header: "Optional BodySpec sync",
            footer: isConfigured
                ? "You can disconnect at any time."
                : "Direct BodySpec account sync is not configured in this build. PDF import is available above."
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
                        sessionState.isConnected ? "Reconnect BodySpec" : "Connect BodySpec",
                        systemImage: "link"
                    )
                }
                .disabled(sessionState.isConnecting)
                .accessibilityHint("Connects your BodySpec account.")

                if sessionState.isConnected {
                    Button("Disconnect BodySpec", role: .destructive) {
                        disconnectTapped()
                    }
                    .disabled(sessionState.isConnecting)
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
            if isConfigured, sessionState.isConnected {
                Button {
                    syncTapped()
                } label: {
                    if sessionState.isSyncing {
                        Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Sync DEXA scans", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(sessionState.isSyncing)
                .accessibilityHint("Checks BodySpec for new DEXA scans now.")
            } else {
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync unavailable",
                    subtitle: syncUnavailableDescription,
                    tintColor: .secondary
                )
            }

            if let lastSyncSummary = sessionState.lastSyncSummary {
                DataInfoRow(
                    icon: sessionState.lastSyncFailed ? "exclamationmark.triangle" : "checkmark.circle",
                    title: sessionState.lastSyncFailed ? "Sync incomplete" : "Sync complete",
                    description: lastSyncSummary,
                    iconColor: sessionState.lastSyncFailed ? Color.appWarning : Color.appSuccess
                )
            }
        }
    }

    private var recentScansSection: some View {
        SettingsSection(
            header: "Recent scans",
            footer: "Your five most recent DEXA and InBody scans appear here."
        ) {
            if sessionState.isLoadingScans {
                DataInfoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading scans",
                    description: "Checking your BodySpec history…",
                    iconColor: .secondary
                )
            } else if let recentScansError = sessionState.recentScansError {
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
            } else if sessionState.recentScans.isEmpty {
                DataInfoRow(
                    icon: "doc.text.magnifyingglass",
                    title: "No DEXA scans yet",
                    description: sessionState.isConnected
                        ? "New scans appear here after syncing or importing a PDF."
                        : "Import a DEXA or InBody PDF to start your scan history.",
                    iconColor: .secondary
                )
            } else {
                ForEach(sessionState.recentScans.prefix(5)) { scan in
                    SettingsRow(
                        icon: "calendar",
                        title: formattedDate(scan.acquireTime),
                        subtitle: scanSummary(scan)
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

            if sessionState.recoveryAction != nil {
                Button {
                    retryLastAction()
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var connectionIcon: String {
        if !isConfigured || sessionState.recoveryAction == .disconnect { return "exclamationmark.triangle" }
        return sessionState.isConnected ? "checkmark.circle.fill" : "link"
    }

    private var connectionTint: Color {
        if !isConfigured || sessionState.recoveryAction == .disconnect { return Color.appWarning }
        return sessionState.isConnected ? Color.appSuccess : .secondary
    }

    private var connectionTitle: String {
        if !isConfigured { return "Direct sync isn’t configured" }
        if sessionState.recoveryAction == .disconnect { return "Disconnect incomplete" }
        return sessionState.isConnected ? "Connected" : "Not connected"
    }

    private var connectionDescription: String {
        if !isConfigured {
            return "PDF import works without a BodySpec account connection."
        }
        return sessionState.connectedEmail ?? (sessionState.isConnected
            ? "Your BodySpec account is ready to sync."
            : "Connect your account to sync DEXA scans automatically.")
    }

    private var syncUnavailableDescription: String {
        if !isConfigured {
            return "Import a DEXA or InBody PDF instead."
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
        sessionState.isConnected = manager.isConnected
        sessionState.connectedEmail = manager.connectedEmail
    }

    @MainActor
    private func loadRecentScansIfNeeded() async {
        guard let ownership = authManager.captureAccountSession() else {
            sessionState.recentScans = []
            sessionState.recentScansError = nil
            return
        }

        let userId = ownership.subject
        let operationID = sessionState.operationID
        sessionState.isLoadingScans = true
        sessionState.recentScansError = nil

        let cached = await CoreDataManager.shared.fetchDexaResults(for: userId, limit: 10)
        guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
        if !cached.isEmpty {
            sessionState.recentScans = cached
        }

        do {
            let scans = try await AppServicePorts.dexaResultRemoteDataProvider.fetchDexaResults(userId: userId, limit: 10)
            guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
            sessionState.recentScans = scans
            CoreDataManager.shared.saveDexaResults(scans, userId: userId)
        } catch {
            guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
            if sessionState.recentScans.isEmpty {
                sessionState.recentScansError = "Check your connection and try again."
            }
        }

        sessionState.isLoadingScans = false
    }

    private func reloadRecentScans() {
        Task { @MainActor in
            await loadRecentScansIfNeeded()
        }
    }

    private func connectTapped() {
        guard let ownership = authManager.captureAccountSession() else { return }
        let operationID = sessionState.replaceConnectionOperation()
        sessionState.errorMessage = nil
        sessionState.recoveryAction = nil
        sessionState.isConnecting = true
        sessionState.isConnected = false
        sessionState.connectedEmail = nil

        Task { @MainActor in
            do {
                try await BodySpecAuthManager.shared.connect()
                guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
                refreshConnectionState()
                await loadRecentScansIfNeeded()
            } catch {
                guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
                refreshConnectionState()
                sessionState.errorMessage = "We couldn’t connect BodySpec. Check your connection and try again."
                sessionState.recoveryAction = .connect
            }
            guard sessionState.operationID == operationID else { return }
            sessionState.isConnecting = false
        }
    }

    private func disconnectTapped() {
        _ = sessionState.replaceConnectionOperation()
        sessionState.errorMessage = nil
        sessionState.recoveryAction = nil
        do {
            try BodySpecAuthManager.shared.disconnect()
        } catch {
            sessionState.disconnectFailed()
        }
        refreshConnectionState()
    }

    private func syncTapped() {
        guard isConfigured else {
            sessionState.errorMessage = "BodySpec isn’t available in this build."
            sessionState.recoveryAction = nil
            return
        }

        guard sessionState.isConnected else {
            sessionState.errorMessage = "Connect BodySpec before syncing your scans."
            sessionState.recoveryAction = .connect
            return
        }

        guard let ownership = authManager.captureAccountSession() else { return }
        let operationID = sessionState.operationID
        sessionState.errorMessage = nil
        sessionState.recoveryAction = nil
        sessionState.lastSyncSummary = nil
        sessionState.isSyncing = true

        Task { @MainActor in
            let result = await BodySpecDexaImporter.shared.importDexaResults()
            guard sessionState.owns(operationID, account: ownership),
                      authManager.ownsAccountSession(ownership) else { return }
            sessionState.isSyncing = false
            sessionState.lastSyncSummary = result.summary
            sessionState.lastSyncFailed = result.failedCount > 0 || result.wasCancelled
            await loadRecentScansIfNeeded()
        }
    }

    private func retryLastAction() {
        switch sessionState.recoveryAction {
        case .connect:
            connectTapped()
        case .disconnect:
            disconnectTapped()
        case nil:
            break
        }
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

    private func scanSummary(_ scan: DexaResult) -> String {
        var details = [scan.externalSource.replacingOccurrences(of: "_", with: " ").capitalized]
        if let bodyFat = scan.bodyFatPercentage {
            details.append("\(bodyFat.formatted(.number.precision(.fractionLength(0...1))))% body fat")
        }
        if let muscleMass = scan.muscleMass {
            details.append("\(muscleMass.formatted(.number.precision(.fractionLength(0...1)))) muscle mass")
        }
        return details.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        BodySpecIntegrationView()
            .environmentObject(AuthManager.shared)
    }
}
