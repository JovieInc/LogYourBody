import XCTest
import RevenueCat
@testable import LogYourBody

@MainActor
final class AuthBillingLifecycleTests: XCTestCase {
    func testOrdinaryAuthLogoutClearsBillingBeforeHeldSDKReply() async {
        let fixture = makeFixture(bind: false)
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        fixture.auth.bindBillingLifecycle(fixture.billing)
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertTrue(fixture.billing.isSubscribed)
        let held = HeldAuthBillingReply()
        fixture.client.logout = { _ = try await held.wait() }

        await fixture.auth.performLogout(exitReason: .userInitiated)

        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
        XCTAssertNil(fixture.billing.currentEntitlementSnapshot)
        await fulfillment(of: [held.started], timeout: 3)
        held.complete(active: false)
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertNil(fixture.client.sdkSubject)
    }

    func testBindingReplaysAlreadyRestoredAccountBeforeConfiguration() async {
        let fixture = makeFixture(configured: false, bind: false)
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        fixture.auth.bindBillingLifecycle(fixture.billing)
        XCTAssertNil(fixture.billing.captureBillingSession())
        XCTAssertTrue(fixture.client.logins.isEmpty)

        fixture.billing.markAsConfigured()
        await fixture.billing.waitForBillingReconciliation()

        XCTAssertEqual(fixture.client.logins, ["account-a"])
        XCTAssertTrue(fixture.billing.isSubscribed)
    }

