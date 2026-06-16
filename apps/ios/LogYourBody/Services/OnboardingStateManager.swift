import Foundation

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
