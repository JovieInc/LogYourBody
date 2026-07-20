//
// NotificationManagerSchedulingTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

private enum StubNotificationError: Error {
    case requestAuthorizationFailed
    case addFailed
}

/// `UNNotificationSettings` has no public initializer, so a base instance is
/// decoded from an empty keyed archive and the one property
/// `NotificationManager` reads (`authorizationStatus`) is overridden.
private final class StubNotificationSettings: UNNotificationSettings {
    private let stubStatus: UNAuthorizationStatus

    init?(status: UNAuthorizationStatus) {
        stubStatus = status
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.finishEncoding()
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else {
            return nil
        }
        super.init(coder: unarchiver)
        unarchiver.finishDecoding()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var authorizationStatus: UNAuthorizationStatus {
        stubStatus
    }
}

/// Records the exact sequence of scheduling calls so tests can assert
/// replace-vs-duplicate semantics, cancellation, and error paths.
private final class FakeNotificationSchedulingClient: NotificationSchedulingClient {
    enum Event: Equatable {
        case notificationSettings
        case requestAuthorization(options: UNAuthorizationOptions)
        case add(identifier: String)
        case removePending(identifiers: [String])
    }

    private(set) var events: [Event] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var requestAuthorizationGranted = true
    var requestAuthorizationError: Error?
    var addError: Error?

    func notificationSettings() async -> UNNotificationSettings {
        events.append(.notificationSettings)
        // The archive-decoding path above is deterministic; unwrap is confined
        // to this test fake.
        return StubNotificationSettings(status: authorizationStatus)!
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        events.append(.requestAuthorization(options: options))
        if let requestAuthorizationError {
            throw requestAuthorizationError
        }
        return requestAuthorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        events.append(.add(identifier: request.identifier))
        if let addError {
            throw addError
        }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        events.append(.removePending(identifiers: identifiers))
    }
}

/// Unit tests for `NotificationManager`'s scheduling side (the
/// `NotificationSchedulingClient` seam). `DailyReminderPolicy` value logic is
/// covered by `DailyReminderPolicyTests` and intentionally not repeated here.
@MainActor
final class NotificationManagerSchedulingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var fake: FakeNotificationSchedulingClient!
    private var manager: NotificationManager!

    private let reminderIdentifier = NotificationReminderKind.dailyWeighIn.requestIdentifier
    private let expectedOptions: UNAuthorizationOptions = [.alert, .badge, .sound]

