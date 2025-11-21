import SwiftUI

struct SyncBannerState {
    enum Style {
        case success
        case error
    }

    let style: Style
    let detail: String?
}

struct DashboardSyncBanner: View {
    let banner: SyncBannerState?
    let onRetry: () -> Void

    var body: some View {
        if let banner {
            content(for: banner)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func content(for banner: SyncBannerState) -> some View {
        let card = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: banner.style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(banner.style == .error ? "Sync failed. Tap to retry." : "Back in sync")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)

            if let detail = banner.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.9))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerBackground(for: banner.style))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(12)

        if banner.style == .error {
            Button(action: onRetry) {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    private func bannerBackground(for style: SyncBannerState.Style) -> LinearGradient {
        switch style {
        case .error:
            return LinearGradient(
                colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .success:
            return LinearGradient(
                colors: [Color.green.opacity(0.85), Color.green.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct DashboardSyncDetailsSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var syncManager: RealtimeSyncManager
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    var body: some View {
        NavigationStack {
            List {
                statusSection

                unsyncedSection

                healthKitSection

                if let error = syncManager.error, !error.isEmpty {
                    Section(header: Text("Last Error")) {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Sync Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Retry") {
                        syncManager.syncAll()
                    }
                    .disabled(!syncManager.isOnline)
                }
            }
        }
    }

    private var statusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                Text("State")
                Spacer()
                Text(statusText)
                    .foregroundColor(.secondary)
            }

            if let last = syncManager.lastSyncDate {
                HStack {
                    Text("Last Sync")
                    Spacer()
                    Text(last.formatted(.dateTime.hour().minute().day().month().year()))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Pending Changes")
                Spacer()
                Text("\(syncManager.pendingSyncCount)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var unsyncedSection: some View {
        Section(header: Text("Unsynced Data")) {
            HStack {
                Text("Body Metrics")
                Spacer()
                Text("\(syncManager.unsyncedBodyCount)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Daily Metrics")
                Spacer()
                Text("\(syncManager.unsyncedDailyCount)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Profiles")
                Spacer()
                Text("\(syncManager.unsyncedProfileCount)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var healthKitSection: some View {
        Section(header: Text("HealthKit")) {
            HStack {
                Text("Authorization")
                Spacer()
                Text(healthKitManager.isAuthorized ? "Authorized" : "Not authorized")
                    .foregroundColor(healthKitManager.isAuthorized ? .green : .orange)
            }

            if healthKitManager.isImporting {
                HStack {
                    Text("Import Progress")
                    Spacer()
                    ProgressView(value: healthKitManager.importProgress)
                        .frame(width: 120)
                }

                if !healthKitManager.importStatus.isEmpty {
                    Text(healthKitManager.importStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if !healthKitManager.importStatus.isEmpty {
                Text(healthKitManager.importStatus)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if healthKitManager.importedCount > 0 {
                HStack {
                    Text("Imported Entries")
                    Spacer()
                    Text("\(healthKitManager.importedCount)")
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task {
                    await healthKitManager.forceFullHealthKitSync()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.heart")
                    Text(healthKitManager.isImporting ? "HealthKit Sync Running…" : "Run Full HealthKit Sync")
                }
            }
            .disabled(!healthKitManager.isAuthorized || healthKitManager.isImporting)
        }
    }

    private var statusText: String {
        if syncManager.isSyncing {
            return "Syncing…"
        }

        switch syncManager.syncStatus {
        case .offline:
            return "Offline"
        case .error:
            return "Error"
        case .success:
            return "Synced"
        case .syncing:
            return "Syncing…"
        case .idle:
            return "Idle"
        }
    }
}
