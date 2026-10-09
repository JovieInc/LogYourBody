import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isSelectingPDF = false
    @State private var selectedPDF: DexaPDFFileSelection?

    private enum RecoveryAction {
        case connect
    }

    var body: some View {
        SettingsDetailScreen(title: "DEXA and InBody") {
            introductionSection
            pdfImportSection
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
                errorMessage = "Choose a readable DEXA or InBody PDF and try again."
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

    #if DEBUG
    private static let fixturePDF = """
    %PDF-1.1
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj
    trailer<</Root 1 0 R>>
    %%EOF
    """

    private static func fixturePDFURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyb-ui-dexa-fixture.pdf")
        if !FileManager.default.fileExists(atPath: url.path) {
            let bytes = Data(Self.fixturePDF.utf8)
            try? bytes.write(to: url, options: .atomic)
        }
        return url
    }
    #endif

    private var pdfImportSection: some View {
        SettingsSection(
            header: "Import from PDF",
            footer: "Choose a report from Files or use the iOS share sheet to open a PDF in LogYourBody."
        ) {
            Button {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-lybUITestDexaPDFSheetFixture") {
                    selectedPDF = DexaPDFFileSelection(url: Self.fixturePDFURL())
                } else {
                    isSelectingPDF = true
                }
                #else
                isSelectingPDF = true
                #endif
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
            footer: "Your five most recent DEXA and InBody scans appear here."
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
                        ? "New scans appear here after syncing or importing a PDF."
                        : "Import a DEXA or InBody PDF to start your scan history.",
                    iconColor: .secondary
                )
            } else {
                ForEach(recentScans.prefix(5)) { scan in
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
        if !isConfigured { return "Direct sync isn’t configured" }
        return isConnected ? "Connected" : "Not connected"
    }

    private var connectionDescription: String {
        if !isConfigured {
            return "PDF import works without a BodySpec account connection."
        }
        return connectedEmail ?? (isConnected
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
        isConnected = manager.isConnected
        connectedEmail = manager.connectedEmail
    }

    @MainActor
    private func loadRecentScansIfNeeded() async {
        guard let userId = authManager.currentUser?.id else {
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
