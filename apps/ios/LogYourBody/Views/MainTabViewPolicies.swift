//
// MainTabViewPolicies.swift
// LogYourBody
//
import CoreGraphics
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

enum HomeSwipeDestination: Equatable {
    case menu
    case stats
    case home
    case collapseChat
    case none
}

enum HomeChatChromePolicy {
    static let pinsComposerOnHome = true
    static let showsTabBarOnHome = false
    static let showsChatAsPeerNavigation = false
    static let showsTopSegmentedTabs = false
    static let usesJovieSwipeStructure = true
    static let swipeMinimumDistance: CGFloat = 72
    static let menuEdgeWidth: CGFloat = 52

    static func shouldExpandChat(afterSendingUserMessage: Bool) -> Bool {
        afterSendingUserMessage
    }

    static func worldClassScreen(isChatExpanded: Bool, selected: WorldClassScreen) -> WorldClassScreen {
        isChatExpanded ? .chat : selected
    }

    static func shouldShowComposer(isChatExpanded: Bool, isOnStats: Bool) -> Bool {
        isChatExpanded || !isOnStats
    }

    static func swipeDestination(
        translationX: CGFloat,
        translationY: CGFloat,
        startX: CGFloat,
        isOnStats: Bool,
        isChatExpanded: Bool
    ) -> HomeSwipeDestination {
        guard abs(translationX) > swipeMinimumDistance,
              abs(translationX) > abs(translationY) else {
            return .none
        }

        if translationX > 0, startX <= menuEdgeWidth {
            return .menu
        }

        if translationX < 0, !isOnStats {
            return .stats
        }

        if translationX > 0, isOnStats {
            return .home
        }

        if translationX > 0, isChatExpanded {
            return .collapseChat
        }

        return .none
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
