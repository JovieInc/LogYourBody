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

    @State private var isLoadingScans = false
    @State private var recentScans: [DexaResult] = []
    @State private var recentScansError: String?

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    connectionSection
                    syncSection
                    recentScansSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("BodySpec")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { @MainActor in
                await handleOnAppear()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BodySpec DEXA")
                .font(.title3.weight(.semibold))
                .foregroundColor(.appText)

            Text("Connect your BodySpec account to import DEXA scans into LogYourBody. This feature is currently in early internal testing.")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.headline)
                .foregroundColor(.appText)

            VStack(alignment: .leading, spacing: 8) {
                if !isConfigured {
                    Text("BodySpec is not configured for this build.")
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                } else if isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.appText)

                            if let connectedEmail {
                                Text(connectedEmail)
                                    .font(.footnote)
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("Not connected")
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: connectTapped) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }

                            Text(isConnected ? "Reconnect" : "Connect BodySpec")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appPrimary)
                    .disabled(!isConfigured || isConnecting)

                    if isConnected {
                        Button(role: .destructive, action: disconnectTapped) {
                            Text("Disconnect")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isConnecting)
                    }
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(16)
        }
    }

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Scans")
                .font(.headline)
                .foregroundColor(.appText)

            VStack(alignment: .leading, spacing: 8) {
                if isLoadingScans {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)

                        Text("Loading scans...")
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)
                    }
                } else if let recentScansError {
                    Text(recentScansError)
                        .font(.footnote)
                        .foregroundColor(.appTextSecondary)
                } else if recentScans.isEmpty {
                    Text("No DEXA scans found yet.")
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                } else {
                    ForEach(recentScans.prefix(5)) { scan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedDate(scan.acquireTime))
                                .font(.subheadline)
                                .foregroundColor(.appText)

                            if let location = scan.locationName, !location.isEmpty {
                                Text(location)
                                    .font(.footnote)
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(16)
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEXA Sync")
                .font(.headline)
                .foregroundColor(.appText)

            VStack(alignment: .leading, spacing: 8) {
                Text("Manually import your DEXA scans from BodySpec. New scans will be added as body metrics and linked to your account.")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)

                Button(action: syncTapped) {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }

                        Text("Sync DEXA Scans")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isConfigured || !isConnected || isSyncing)

                if let lastSyncSummary {
                    Text(lastSyncSummary)
                        .font(.footnote)
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(16)
            .background(Color.appCard)
            .cornerRadius(16)
        }
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

        do {
            let scans = try await SupabaseManager.shared.fetchDexaResults(userId: userId, limit: 10)
            recentScans = scans
        } catch {
            recentScans = []
            recentScansError = "Unable to load recent scans."
        }

        isLoadingScans = false
    }

    private func connectTapped() {
        errorMessage = nil
        isConnecting = true

        Task { @MainActor in
            do {
                try await BodySpecAuthManager.shared.connect()
                refreshConnectionState()
                await loadRecentScansIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }

            isConnecting = false
        }
    }

    private func disconnectTapped() {
        errorMessage = nil

        Task { @MainActor in
            BodySpecAuthManager.shared.disconnect()
            refreshConnectionState()
            await loadRecentScansIfNeeded()
        }
    }

    private func syncTapped() {
        guard isConfigured else {
            errorMessage = "BodySpec is not configured for this build."
            return
        }

        guard isConnected else {
            errorMessage = "Connect your BodySpec account before syncing."
            return
        }

        errorMessage = nil
        lastSyncSummary = nil
        isSyncing = true

        Task { @MainActor in
            let result = await BodySpecDexaImporter.shared.importDexaResults()

            isSyncing = false

            if result.importedCount == 0 && result.skippedCount == 0 {
                lastSyncSummary = "No new DEXA scans found."
            } else {
                lastSyncSummary = "Imported \(result.importedCount) new scan(s), skipped \(result.skippedCount)."
            }

            await loadRecentScansIfNeeded()
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
}

#Preview {
    NavigationView {
        BodySpecIntegrationView()
            .environmentObject(AuthManager.shared)
    }
}
