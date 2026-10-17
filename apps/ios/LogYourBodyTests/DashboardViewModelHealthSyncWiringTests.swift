//
// HealthSyncPipelineTests.swift
// LogYourBodyTests
//
import XCTest
import Combine
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


@MainActor
final class DashboardViewModelHealthSyncWiringTests: XCTestCase {
    func testNewestRefreshPreservesLoadedHistoryAndIncludesNewMeasurement() async throws {
        let userId = "dashboard_history_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "history@example.com", name: "History",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        authManager.authSession = .localFixture(subject: userId, email: "history@example.com")
        let viewModel = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        let now = Date()
        for index in 0..<5 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: now.addingTimeInterval(Double(index) * 86_400))
        }
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        XCTAssertEqual(viewModel.bodyMetrics.count, 5)
        try await saveHistoryMetric(userId: userId, index: 5,
                                    date: now.addingTimeInterval(5 * 86_400))

        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)

        XCTAssertEqual(viewModel.bodyMetrics.count, 6, "A refresh must not collapse loaded history")
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.count, 6)
        XCTAssertEqual(viewModel.bodyMetrics.first?.id, "\(userId)_5")
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.first?.id, "\(userId)_0")
    }

    func testNewestRefreshReconcilesDeletionAndUserChange() async throws {
        let userId = "dashboard_reconcile_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "history@example.com", name: "History",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        authManager.authSession = .localFixture(subject: userId, email: "history@example.com")
        let viewModel = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        for index in 0..<3 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: Date().addingTimeInterval(Double(index) * 86_400))
        }
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        let deleted = await CoreDataManager.shared.markBodyMetricDeleted(id: "\(userId)_0", userId: userId)
        XCTAssertTrue(deleted)
        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        XCTAssertEqual(Set(viewModel.bodyMetrics.map(\.id)), Set(["\(userId)_1", "\(userId)_2"]))

        let otherId = "dashboard_other_\(UUID().uuidString)"
        try await saveHistoryMetric(userId: otherId, index: 0, date: Date())
        authManager.currentUser = LocalUser(
            id: otherId, email: "other@example.com", name: "Other",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        authManager.authSession = .localFixture(subject: otherId, email: "other@example.com")
        await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        XCTAssertEqual(viewModel.bodyMetrics.map(\.id), ["\(otherId)_0"])
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.map(\.userId), [otherId])
    }

    func testSuspendedFirstPaintCannotOverwriteCompletedHistory() async throws {
        let userId = "dashboard_overlap_\(UUID().uuidString)"
        let authManager = AuthManager()
        authManager.currentUser = LocalUser(
            id: userId, email: "overlap@example.com", name: "Overlap",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        authManager.authSession = .localFixture(subject: userId, email: "overlap@example.com")
        for index in 0..<3 {
            try await saveHistoryMetric(userId: userId, index: index,
                                        date: Date().addingTimeInterval(Double(index) * 86_400))
        }
        let fetchStarted = expectation(description: "First-paint fetch suspended")
        var pendingFetch: CheckedContinuation<BodyMetrics?, Never>?
        let viewModel = DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(),
            latestMetricLoader: { _ in
                await withCheckedContinuation { continuation in
                    pendingFetch = continuation
                    fetchStarted.fulfill()
                }
            }
        )
        let initialLoad = Task {
            await viewModel.loadData(authManager: authManager, loadOnlyNewest: true, selectedIndex: 0)
        }
        await fulfillment(of: [fetchStarted], timeout: 3)
        await viewModel.loadData(authManager: authManager, selectedIndex: 0)
        pendingFetch?.resume(returning: viewModel.bodyMetrics.first)
        await awaitDashboardTask(initialLoad)
        XCTAssertEqual(viewModel.bodyMetrics.count, 3)
        XCTAssertEqual(viewModel.sortedBodyMetricsAscending.count, 3)
    }

    private func saveHistoryMetric(userId: String, index: Int, date: Date) async throws {
        let metric = BodyMetrics(
            id: "\(userId)_\(index)", userId: userId, date: date,
            weight: 82 + Double(index), weightUnit: "kg", bodyFatPercentage: 16,
            bodyFatMethod: "manual", muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: "manual", createdAt: date, updatedAt: date
        )
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: true)
    }

    func testCanInitializeWithMockHealthSyncCoordinator() {
        let viewModel = DashboardViewModel(
            healthKitManager: HealthKitManager.shared,
            healthSyncCoordinator: MockHealthSyncCoordinator()
        )

        XCTAssertNotNil(viewModel)
    }

    func testRefreshSkipsHealthKitSyncWhenDeniedAndKeepsLocalMetrics() async throws {
        let userId = "dashboard_healthkit_denied_\(UUID().uuidString)"
        let user = LocalUser(
            id: userId,
            email: "hk_denied@example.com",
            name: "HealthKit Denied",
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: true
        )
        let authManager = AuthManager()
        authManager.currentUser = user
        authManager.authSession = .localFixture(
            subject: userId,
            email: "hk_denied@example.com",
            name: "HealthKit Denied"
        )

        let localMetric = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            weight: 82.1,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: "manual still works",
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        CoreDataManager.shared.saveBodyMetrics(localMetric, userId: userId, markAsSynced: false)

        let healthKitManager = HealthKitManager.shared
        healthKitManager.isAuthorized = false
        let mockCoordinator = MockHealthSyncCoordinator()
        let viewModel = DashboardViewModel(
            healthKitManager: healthKitManager,
            healthSyncCoordinator: mockCoordinator
        )

        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: RealtimeSyncManager.shared
        )

        XCTAssertFalse(mockCoordinator.didCallSyncWeightFromHealthKit)
        XCTAssertTrue(viewModel.hasLoadedInitialData)
        XCTAssertEqual(viewModel.bodyMetrics.first?.id, localMetric.id)
        XCTAssertEqual(viewModel.bodyMetrics.first?.dataSource, "manual")
    }
    func testHeldLatestLoadCannotPublishAcrossOwnerOrGenerationReplacement() async throws {
        for sameSubject in [false, true] {
            let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
            let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
            defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
            let auth = AuthManager(userDefaults: authDefaults)
            let subject = "dashboard_held_\(UUID().uuidString)"
            installDashboardSession(auth, subject: subject)
            try await seedDashboardDay(subject: subject, steps: 100)
            try await saveHistoryMetric(userId: subject, index: 0, date: Date())
            let oldCached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
            let oldRow = try XCTUnwrap(oldCached?.toBodyMetrics())
            let held = HeldDashboardRead<BodyMetrics?>()
            let vm = DashboardViewModel(
                healthSyncCoordinator: MockHealthSyncCoordinator(), latestMetricLoader: { _ in await held.read() }
            )
            let task = Task { await vm.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0) }
            defer { task.cancel(); held.resumeIfWaiting(returning: oldRow) }
            await fulfillment(of: [held.started], timeout: 3)
            XCTAssertFalse(vm.hasLoadedInitialData)
            let replacement = sameSubject ? subject : "dashboard_replacement_\(UUID().uuidString)"
            installDashboardSession(auth, subject: replacement)
            XCTAssertFalse(vm.hasCurrentPublication(for: auth), "Receipt accessor revokes without waiting for a reader")
            try await seedDashboardDay(subject: replacement, steps: 222)
            try await saveHistoryMetric(userId: replacement, index: 1, date: Date())
            await vm.loadData(authManager: auth, selectedIndex: 0)
            let admittedIDs = vm.bodyMetrics.map(\.id)
            let admittedRecent = try dailySnapshot(vm.recentDailyMetrics)
            held.resumeIfWaiting(returning: oldRow)
            await awaitDashboardTask(task)
            XCTAssertEqual(vm.bodyMetrics.map(\.id), admittedIDs)
            XCTAssertEqual(vm.sortedBodyMetricsAscending.map(\.id), Array(admittedIDs.reversed()))
            XCTAssertEqual(vm.dailyMetrics?.steps, 222)
            XCTAssertEqual(try dailySnapshot(vm.recentDailyMetrics), admittedRecent)
            XCTAssertTrue(vm.hasCurrentPublication(for: auth))
            XCTAssertTrue(vm.hasLoadedInitialData)
            XCTAssertFalse(vm.isSyncingData)
            XCTAssertNil(vm.lastRefreshDate)
        }
    }

    func testCancelledHeldLoadCannotPublishAndCurrentOwnerCanRecover() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_cancelled_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await seedDashboardDay(subject: subject, steps: 345)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
        let row = try XCTUnwrap(cached?.toBodyMetrics())
        let held = HeldDashboardRead<BodyMetrics?>()
        let vm = DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(), latestMetricLoader: { _ in await held.read() }
        )
        let task = Task { await vm.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0) }
        defer { task.cancel(); held.resumeIfWaiting(returning: row) }
        await fulfillment(of: [held.started], timeout: 3)
        task.cancel()
        held.resumeIfWaiting(returning: row)
        await awaitDashboardTask(task)
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertTrue(vm.sortedBodyMetricsAscending.isEmpty)
        XCTAssertNil(vm.dailyMetrics)
        XCTAssertTrue(vm.recentDailyMetrics.isEmpty)
        XCTAssertFalse(vm.hasLoadedInitialData)
        XCTAssertFalse(vm.isSyncingData)
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertEqual(vm.bodyMetrics.map(\.id), [row.id])
        XCTAssertEqual(vm.dailyMetrics?.steps, 345)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
    }

    func testNewerSameOwnerLoadKeepsDailyTailWhenOlderLatestReturns() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_revision_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await seedDashboardDay(subject: subject, steps: 111)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
        let row = try XCTUnwrap(cached?.toBodyMetrics())
        let held = HeldDashboardRead<BodyMetrics?>()
        let vm = DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(), latestMetricLoader: { _ in await held.read() }
        )
        let old = Task { await vm.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0) }
        defer { old.cancel(); held.resumeIfWaiting(returning: row) }
        await fulfillment(of: [held.started], timeout: 3)
        try await seedDashboardDay(subject: subject, steps: 999)
        try await saveHistoryMetric(userId: subject, index: 1, date: Date().addingTimeInterval(60))
        await vm.loadData(authManager: auth, selectedIndex: 0)
        let currentRows = vm.bodyMetrics
        let currentRecent = try dailySnapshot(vm.recentDailyMetrics)
        held.resumeIfWaiting(returning: row)
        await awaitDashboardTask(old)
        XCTAssertEqual(vm.bodyMetrics, currentRows)
        XCTAssertEqual(vm.sortedBodyMetricsAscending, currentRows.sorted { $0.date < $1.date })
        XCTAssertEqual(vm.dailyMetrics?.steps, 999)
        XCTAssertEqual(try dailySnapshot(vm.recentDailyMetrics), currentRecent)
        XCTAssertTrue(vm.hasLoadedInitialData)
    }

    func testPublishedLifetimeClearsWithoutHeldReaderReturning() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_clear_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await seedDashboardDay(subject: subject, steps: 777)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        let health = HealthKitManager.shared
        let wasAuthorized = health.isAuthorized
        let sync = makeDashboardSync(auth: auth)
        let wasOnline = sync.isOnline
        defer { health.isAuthorized = wasAuthorized; sync.isOnline = wasOnline }
        health.isAuthorized = true
        sync.isOnline = false
        let coordinator = HeldDashboardSyncCoordinator()
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, todayStepCountLoader: { 0 },
            dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertFalse(vm.bodyMetrics.isEmpty)
        let heldRefresh = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { heldRefresh.cancel(); coordinator.held.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        XCTAssertTrue(vm.isSyncingData)
        let cleared = expectation(description: "Old publication clears while actual coordinator remains held")
        var fulfilled = false
        let subscription = vm.$recentDailyMetrics.dropFirst().sink { rows in
            if rows.isEmpty, !fulfilled { fulfilled = true; cleared.fulfill() }
        }
        installDashboardSession(auth, subject: subject)
        XCTAssertFalse(vm.hasCurrentPublication(for: auth), "Synchronous accessor rejects original receipt before deferred clear")
        await fulfillment(of: [cleared], timeout: 3)
        withExtendedLifetime(subscription) {}
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertTrue(vm.sortedBodyMetricsAscending.isEmpty)
        XCTAssertNil(vm.dailyMetrics)
        XCTAssertTrue(vm.recentDailyMetrics.isEmpty)
        XCTAssertFalse(vm.hasLoadedInitialData)
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNil(vm.lastRefreshDate)
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(heldRefresh)
        XCTAssertTrue(vm.bodyMetrics.isEmpty, "Released stale coordinator must not republish")
    }

    func testNilOwnerAndOwnedEmptyLoadHaveDifferentCompletionSemantics() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let vm = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertTrue(vm.hasLoadedInitialData)
        XCTAssertFalse(vm.hasCurrentPublication(for: auth))
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertNil(vm.dailyMetrics)
        XCTAssertFalse(vm.isSyncingData)
        installDashboardSession(auth, subject: "dashboard_empty_\(UUID().uuidString)")
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertTrue(vm.hasLoadedInitialData)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth), "An admitted empty result is a completed owned load")
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertTrue(vm.sortedBodyMetricsAscending.isEmpty)
        XCTAssertTrue(vm.recentDailyMetrics.isEmpty)
        XCTAssertNil(vm.dailyMetrics)
        XCTAssertNil(vm.lastRefreshDate)
        XCTAssertFalse(vm.isSyncingData)
    }

    func testQueuedNilCaptureCannotRebaseOrClearNewerHeldRefresh() async throws {
        let defaultsName = "dashboard_nil_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let auth = AuthManager(userDefaults: defaults)
        let capturedNil = auth.captureAccountSession()
        XCTAssertNil(capturedNil)
        let health = HealthKitManager.shared
        let sync = makeDashboardSync(auth: auth)
        let wasAuthorized = health.isAuthorized
        let wasOnline = sync.isOnline
        defer { health.isAuthorized = wasAuthorized; sync.isOnline = wasOnline }
        health.isAuthorized = true
        sync.isOnline = false
        let coordinator = HeldDashboardSyncCoordinator()
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, todayStepCountLoader: { 0 },
            dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        let queued = HeldDashboardRead<Void>()
        let oldTask = Task {
            await queued.read()
            await vm.loadDataForCapturedSession(
                capturedNil, authManager: auth, loadOnlyNewest: true, selectedIndex: 0
            )
        }
        defer { oldTask.cancel(); queued.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [queued.started], timeout: 3)
        let subject = "dashboard_nil_owner_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        await vm.loadData(authManager: auth, selectedIndex: 0)
        let originalRows = vm.bodyMetrics
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let newer = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { newer.cancel(); coordinator.held.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        XCTAssertTrue(vm.isSyncingData)
        queued.resumeIfWaiting(returning: ())
        await awaitDashboardTask(oldTask)
        XCTAssertTrue(vm.isSyncingData, "Captured nil cannot finalize a newer owner's held request")
        XCTAssertEqual(vm.bodyMetrics, originalRows)
        XCTAssertEqual(vm.publicationOwnership, ownership)
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(newer)
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
    }

    func testActualStartupPaintsLatestBeforeHeldCoordinatorAndThenLoadsHistory() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_startup_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        for index in 0..<3 {
            try await saveHistoryMetric(
                userId: subject, index: index, date: Date().addingTimeInterval(Double(index) * 60)
            )
        }
        let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
        let newest = try XCTUnwrap(cached?.toBodyMetrics())
        let coordinator = HeldDashboardSyncCoordinator()
        let latest = HeldDashboardRead<BodyMetrics?>()
        let health = HealthKitManager.shared
        let sync = makeDashboardSync(auth: auth)
        let wasAuthorized = health.isAuthorized
        let wasOnline = sync.isOnline
        defer { health.isAuthorized = wasAuthorized; sync.isOnline = wasOnline }
        health.isAuthorized = true
        sync.isOnline = false
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, latestMetricLoader: { _ in await latest.read() },
            todayStepCountLoader: { 0 }, dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let startup = Task {
            await vm.loadInitialDataAndRefresh(
                for: ownership, authManager: auth, realtimeSyncManager: sync,
                loadOnlyNewest: true, selectedIndex: 0
            )
        }
        defer { startup.cancel(); latest.resumeIfWaiting(returning: newest); coordinator.held.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [latest.started], timeout: 3)
        XCTAssertFalse(vm.hasLoadedInitialData)
        latest.resumeIfWaiting(returning: newest)
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        XCTAssertEqual(vm.bodyMetrics, [newest], "Actual caller paints latest before coordinator returns")
        XCTAssertEqual(vm.sortedBodyMetricsAscending, [newest])
        XCTAssertEqual(vm.publicationOwnership, ownership)
        XCTAssertTrue(vm.hasLoadedInitialData)
        XCTAssertTrue(vm.isSyncingData)
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(startup)
        XCTAssertEqual(vm.bodyMetrics.count, 3)
        XCTAssertEqual(vm.sortedBodyMetricsAscending.count, 3)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNotNil(vm.lastRefreshDate)
    }

    func testSupersededStartupCannotReplaceNewerSameOwnerHeldRefresh() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_startup_newer_refresh_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
        let newest = try XCTUnwrap(cached?.toBodyMetrics())
        let latest = HeldDashboardRead<BodyMetrics?>()
        let coordinator = HeldDashboardSyncCoordinator()
        let health = HealthKitManager.shared
        let wasAuthorized = health.isAuthorized
        defer { health.isAuthorized = wasAuthorized }
        health.isAuthorized = true
        let sync = makeDashboardSync(auth: auth)
        var latestCalls = 0
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, latestMetricLoader: { userId in
                latestCalls += 1
                if latestCalls == 1 { return await latest.read() }
                return await CoreDataManager.shared.fetchLatestBodyMetric(for: userId)?.toBodyMetrics()
            },
            todayStepCountLoader: { 0 }, dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let old = Task {
            await vm.loadInitialDataAndRefresh(
                for: ownership, authManager: auth, realtimeSyncManager: sync,
                loadOnlyNewest: true, selectedIndex: 0
            )
        }
        defer {
            old.cancel()
            latest.resumeIfWaiting(returning: newest)
            coordinator.held.resumeIfWaiting(returning: ())
            coordinator.next.resumeIfWaiting(returning: ())
        }
        await fulfillment(of: [latest.started], timeout: 3)
        let newer = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { newer.cancel() }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        XCTAssertTrue(vm.isSyncingData)
        latest.resumeIfWaiting(returning: newest)
        await awaitDashboardTask(old)
        XCTAssertEqual(coordinator.weightCalls, 1, "Old startup must not enter a successor coordinator")
        XCTAssertTrue(vm.isSyncingData, "Old startup must not cancel or finish newer held refresh")
        XCTAssertNil(vm.lastRefreshDate)
        XCTAssertTrue(vm.bodyMetrics.isEmpty, "Rejected old latest read cannot publish")
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(newer, timeout: 5)
        XCTAssertEqual(vm.bodyMetrics, [newest])
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNotNil(vm.lastRefreshDate)
        XCTAssertEqual(coordinator.weightCalls, 1)
        XCTAssertEqual(latestCalls, 2, "Recovery uses the actual latest-reader port after the rejected held read")
        if let history = vm.pendingHistoricalLoadForTests() {
            history.cancel()
            await awaitDashboardTask(history)
        }
    }

    func testSupersededStartupCannotRestartAfterNewerSameOwnerLoadCompletes() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_startup_newer_load_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        for index in 0..<3 {
            try await saveHistoryMetric(
                userId: subject, index: index, date: Date().addingTimeInterval(Double(index) * 60)
            )
        }
        let cached = await CoreDataManager.shared.fetchLatestBodyMetric(for: subject)
        let newest = try XCTUnwrap(cached?.toBodyMetrics())
        let latest = HeldDashboardRead<BodyMetrics?>()
        let coordinator = HeldDashboardSyncCoordinator()
        let health = HealthKitManager.shared
        let wasAuthorized = health.isAuthorized
        defer { health.isAuthorized = wasAuthorized }
        health.isAuthorized = true
        let sync = makeDashboardSync(auth: auth)
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, latestMetricLoader: { _ in await latest.read() },
            todayStepCountLoader: { 0 }, dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let old = Task {
            await vm.loadInitialDataAndRefresh(
                for: ownership, authManager: auth, realtimeSyncManager: sync,
                loadOnlyNewest: true, selectedIndex: 0
            )
        }
        defer {
            old.cancel()
            latest.resumeIfWaiting(returning: newest)
            coordinator.held.resumeIfWaiting(returning: ())
            coordinator.next.resumeIfWaiting(returning: ())
        }
        await fulfillment(of: [latest.started], timeout: 3)
        await vm.loadData(authManager: auth, selectedIndex: 0)
        let currentRows = vm.bodyMetrics
        XCTAssertEqual(currentRows.count, 3)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        latest.resumeIfWaiting(returning: newest)
        await awaitDashboardTask(old)
        XCTAssertEqual(coordinator.weightCalls, 0, "Superseded completed startup must not restart refresh")
        XCTAssertEqual(vm.bodyMetrics, currentRows)
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNil(vm.lastRefreshDate)
        let recovery = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { recovery.cancel() }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(recovery, timeout: 5)
        XCTAssertEqual(vm.bodyMetrics, currentRows)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNotNil(vm.lastRefreshDate)
        XCTAssertEqual(coordinator.weightCalls, 1)
    }

    func testSameLifetimeProfilePublicationPreservesHeldRequest() async throws {
        let defaultsName = "dashboard_profile_event_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let auth = AuthManager(userDefaults: defaults)
        let subject = "dashboard_profile_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        let ownership = try XCTUnwrap(auth.captureAccountSession())
        let latest = HeldDashboardRead<BodyMetrics?>()
        let vm = DashboardViewModel(
            healthSyncCoordinator: MockHealthSyncCoordinator(), latestMetricLoader: { _ in await latest.read() }
        )
        let task = Task {
            await vm.loadDataForCapturedSession(
                ownership, authManager: auth, loadOnlyNewest: true, selectedIndex: 0
            )
        }
        defer { task.cancel(); latest.resumeIfWaiting(returning: nil); vm.onAccountObservationForTests = nil }
        await fulfillment(of: [latest.started], timeout: 3)
        let observed = expectation(description: "Actual deferred VM account observer processed same-lifetime profile event")
        vm.onAccountObservationForTests = { observed.fulfill() }
        auth.currentUser = LocalUser(
            id: subject, email: "dashboard@example.invalid", name: "Updated profile",
            avatarUrl: nil, profile: nil, onboardingCompleted: true
        )
        XCTAssertEqual(auth.captureAccountSession(), ownership)
        await fulfillment(of: [observed], timeout: 3)
        XCTAssertFalse(vm.hasLoadedInitialData)
        latest.resumeIfWaiting(returning: nil)
        await awaitDashboardTask(task)
        XCTAssertEqual(vm.publicationOwnership, ownership)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertTrue(vm.hasLoadedInitialData)
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertNil(vm.pendingHistoricalLoadForTests())
        // This is an actual Published profile event, NOT token-rotation or credential persistence proof.
    }

    func testActualPublishedPayloadsCarryReceiptBeforeStoredGetterChanges() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_emission_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        let original = try XCTUnwrap(auth.captureAccountSession())
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        try await seedDashboardDay(subject: subject, steps: 321)
        let vm = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        var bodyEvents: [([BodyMetrics], AuthManager.ProfileSessionOwnership?)] = []
        var sortedEvents: [([BodyMetrics], AuthManager.ProfileSessionOwnership?)] = []
        var dayEvents: [(DailyMetrics?, AuthManager.ProfileSessionOwnership?)] = []
        var recentEvents: [([DailyMetrics], AuthManager.ProfileSessionOwnership?)] = []
        var sawPayloadBeforeStoredBody = false
        let subscriptions = [
            vm.$bodyMetrics.dropFirst().sink {
                bodyEvents.append(($0, vm.publicationOwnership))
                if !$0.isEmpty, vm.bodyMetrics.isEmpty { sawPayloadBeforeStoredBody = true }
            },
            vm.$sortedBodyMetricsAscending.dropFirst().sink { sortedEvents.append(($0, vm.publicationOwnership)) },
            vm.$dailyMetrics.dropFirst().sink { dayEvents.append(($0, vm.publicationOwnership)) },
            vm.$recentDailyMetrics.dropFirst().sink { recentEvents.append(($0, vm.publicationOwnership)) }
        ]
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertTrue(sawPayloadBeforeStoredBody, "The emitted payload is authoritative during willSet")
        XCTAssertEqual(bodyEvents.last?.1, original)
        XCTAssertEqual(sortedEvents.last?.1, original)
        XCTAssertEqual(dayEvents.last?.1, original)
        XCTAssertEqual(recentEvents.last?.1, original)
        XCTAssertEqual(bodyEvents.last?.0.first?.userId, subject)
        XCTAssertEqual(sortedEvents.last?.0.first?.userId, subject)
        XCTAssertEqual(dayEvents.last?.0?.userId, subject)
        XCTAssertEqual(recentEvents.last?.0.first?.userId, subject)
        auth.authSession = nil
        auth.currentUser = nil
        XCTAssertFalse(vm.hasCurrentPublication(for: auth))
        await vm.loadData(authManager: auth, selectedIndex: 0)
        XCTAssertNil(bodyEvents.last?.1)
        XCTAssertNil(sortedEvents.last?.1)
        XCTAssertNil(dayEvents.last?.1)
        XCTAssertNil(recentEvents.last?.1)
        XCTAssertTrue(bodyEvents.last?.0.isEmpty ?? false)
        XCTAssertTrue(sortedEvents.last?.0.isEmpty ?? false)
        XCTAssertNil(dayEvents.last?.0)
        XCTAssertTrue(recentEvents.last?.0.isEmpty ?? false)
        withExtendedLifetime(subscriptions) {}
    }

    func testCoordinatorErrorStillCompletesOwnedLocalRefreshWithoutStuckSpinner() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_error_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        try await seedDashboardDay(subject: subject, steps: 456)
        let health = HealthKitManager.shared
        let sync = makeDashboardSync(auth: auth)
        let wasAuthorized = health.isAuthorized
        let wasOnline = sync.isOnline
        defer { health.isAuthorized = wasAuthorized; sync.isOnline = wasOnline }
        health.isAuthorized = true
        sync.isOnline = false
        let coordinator = MockHealthSyncCoordinator()
        coordinator.syncWeightError = URLError(.cannotFindHost)
        let vm = DashboardViewModel(healthSyncCoordinator: coordinator)
        let task = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { task.cancel() }
        await awaitDashboardTask(task)
        XCTAssertTrue(coordinator.didCallSyncWeightFromHealthKit)
        XCTAssertEqual(vm.bodyMetrics.map(\.id), [subject + "_0"])
        XCTAssertEqual(vm.dailyMetrics?.steps, 456)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertTrue(vm.hasLoadedInitialData)
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNotNil(vm.lastRefreshDate)
    }

    func testHistoricalTaskUsesOriginalLifetimeAndCurrentOwnerRecovers() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_history_lifetime_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        for index in 0..<3 {
            try await saveHistoryMetric(userId: subject, index: index,
                                        date: Date().addingTimeInterval(Double(index) * 60))
        }
        let vm = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        await vm.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0)
        XCTAssertEqual(vm.bodyMetrics.count, 1, "Keep actual latest-only first paint")
        let oldHistory = try XCTUnwrap(vm.pendingHistoricalLoadForTests())
        let cleared = expectation(description: "Same subject new generation revokes old history")
        var fulfilled = false
        let subscription = vm.$bodyMetrics.dropFirst().sink { rows in
            if rows.isEmpty, !fulfilled { fulfilled = true; cleared.fulfill() }
        }
        installDashboardSession(auth, subject: subject)
        await fulfillment(of: [cleared], timeout: 3)
        withExtendedLifetime(subscription) {}
        await awaitDashboardTask(oldHistory)
        XCTAssertTrue(vm.bodyMetrics.isEmpty)
        XCTAssertNil(vm.pendingHistoricalLoadForTests())
        await vm.loadData(authManager: auth, loadOnlyNewest: true, selectedIndex: 0)
        let currentHistory = try XCTUnwrap(vm.pendingHistoricalLoadForTests())
        await awaitDashboardTask(currentHistory, timeout: 5)
        XCTAssertEqual(vm.bodyMetrics.count, 3)
        XCTAssertEqual(vm.sortedBodyMetricsAscending.count, 3)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertNil(vm.pendingHistoricalLoadForTests())
    }

    func testOlderHeldRefreshCannotClearNewerRefreshTerminalState() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let subject = "dashboard_refresh_revision_\(UUID().uuidString)"
        installDashboardSession(auth, subject: subject)
        try await saveHistoryMetric(userId: subject, index: 0, date: Date())
        let health = HealthKitManager.shared
        let wasAuthorized = health.isAuthorized
        let sync = makeDashboardSync(auth: auth)
        let wasOnline = sync.isOnline
        defer { health.isAuthorized = wasAuthorized; sync.isOnline = wasOnline }
        sync.isOnline = false
        health.isAuthorized = true
        let coordinator = HeldDashboardSyncCoordinator()
        let vm = DashboardViewModel(
            healthSyncCoordinator: coordinator, todayStepCountLoader: { 0 },
            dailyStepWriter: { _, admission in try admission() }, stepSyncTrigger: {}
        )
        let old = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { old.cancel(); coordinator.held.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        let newer = Task { await vm.refreshData(authManager: auth, realtimeSyncManager: sync) }
        defer { newer.cancel(); coordinator.next.resumeIfWaiting(returning: ()) }
        await fulfillment(of: [coordinator.next.started], timeout: 3)
        coordinator.held.resumeIfWaiting(returning: ())
        await awaitDashboardTask(old)
        XCTAssertTrue(vm.isSyncingData, "Old finalizer must not clear newer held request's spinner")
        coordinator.next.resumeIfWaiting(returning: ())
        await awaitDashboardTask(newer, timeout: 5)
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNotNil(vm.lastRefreshDate)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
    }


    func testStaleExplicitRefreshReceiptCannotInvalidateCurrentPublication() async throws {
        let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
        let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
        defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
        let auth = AuthManager(userDefaults: authDefaults)
        let first = "dashboard_original_\(UUID().uuidString)"
        installDashboardSession(auth, subject: first)
        let original = try XCTUnwrap(auth.captureAccountSession())
        let current = "dashboard_current_\(UUID().uuidString)"
        installDashboardSession(auth, subject: current)
        try await seedDashboardDay(subject: current, steps: 456)
        try await saveHistoryMetric(userId: current, index: 0, date: Date())
        let vm = DashboardViewModel(healthSyncCoordinator: MockHealthSyncCoordinator())
        await vm.loadData(authManager: auth, selectedIndex: 0)
        let before = vm.bodyMetrics
        let beforeDaily = try dailySnapshot(vm.recentDailyMetrics)
        await vm.refreshData(
            authManager: auth, realtimeSyncManager: RealtimeSyncManager.shared, expectedOwnership: original
        )
        XCTAssertEqual(vm.bodyMetrics, before)
        XCTAssertEqual(try dailySnapshot(vm.recentDailyMetrics), beforeDaily)
        XCTAssertEqual(vm.dailyMetrics?.steps, 456)
        XCTAssertTrue(vm.hasCurrentPublication(for: auth))
        XCTAssertFalse(vm.isSyncingData)
        XCTAssertNil(vm.lastRefreshDate)
    }


    func testHeldRefreshCannotAdoptReplacementOrFinishAfterCancellation() async throws {
        let health = HealthKitManager.shared
        let wasAuthorized = health.isAuthorized
        defer { health.isAuthorized = wasAuthorized }
        health.isAuthorized = true
        for scenario in ["foreign", "same-subject", "logout", "cancel"] {
            let authDefaultsName = "dashboard_auth_fixture_\(UUID().uuidString)"
            let authDefaults = try XCTUnwrap(UserDefaults(suiteName: authDefaultsName))
            defer { authDefaults.removePersistentDomain(forName: authDefaultsName) }
            let auth = AuthManager(userDefaults: authDefaults)
            let sync = makeDashboardSync(auth: auth)
            let subject = "dashboard_refresh_\(UUID().uuidString)"
            installDashboardSession(auth, subject: subject)
            let original = try XCTUnwrap(auth.captureAccountSession())
            let coordinator = HeldDashboardSyncCoordinator()
            var admittedSteps = 0
            var syncs = 0
            let vm = DashboardViewModel(
                healthSyncCoordinator: coordinator, todayStepCountLoader: { 0 },
                dailyStepWriter: { _, admission in try admission(); admittedSteps += 1 },
                stepSyncTrigger: { syncs += 1 }
            )
            let task = Task {
                await vm.refreshData(authManager: auth, realtimeSyncManager: sync, expectedOwnership: original)
            }
            defer { task.cancel(); coordinator.held.resumeIfWaiting(returning: ()) }
            await fulfillment(of: [coordinator.held.started], timeout: 3)
            switch scenario {
            case "foreign": installDashboardSession(auth, subject: "dashboard_foreign_\(UUID().uuidString)")
            case "same-subject": installDashboardSession(auth, subject: subject)
            case "logout": auth.authSession = nil; auth.currentUser = nil
            default: task.cancel()
            }
            coordinator.held.resumeIfWaiting(returning: ())
            await awaitDashboardTask(task)
            XCTAssertEqual(admittedSteps, 0, scenario)
            XCTAssertEqual(syncs, 0, scenario)
            XCTAssertTrue(vm.bodyMetrics.isEmpty, scenario)
            XCTAssertTrue(vm.sortedBodyMetricsAscending.isEmpty, scenario)
            XCTAssertNil(vm.dailyMetrics, scenario)
            XCTAssertTrue(vm.recentDailyMetrics.isEmpty, scenario)
            XCTAssertFalse(vm.isSyncingData, scenario)
            XCTAssertNil(vm.lastRefreshDate, scenario)
        }
    }


    func testSupersededRefreshMissingStepsCannotFinishNewerSameOwnerRefresh() async throws {
        let fixture = try makeCombinedStepFixture()
        let coordinator = HeldDashboardSyncCoordinator()
        let heldSteps = HeldDashboardRead<Int?>()
        fixture.releases = [
            { heldSteps.resumeIfWaiting(returning: nil) },
            { coordinator.held.resumeIfWaiting(returning: ()) },
            { coordinator.next.resumeIfWaiting(returning: ()) }
        ]
        let vm = DashboardViewModel(
            healthKitManager: fixture.health, healthSyncCoordinator: coordinator,
            todayStepCountLoader: {
                guard !fixture.disarmed else { throw CancellationError() }
                return await heldSteps.read()
            },
            dailyStepLoader: { owner, date in
                await fixture.store.fetchDailyMetrics(for: owner, date: date)?.toDailyMetrics()
            },
            dailyStepWriter: { _, _ in
                fixture.writes += 1
                XCTFail("Missing steps must never reach a writer")
            },
            stepSyncTrigger: { fixture.syncs += 1 }
        )
        fixture.subscriptions.append(vm.$dailyMetrics.dropFirst().sink { _ in fixture.publications += 1 })
        let old = fixture.launch {
            await vm.refreshData(authManager: fixture.auth, realtimeSyncManager: fixture.sync)
        }
        await fulfillment(of: [coordinator.held.started], timeout: 3)
        coordinator.held.resumeIfWaiting(returning: ())
        await fulfillment(of: [heldSteps.started], timeout: 3)
        let newer = fixture.launch {
            await vm.refreshData(authManager: fixture.auth, realtimeSyncManager: fixture.sync)
        }
        await fulfillment(of: [coordinator.next.started], timeout: 3)
        XCTAssertTrue(vm.isSyncingData)
        let originalReceipt = fixture.auth.captureAccountSession()
        heldSteps.resumeIfWaiting(returning: nil)
        await fixture.observeTerminal(old, test: self)
        XCTAssertTrue(old.terminal, "Original task must terminate while newer work stays held")
        XCTAssertFalse(newer.terminal)
        XCTAssertEqual(coordinator.weightCalls, 2)
        XCTAssertTrue(vm.isSyncingData, "Old nil cannot finalize the newer same-owner spinner")
        XCTAssertEqual(fixture.auth.captureAccountSession(), originalReceipt)
        XCTAssertNil(vm.publicationOwnership)
        XCTAssertNil(vm.dailyMetrics)
        XCTAssertNil(vm.lastRefreshDate)
        XCTAssertEqual(fixture.writes, 0)
        XCTAssertEqual(fixture.publications, 0)
        XCTAssertEqual(fixture.syncs, 0)
        let rows = try await fixture.independentRows()
        XCTAssertTrue(rows.isEmpty)
    }

    func testCurrentObservedZeroSavesAndReadsBackBeforeReceiptPublicationAndSync() async throws {
        let fixture = try makeCombinedStepFixture()
        let original = try await fixture.seedDay()
        weak var observedVM: DashboardViewModel?
        let vm = DashboardViewModel(
            healthKitManager: fixture.health, healthSyncCoordinator: MockHealthSyncCoordinator(),
            todayStepCountLoader: { 0 },
            dailyStepLoader: { owner, date in
                await fixture.store.fetchDailyMetrics(for: owner, date: date)?.toDailyMetrics()
            },
            dailyStepWriter: { metrics, admission in
                XCTAssertEqual(metrics.steps, 0)
                XCTAssertNil(observedVM?.publicationOwnership)
                try await fixture.store.saveDailyMetricsAndWait(
                    metrics, userId: metrics.userId, writeAdmission: {
                        fixture.admissions += 1
                        guard !fixture.disarmed else { throw CancellationError() }
                        try admission()
                    }
                )
                let rows = try await fixture.independentRows()
                XCTAssertEqual(rows.count, 1)
                let row = try XCTUnwrap(rows.first)
                XCTAssertEqual(row["id"] as? String, original.id)
                XCTAssertEqual((row["steps"] as? NSNumber)?.intValue, 0)
                XCTAssertEqual(row["notes"] as? String, original.notes)
                XCTAssertEqual(row["createdAt"] as? Date, original.createdAt)
                XCTAssertNil(observedVM?.publicationOwnership, "Real writer has not returned to publication")
                XCTAssertNil(observedVM?.dailyMetrics)
                fixture.savedAndReadBack = true
                fixture.events.append("saved-and-independent-readback")
            },
            stepSyncTrigger: {
                XCTAssertTrue(fixture.savedAndReadBack)
                XCTAssertEqual(observedVM?.publicationOwnership, fixture.auth.captureAccountSession())
                XCTAssertEqual(observedVM?.dailyMetrics?.steps, 0)
                fixture.syncs += 1
                fixture.events.append("sync")
            }
        )
        observedVM = vm
        fixture.subscriptions.append(vm.$dailyMetrics.dropFirst().sink { row in
            guard let row else { return }
            XCTAssertTrue(fixture.savedAndReadBack)
            XCTAssertEqual(vm.publicationOwnership, fixture.auth.captureAccountSession())
            XCTAssertEqual(row.steps, 0)
            fixture.publications += 1
            fixture.events.append("publication")
        })
        let task = fixture.launch {
            await vm.syncStepsFromHealthKit(authManager: fixture.auth, realtimeSyncManager: fixture.sync)
        }
        await fixture.observeTerminal(task, test: self)
        XCTAssertTrue(task.terminal)
        XCTAssertEqual(fixture.admissions, 1)
        XCTAssertEqual(fixture.publications, 1)
        XCTAssertEqual(fixture.syncs, 1)
        XCTAssertEqual(fixture.events, ["saved-and-independent-readback", "publication", "sync"])
        XCTAssertEqual(vm.dailyMetrics?.id, original.id)
        XCTAssertEqual(vm.dailyMetrics?.notes, original.notes)
        XCTAssertEqual(vm.publicationOwnership, fixture.auth.captureAccountSession())
        XCTAssertFalse(fixture.store.viewContext.hasChanges)
    }

    func testHeldObservedZeroIsRejectedInsideStoreAfterSupersessionOrCancellation() async throws {
        for cancel in [false, true] {
            let fixture = try makeCombinedStepFixture()
            _ = try await fixture.seedDay()
            let originalRows = try await fixture.independentRows()
            let coordinator = HeldDashboardSyncCoordinator()
            let heldWriter = HeldDashboardRead<Void>()
            fixture.releases = [
                { heldWriter.resumeIfWaiting(returning: ()) },
                { coordinator.held.resumeIfWaiting(returning: ()) },
                { coordinator.next.resumeIfWaiting(returning: ()) }
            ]
            let vm = DashboardViewModel(
                healthKitManager: fixture.health, healthSyncCoordinator: coordinator,
                todayStepCountLoader: { 0 },
                dailyStepLoader: { owner, date in
                    await fixture.store.fetchDailyMetrics(for: owner, date: date)?.toDailyMetrics()
                },
                dailyStepWriter: { metrics, admission in
                    guard !fixture.disarmed else { throw CancellationError() }
                    fixture.writes += 1
                    XCTAssertEqual(metrics.steps, 0)
                    // Hold the existing async writer BEFORE the real store call.
                    await heldWriter.read()
                    try await fixture.store.saveDailyMetricsAndWait(
                        metrics, userId: metrics.userId, writeAdmission: {
                            // Production context.perform invokes this BEFORE mutation.
                            fixture.admissions += 1
                            do {
                                guard !fixture.disarmed else { throw CancellationError() }
                                try admission()
                            } catch {
                                fixture.rejections += 1
                                throw error
                            }
                        }
                    )
                    XCTFail("Stale or cancelled zero must not pass real store admission")
                },
                stepSyncTrigger: { fixture.syncs += 1 }
            )
            fixture.subscriptions.append(vm.$dailyMetrics.dropFirst().sink { _ in fixture.publications += 1 })
            let old = fixture.launch {
                await vm.refreshData(authManager: fixture.auth, realtimeSyncManager: fixture.sync)
            }
            await fulfillment(of: [coordinator.held.started], timeout: 3)
            coordinator.held.resumeIfWaiting(returning: ())
            await fulfillment(of: [heldWriter.started], timeout: 3)
            if cancel {
                old.task?.cancel()
            } else {
                _ = fixture.launch {
                    await vm.refreshData(authManager: fixture.auth, realtimeSyncManager: fixture.sync)
                }
                await fulfillment(of: [coordinator.next.started], timeout: 3)
                XCTAssertTrue(vm.isSyncingData)
            }
            heldWriter.resumeIfWaiting(returning: ())
            await fixture.observeTerminal(old, test: self)
            XCTAssertTrue(old.terminal)
            XCTAssertEqual(fixture.writes, 1)
            XCTAssertEqual(fixture.admissions, 1, "Reject inside actual store, not before calling it")
            XCTAssertEqual(fixture.rejections, 1)
            let rows = try await fixture.independentRows()
            XCTAssertEqual(NSArray(array: rows), NSArray(array: originalRows))
            XCTAssertFalse(fixture.store.viewContext.hasChanges)
            XCTAssertNil(vm.publicationOwnership)
            XCTAssertNil(vm.dailyMetrics)
            XCTAssertNil(vm.lastRefreshDate)
            XCTAssertEqual(fixture.publications, 0)
            XCTAssertEqual(fixture.syncs, 0)
            XCTAssertEqual(vm.isSyncingData, !cancel, "Only current cancelled work may finalize its spinner")
        }
    }

    private func makeCombinedStepFixture() throws -> CombinedStepFixture {
        let fixture = try CombinedStepFixture()
        // Register async cleanup BEFORE this fixture can launch any task.
        addTeardownBlock { @MainActor in
            await fixture.tearDown(test: self)
        }
        return fixture
    }

    private func makeDashboardSync(auth: AuthManager) -> RealtimeSyncManager {
        let sync = RealtimeSyncManager(
            coreDataManager: .shared, authManager: auth, productAPIClient: ProductAPIClient()
        )
        sync.isOnline = false
        return sync
    }

    private func dailySnapshot(_ rows: [DailyMetrics]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(rows)
    }

    private func installDashboardSession(_ auth: AuthManager, subject: String) {
        auth.authSession = .localFixture(subject: subject, email: "dashboard@example.invalid")
        auth.currentUser = LocalUser(id: subject, email: "dashboard@example.invalid", name: "Dashboard")
    }

    private func seedDashboardDay(subject: String, steps: Int) async throws {
        let now = Date()
        let row = DailyMetrics(
            id: subject + "_day", userId: subject, date: now, steps: steps,
            notes: "Synthetic dashboard fixture", createdAt: now, updatedAt: now
        )
        try await CoreDataManager.shared.saveDailyMetricsAndWait(row, userId: subject)
    }

    private func awaitDashboardTask(_ task: Task<Void, Never>, timeout: TimeInterval = 3) async {
        let completed = expectation(description: "Actual dashboard task completed")
        Task { await task.value; completed.fulfill() }
        await fulfillment(of: [completed], timeout: timeout)
    }
}


