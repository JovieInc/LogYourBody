import SwiftUI
import Foundation

extension DashboardViewLiquid {
    // MARK: - Compact Header

    var compactHeader: some View {
        DashboardHeaderCompact(
            avatarURL: avatarURL,
            userFirstName: userFirstName,
            hasAge: hasAge,
            hasHeight: hasHeight,
            syncStatusTitle: syncStatusTitle,
            syncStatusDetail: syncStatusDetail,
            syncStatusColor: syncStatusColor,
            isSyncError: isSyncError,
            onShowSyncDetails: { showSyncDetails = true }
        )
    }

    var avatarURL: URL? {
        guard let urlString = authManager.currentUser?.avatarUrl else {
            return nil
        }
        return URL(string: urlString)
    }

    var userFirstName: String {
        if let fullName = authManager.currentUser?.profile?.fullName, !fullName.isEmpty {
            return fullName.components(separatedBy: " ").first ?? fullName
        } else if let username = authManager.currentUser?.profile?.username {
            return username
        } else if let name = authManager.currentUser?.name, !name.isEmpty {
            return name
        } else if let email = authManager.currentUser?.email {
            let localPart = email.components(separatedBy: "@").first
            if let localPart, !localPart.isEmpty {
                return localPart
            }
        }
        return "User"
    }

    var userGender: String {
        authManager.currentUser?.profile?.gender ?? "N/A"
    }

    var userGenderShort: String {
        let gender = authManager.currentUser?.profile?.gender ?? ""
        switch gender.lowercased() {
        case "male": return "M"
        case "female": return "F"
        case "non-binary", "nonbinary": return "NB"
        case "other": return "O"
        default: return gender.prefix(1).uppercased()
        }
    }

    var hasAge: Bool {
        if let dob = authManager.currentUser?.profile?.dateOfBirth,
           let age = calculateAge(from: dob), age > 0 {
            return true
        }
        return false
    }

    var hasHeight: Bool {
        if let height = authManager.currentUser?.profile?.height, height > 0 {
            return true
        }
        return false
    }

    var userAgeDisplay: String {
        if let dob = authManager.currentUser?.profile?.dateOfBirth,
           let age = calculateAge(from: dob), age > 0 {
            return String(age)
        }
        return "—"
    }

    var userHeightDisplay: String {
        guard let heightCm = authManager.currentUser?.profile?.height,
              heightCm > 0 else {
            return "—"
        }

        let unit = authManager.currentUser?.profile?.heightUnit?.lowercased() ?? "cm"
        if unit == "cm" {
            let centimeters = Int(heightCm.rounded())
            return "\(centimeters) cm"
        }

        let totalInches = Int((heightCm / 2.54).rounded())
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }

    var isSyncError: Bool {
        if case .error = realtimeSyncManager.syncStatus {
            return true
        }
        return false
    }

    var syncStatusTitle: String {
        if realtimeSyncManager.isSyncing || realtimeSyncManager.syncStatus == .syncing {
            return "Syncing…"
        }

        switch realtimeSyncManager.syncStatus {
        case .offline:
            return "Offline"
        case .error:
            // Keep header copy neutral; red banner handles the explicit error messaging
            return "Sync"
        case .success, .idle:
            return "Synced"
        case .syncing:
            return "Syncing…"
        }
    }

    var syncStatusDetail: String? {
        if case .error = realtimeSyncManager.syncStatus {
            if let message = realtimeSyncManager.error, !message.isEmpty {
                return message
            }

            if let timeString = lastSyncClockText() {
                return "Last successful sync: \(timeString)"
            }

            return nil
        }

        // Offline messaging stays inline, since the banner is reserved for hard errors
        if !realtimeSyncManager.isOnline || realtimeSyncManager.syncStatus == .offline {
            return "Offline · changes queued"
        }

        // For healthy states, show explicit last-sync time (time-of-day) if available
        if let timeString = lastSyncClockText(),
           realtimeSyncManager.syncStatus == .success || realtimeSyncManager.syncStatus == .idle {
            return "Last synced: \(timeString)"
        }

        return nil
    }

    var syncStatusColor: Color {
        if realtimeSyncManager.isSyncing {
            return .yellow
        }

        switch realtimeSyncManager.syncStatus {
        case .offline:
            return .gray
        case .error:
            return .red
        case .success:
            return .green
        case .syncing:
            return .yellow
        case .idle:
            return .green
        }
    }

    @ViewBuilder
    var syncStatusBanner: some View {
        DashboardSyncBanner(banner: syncBannerState) {
            realtimeSyncManager.syncAll()
        }
    }

    func handleSyncStatusChange(
        from _: RealtimeSyncManager.SyncStatus,
        to _: RealtimeSyncManager.SyncStatus
    ) {
        syncBannerDismissTask?.cancel()

        withAnimation(.easeOut(duration: 0.2)) {
            syncBannerState = nil
        }
    }

    func lastSyncClockText() -> String? {
        guard let last = realtimeSyncManager.lastSyncDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: last)
    }
}
