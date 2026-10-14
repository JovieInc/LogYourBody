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

        // Founder IA contract (LYB-88): from Home, right opens Stats and left opens
        // the sidebar. Stats reverses with a left swipe. Expanded chat keeps the
        // right-swipe collapse gesture rather than navigating underneath the chat.
        if translationX > 0, isChatExpanded {
            return .collapseChat
        }

        if translationX > 0, !isOnStats {
            return .stats
        }

        if translationX < 0, isOnStats {
            return .home
        }

        if translationX < 0, !isOnStats {
            return .menu
        }

        return .none
    }
}

enum ComposerLoggingMode: String, CaseIterable, Equatable, Hashable, Identifiable {
    case weight
    case bodyFat
    case photo

    var id: Self { self }

    var title: String {
        switch self {
        case .weight:
            return "Weight"
        case .bodyFat:
            return "Body fat"
        case .photo:
            return "Photo"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .weight:
            return "composer_log_weight"
        case .bodyFat:
            return "composer_log_body_fat"
        case .photo:
            return "composer_log_photo"
        }
    }
}

enum ComposerLoggingSelectorPhase: Equatable {
    case composer
    case tapSelection
    case dragSelection
}

struct ComposerLoggingSelectorState: Equatable {
    private(set) var phase: ComposerLoggingSelectorPhase = .composer
    private(set) var highlightedMode: ComposerLoggingMode?

    var isPresented: Bool {
        phase != .composer
    }

    var isDragging: Bool {
        phase == .dragSelection
    }

    mutating func toggleTapSelection() {
        if isPresented {
            cancel()
        } else {
            phase = .tapSelection
        }
    }

    mutating func beginDragSelection() {
        phase = .dragSelection
        highlightedMode = nil
    }

    @discardableResult
    mutating func updateDragSelection(over mode: ComposerLoggingMode?) -> Bool {
        guard isDragging, highlightedMode != mode else { return false }
        highlightedMode = mode
        return true
    }

    mutating func finishDragSelection(over mode: ComposerLoggingMode?) -> ComposerLoggingMode? {
        guard isDragging else {
            cancel()
            return nil
        }
        cancel()
        return mode
    }

    mutating func selectFromTap(_ mode: ComposerLoggingMode) -> ComposerLoggingMode? {
        guard phase == .tapSelection else { return nil }
        cancel()
        return mode
    }

    mutating func cancel() {
        phase = .composer
        highlightedMode = nil
    }
}

enum ComposerLoggingPrototypePolicy {
    static let gateKey = "composer_logging_selector_prototype"
    static let fixtureArgument = "-lybUITestComposerLoggingPrototype"

    static func allowsHoldDrag(isAccessibilitySize: Bool) -> Bool {
        !isAccessibilitySize
    }

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument) { return true }
        #endif

        let checkGate = isGateEnabled ?? {
            AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0)
        }
        return checkGate(gateKey)
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