@MainActor
private final class HeldDashboardRead<Value> {
    let started = XCTestExpectation(description: "Actual dashboard reader or coordinator held")
    private var continuation: CheckedContinuation<Value, Never>?

    func read() async -> Value {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func resumeIfWaiting(returning value: Value) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}

@MainActor
private final class HeldDashboardSyncCoordinator: HealthSyncCoordinating {
    let held = HeldDashboardRead<Void>()
    let next = HeldDashboardRead<Void>()
    private(set) var weightCalls = 0
    func bootstrapIfNeeded(syncEnabled: Bool) {}
    func resetForCurrentUser() async {}
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {}
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {}
    func warmUpAfterLoginIfNeeded() async {}
    func performInitialConnectSync() async throws {}
    func runDeferredOnboardingWeightSync() async {}
    func syncWeightFromHealthKit() async throws {
        weightCalls += 1
        if weightCalls == 1 { await held.read() } else { await next.read() }
    }
    func syncStepsFromHealthKit() async throws {}
    func forceFullHealthKitSync() async -> Bool { true }
}


@MainActor
private final class CombinedStepTask {
    let completed = XCTestExpectation(description: "Actual combined-step task terminal")
    private(set) var terminal = false
    var task: Task<Void, Never>?

    func start(_ operation: @escaping @MainActor () async -> Void) {
        task = Task {
            await operation()
            self.terminal = true
            self.completed.fulfill()
        }
    }
}

private final class CombinedStepAnalytics: AnalyticsClient {
    func start() { XCTFail("Synthetic combined-step scenario must not start analytics") }
    func identify(userId: String?, properties: [String: String]?) {
        XCTFail("No analytics identity in combined-step tests")
    }
    func track(event: String, properties: [String: String]?) {
        XCTFail("No provider analytics in combined-step tests")
    }
    func reset() {}
    func isFeatureEnabled(flagKey: String) -> Bool { false }
}

@MainActor
private final class CombinedStepFixture {
    let suite: String
    let defaults: UserDefaults
    let session: URLSession
    let auth: AuthManager
    let store: CoreDataManager
    let health: HealthKitManager
    let sync: RealtimeSyncManager
    let subject: String
    var disarmed = false
    var releases: [@MainActor () -> Void] = []
    var subscriptions: [AnyCancellable] = []
    var tasks: [CombinedStepTask] = []
    var writes = 0
    var admissions = 0
    var rejections = 0
    var publications = 0
    var syncs = 0
    var savedAndReadBack = false
    var events: [String] = []