    override func setUp() {
        super.setUp()
        suiteName = "NotificationManagerSchedulingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeNotificationSchedulingClient()
        manager = NotificationManager(center: fake, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        fake = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEnableWithGrantedAuthorizationSchedulesRepeatingDailyReminder() async throws {
        let granted = await manager.requestDailyWeighInReminder(hour: 7, minute: 30)

        XCTAssertTrue(granted)
        XCTAssertTrue(manager.isDailyWeighInReminderEnabled)
        XCTAssertEqual(manager.dailyWeighInHour, 7)
        XCTAssertEqual(manager.dailyWeighInMinute, 30)
        XCTAssertEqual(manager.authorizationStatus, .authorized)
        XCTAssertTrue(manager.hasCompletedDailyWeighInPrompt)
        XCTAssertEqual(
            fake.events,
            [
                .requestAuthorization(options: expectedOptions),
                .notificationSettings,
                .removePending(identifiers: [reminderIdentifier]),
                .add(identifier: reminderIdentifier)
            ]
        )

        let request = try XCTUnwrap(fake.addedRequests.first)
        XCTAssertEqual(request.identifier, reminderIdentifier)
        XCTAssertEqual(request.content.categoryIdentifier, NotificationReminderKind.dailyWeighIn.rawValue)
        XCTAssertFalse(request.content.title.isEmpty)
        XCTAssertFalse(request.content.body.isEmpty)
        XCTAssertNotNil(request.content.sound)

        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 7)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertTrue(trigger.repeats)
        // Only hour/minute are pinned so the trigger repeats daily.
        XCTAssertNil(trigger.dateComponents.day)
        XCTAssertNil(trigger.dateComponents.weekday)

        XCTAssertTrue(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderHourKey), 7)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderMinuteKey), 30)
    }

    func testEnableWithDeniedAuthorizationDoesNotScheduleAndDisables() async {
        fake.requestAuthorizationGranted = false
        fake.authorizationStatus = .denied

        let granted = await manager.requestDailyWeighInReminder(hour: 7, minute: 30)

        XCTAssertFalse(granted)
        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertEqual(manager.authorizationStatus, .denied)
        // Asking counts as completing the prompt even when the user declines.
        XCTAssertTrue(manager.hasCompletedDailyWeighInPrompt)
        XCTAssertEqual(
            fake.events,
            [
                .requestAuthorization(options: expectedOptions),
                .notificationSettings
            ]
        )
        XCTAssertFalse(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testEnableWhenAuthorizationRequestThrowsDisablesAndReturnsFalse() async {
        fake.requestAuthorizationError = StubNotificationError.requestAuthorizationFailed

        let granted = await manager.requestDailyWeighInReminder(hour: 7, minute: 30)

        XCTAssertFalse(granted)
        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertTrue(fake.addedRequests.isEmpty)
        XCTAssertFalse(fake.events.contains(.add(identifier: reminderIdentifier)))
        XCTAssertFalse(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testSchedulingFailureDisablesReminderAndReturnsFalse() async {
        fake.addError = StubNotificationError.addFailed

        let granted = await manager.requestDailyWeighInReminder(hour: 7, minute: 30)

        XCTAssertFalse(granted)
        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertTrue(fake.addedRequests.isEmpty)
        // The stale pending request was cleared before the failed add, so
        // nothing half-scheduled lingers after the error.
        XCTAssertEqual(
            fake.events,
            [
                .requestAuthorization(options: expectedOptions),
                .notificationSettings,
                .removePending(identifiers: [reminderIdentifier]),
                .add(identifier: reminderIdentifier)
            ]
        )
        XCTAssertFalse(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testDisableCancelsPendingRequestWithoutScheduling() async {
        let result = await manager.setDailyWeighInReminderEnabled(false)

        XCTAssertTrue(result)
        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertTrue(manager.hasCompletedDailyWeighInPrompt)
        XCTAssertEqual(fake.events, [.removePending(identifiers: [reminderIdentifier])])
        XCTAssertFalse(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testReschedulingReplacesExistingRequest() async throws {
        _ = await manager.requestDailyWeighInReminder(hour: 7, minute: 30)
        let newTime = try XCTUnwrap(Calendar.current.date(from: DateComponents(hour: 21, minute: 15)))

        await manager.updateDailyWeighInReminderTime(to: newTime)

        XCTAssertEqual(manager.dailyWeighInHour, 21)
        XCTAssertEqual(manager.dailyWeighInMinute, 15)
        XCTAssertEqual(fake.addedRequests.count, 2)
        // Every add is preceded by a remove for the same identifier: the new
        // request replaces the old one instead of stacking duplicates.
        XCTAssertEqual(
            fake.events,
            [
                .requestAuthorization(options: expectedOptions),
                .notificationSettings,
                .removePending(identifiers: [reminderIdentifier]),
                .add(identifier: reminderIdentifier),
                .removePending(identifiers: [reminderIdentifier]),
                .add(identifier: reminderIdentifier)
            ]
        )

        let latest = try XCTUnwrap(fake.addedRequests.last)
        let trigger = try XCTUnwrap(latest.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 21)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderHourKey), 21)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderMinuteKey), 15)
    }

    func testTimeUpdateWhileDisabledPersistsTimeWithoutScheduling() async throws {
        let newTime = try XCTUnwrap(Calendar.current.date(from: DateComponents(hour: 6, minute: 45)))

        await manager.updateDailyWeighInReminderTime(to: newTime)

        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertEqual(manager.dailyWeighInHour, 6)
        XCTAssertEqual(manager.dailyWeighInMinute, 45)
        XCTAssertTrue(fake.events.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderHourKey), 6)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderMinuteKey), 45)
    }

    func testRefreshAuthorizationStatusDisablesEnabledReminderWhenDenied() async {
        defaults.set(true, forKey: Constants.dailyWeighInReminderEnabledKey)
        manager = NotificationManager(center: fake, defaults: defaults)
        XCTAssertTrue(manager.isDailyWeighInReminderEnabled)
        fake.authorizationStatus = .denied

        await manager.refreshAuthorizationStatus()

        XCTAssertEqual(manager.authorizationStatus, .denied)
        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertFalse(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testRefreshAuthorizationStatusKeepsEnabledReminderWhenAuthorized() async {
        defaults.set(true, forKey: Constants.dailyWeighInReminderEnabledKey)
        manager = NotificationManager(center: fake, defaults: defaults)
        fake.authorizationStatus = .authorized

        await manager.refreshAuthorizationStatus()

        XCTAssertEqual(manager.authorizationStatus, .authorized)
        XCTAssertTrue(manager.isDailyWeighInReminderEnabled)
        XCTAssertTrue(defaults.bool(forKey: Constants.dailyWeighInReminderEnabledKey))
    }

    func testRequestNormalizesOutOfRangeTimeBeforeScheduling() async throws {
        let granted = await manager.requestDailyWeighInReminder(hour: 25, minute: 90)

        XCTAssertTrue(granted)
        XCTAssertEqual(manager.dailyWeighInHour, 23)
        XCTAssertEqual(manager.dailyWeighInMinute, 59)
        let request = try XCTUnwrap(fake.addedRequests.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 23)
        XCTAssertEqual(trigger.dateComponents.minute, 59)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderHourKey), 23)
        XCTAssertEqual(defaults.integer(forKey: Constants.dailyWeighInReminderMinuteKey), 59)
    }

    func testSkipPromptDisablesReminderWithoutSchedulerCalls() {
        manager.skipDailyWeighInPrompt()

        XCTAssertFalse(manager.isDailyWeighInReminderEnabled)
        XCTAssertTrue(manager.hasCompletedDailyWeighInPrompt)
        XCTAssertTrue(fake.events.isEmpty)
    }

    func testEnabledReminderStatePersistsAcrossManagerInstances() async {
        _ = await manager.requestDailyWeighInReminder(hour: 8, minute: 5)

        let reloaded = NotificationManager(center: fake, defaults: defaults)

        XCTAssertTrue(reloaded.isDailyWeighInReminderEnabled)
        XCTAssertEqual(reloaded.dailyWeighInHour, 8)
        XCTAssertEqual(reloaded.dailyWeighInMinute, 5)
        XCTAssertTrue(reloaded.hasCompletedDailyWeighInPrompt)
    }
}
