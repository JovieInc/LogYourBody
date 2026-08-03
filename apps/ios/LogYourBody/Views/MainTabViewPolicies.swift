//
// MainTabViewPolicies.swift
// LogYourBody
//
import Foundation

enum PaidAppSurface: Equatable {
    case weightLoggerMVP
    case legacyFullDashboardBeta
    case photoTimelineHUD
}

enum PaidAppSurfacePolicy {
    static func surface() -> PaidAppSurface {
        .photoTimelineHUD
    }
}

enum PaidWeightLoggerMVPPolicy {
    static func validationMessage(weightText: String, unit: String) -> String? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            _ = try ValidationService.shared.validateWeight(trimmed, unit: unit)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func canSaveWeight(weightText: String, unit: String, isSaving: Bool) -> Bool {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return false }
        return validationMessage(weightText: trimmed, unit: unit) == nil
    }

    static func syncStatusText(status: RealtimeSyncManager.SyncStatus, pendingCount: Int) -> String {
        switch status {
        case .syncing:
            return "Syncing"
        case .success:
            return "Synced"
        case .error:
            return "Sync needs retry"
        case .offline:
            return pendingCount > 0 ? "Saved offline" : "Offline"
        case .idle:
            return pendingCount > 0 ? "Pending sync" : "Synced"
        }
    }

    static func savedConfirmationText(isOnline: Bool) -> String {
        isOnline ? "Saved locally. Pending sync." : "Saved locally. Will sync when online."
    }
}
