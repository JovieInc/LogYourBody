//
// SecuritySessionsView.swift
// LogYourBody
//
import SwiftUI

struct SecuritySessionsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    var dismiss
    @Environment(\.theme)
    private var theme
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
                    VStack(spacing: theme.spacing.sectionSpacing) {
                        SettingsSection {
                            DataInfoRow(
                                icon: "lock.shield.fill",
                                title: "Signed-in devices",
                                description: "Review the devices currently using your account.",
                                iconColor: theme.colors.info
                            )
                        }

                        if sessions.isEmpty {
                            SettingsEmptyState(
                                icon: "checkmark.shield.fill",
                                title: "Only this device",
                                message: "No other devices are signed in.",
                                iconColor: theme.colors.success
                            )
                            .padding(.top, theme.spacing.lg)
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
                                .font(theme.typography.captionMedium)
                                .foregroundColor(theme.colors.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, theme.spacing.xs)
                        }
                    }
                    .padding(.vertical, theme.spacing.md)
                    .settingsSectionStyle()
                }
                .scrollBounceBehavior(.basedOnSize)
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
            if sessionToRevoke != nil {
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
    @Environment(\.theme)
    private var theme

    let session: SessionInfo
    let onRevoke: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main Content
            Button(
                action: {
                    withAnimation(theme.animation.spring) {
                        isExpanded.toggle()
                    }
                },
                label: {
                    HStack(spacing: theme.spacing.sm) {
                        Image(systemName: deviceIcon)
                            .font(theme.typography.headlineSmall)
                            .foregroundColor(iconColor)
                            .frame(width: 24)
                            .padding(theme.spacing.xs)
                            .background(iconBackgroundColor)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                            HStack {
                                Text(session.deviceName)
                                    .font(theme.typography.labelLarge)
                                    .foregroundColor(theme.colors.text)

                                if session.isCurrentSession {
                                    Text("THIS DEVICE")
                                        .font(theme.typography.captionSmall.weight(.bold))
                                        .foregroundColor(theme.colors.success)
                                        .padding(.horizontal, theme.spacing.xs)
                                        .padding(.vertical, theme.spacing.xxxs)
                                        .background(theme.colors.success.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            VStack(alignment: .leading, spacing: theme.spacing.xxxs) {
                                Text(session.location)
                                    .font(theme.typography.captionLarge)
                                    .foregroundColor(theme.colors.textSecondary)

                                HStack(spacing: theme.spacing.xxs) {
                                    Image(systemName: "clock")
                                        .font(theme.typography.captionSmall)
                                    Text(timeAgoString(from: session.lastActiveAt))
                                        .font(theme.typography.captionLarge)
                                }
                                .foregroundColor(theme.colors.textSecondary)
                            }
                        }

                        Spacer()

                        if !session.isCurrentSession {
                            Button(action: onRevoke) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(theme.typography.headlineSmall)
                                    .foregroundColor(theme.colors.error)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if !session.ipAddress.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(theme.colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(PlainButtonStyle())

            // Additional Details (expandable)
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()

                    VStack(spacing: theme.spacing.xs) {
                        HStack {
                            Label("IP Address", systemImage: "network")
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                            Spacer()
                            Text(session.ipAddress)
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                        }

                        HStack {
                            Label("First Signed In", systemImage: "calendar")
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                            Spacer()
                            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.vertical, theme.spacing.sm)
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
        session.isCurrentSession ? theme.colors.success : theme.colors.info
    }

    private var iconBackgroundColor: Color {
        session.isCurrentSession ? theme.colors.success.opacity(0.15) : theme.colors.info.opacity(0.15)
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
