//
// RevenueCatFlowTests.swift
// LogYourBodyTests
//
import XCTest
import RevenueCat
@testable import LogYourBody

@MainActor
final class RevenueCatFlowTests: XCTestCase {
    private static let isSubscribedKey = "revenuecat_isSubscribed"

    func testDelegateCustomerInfoDoesNotSubscribeAReplacementBillingSession() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)
        let replacement = fixture.manager.beginBillingSession(subject: "delegate-replacement")
        fixture.manager.finishBillingSession(replacement)

        await fixture.manager.refreshForDelegate(appUserID: "delegate-owner")

        XCTAssertTrue(fixture.client.reads.isEmpty)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(replacement))
        XCTAssertFalse(fixture.manager.ownsBillingSession(owner))
    }

    func testDelegateCustomerInfoDoesNotSubscribeWhileBillingSessionIsPending() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)
        let pending = fixture.manager.beginBillingSession(subject: "delegate-pending")

        await fixture.manager.refreshForDelegate(appUserID: "delegate-owner")

        XCTAssertTrue(fixture.client.reads.isEmpty)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.captureBillingSession())
        fixture.manager.finishBillingSession(pending)
    }

    func testDelegateCustomerInfoDoesNotSubscribeALoggedOutBillingSession() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let loggedOut = fixture.manager.beginBillingSession(subject: nil)
        fixture.manager.finishBillingSession(loggedOut)

        await fixture.manager.refreshForDelegate(appUserID: "$RCAnonymousID:delegate-logged-out")

        XCTAssertTrue(fixture.client.reads.isEmpty)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(loggedOut))
    }

    func testDelegateCustomerInfoSubscribesTheMatchingBillingSession() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)

        fixture.client.result = .success(Self.activeCustomer())

        await fixture.manager.refreshForDelegate(appUserID: "delegate-owner")

        XCTAssertEqual(fixture.client.reads, [.current(expectedAppUserID: "delegate-owner")])
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(owner))
    }

    func testDelayedOwnerAPayloadCannotGrantAccessWhenSDKIdentityIsB() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let delivery = HeldDelegateNotification()
        let task = Task { @MainActor in
            await delivery.wait()
            await self.deliverNotification(Self.activeCustomer(), appUserID: "owner-b", manager: fixture.manager)
        }
        await fulfillment(of: [delivery.started], timeout: 5)
        let replacement = fixture.manager.beginBillingSession(subject: "owner-b")
        fixture.manager.finishBillingSession(replacement)
        delivery.release()
        await task.value

        XCTAssertEqual(fixture.client.reads, [.current(expectedAppUserID: "owner-b")])
        XCTAssertFalse(fixture.manager.isSubscribed, "An A payload delivered while the SDK identifies B must not grant B access")
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.currentEntitlementSnapshot)
        XCTAssertTrue(fixture.manager.ownsBillingSession(replacement))
    }

    func testQueuedDelegatePayloadCannotGrantAccessAfterSameSubjectReplacement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let delivery = HeldDelegateNotification()
        let task = Task { @MainActor in
            await delivery.wait()
            await self.deliverNotification(Self.activeCustomer(), appUserID: "owner-a", manager: fixture.manager)
        }
        await fulfillment(of: [delivery.started], timeout: 5)
        let replacement = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(replacement)
        delivery.release()
        await task.value

        XCTAssertEqual(fixture.client.reads, [.current(expectedAppUserID: "owner-a")])
        XCTAssertFalse(fixture.manager.isSubscribed, "A queued payload cannot grant access to a replacement generation")
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.currentEntitlementSnapshot)
        XCTAssertTrue(fixture.manager.ownsBillingSession(replacement))
        XCTAssertFalse(fixture.manager.ownsBillingSession(owner))
    }

    func testSuspendedDelegateRefreshCannotApplyToSameSubjectReplacement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let first = HeldDelegateCustomer()
        let second = HeldDelegateCustomer()
        fixture.client.handler = { _ in
            if fixture.client.reads.count == 1 { return try await first.wait() }
            if fixture.client.reads.count == 2 { return try await second.wait() }
            return Self.inactiveCustomer()
        }
        let oldTask = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        await fulfillment(of: [first.started], timeout: 5)
        let replacement = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(replacement)
        let newTask = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        await fulfillment(of: [second.started], timeout: 5)

        first.finish(.success(Self.activeCustomer()))
        await oldTask.value
        XCTAssertFalse(fixture.manager.isSubscribed)
        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertEqual(fixture.client.reads.count, 2, "Old cleanup must leave the replacement refresh coalescing")
        second.finish(.success(Self.inactiveCustomer()))
        await newTask.value

        XCTAssertEqual(fixture.client.reads.count, 3)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(replacement))
    }

    func testStaleFailureCannotClearReplacementDelegateRefresh() async {
        await assertOldRefreshCannotClearReplacement(cancelOld: false)
    }

    func testCancelledRefreshCannotClearReplacementDelegateRefresh() async {
        await assertOldRefreshCannotClearReplacement(cancelOld: true)
    }

    private func assertOldRefreshCannotClearReplacement(cancelOld: Bool) async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let first = HeldDelegateCustomer()
        let second = HeldDelegateCustomer()
        fixture.client.handler = { _ in
            if fixture.client.reads.count == 1 { return try await first.wait() }
            if fixture.client.reads.count == 2 { return try await second.wait() }
            return Self.activeCustomer()
        }
        let oldTask = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        await fulfillment(of: [first.started], timeout: 5)
        let replacement = fixture.manager.beginBillingSession(subject: "owner-b")
        fixture.manager.finishBillingSession(replacement)
        let newTask = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-b") }
        await fulfillment(of: [second.started], timeout: 5)
        if cancelOld { oldTask.cancel() }
        first.finish(cancelOld ? .success(Self.activeCustomer()) : .failure(IdleRevenueCatError.unused))
        await oldTask.value

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertNil(fixture.manager.errorMessage)
        await fixture.manager.refreshForDelegate(appUserID: "owner-b")
        XCTAssertEqual(fixture.client.reads.count, 2)
        second.finish(.success(Self.activeCustomer()))
        await newTask.value
        XCTAssertEqual(fixture.client.reads, [
            .current(expectedAppUserID: "owner-a"),
            .current(expectedAppUserID: "owner-b"),
            .current(expectedAppUserID: "owner-b")
        ])
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testDelegateInvalidationsCoalesceAndStableRefreshTerminates() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let first = HeldDelegateCustomer()
        fixture.client.handler = { _ in
            if fixture.client.reads.count == 1 { return try await first.wait() }
            return Self.activeCustomer()
        }
        let task = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        await fulfillment(of: [first.started], timeout: 5)
        // A changed SDK result can notify before its read completes; equal results do not notify.
        for _ in 0..<3 { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        XCTAssertEqual(fixture.client.reads.count, 1)
        first.finish(.success(Self.activeCustomer()))
        await task.value
        XCTAssertEqual(fixture.client.reads.count, 2)
        XCTAssertTrue(fixture.manager.isSubscribed)

        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertEqual(fixture.client.reads.count, 3, "A later external notification still starts a read")
    }

    func testFailedDelegateReadPreservesAccessAndLaterNotificationRecovers() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        fixture.client.result = .success(Self.activeCustomer())
        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.result = .failure(IdleRevenueCatError.unused)

        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertEqual(fixture.client.reads.count, 2)
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.currentEntitlementSnapshot, Self.activeCustomer().entitlement)

        fixture.client.result = .success(Self.inactiveCustomer())
        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertEqual(fixture.client.reads.count, 3)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testCoalescedNotificationRecoversAfterOwnedFetchFails() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        let first = HeldDelegateCustomer()
        fixture.client.handler = { _ in
            if fixture.client.reads.count == 1 { return try await first.wait() }
            return Self.activeCustomer()
        }
        let task = Task { await fixture.manager.refreshForDelegate(appUserID: "owner-a") }
        await fulfillment(of: [first.started], timeout: 5)
        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        XCTAssertEqual(fixture.client.reads.count, 1)
        first.finish(.failure(IdleRevenueCatError.unused))
        await task.value

        XCTAssertEqual(fixture.client.reads.count, 2, "A notification received during the failed fetch must still drain")
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testUnconfiguredOrEmptyDelegateIdentityDoesNotRead() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "owner-a")
        fixture.manager.finishBillingSession(owner)
        fixture.manager.isConfigured = false
        await fixture.manager.refreshForDelegate(appUserID: "owner-a")
        fixture.manager.isConfigured = true
        let empty = fixture.manager.beginBillingSession(subject: "")
        fixture.manager.finishBillingSession(empty)
        await fixture.manager.refreshForDelegate(appUserID: "")
        XCTAssertTrue(fixture.client.reads.isEmpty)
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testCurrentAdapterReadRejectsSDKIdentityMismatchBeforeFetching() async {
        do {
            _ = try await LiveRevenueCatPurchasesClient.readCustomerInfo(
                read: .current(expectedAppUserID: "owner-b"), currentAppUserID: { "owner-a" },
                fetch: { _ in
                    XCTFail("A mismatched SDK owner must not be fetched")
                    return Self.activeCustomer()
                }
            )
            XCTFail("Expected identity rejection")
        } catch RevenueCatCustomerInfoError.identityChanged {
            // Expected, without configuring or invoking the SDK.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCurrentAdapterReadRejectsSDKIdentityChangedDuringFetch() async {
        var sdkIdentity = "owner-a"
        do {
            _ = try await LiveRevenueCatPurchasesClient.readCustomerInfo(
                read: .current(expectedAppUserID: "owner-a"), currentAppUserID: { sdkIdentity },
                fetch: { policy in
                    XCTAssertEqual(policy, .fetchCurrent)
                    sdkIdentity = "owner-b"
                    return Self.activeCustomer()
                }
            )
            XCTFail("A result for the replaced SDK identity must not be returned")
        } catch RevenueCatCustomerInfoError.identityChanged {
            // Expected, without configuring or invoking the SDK.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCurrentAdapterReadUsesFreshPolicyAndPreservesAnonymousAlias() async throws {
        let customer = try await LiveRevenueCatPurchasesClient.readCustomerInfo(
            read: .current(expectedAppUserID: "owner-a"), currentAppUserID: { "owner-a" },
            fetch: { policy in
                XCTAssertEqual(policy, .fetchCurrent)
                return Self.activeCustomer()
            }
        )
        XCTAssertEqual(customer.originalAppUserId, "$RCAnonymousID:delegate-fixture")
        XCTAssertEqual(customer.entitlement, Self.activeCustomer().entitlement)
    }

    func testCachedAdapterReadKeepsExistingPolicyAndDoesNotRequireIdentity() async throws {
        let customer = try await LiveRevenueCatPurchasesClient.readCustomerInfo(
            read: .cached,
            currentAppUserID: {
                XCTFail("Cached read has no new identity requirement")
                return ""
            },
            fetch: { policy in
                XCTAssertEqual(policy, .cachedOrFetched)
                return Self.activeCustomer()
            }
        )
        XCTAssertEqual(customer.entitlement, Self.activeCustomer().entitlement)
    }

    private static func inactiveCustomer() -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(originalAppUserId: "$RCAnonymousID:current-fixture", entitlement: nil)
    }

    private func deliverNotification(
        _: RevenueCatCustomerSnapshot,
        appUserID: String,
        manager: RevenueCatManager
    ) async {
        await manager.refreshForDelegate(appUserID: appUserID)
    }

    private func makeFixture() -> DelegateBillingFixture {
        let suiteName = "revenuecat-delegate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let client = IdleRevenueCatClient()
        let manager = RevenueCatManager(
            purchasesClient: client,
            userDefaults: defaults
        )
        manager.markAsConfigured()
        return DelegateBillingFixture(manager: manager, client: client, defaults: defaults, suiteName: suiteName)
    }

    private static func activeCustomer() -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(
            originalAppUserId: "$RCAnonymousID:delegate-fixture",
            entitlement: RevenueCatEntitlementSnapshot(
                isActive: true,
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
                periodType: .normal,
                willRenew: true,
                productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                unsubscribeDetectedAt: nil
            )
        )
    }
}

