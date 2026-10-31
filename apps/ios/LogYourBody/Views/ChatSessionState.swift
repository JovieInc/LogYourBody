import SwiftUI

/// An unsent draft belongs to one authenticated account lifetime, not one mounted Ask view.
@MainActor
struct AccountSessionChatDraft {
    private var owner: AuthManager.ProfileSessionOwnership?
    private var text = ""

    static func binding(
        storage: Binding<Self>,
        owner: AuthManager.ProfileSessionOwnership?,
        isCurrent: @escaping () -> Bool
    ) -> Binding<String> {
        Binding(
            get: {
                guard let owner, isCurrent(), storage.wrappedValue.owner == owner else { return "" }
                return storage.wrappedValue.text
            },
            set: { value in
                // An old field/voice callback must never adopt the replacement account's session.
                guard let owner, isCurrent() else { return }
                storage.wrappedValue = Self(owner: owner, text: value)
            }
        )
    }
}

/// Records the last few chat send and conversation-load events for UI tests.
/// The launch-quality chat-root check once saw a delivered prompt tap leave the
/// welcome state untouched (run 38328287365). `send` silently returns while a
/// load or reply is in flight, so this exposes which path ran. It is empty
/// outside the UI-test chat fixture, so VoiceOver never reads it.
struct ChatSendProbe {
    private static let isEnabled = ProcessInfo.processInfo.arguments.contains("-lybUITestChatFirstFixture")
    private(set) var events: [String] = []

    mutating func record(_ event: String) {
        guard Self.isEnabled else { return }
        events = Array((events + [event]).suffix(8))
    }

    var accessibilityValue: String {
        Self.isEnabled ? events.joined(separator: ",") : ""
    }
}
