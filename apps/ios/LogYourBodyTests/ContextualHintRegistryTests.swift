import XCTest
@testable import LogYourBody

@MainActor
final class ContextualHintRegistryTests: XCTestCase {
    private let userId = "hint-user-A"

    func testRegistryContainsOnlyTheFourStableHintKeys() {
        XCTAssertEqual(
            ContextualHintID.allCases.map(\.rawValue),
            ["first_import", "first_photo", "first_workout", "plan_revision"]
        )
    }

    func testOnlyEligibleHintsAreReturned() {
        let registry = ContextualHintRegistry(states: [:])
        XCTAssertNil(registry.nextHint(context: ContextualHintContext(eligibleHints: [])))

        for hint in ContextualHintID.allCases {
            XCTAssertEqual(registry.nextHint(context: ContextualHintContext(eligibleHints: [hint])), hint)
        }
    }

    func testMultipleEligibleHintsReturnOneInStableOrder() {
        let context = ContextualHintContext(eligibleHints: Set(ContextualHintID.allCases))
        var states: [ContextualHintID: ContextualHintState] = [:]

        for hint in ContextualHintID.allCases {
            XCTAssertEqual(ContextualHintRegistry(states: states).nextHint(context: context), hint)
            states[hint] = .seen
        }

        XCTAssertNil(ContextualHintRegistry(states: states).nextHint(context: context))
    }

    func testSeenAndSkippedHintsAreIneligible() {
        for hint in ContextualHintID.allCases {
            let context = ContextualHintContext(eligibleHints: [hint])
            XCTAssertNil(ContextualHintRegistry(states: [hint: .seen]).nextHint(context: context))
            XCTAssertNil(ContextualHintRegistry(states: [hint: .skipped]).nextHint(context: context))
        }
    }

    func testPrimaryActionFocusSuppressesEveryHintWithoutConsumingIt() {
        let registry = ContextualHintRegistry(states: [:])
        for hint in ContextualHintID.allCases {
            var context = ContextualHintContext(eligibleHints: [hint], isPrimaryActionInFocus: true)
            XCTAssertNil(registry.nextHint(context: context))
            context.isPrimaryActionInFocus = false
            XCTAssertEqual(registry.nextHint(context: context), hint)
        }
    }

    func testSelectionIsPureAndDoesNotWriteDefaults() throws {
        try withDefaults { defaults, manager in
            let registry = manager.contextualHintRegistry(for: userId)
            let context = ContextualHintContext(eligibleHints: [.firstImport, .firstPhoto])
            let before = defaults.dictionaryRepresentation() as NSDictionary

            XCTAssertEqual(registry.nextHint(context: context), .firstImport)
            XCTAssertEqual(registry.nextHint(context: context), .firstImport)
            XCTAssertEqual(manager.contextualHintRegistry(for: userId), registry)
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        }
    }

    func testEachPresentedHintIsReturnedOnlyOnceAcrossManagerRecreation() throws {
        try withDefaults { defaults, manager in
            for hint in ContextualHintID.allCases {
                let context = ContextualHintContext(eligibleHints: [hint])
                XCTAssertEqual(manager.contextualHintRegistry(for: userId).nextHint(context: context), hint)

                manager.markHintSeen(hint, for: userId)

                let reloaded = OnboardingStateManager(defaults: defaults)
                XCTAssertEqual(reloaded.contextualHintRegistry(for: userId).states[hint], .seen)
                XCTAssertNil(manager.contextualHintRegistry(for: userId).nextHint(context: context))
                XCTAssertNil(reloaded.contextualHintRegistry(for: userId).nextHint(context: context))
            }
        }
    }

    func testEachSkippedHintStaysSkippedAcrossDefaultsAndManagerRecreation() throws {
        let suiteName = "ContextualHintRegistryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = OnboardingStateManager(defaults: defaults)

        for hint in ContextualHintID.allCases {
            manager.skipHint(hint, for: userId)
        }

        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let reloaded = OnboardingStateManager(defaults: reloadedDefaults)
        for hint in ContextualHintID.allCases {
            let context = ContextualHintContext(eligibleHints: [hint])
            XCTAssertEqual(reloaded.contextualHintRegistry(for: userId).states[hint], .skipped)
            XCTAssertNil(reloaded.contextualHintRegistry(for: userId).nextHint(context: context))
        }
    }

