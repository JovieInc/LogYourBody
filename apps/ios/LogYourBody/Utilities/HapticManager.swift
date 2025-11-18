//
// HapticManager.swift
// LogYourBody
//

import UIKit

class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // MARK: - Impact Feedback
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    // MARK: - Notification Feedback
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }

    // MARK: - Selection Feedback
    func selection() {
        Task { @MainActor in
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }

    // MARK: - Custom Patterns
    func buttonTap() {
        impact(style: .light)
    }

    func tabSelection() {
        impact(style: .medium)
    }

    func successAction() {
        notification(type: .success)
    }

    func errorAction() {
        notification(type: .error)
    }

    func warningAction() {
        notification(type: .warning)
    }
}