    func testSignInAfterSignedOutStartupIdentifiesNewAccount() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.auth.isAuthProviderLoaded = true
        await fixture.billing.waitForBillingReconciliation()
        fixture.signIn("account-b")
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertEqual(fixture.client.logins, ["account-b"])
        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
    }

    func testHeldLoginAIsReconciledToBWithoutPublishingA() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldAuthBillingReply()
        fixture.client.login = { subject in
            if subject == "account-a" { return try await held.wait() }
            return Self.customer(active: false)
        }
        fixture.signIn("account-a")
        await fulfillment(of: [held.started], timeout: 3)
        fixture.signIn("account-b")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertNil(fixture.billing.captureBillingSession())
        XCTAssertEqual(fixture.client.logins, ["account-a"])

        held.complete(active: true)
        await fixture.billing.waitForBillingReconciliation()

        XCTAssertEqual(fixture.client.logins, ["account-a", "account-b"])
        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
    }

    func testHeldLoginCannotPublishAcrossLogoutAndNewSameAccountLifetime() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldAuthBillingReply()
        fixture.client.login = { _ in try await held.wait() }
        fixture.signIn("account-a")
        await fulfillment(of: [held.started], timeout: 3)
        await fixture.auth.performLogout(exitReason: .userInitiated)
        fixture.client.login = { _ in Self.customer(active: false) }
        fixture.signIn("account-a")
        held.complete(active: true)
        await fixture.billing.waitForBillingReconciliation()

        XCTAssertEqual(fixture.client.logins, ["account-a", "account-a"])
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
    }

    func testHeldLogoutFinishesBeforeReplacementSDKLogin() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        let held = HeldAuthBillingReply()
        fixture.client.logout = { _ = try await held.wait() }
        await fixture.auth.performLogout(exitReason: .userInitiated)
        await fulfillment(of: [held.started], timeout: 3)
        fixture.signIn("account-b")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertEqual(fixture.client.logins, ["account-a"])
        held.complete(active: false)
        await fixture.billing.waitForBillingReconciliation()

        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
        XCTAssertTrue(fixture.billing.isSubscribed)
        XCTAssertEqual(fixture.client.logins, ["account-a", "account-b"])
    }

    func testFailedReplacementLoginDoesNotAdmitBillingReadsOrRestore() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        fixture.client.login = { _ in throw URLError(.notConnectedToInternet) }
        fixture.signIn("account-b")
        await fixture.billing.waitForBillingReconciliation()

        XCTAssertEqual(fixture.client.sdkSubject, "account-a")
        XCTAssertNil(fixture.billing.captureBillingSession())
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
        await fixture.billing.refreshCustomerInfo()
        await fixture.billing.refreshForDelegate(appUserID: "account-a")
        let restored = await fixture.billing.restorePurchases()
        let purchased = await fixture.billing.purchase(package: RevenueCatPurchaseRestoreFlowTests.makeAnnualPackage())
        XCTAssertFalse(restored)
        XCTAssertFalse(purchased)
        XCTAssertEqual(fixture.client.reads, 0)
        XCTAssertEqual(fixture.client.restores, 0)
        XCTAssertEqual(fixture.client.purchases, 0)
    }

    func testExplicitRefreshRetriesFailedIdentityBeforeReadingCustomerInfo() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.client.login = { _ in throw URLError(.notConnectedToInternet) }
        fixture.signIn("account-b")
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertNil(fixture.billing.captureBillingSession())
        fixture.client.login = { _ in Self.customer(active: true) }

        await fixture.billing.refreshCustomerInfo()

        XCTAssertEqual(fixture.client.logins, ["account-b", "account-b"])
        XCTAssertEqual(fixture.client.reads, 0)
        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
        XCTAssertTrue(fixture.billing.isSubscribed)
        XCTAssertNotNil(fixture.billing.captureBillingSession())
    }

    func testHeldDelegateReadCannotPublishAfterActualAuthReplacement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        let held = HeldAuthBillingReply()
        fixture.client.read = { try await held.wait() }
        let oldRead = Task { await fixture.billing.refreshForDelegate(appUserID: "account-a") }
        await fulfillment(of: [held.started], timeout: 3)
        fixture.client.login = { _ in Self.customer(active: false) }
        fixture.signIn("account-b")
        await fixture.billing.waitForBillingReconciliation()
        held.complete(active: true)
        await oldRead.value
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
    }

    func testCacheWaitsForKnownOwnerAndRejectsAnotherAccount() {
        let fixture = makeFixture(configured: false, cacheOwner: "account-a")
        defer { fixture.cleanup() }
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertTrue(fixture.cachedAccess)
        fixture.signIn("account-b")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
    }

    func testMatchingOwnerCacheSurvivesTransientRefreshFailure() async {
        let fixture = makeFixture(configured: false, cacheOwner: "account-a")
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        XCTAssertTrue(fixture.billing.isSubscribed)
        fixture.billing.markAsConfigured()
        await fixture.billing.waitForBillingReconciliation()
        fixture.client.read = { throw URLError(.notConnectedToInternet) }
        await fixture.billing.refreshCustomerInfo()
        XCTAssertTrue(fixture.billing.isSubscribed)
        XCTAssertTrue(fixture.cachedAccess)
    }

    func testUnownedCacheCannotGrantSignedInAccess() {
        let fixture = makeFixture(configured: false, cacheOwner: nil, cached: true)
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
    }

    func testColdSignedOutResolutionClearsRetainedCacheBeforeConfiguration() {
        let fixture = makeFixture(configured: false, cacheOwner: "account-a")
        defer { fixture.cleanup() }
        fixture.auth.isAuthProviderLoaded = true
        XCTAssertFalse(fixture.cachedAccess)
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertNil(fixture.billing.captureBillingSession())
    }

    func testSupersededDirectAwaiterFinishesWhileSDKOperationIsHeld() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldAuthBillingReply()
        let completed = expectation(description: "Superseded caller finishes")
        fixture.client.login = { subject in
            if subject == "account-a" { return try await held.wait() }
            return Self.customer(active: false)
        }
        let old = Task {
            await fixture.billing.identifyUser(userId: "account-a")
            completed.fulfill()
        }
        await fulfillment(of: [held.started], timeout: 3)
        fixture.signIn("account-b")
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(fixture.client.logins, ["account-a"])
        held.complete(active: true)
        await old.value
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
    }

    func testCancelledDirectCallerFinishesBeforeHeldSDKResponse() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldAuthBillingReply()
        let completed = expectation(description: "Cancelled caller finishes before SDK reply")
        fixture.client.login = { _ in try await held.wait() }
        let caller = Task {
            await fixture.billing.identifyUser(userId: "account-a")
            completed.fulfill()
        }
        await fulfillment(of: [held.started], timeout: 3)
        caller.cancel()
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertFalse(fixture.billing.isSubscribed)
        held.complete(active: true)
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertEqual(fixture.client.sdkSubject, "account-a")
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertNotNil(fixture.billing.captureBillingSession())
    }

    func testAlreadyCancelledWaiterDoesNotStrandContinuation() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldAuthBillingReply()
        let completed = expectation(description: "Pre-cancelled waiter finishes")
        fixture.client.login = { _ in try await held.wait() }
        let request = fixture.billing.requestBillingIdentity(subject: "account-a")
        let caller = Task {
            await fixture.billing.waitForBillingIdentity(request)
            completed.fulfill()
        }
        caller.cancel()
        await fulfillment(of: [held.started, completed], timeout: 3)
        XCTAssertTrue(fixture.billing.billingIdentityWaiters.isEmpty)
        held.complete(active: true)
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertFalse(fixture.billing.isSubscribed)
    }

    func testHeldOrdinaryReadCannotPublishAfterAuthSessionExpiry() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        let held = HeldAuthBillingReply()
        fixture.client.read = { try await held.wait() }
        let read = Task { await fixture.billing.refreshCustomerInfo() }
        await fulfillment(of: [held.started], timeout: 3)
        await fixture.auth.performLogout(exitReason: .sessionExpired)
        held.complete(active: true)
        await read.value
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertFalse(fixture.billing.isSubscribed)
        XCTAssertFalse(fixture.cachedAccess)
        XCTAssertNil(fixture.billing.captureBillingSession())
    }

    func testAnonymousSDKLogoutIsAlreadyReconciled() async throws {
        var calls = 0
        try await LiveRevenueCatPurchasesClient.logOutIfIdentified(isAnonymous: { true }, logOut: { calls += 1 })
        XCTAssertEqual(calls, 0)
        try await LiveRevenueCatPurchasesClient.logOutIfIdentified(isAnonymous: { false }, logOut: { calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    func testStaleDeletionCannotLogOutReplacementBillingAccount() async throws {
        try await assertStaleDeletionLeavesBillingOwned(replacement: "account-b")
    }

    func testStaleDeletionCannotLogOutNewSameAccountLifetime() async throws {
        try await assertStaleDeletionLeavesBillingOwned(replacement: "account-a")
    }

    private func assertStaleDeletionLeavesBillingOwned(replacement: String) async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        let owner = try XCTUnwrap(fixture.auth.captureAccountSession())
        fixture.signIn(replacement)
        await fixture.billing.waitForBillingReconciliation()

        await AccountDeletionCleanupService.logoutSubscriptionIfOwned(
            authManager: fixture.auth, ownership: owner, subscriptionManager: fixture.billing
        )

        XCTAssertEqual(fixture.client.logouts, 0)
        XCTAssertTrue(fixture.billing.isSubscribed)
        XCTAssertEqual(fixture.client.sdkSubject, replacement)
    }

    func testAdmittedDeletionLogoutCannotUndoLaterReplacementLogin() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.signIn("account-a")
        await fixture.billing.waitForBillingReconciliation()
        let owner = try XCTUnwrap(fixture.auth.captureAccountSession())
        let held = HeldAuthBillingReply()
        fixture.client.logout = { _ = try await held.wait() }
        let deletion = Task {
            await AccountDeletionCleanupService.logoutSubscriptionIfOwned(
                authManager: fixture.auth, ownership: owner, subscriptionManager: fixture.billing
            )
        }
        await fulfillment(of: [held.started], timeout: 3)
        XCTAssertFalse(fixture.billing.isSubscribed)
        fixture.signIn("account-b")
        await deletion.value
        held.complete(active: false)
        await fixture.billing.waitForBillingReconciliation()
        XCTAssertEqual(fixture.client.sdkSubject, "account-b")
        XCTAssertTrue(fixture.billing.isSubscribed)
    }

    private func makeFixture(
        configured: Bool = true,
        bind: Bool = true,
        cacheOwner: String? = nil,
        cached: Bool = false
    ) -> AuthBillingFixture {
        let suiteName = "AuthBillingLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(cached || cacheOwner != nil, forKey: "revenuecat_isSubscribed")
        defaults.set(cacheOwner, forKey: RevenueCatManager.DefaultsKey.subscriptionOwner)
        let client = AuthBillingClient()
        let billing = RevenueCatManager(purchasesClient: client, userDefaults: defaults)
        let auth = AuthManager(userDefaults: defaults)
        if bind { auth.bindBillingLifecycle(billing) }
        if configured { billing.markAsConfigured() }
        return AuthBillingFixture(auth: auth, billing: billing, client: client, defaults: defaults, suiteName: suiteName)
    }

    fileprivate static func customer(active: Bool) -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(
            originalAppUserId: "synthetic-original-identity",
            entitlement: active ? RevenueCatEntitlementSnapshot(
                isActive: true, expirationDate: nil, periodType: .normal, willRenew: true,
                productIdentifier: "synthetic-product", unsubscribeDetectedAt: nil
            ) : nil
        )
    }
}

