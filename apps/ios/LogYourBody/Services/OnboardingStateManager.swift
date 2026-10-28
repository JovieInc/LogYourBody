import Foundation

/// Stable persistence keys only; hint copy belongs to the presenting surface.
enum ContextualHintID: String, CaseIterable {
    case firstImport = "first_import"
    case firstPhoto = "first_photo"
    case firstWorkout = "first_workout"
    case planRevision = "plan_revision"

    fileprivate func defaultsKey(scopedWith userId: String?) -> String {
        let key = "contextualHint.\(rawValue)"
        guard let userId, !userId.isEmpty else { return key }
        return "\(key)_\(userId)"
    }
}

enum ContextualHintState: String {
    case seen
    case skipped
}

struct ContextualHintContext: Equatable {
    let eligibleHints: Set<ContextualHintID>
    var isPrimaryActionInFocus = false
}

/// An immutable snapshot. Reload from the manager after recording a presentation or skip.
struct ContextualHintRegistry: Equatable {
    let states: [ContextualHintID: ContextualHintState]

    /// Pure selection in registry order. Record `markHintSeen` when actually presenting
    /// the result, or `skipHint` when skipping it, before selecting again.
    func nextHint(context: ContextualHintContext) -> ContextualHintID? {
        guard !context.isPrimaryActionInFocus else { return nil }
        return ContextualHintID.allCases.first { hint in
            context.eligibleHints.contains(hint) && states[hint] == nil
        }
    }
}

/// Centralized manager for tracking whether the user has completed the current onboarding version.
@MainActor
final class OnboardingStateManager {
    static let shared = OnboardingStateManager()
    static let onboardingStateDidChange = Notification.Name("onboardingStateDidChange")

    private let defaults: UserDefaults
    private let currentOnboardingVersion: Int

    var hasCompletedCurrentVersion: Bool {
        let didComplete = defaults.bool(forKey: Constants.hasCompletedOnboardingKey)
        let storedVersion = defaults.integer(forKey: Constants.onboardingCompletedVersionKey)
        return didComplete && storedVersion >= currentOnboardingVersion
    }

    func hasCompletedCurrentVersion(for userId: String?) -> Bool {
        guard hasCompletedCurrentVersion else { return false }
        guard let storedUserId = defaults.string(forKey: Constants.onboardingCompletedUserIdKey),
              !storedUserId.isEmpty,
              let userId,
              !userId.isEmpty else {
            return true
        }

        return storedUserId == userId
    }

    init(defaults: UserDefaults = .standard, currentVersion: Int = 1) {
        self.defaults = defaults
        self.currentOnboardingVersion = currentVersion
        ensureVersionConsistency()
    }

    func contextualHintRegistry(for userId: String?) -> ContextualHintRegistry {
        var states: [ContextualHintID: ContextualHintState] = [:]
        for hint in ContextualHintID.allCases {
            if let rawState = defaults.string(forKey: hint.defaultsKey(scopedWith: userId)),
               let state = ContextualHintState(rawValue: rawState) {
                states[hint] = state
            }
        }
        return ContextualHintRegistry(states: states)
    }

    func markHintSeen(_ hint: ContextualHintID, for userId: String?) {
        let key = hint.defaultsKey(scopedWith: userId)
        // Preserve an explicit skip if a delayed presentation callback arrives.
        guard defaults.string(forKey: key) != ContextualHintState.skipped.rawValue else { return }
        defaults.set(ContextualHintState.seen.rawValue, forKey: key)
    }

    func skipHint(_ hint: ContextualHintID, for userId: String?) {
        defaults.set(ContextualHintState.skipped.rawValue, forKey: hint.defaultsKey(scopedWith: userId))
    }

    func markCompleted(version: Int? = nil, userId: String? = nil) {
        let versionToPersist = version ?? currentOnboardingVersion
        defaults.set(true, forKey: Constants.hasCompletedOnboardingKey)
        defaults.set(versionToPersist, forKey: Constants.onboardingCompletedVersionKey)
        if let userId, !userId.isEmpty {
            defaults.set(userId, forKey: Constants.onboardingCompletedUserIdKey)
        } else {
            defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
        }
        AnalyticsService.shared.track(
            event: "onboarding_completed",
            properties: [
                "version": String(versionToPersist)
            ]
        )
        notifyChange()
    }

    func updateCompletionStatus(_ isCompleted: Bool, userId: String? = nil) {
        if isCompleted {
            markCompleted(userId: userId)
        } else {
            if shouldPreserveLocalCompletionForStaleFalse(userId: userId) {
                return
            }
            defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
            defaults.removeObject(forKey: Constants.onboardingCompletedVersionKey)
            defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
            notifyChange()
        }
    }

    func syncCompletionFlagFromProfile(_ isCompleted: Bool, userId: String? = nil) {
        if isCompleted {
            defaults.set(true, forKey: Constants.hasCompletedOnboardingKey)
            defaults.set(currentOnboardingVersion, forKey: Constants.onboardingCompletedVersionKey)
            if let userId, !userId.isEmpty {
                defaults.set(userId, forKey: Constants.onboardingCompletedUserIdKey)
            } else {
                defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
            }
        } else {
            if shouldPreserveLocalCompletionForStaleFalse(userId: userId) {
                return
            }
            defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
            defaults.removeObject(forKey: Constants.onboardingCompletedVersionKey)
            defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
        }
        notifyChange()
    }

    func resetForNextVersion(newVersion: Int) {
        guard newVersion > currentOnboardingVersion else { return }
        defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
        defaults.set(newVersion - 1, forKey: Constants.onboardingCompletedVersionKey)
        defaults.removeObject(forKey: Constants.onboardingCompletedUserIdKey)
        notifyChange()
    }

    private func ensureVersionConsistency() {
        let storedVersion = defaults.integer(forKey: Constants.onboardingCompletedVersionKey)
        if storedVersion < currentOnboardingVersion {
            defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
        }
    }

    private func shouldPreserveLocalCompletionForStaleFalse(userId: String?) -> Bool {
        guard hasCompletedCurrentVersion else { return false }
        guard let completedUserId = defaults.string(forKey: Constants.onboardingCompletedUserIdKey),
              !completedUserId.isEmpty else {
            return false
        }
        guard let userId, !userId.isEmpty else { return true }

        return completedUserId == userId
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: OnboardingStateManager.onboardingStateDidChange, object: nil)
    }
}
