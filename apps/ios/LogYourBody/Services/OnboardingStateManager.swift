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

    init(defaults: UserDefaults = .standard, currentVersion: Int = 1) {
        self.defaults = defaults
        self.currentOnboardingVersion = currentVersion
        ensureVersionConsistency()
    }

    func markCompleted(version: Int? = nil) {
        let versionToPersist = version ?? currentOnboardingVersion
        defaults.set(true, forKey: Constants.hasCompletedOnboardingKey)
        defaults.set(versionToPersist, forKey: Constants.onboardingCompletedVersionKey)
        notifyChange()
    }

    func updateCompletionStatus(_ isCompleted: Bool) {
        if isCompleted {
            markCompleted()
        } else {
            defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
            defaults.removeObject(forKey: Constants.onboardingCompletedVersionKey)
            notifyChange()
        }
    }

    func resetForNextVersion(newVersion: Int) {
        guard newVersion > currentOnboardingVersion else { return }
        defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
        defaults.set(newVersion - 1, forKey: Constants.onboardingCompletedVersionKey)
        notifyChange()
    }

    private func ensureVersionConsistency() {
        let storedVersion = defaults.integer(forKey: Constants.onboardingCompletedVersionKey)
        if storedVersion < currentOnboardingVersion {
            defaults.set(false, forKey: Constants.hasCompletedOnboardingKey)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: OnboardingStateManager.onboardingStateDidChange, object: nil)
    }
}
