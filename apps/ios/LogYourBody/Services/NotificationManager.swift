import Foundation
import UserNotifications

enum NotificationReminderKind: String, CaseIterable {
    case dailyWeighIn = "daily_weigh_in"

    var requestIdentifier: String {
        "lyb.notification.\(rawValue)"
    }
}

enum DailyReminderPolicy {
    static let defaultHour = 7
    static let defaultMinute = 0

    static func shouldShowPostPaywallPrompt(
        isSubscribed: Bool,
        hasCompletedPrompt: Bool
    ) -> Bool {
        isSubscribed && !hasCompletedPrompt
    }

    static func normalizedTime(hour: Int, minute: Int) -> (hour: Int, minute: Int) {
        (
            hour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59)
        )
    }

    static func triggerDateComponents(hour: Int, minute: Int) -> DateComponents {
        let normalized = normalizedTime(hour: hour, minute: minute)
        var components = DateComponents()
        components.hour = normalized.hour
        components.minute = normalized.minute
        return components
    }

    static func displayTime(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        let normalized = normalizedTime(hour: hour, minute: minute)
        var components = DateComponents()
        components.hour = normalized.hour
        components.minute = normalized.minute

        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", normalized.hour, normalized.minute)
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

protocol NotificationSchedulingClient {
    func notificationSettings() async -> UNNotificationSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationSchedulingClient {}

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isDailyWeighInReminderEnabled: Bool
    @Published private(set) var dailyWeighInHour: Int
    @Published private(set) var dailyWeighInMinute: Int
    @Published private(set) var hasCompletedDailyWeighInPrompt: Bool

    private let center: NotificationSchedulingClient
    private let defaults: UserDefaults

    init(
        center: NotificationSchedulingClient = UNUserNotificationCenter.current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults

        isDailyWeighInReminderEnabled = defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey)
        dailyWeighInHour = defaults.object(forKey: Constants.dailyWeighInReminderHourKey) as? Int
            ?? DailyReminderPolicy.defaultHour
        dailyWeighInMinute = defaults.object(forKey: Constants.dailyWeighInReminderMinuteKey) as? Int
            ?? DailyReminderPolicy.defaultMinute
        hasCompletedDailyWeighInPrompt = defaults.bool(forKey: Constants.dailyWeighInReminderPromptCompletedKey)

        let normalized = DailyReminderPolicy.normalizedTime(hour: dailyWeighInHour, minute: dailyWeighInMinute)
        dailyWeighInHour = normalized.hour
        dailyWeighInMinute = normalized.minute
    }

    var dailyWeighInDisplayTime: String {
        DailyReminderPolicy.displayTime(hour: dailyWeighInHour, minute: dailyWeighInMinute)
    }

    var dailyWeighInReminderDate: Date {
        let components = DailyReminderPolicy.triggerDateComponents(
            hour: dailyWeighInHour,
            minute: dailyWeighInMinute
        )
        return Calendar.current.date(from: components) ?? Date()
    }

    func shouldShowPostPaywallPrompt(isSubscribed: Bool) -> Bool {
        DailyReminderPolicy.shouldShowPostPaywallPrompt(
            isSubscribed: isSubscribed,
            hasCompletedPrompt: hasCompletedDailyWeighInPrompt
        )
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if settings.authorizationStatus == .denied, isDailyWeighInReminderEnabled {
            setDailyWeighInReminder(enabled: false)
        }
    }

    @discardableResult
    func requestDailyWeighInReminder(at date: Date) async -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return await requestDailyWeighInReminder(
            hour: components.hour ?? DailyReminderPolicy.defaultHour,
            minute: components.minute ?? DailyReminderPolicy.defaultMinute
        )
    }

    @discardableResult
    func requestDailyWeighInReminder(hour: Int, minute: Int) async -> Bool {
        markDailyWeighInPromptCompleted()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()

            guard granted else {
                setDailyWeighInReminder(enabled: false)
                return false
            }

            let normalized = DailyReminderPolicy.normalizedTime(hour: hour, minute: minute)
            setDailyWeighInReminder(enabled: true, hour: normalized.hour, minute: normalized.minute)
            try await scheduleDailyWeighInReminder(hour: normalized.hour, minute: normalized.minute)

            AnalyticsService.shared.track(
                event: "notification_permission_granted",
                properties: ["notification_type": NotificationReminderKind.dailyWeighIn.rawValue]
            )
            return true
        } catch {
            setDailyWeighInReminder(enabled: false)
            return false
        }
    }

    @discardableResult
    func setDailyWeighInReminderEnabled(_ isEnabled: Bool) async -> Bool {
        if isEnabled {
            return await requestDailyWeighInReminder(
                hour: dailyWeighInHour,
                minute: dailyWeighInMinute
            )
        }

        markDailyWeighInPromptCompleted()
        setDailyWeighInReminder(enabled: false)
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationReminderKind.dailyWeighIn.requestIdentifier]
        )
        return true
    }

    func updateDailyWeighInReminderTime(to date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let normalized = DailyReminderPolicy.normalizedTime(
            hour: components.hour ?? DailyReminderPolicy.defaultHour,
            minute: components.minute ?? DailyReminderPolicy.defaultMinute
        )
        setDailyWeighInReminder(
            enabled: isDailyWeighInReminderEnabled,
            hour: normalized.hour,
            minute: normalized.minute
        )

        guard isDailyWeighInReminderEnabled else { return }
        try? await scheduleDailyWeighInReminder(hour: normalized.hour, minute: normalized.minute)
    }

    func skipDailyWeighInPrompt() {
        markDailyWeighInPromptCompleted()
        setDailyWeighInReminder(enabled: false)
    }

    private func scheduleDailyWeighInReminder(hour: Int, minute: Int) async throws {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationReminderKind.dailyWeighIn.requestIdentifier]
        )

        let content = UNMutableNotificationContent()
        content.title = "Log today's weight"
        content.body = "A quick weigh-in keeps your body trend current."
        content.sound = .default
        content.categoryIdentifier = NotificationReminderKind.dailyWeighIn.rawValue

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DailyReminderPolicy.triggerDateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: NotificationReminderKind.dailyWeighIn.requestIdentifier,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }

    private func markDailyWeighInPromptCompleted() {
        hasCompletedDailyWeighInPrompt = true
        defaults.set(true, forKey: Constants.dailyWeighInReminderPromptCompletedKey)
    }

    private func setDailyWeighInReminder(enabled: Bool, hour: Int? = nil, minute: Int? = nil) {
        let normalized = DailyReminderPolicy.normalizedTime(
            hour: hour ?? dailyWeighInHour,
            minute: minute ?? dailyWeighInMinute
        )

        isDailyWeighInReminderEnabled = enabled
        dailyWeighInHour = normalized.hour
        dailyWeighInMinute = normalized.minute

        defaults.set(enabled, forKey: Constants.dailyWeighInReminderEnabledKey)
        defaults.set(normalized.hour, forKey: Constants.dailyWeighInReminderHourKey)
        defaults.set(normalized.minute, forKey: Constants.dailyWeighInReminderMinuteKey)
    }
}