@MainActor
private struct AuthBillingFixture {
    let auth: AuthManager
    let billing: RevenueCatManager
    let client: AuthBillingClient
    let defaults: UserDefaults
    let suiteName: String
    var cachedAccess: Bool { defaults.bool(forKey: "revenuecat_isSubscribed") }

    func signIn(_ subject: String) {
        auth.authSession = .localFixture(subject: subject, email: "synthetic@example.invalid")
        auth.currentUser = LocalUser(
            id: subject, email: "synthetic@example.invalid", name: nil, avatarUrl: nil, profile: nil
        )
    }

    func cleanup() { defaults.removePersistentDomain(forName: suiteName) }
}

@MainActor
private final class AuthBillingClient: RevenueCatPurchasesProtocol {
    var sdkSubject: String?
    var logins: [String] = []
    var logouts = 0
    var reads = 0
    var restores = 0
    var purchases = 0
    var login: ((String) async throws -> RevenueCatCustomerSnapshot)?
    var logout: (() async throws -> Void)?
    var read: (() async throws -> RevenueCatCustomerSnapshot)?

    func configure(apiKey: String, delegate: PurchasesDelegate) {}
    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        logins.append(userId)
        let result = try await login?(userId) ?? AuthBillingLifecycleTests.customer(active: true)
        sdkSubject = userId
        return result
    }
    func logOut() async throws {
        logouts += 1
        try await logout?()
        sdkSubject = nil
    }
    func customerInfo(entitlementID: String, read: RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot {
        reads += 1
        return try await self.read?() ?? AuthBillingLifecycleTests.customer(active: true)
    }
    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        restores += 1
        return AuthBillingLifecycleTests.customer(active: true)
    }
    func offerings() async throws -> Offerings { throw URLError(.unsupportedURL) }
    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        purchases += 1
        return AuthBillingLifecycleTests.customer(active: true)
    }
}

@MainActor
private final class HeldAuthBillingReply {
    let started = XCTestExpectation(description: "Synthetic SDK response is held")
    private var continuation: CheckedContinuation<RevenueCatCustomerSnapshot, Error>?

    func wait() async throws -> RevenueCatCustomerSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func complete(active: Bool) {
        continuation?.resume(returning: AuthBillingLifecycleTests.customer(active: active))
        continuation = nil
    }
}
