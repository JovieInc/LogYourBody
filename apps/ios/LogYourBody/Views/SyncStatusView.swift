//
// SyncStatusView.swift
// LogYourBody
//
import SwiftUI

struct SyncStatusView: View {
    @StateObject private var syncManager = RealtimeSyncManager.shared
    @State private var showDetails = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            if !isCompact {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundcolor)
        .cornerRadius(20)
        .onTapGesture {
            if syncManager.pendingSyncCount > 0 || syncManager.error != nil {
                showDetails = true
            } else if !syncManager.isSyncing {
                syncManager.syncAll()
            }
        }
        .sheet(isPresented: $showDetails) {
            SyncDetailsView()
        }
    }

    private var isCompact: Bool {
        // Show compact view on smaller screens or when space is limited
        horizontalSizeClass == .compact
    }

    @ViewBuilder

    private var statusIcon: some View {
        switch (syncManager.isOnline, syncManager.syncStatus) {
        case (false, _):
            Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
        case (true, .syncing):
            ProgressView()
                .scaleEffect(0.8)
        case (true, .error):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        case (true, _) where syncManager.pendingSyncCount > 0:
            HStack(spacing: 4) {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                Text("\(syncManager.pendingSyncCount)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        case (true, _) where syncManager.realtimeConnected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        default:
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
        }
    }

    private var statusText: String {
        if !syncManager.isOnline {
            return "Offline"
        }

        switch syncManager.syncStatus {
        case .syncing:
            return "Syncing..."
        case .error:
            return "Sync Error"
        case .offline:
            return "Offline"
        default:
            if syncManager.pendingSyncCount > 0 {
                return "\(syncManager.pendingSyncCount) pending"
            } else if syncManager.realtimeConnected {
                return "Live"
            } else {
                return "Synced"
            }
        }
    }

    private var backgroundcolor: Color {
        if !syncManager.isOnline {
            return Color.gray.opacity(0.2)
        }

        switch syncManager.syncStatus {
        case .error:
            return Color.red.opacity(0.2)
        case .syncing:
            return Color.blue.opacity(0.2)
        default:
            if syncManager.pendingSyncCount > 0 {
                return Color.orange.opacity(0.2)
            } else {
                return Color.green.opacity(0.2)
            }
        }
    }
}

struct SyncDetailsView: View {
    @StateObject private var syncManager = RealtimeSyncManager.shared
    @Environment(\.dismiss)
    private var dismiss
    var body: some View {
        NavigationView {
            List {
                Section("Sync Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(syncManager.isOnline ? "Online" : "Offline")
                            .foregroundColor(syncManager.isOnline ? .green : .gray)
                    }

                    HStack {
                        Text("Real-time")
                        Spacer()
                        Text(syncManager.realtimeConnected ? "Connected" : "Disconnected")
                            .foregroundColor(syncManager.realtimeConnected ? .green : .gray)
                    }

                    if syncManager.pendingSyncCount > 0 {
                        HStack {
                            Text("Pending Changes")
                            Spacer()
                            Text("\(syncManager.pendingSyncCount)")
                                .foregroundColor(.orange)
                        }
                    }

                    if let lastSync = syncManager.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let error = syncManager.error {
                    Section("Error Details") {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(
                        action: {
                            syncManager.syncAll()
                            dismiss()
                        },
                        label: {
                            HStack {
                                if syncManager.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(syncManager.isSyncing ? "Syncing..." : "Sync Now")
                            }
                        }
                    )
                    .disabled(syncManager.isSyncing || !syncManager.isOnline)

                    if syncManager.error != nil {
                        Button(
                            action: {
                                syncManager.clearError()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                    Text("Clear Error")
                                }
                            }
                        )
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Minimal sync indicator for compact spaces
struct CompactSyncIndicator: View {
    @StateObject private var syncManager = RealtimeSyncManager.shared

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1)
            )
            .animation(.easeInOut, value: syncManager.syncStatus)
    }

    private var indicatorColor: Color {
        if !syncManager.isOnline {
            return .gray
        }

        switch syncManager.syncStatus {
        case .error:
            return .red
        case .syncing:
            return .blue
        default:
            if syncManager.pendingSyncCount > 0 {
                return .orange
            } else {
                return .green
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusView()
        CompactSyncIndicator()
    }
    .padding()
}