    init() throws {
        let ownedSuite = "CombinedDashboardSteps.\(UUID().uuidString)"
        let ownedDefaults = try XCTUnwrap(UserDefaults(suiteName: ownedSuite))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        let ownedSession = URLSession(configuration: configuration)
        let ownedAuth = AuthManager(userDefaults: ownedDefaults, urlSession: ownedSession)
        let ownedSubject = "combined-dashboard-\(UUID().uuidString)"
        ownedAuth.authSession = .localFixture(subject: ownedSubject, email: "combined@example.invalid")
        ownedAuth.currentUser = LocalUser(
            id: ownedSubject, email: "combined@example.invalid", name: "Synthetic Combined Steps"
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        let ownedStore = CoreDataManager(persistentStoreDescriptions: [description])
        let ownedHealth = HealthKitManager(
            userDefaults: ownedDefaults, authManager: ownedAuth, coreDataManager: ownedStore
        )
        ownedHealth.isAuthorized = true
        let api = ProductAPIClient()
        api.session = ownedSession
        let ownedSync = RealtimeSyncManager(
            coreDataManager: ownedStore, authManager: ownedAuth, productAPIClient: api,
            userDefaults: ownedDefaults, analyticsService: AnalyticsService(client: CombinedStepAnalytics())
        )
        // Injected initializer starts no network monitor or auth/lifecycle observer.
        ownedSync.isOnline = false
        suite = ownedSuite
        defaults = ownedDefaults
        session = ownedSession
        auth = ownedAuth
        subject = ownedSubject
        store = ownedStore
        health = ownedHealth
        sync = ownedSync
    }

    func launch(_ operation: @escaping @MainActor () async -> Void) -> CombinedStepTask {
        let record = CombinedStepTask()
        tasks.append(record)
        record.start(operation)
        return record
    }

    func observeTerminal(_ record: CombinedStepTask, test: XCTestCase) async {
        if !record.terminal {
            await test.fulfillment(of: [record.completed], timeout: 3)
        }
    }

    func seedDay() async throws -> DailyMetrics {
        let now = Date()
        let row = DailyMetrics(
            id: subject + "_day", userId: subject, date: now, steps: 111,
            notes: "keep-owned-note", createdAt: now, updatedAt: now
        )
        try await store.saveDailyMetricsAndWait(row, userId: subject)
        return row
    }

    func independentRows() async throws -> [NSDictionary] {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = store.viewContext.persistentStoreCoordinator
        let owner = subject
        return try await context.perform {
            let request = CachedDailyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", owner)
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            return try context.fetch(request).map { row in
                NSDictionary(dictionary: row.dictionaryWithValues(forKeys: Array(row.entity.attributesByName.keys)))
            }
        }
    }

    func tearDown(test: XCTestCase) async {
        disarmed = true
        subscriptions.forEach { $0.cancel() }
        tasks.forEach { $0.task?.cancel() }
        releases.forEach { $0() }
        for record in tasks { await observeTerminal(record, test: test) }
        let allTerminal = tasks.allSatisfy(\.terminal)
        let evidence = XCTAttachment(string: """
            Combined step cleanup: disarmed=true; taskCount=\(tasks.count);
            actualTerminalCount=\(tasks.filter(\.terminal).count); allTerminal=\(allTerminal).
            Original assertion failures remain. Timeout does NOT prove task termination.
            Owned store/defaults disposed only after all actual tasks are terminal.
            """)
        evidence.name = "combined-step-owned-cleanup"
        evidence.lifetime = .keepAlways
        test.add(evidence)
        guard allTerminal else {
            XCTFail("Cleanup did not observe actual task terminal; pending tasks retain owned resources")
            return
        }
        releases.removeAll()
        subscriptions.removeAll()
        tasks.removeAll()
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
    }
}