@MainActor
private struct DelegateBillingFixture {
    let manager: RevenueCatManager
    let client: IdleRevenueCatClient
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class IdleRevenueCatClient: RevenueCatPurchasesProtocol {
    func configure(apiKey: String, delegate: PurchasesDelegate) {}

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(originalAppUserId: userId, entitlement: nil)
    }

    func logOut() async throws {}

    var reads: [RevenueCatCustomerInfoRead] = []
    var result: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "$RCAnonymousID:current-fixture", entitlement: nil)
    )
    var handler: ((RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot)?

    func customerInfo(entitlementID: String, read: RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot {
        reads.append(read)
        XCTAssertEqual(entitlementID, RevenueCatManager.entitlementID)
        if let handler { return try await handler(read) }
        return try result.get()
    }

    func offerings() async throws -> Offerings {
        throw IdleRevenueCatError.unused
    }

    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        throw IdleRevenueCatError.unused
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        throw IdleRevenueCatError.unused
    }
}

private enum IdleRevenueCatError: Error {
    case unused
}

@MainActor
private final class HeldDelegateNotification {
    let started = XCTestExpectation(description: "Delegate notification queued")
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class HeldDelegateCustomer {
    let started = XCTestExpectation(description: "Current delegate read started")
    private var continuation: CheckedContinuation<RevenueCatCustomerSnapshot, Error>?

    func wait() async throws -> RevenueCatCustomerSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish(_ result: Result<RevenueCatCustomerSnapshot, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
