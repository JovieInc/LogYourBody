//
// SecuritySessionsView.swift
// LogYourBody
//
import SwiftUI

enum SessionListOrdering {
    /// Orders sessions for display: the current session pinned first, then most-recently-active first.
    static func sorted(_ sessions: [SessionInfo]) -> [SessionInfo] {
        sessions.sorted { session1, session2 in
            if session1.isCurrentSession != session2.isCurrentSession {
                return session1.isCurrentSession
            }
            return session1.lastActiveAt > session2.lastActiveAt
        }
    }
}

struct SecuritySessionsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var sessions: [SessionInfo] = []
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var sessionToRevoke: SessionInfo?
    @State private var showRevokeConfirmation = false
    @State private var isRevokingSession = false
    @State private var showSuccessToast = false
    @State private var successMessage = ""
    @State private var refreshTimer: Timer?

    // Pull to refresh
    @State private var refreshing = false

    var body: some View {
        List {
            SettingsSection {
                DataInfoRow(
                    icon: "lock.shield.fill",
                    title: "Signed-in devices",
                    description: "Current device is marked. Locations are approximate, " +
                        "and revoked devices can sign in again.",
                    iconColor: .accentColor
                )
            }

            if sessions.isEmpty && !isLoading {
                SettingsSection {
                    SettingsEmptyState(
                        icon: "checkmark.shield.fill",
                        title: "Only this device",
                        message: "No other devices are signed in.",
                        iconColor: Color.appSuccess
                    )
                }
            } else if !sessions.isEmpty {
                SettingsSection(header: "Active Sessions") {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            onRevoke: {
                                sessionToRevoke = session
                                showRevokeConfirmation = true
                            }
                        )
                    }
                }

                SettingsSection {
                    Text("Last updated: \(Date().formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            await loadSessions()
        }
        .overlay {
            if isLoading && sessions.isEmpty {
                LoadingOverlay(message: "Loading sessions...")
            }
        }
        .navigationTitle("Active Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoading && !sessions.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .onAppear {
            Task {
                await loadSessions()
            }
            // Auto-refresh every 30 seconds
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                Task {
                    await loadSessions(showLoading: false)
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
        .confirmationDialog(
            "Revoke Session?",
            isPresented: $showRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let session = sessionToRevoke {
                    Task {
                        await revokeSession(session)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to revoke this session? The device will be signed out immediately.")
        }
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .overlay(
            SuccessOverlay(
                isShowing: $showSuccessToast,
                message: successMessage
            )
        )
        .worldClassScreen(.activeSessions)
    }

    // MARK: - Methods

    private func loadSessions(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }

        do {
            let fetchedSessions = try await AuthManager.shared.fetchActiveSessions()
            await MainActor.run {
                self.sessions = SessionListOrdering.sorted(fetchedSessions)
                isLoading = false
                refreshing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                showError = true
                isLoading = false
                refreshing = false
            }
        }
    }

    private func revokeSession(_ session: SessionInfo) async {
        isRevokingSession = true

        do {
            try await authManager.revokeSession(sessionId: session.id)
            await MainActor.run {
                // Remove from list with animation
                withAnimation(.easeOut(duration: 0.3)) {
                    sessions.removeAll { $0.id == session.id }
                }
                isRevokingSession = false

                // Show success toast
                successMessage = "Session revoked successfully"
                withAnimation {
                    showSuccessToast = true
                }

                // Haptic feedback
                HapticManager.shared.successAction()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to revoke session: \(error.localizedDescription)"
                showError = true
                isRevokingSession = false
            }
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: SessionInfo
    let onRevoke: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: deviceIcon)
                        .foregroundStyle(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconBackgroundColor, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.deviceName)
                                .foregroundStyle(.primary)

                            if session.isCurrentSession {
                                Text("THIS DEVICE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.appSuccess)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.appSuccess.opacity(0.15), in: Capsule())
                            }
                        }

                        Text(session.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Label(timeAgoString(from: session.lastActiveAt), systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !session.isCurrentSession {
                        Button(action: onRevoke) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    } else if !session.ipAddress.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    LabeledContent("IP Address", value: session.ipAddress)
                    LabeledContent(
                        "First Signed In",
                        value: session.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var deviceIcon: String {
        switch session.deviceType.lowercased() {
        case "iphone":
            return "iphone"
        case "ipad":
            return "ipad"
        case "mac":
            return "desktopcomputer"
        case "web":
            return "globe"
        default:
            return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        session.isCurrentSession ? .green : .accentColor
    }

    private var iconBackgroundColor: Color {
        session.isCurrentSession ? Color.appSuccess.opacity(0.15) : .accentColor.opacity(0.15)
    }

    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SecuritySessionsView()
            .environmentObject(AuthManager.shared)
    }
}
