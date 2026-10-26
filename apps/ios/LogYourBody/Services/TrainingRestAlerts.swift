import ActivityKit
import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
protocol TrainingRestAlerting {
    func start(_ countdown: TrainingRestCountdown) async
    func stop(cancelNotification: Bool)
    func playCompletionHaptic()
}

@MainActor
final class TrainingRestAlerts: ObservableObject {
    private let client: TrainingRestAlerting
    private let now: () -> Date
    private var countdown: TrainingRestCountdown?
    private var task: Task<Void, Never>?

    init(client: TrainingRestAlerting? = nil, now: @escaping () -> Date = Date.init) {
        self.client = client ?? SystemTrainingRestAlerts()
        self.now = now
    }

    func synchronize(_ updated: TrainingRestCountdown?, isCurrent: @escaping () -> Bool) {
        guard countdown != updated else { return }
        cancel()
        guard let updated, isCurrent(), updated.remaining(at: now()) > 0 else { return }
        countdown = updated
        task = Task { [weak self] in
            guard let self, !Task.isCancelled, countdown == updated, isCurrent() else { return }
            await client.start(updated)
            guard !Task.isCancelled else { return }
            let delay = max(0, updated.endsAt.timeIntervalSince(now()))
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            completeIfElapsed(at: now(), isCurrent: isCurrent(), isForeground: UIApplication.shared.applicationState == .active)
        }
    }

    /// A resumed app must not replay a haptic for a timer that elapsed while suspended.
    func completeIfElapsed(at date: Date, isCurrent: Bool, isForeground: Bool) {
        guard let countdown, countdown.remaining(at: date) == 0 else { return }
        let recentlyElapsed = (0...2).contains(date.timeIntervalSince(countdown.endsAt))
        cancel(cancelNotification: isForeground || !isCurrent)
        if isCurrent && isForeground && recentlyElapsed { client.playCompletionHaptic() }
    }

    func cancel(cancelNotification: Bool = true) {
        task?.cancel()
        task = nil
        countdown = nil
        client.stop(cancelNotification: cancelNotification)
    }
}

/// All system effects stay outside the session model and SwiftUI controls.
@MainActor
final class SystemTrainingRestAlerts: TrainingRestAlerting {
    private let center: UNUserNotificationCenter
    private var activity: Activity<TrainingRestActivityAttributes>?
    private var notificationId: String?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func start(_ countdown: TrainingRestCountdown) async {
        stop(cancelNotification: true)
        let identifier = "lyb.training.rest.\(UUID().uuidString)"
        notificationId = identifier
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(
                attributes: TrainingRestActivityAttributes(),
                content: ActivityContent(
                    state: TrainingRestActivityAttributes.ContentState(
                        startedAt: countdown.startedAt, endsAt: countdown.endsAt
                    ), staleDate: countdown.endsAt
                ),
                pushType: nil
            )
        }
        // iOS owns delivery while the app is suspended. Sound/haptics respect system settings.
        // Reconcile alerts left by a terminated process before scheduling a replacement.
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled, notificationId == identifier else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix("lyb.training.rest.") && $0 != identifier
        })
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted, !Task.isCancelled, notificationId == identifier else { return }
        let remaining = countdown.endsAt.timeIntervalSinceNow
        guard remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest timer finished"
        content.body = "Check how you feel before your next set."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        )
        try? await center.add(request)
        if Task.isCancelled || notificationId != identifier {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }

    func stop(cancelNotification: Bool) {
        if cancelNotification, let notificationId {
            center.removePendingNotificationRequests(withIdentifiers: [notificationId])
            center.removeDeliveredNotifications(withIdentifiers: [notificationId])
        }
        notificationId = nil
        var activities = Activity<TrainingRestActivityAttributes>.activities
        if let activity, !activities.contains(where: { $0.id == activity.id }) {
            activities.append(activity)
        }
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }

    func playCompletionHaptic() {
        HapticManager.shared.notification(type: .success)
    }
}
