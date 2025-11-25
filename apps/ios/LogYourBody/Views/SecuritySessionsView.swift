//
// SecuritySessionsView.swift
// LogYourBody
//
import SwiftUI
import Clerk

struct SecuritySessionsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    var dismiss
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
        ZStack {
            if isLoading && sessions.isEmpty {
                LoadingOverlay(message: "Loading sessions...")
            } else {
                ScrollView {
                    VStack(spacing: SettingsDesign.sectionSpacing) {
                        // Security Info Section
                        SettingsSection {
                            DataInfoRow(
                                icon: "lock.shield.fill",
                                title: "Session Management",
                                description: "View and manage devices signed into your account",
                                iconColor: .blue
                            )
                        }

                        // Sessions List
                        if sessions.isEmpty {
                            SettingsEmptyState(
                                icon: "checkmark.shield.fill",
                                title: "No Other Sessions",
                                message: "Only this device is currently signed in",
                                iconColor: .green
                            )
                            .padding(.top, 40)
                        } else {
                            SettingsSection(header: "Active Sessions") {
                                VStack(spacing: 0) {
                                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                        if index > 0 {
                                            Divider()
                                        }
                                        SessionRowView(
                                            session: session,
                                            onRevoke: {
                                                sessionToRevoke = session
                                                showRevokeConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        // Last Updated
                        if !sessions.isEmpty {
                            Text("Last updated: \(Date().formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical)
                    .settingsSectionStyle()
                }
                .refreshable {
                    await loadSessions()
                }
                .settingsBackground()
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
        .alert("Revoke Session?", isPresented: $showRevokeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                if let session = sessionToRevoke {
                    Task {
                        await revokeSession(session)
                    }
                }
            }
        } message: {
            if let session = sessionToRevoke {
                Text("Are you sure you want to revoke this session? The device will be signed out immediately.")
            }
        }
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .overlay(
            SuccessOverlay(
                isShowing: $showSuccessToast,
                message: successMessage
            )
        )
    }

    // MARK: - View Components

    // MARK: - Methods

    private func loadSessions(showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        }

        do {
            let fetchedSessions = try await AuthManager.shared.fetchActiveSessions()
            await MainActor.run {
                self.sessions = fetchedSessions.sorted { session1, session2 in
                    // Current session first, then by last active
                    if session1.isCurrentSession != session2.isCurrentSession {
                        return session1.isCurrentSession
                    }
                    return session1.lastActiveAt > session2.lastActiveAt
                }
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
        VStack(spacing: 0) {
            // Main Content
            Button(
                action: {
                    withAnimation(SettingsDesign.animation) {
                        isExpanded.toggle()
                    }
                },
                label: {
                    HStack(spacing: 12) {
                        // Device Icon
                        Image(systemName: deviceIcon)
                            .font(.system(size: SettingsDesign.iconSize))
                            .foregroundColor(iconColor)
                            .frame(width: SettingsDesign.iconFrame)
                            .padding(8)
                            .background(iconBackgroundColor)
                            .clipShape(Circle())

                        // Session Details
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.deviceName)
                                    .font(SettingsDesign.titleFont)
                                    .foregroundColor(.primary)

                                if session.isCurrentSession {
                                    Text("THIS DEVICE")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .cornerRadius(4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.location)
                                    .font(SettingsDesign.valueFont)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                    Text(timeAgoString(from: session.lastActiveAt))
                                        .font(SettingsDesign.valueFont)
                                }
                                .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Revoke Button or Chevron
                        if !session.isCurrentSession {
                            Button(action: onRevoke) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if !session.ipAddress.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(SettingsDesign.chevronSize)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(PlainButtonStyle())

            // Additional Details (expandable)
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()

                    VStack(spacing: 8) {
                        HStack {
                            Label("IP Address", systemImage: "network")
                                .font(SettingsDesign.valueFont)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(session.ipAddress)
                                .font(SettingsDesign.valueFont)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Label("First Signed In", systemImage: "calendar")
                                .font(SettingsDesign.valueFont)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SettingsDesign.valueFont)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, 12)
                }
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
        session.isCurrentSession ? .green : .blue
    }

    private var iconBackgroundColor: Color {
        session.isCurrentSession ? Color.green.opacity(0.15) : Color.blue.opacity(0.15)
    }

    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


// MARK: - Preview

#Preview {
    NavigationView {
        SecuritySessionsView()
            .environmentObject(AuthManager.shared)
    }
}