    func testSkippingASeenHintRemainsSkippedAfterRepeatedPresentationCallbacks() throws {
        try withDefaults { _, manager in
            for hint in ContextualHintID.allCases {
                manager.markHintSeen(hint, for: userId)
                manager.skipHint(hint, for: userId)
                manager.skipHint(hint, for: userId)
                manager.markHintSeen(hint, for: userId)
                XCTAssertEqual(manager.contextualHintRegistry(for: userId).states[hint], .skipped)
            }
        }
    }

    func testSeenAndSkippedStatesAreIsolatedPerUserAndSurviveSwitchingBack() throws {
        try withDefaults { _, manager in
            manager.markHintSeen(.firstImport, for: userId)
            manager.skipHint(.firstPhoto, for: userId)

            let otherUser = "hint-user-B"
            XCTAssertTrue(manager.contextualHintRegistry(for: otherUser).states.isEmpty)
            manager.skipHint(.firstWorkout, for: otherUser)

            XCTAssertEqual(manager.contextualHintRegistry(for: userId).states, [
                .firstImport: .seen,
                .firstPhoto: .skipped
            ])
            XCTAssertEqual(manager.contextualHintRegistry(for: otherUser).states, [.firstWorkout: .skipped])
        }
    }

    func testNilAndEmptyUserIDsShareOnlyTheUnscopedStateLikeHealthKit() throws {
        try withDefaults { _, manager in
            manager.markHintSeen(.firstImport, for: nil)
            manager.skipHint(.firstPhoto, for: "")

            XCTAssertEqual(manager.contextualHintRegistry(for: nil).states, [
                .firstImport: .seen,
                .firstPhoto: .skipped
            ])
            XCTAssertEqual(manager.contextualHintRegistry(for: nil), manager.contextualHintRegistry(for: ""))
            XCTAssertTrue(manager.contextualHintRegistry(for: userId).states.isEmpty)
        }
    }

    func testHintUpdatesDoNotChangeFirstLaunchCompletionOrVersion() throws {
        try withDefaults { defaults, manager in
            XCTAssertFalse(manager.hasCompletedCurrentVersion)
            let before = completionValues(defaults)
            manager.markHintSeen(.firstImport, for: userId)
            manager.skipHint(.firstPhoto, for: userId)
            XCTAssertEqual(completionValues(defaults), before)
            XCTAssertFalse(manager.hasCompletedCurrentVersion)

            manager.syncCompletionFlagFromProfile(true, userId: userId)
            let completed = completionValues(defaults)
            manager.markHintSeen(.firstWorkout, for: userId)
            manager.skipHint(.planRevision, for: userId)
            XCTAssertEqual(completionValues(defaults), completed)
            XCTAssertTrue(manager.hasCompletedCurrentVersion(for: userId))
        }
    }

    func testOnboardingVersionResetDoesNotRepeatConsumedHints() throws {
        try withDefaults { defaults, manager in
            manager.markHintSeen(.firstImport, for: userId)
            manager.skipHint(.firstPhoto, for: userId)
            let before = manager.contextualHintRegistry(for: userId)

            manager.resetForNextVersion(newVersion: 2)
            let reloaded = OnboardingStateManager(defaults: defaults, currentVersion: 2)

            XCTAssertFalse(reloaded.hasCompletedCurrentVersion)
            XCTAssertEqual(reloaded.contextualHintRegistry(for: userId), before)
        }
    }

    private func withDefaults(_ body: (UserDefaults, OnboardingStateManager) throws -> Void) throws {
        let suiteName = "ContextualHintRegistryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, OnboardingStateManager(defaults: defaults))
    }

    private func completionValues(_ defaults: UserDefaults) -> NSDictionary {
        let keys = [
            Constants.hasCompletedOnboardingKey,
            Constants.onboardingCompletedVersionKey,
            Constants.onboardingCompletedUserIdKey
        ]
        return defaults.dictionaryRepresentation().filter { keys.contains($0.key) } as NSDictionary
    }
}
