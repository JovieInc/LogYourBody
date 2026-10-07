//
// RevenueCatFlowTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


@MainActor
final class RevenueCatPurchaseRestoreFlowTests: XCTestCase {
    private static let isSubscribedKey = "revenuecat_isSubscribed"

    func testPurchaseSuccessMarksSubscribedAndPersistsCache() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        let package = Self.makeAnnualPackage()
        fixture.client.purchaseResult = .success(Self.customer(isActive: true))
        fixture.client.onPurchase = {
            XCTAssertTrue(fixture.manager.isPurchasing)
        }

        let didPurchase = await fixture.manager.purchase(package: package)

        XCTAssertTrue(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.purchasedPackageIdentifier, "$rc_annual")
        XCTAssertEqual(fixture.client.purchaseEntitlementID, Constants.proEntitlementID)
    }

    func testPurchaseCancellationStopsPurchasingWithoutShowingError() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.purchaseResult = .failure(RevenueCatPurchasingError.purchaseCancelled)

        let didPurchase = await fixture.manager.purchase(package: Self.makeAnnualPackage())

        XCTAssertFalse(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testPurchaseStoreProblemSetsFriendlyError() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.purchaseResult = .failure(RevenueCatPurchasingError.storeProblem)

        let didPurchase = await fixture.manager.purchase(package: Self.makeAnnualPackage())

        XCTAssertFalse(didPurchase)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertEqual(fixture.manager.errorMessage, "There was a problem with the App Store. Please try again.")
    }

    func testRestoreSuccessMarksSubscribedAndPersistsCache() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.client.restoreResult = .success(Self.customer(isActive: true))
        fixture.client.onRestore = {
            XCTAssertTrue(fixture.manager.isPurchasing)
        }

        let didRestore = await fixture.manager.restorePurchases()

        XCTAssertTrue(didRestore)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertNil(fixture.manager.errorMessage)
        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.restoreEntitlementID, Constants.proEntitlementID)
    }

    func testRestoreWithoutActiveSubscriptionInvalidatesStaleCache() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.restoreResult = .success(Self.customer(isActive: false))

        let didRestore = await fixture.manager.restorePurchases()

        XCTAssertFalse(didRestore)
        XCTAssertFalse(fixture.manager.isPurchasing)
        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.errorMessage, "No active subscriptions found")
    }

    func testRefreshFailurePreservesCachedSubscribedAccess() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.customerInfoResult = .failure(MockRevenueCatPurchasesClient.MockError.customerInfoFailed)

        await fixture.manager.refreshCustomerInfo()

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testRefreshInactiveCustomerInvalidatesStaleSubscribedCache() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        XCTAssertTrue(fixture.manager.isSubscribed)
        fixture.client.customerInfoResult = .success(Self.customer(isActive: false))

        await fixture.manager.refreshCustomerInfo()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testLogoutUserFailureStillClearsLocalSubscriptionState() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        fixture.client.customerInfoResult = .success(Self.customer(isActive: true))
        await fixture.manager.refreshCustomerInfo()
        fixture.client.logOutResult = .failure(MockRevenueCatPurchasesClient.MockError.logOutFailed)

        await fixture.manager.logoutUser()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.customerInfo)
    }

    func testLogoutUserSuccessClearsLocalSubscriptionState() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }

        fixture.client.customerInfoResult = .success(Self.customer(isActive: true))
        await fixture.manager.refreshCustomerInfo()

        await fixture.manager.logoutUser()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.customerInfo)
    }

    func testEntitlementIdentifierMatchesRevenueCatDashboardContract() {
        XCTAssertEqual(RevenueCatManager.entitlementID, Constants.proEntitlementID)
        XCTAssertEqual(RevenueCatManager.entitlementID, "Premium")
    }

    func testIdentifyUsesSharedProductSubjectAndExistingEntitlement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        await fixture.manager.identifyUser(userId: "billing-fixture-a")

        XCTAssertEqual(fixture.client.identifiedUserIDs, ["billing-fixture-a"])
        XCTAssertEqual(fixture.client.loginEntitlementIDs, [Constants.proEntitlementID])
    }

    func testDelayedIdentificationDoesNotRestoreAccessAfterLogout() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { _ in try await held.wait() }

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-a") }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.logoutUser()
        held.complete(Self.customer(isActive: true, appUserId: "billing-fixture-a"))
        await identify.value

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.currentEntitlementSnapshot)
    }

    func testDelayedIdentificationDoesNotReplaceNewAccountEntitlement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { userId in
            if userId == "billing-fixture-a" { return try await held.wait() }
            return Self.customer(isActive: true, appUserId: userId)
        }

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-a") }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.identifyUser(userId: "billing-fixture-b")
        XCTAssertTrue(fixture.manager.isSubscribed)
        let newAccountEntitlement = fixture.manager.currentEntitlementSnapshot
        held.complete(Self.customer(isActive: false, appUserId: "billing-fixture-a"))
        await identify.value

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.currentEntitlementSnapshot, newAccountEntitlement)
    }

    func testDelayedIdentificationDoesNotRestoreAccessAcrossSameSubjectLogin() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { _ in try await held.wait() }

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-a") }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.logoutUser()
        fixture.client.logInHandler = { userId in Self.customer(isActive: false, appUserId: userId) }
        await fixture.manager.identifyUser(userId: "billing-fixture-a")
        held.complete(Self.customer(isActive: true, appUserId: "billing-fixture-a"))
        await identify.value

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.currentEntitlementSnapshot)
    }

    func testDelayedLogoutDoesNotClearNewAccountEntitlement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { userId in Self.customer(isActive: true, appUserId: userId) }
        await fixture.manager.identifyUser(userId: "billing-fixture-a")
        fixture.client.logOutHandler = { _ = try await held.wait() }

        let logout = Task { await fixture.manager.logoutUser() }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.identifyUser(userId: "billing-fixture-b")
        XCTAssertTrue(fixture.manager.isSubscribed)
        let newAccountEntitlement = fixture.manager.currentEntitlementSnapshot
        held.complete(Self.customer(isActive: false, appUserId: "billing-fixture-a"))
        await logout.value

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.currentEntitlementSnapshot, newAccountEntitlement)
    }

    func testDelayedRefreshDoesNotReplaceNewAccountEntitlement() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { userId in Self.customer(isActive: true, appUserId: userId) }
        await fixture.manager.identifyUser(userId: "billing-fixture-a")
        fixture.client.customerInfoHandler = { try await held.wait() }

        let refresh = Task { await fixture.manager.refreshCustomerInfo() }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.identifyUser(userId: "billing-fixture-b")
        let newAccountEntitlement = fixture.manager.currentEntitlementSnapshot
        held.complete(Self.customer(isActive: false, appUserId: "billing-fixture-a"))
        await refresh.value

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.manager.currentEntitlementSnapshot, newAccountEntitlement)
    }

    func testLogoutClearsAccessBeforeRemoteLogoutReturns() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logOutHandler = { _ = try await held.wait() }

        let logout = Task { await fixture.manager.logoutUser() }
        await fulfillment(of: [held.started], timeout: 5)

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))

        held.complete(Self.customer(isActive: false))
        await logout.value
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testRelaunchAfterLogoutDoesNotRestoreCachedAccess() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.client.logInHandler = { userId in Self.customer(isActive: true, appUserId: userId) }
        await fixture.manager.identifyUser(userId: "billing-fixture-a")
        XCTAssertTrue(fixture.manager.isSubscribed)

        await fixture.manager.logoutUser()
        let relaunched = RevenueCatManager(purchasesClient: fixture.client, userDefaults: fixture.defaults)

        XCTAssertFalse(relaunched.isSubscribed)
        XCTAssertNil(relaunched.currentEntitlementSnapshot)
    }

    func testUnconfiguredIdentificationDoesNotCallPurchasesClient() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.manager.isConfigured = false

        await fixture.manager.identifyUser(userId: "billing-fixture-a")

        XCTAssertTrue(fixture.client.identifiedUserIDs.isEmpty)
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testDelayedIdentificationFailureDoesNotReplaceNewAccountError() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { userId in
            if userId == "billing-fixture-a" { return try await held.wait() }
            return Self.customer(isActive: false, appUserId: userId)
        }

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-a") }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.identifyUser(userId: "billing-fixture-b")
        fixture.manager.errorMessage = "Current fixture account error"
        held.fail(MockRevenueCatPurchasesClient.MockError.customerInfoFailed)
        await identify.value

        XCTAssertEqual(fixture.manager.errorMessage, "Current fixture account error")
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testCancelledIdentificationDoesNotApplyCustomer() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { _ in try await held.wait() }

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-a") }
        await fulfillment(of: [held.started], timeout: 5)
        identify.cancel()
        held.complete(Self.customer(isActive: true, appUserId: "billing-fixture-a"))
        await identify.value

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.currentEntitlementSnapshot)
    }

    func testCancelledRefreshPreservesCurrentCachedAccess() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.customerInfoHandler = { try await held.wait() }

        let refresh = Task { await fixture.manager.refreshCustomerInfo() }
        await fulfillment(of: [held.started], timeout: 5)
        refresh.cancel()
        held.complete(Self.customer(isActive: false))
        await refresh.value

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
    }

    func testRefreshDuringLogoutCannotRestoreDepartingAccountAccess() async {
        let fixture = makeFixture(cachedSubscribed: true)
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logOutHandler = { _ = try await held.wait() }
        fixture.client.customerInfoResult = .success(Self.customer(isActive: true, appUserId: "billing-fixture-a"))

        let logout = Task { await fixture.manager.logoutUser() }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.refreshCustomerInfo()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.customerInfoCallCount, 0)

        held.complete(Self.customer(isActive: false))
        await logout.value
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testRefreshDuringIdentificationCannotApplyPreviousSDKCustomer() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let held = HeldBillingCustomer()
        fixture.client.logInHandler = { _ in try await held.wait() }
        fixture.client.customerInfoResult = .success(Self.customer(isActive: true, appUserId: "billing-fixture-a"))

        let identify = Task { await fixture.manager.identifyUser(userId: "billing-fixture-b") }
        await fulfillment(of: [held.started], timeout: 5)
        await fixture.manager.refreshCustomerInfo()

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertEqual(fixture.client.customerInfoCallCount, 0)

        held.complete(Self.customer(isActive: false, appUserId: "billing-fixture-b"))
        await identify.value
        XCTAssertFalse(fixture.manager.isSubscribed)
    }

    func testInitialAnonymousRefreshRemainsAvailable() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.client.customerInfoResult = .success(
            Self.customer(isActive: true, appUserId: "billing-fixture-anonymous")
        )

        await fixture.manager.refreshCustomerInfo()

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertEqual(fixture.client.customerInfoCallCount, 1)
    }

    private func makeFixture(cachedSubscribed: Bool = false) -> RevenueCatPurchaseFixture {
        let suiteName = "revenuecat-purchase-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(cachedSubscribed, forKey: Self.isSubscribedKey)

        let client = MockRevenueCatPurchasesClient()
        let manager = RevenueCatManager(purchasesClient: client, userDefaults: defaults)
        manager.markAsConfigured()

        return RevenueCatPurchaseFixture(
            manager: manager,
            client: client,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private static func customer(
        isActive: Bool,
        appUserId: String = "unit-test-user",
        periodType: PeriodType = .normal
    ) -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(
            originalAppUserId: appUserId,
            entitlement: isActive ? RevenueCatEntitlementSnapshot(
                isActive: true,
                expirationDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                periodType: periodType,
                willRenew: true,
                productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
                unsubscribeDetectedAt: nil
            ) : nil
        )
    }

    private static func makeAnnualPackage() -> Package {
        let product = TestStoreProduct(
            localizedTitle: "LogYourBody Pro Annual",
            price: Decimal(string: "69.99") ?? 0,
            localizedPriceString: "$69.99",
            productIdentifier: "com.logyourbody.app.pro1.annual.3daytrial",
            productType: .autoRenewableSubscription,
            localizedDescription: "Annual LogYourBody Pro subscription",
            subscriptionGroupIdentifier: "logyourbody_pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
            locale: Locale(identifier: "en_US")
        ).toStoreProduct()

        return Package(
            identifier: "$rc_annual",
            packageType: .annual,
            storeProduct: product,
            offeringIdentifier: "unit_test_paywall",
            webCheckoutUrl: nil
        )
    }
}

@MainActor
struct RevenueCatPurchaseFixture {
    let manager: RevenueCatManager
    let client: MockRevenueCatPurchasesClient
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
final class MockRevenueCatPurchasesClient: RevenueCatPurchasesProtocol {
    enum MockError: Error {
        case notImplemented
        case customerInfoFailed
        case logOutFailed
    }

    var customerInfoResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var purchaseResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var restoreResult: Result<RevenueCatCustomerSnapshot, Error> = .success(
        RevenueCatCustomerSnapshot(originalAppUserId: "unit-test-user", entitlement: nil)
    )
    var logOutResult: Result<Void, Error> = .success(())
    var onPurchase: (() -> Void)?
    var onRestore: (() -> Void)?
    var logInHandler: ((String) async throws -> RevenueCatCustomerSnapshot)?
    var logOutHandler: (() async throws -> Void)?
    var customerInfoHandler: (() async throws -> RevenueCatCustomerSnapshot)?

    private(set) var configuredAPIKey: String?
    private(set) var delegateWasSet = false
    private(set) var purchaseEntitlementID: String?
    private(set) var purchasedPackageIdentifier: String?
    private(set) var restoreEntitlementID: String?
    private(set) var identifiedUserIDs: [String] = []
    private(set) var loginEntitlementIDs: [String] = []
    private(set) var customerInfoCallCount = 0

    func configure(apiKey: String, delegate: PurchasesDelegate) {
        configuredAPIKey = apiKey
        delegateWasSet = true
    }

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        identifiedUserIDs.append(userId)
        loginEntitlementIDs.append(entitlementID)
        if let logInHandler { return try await logInHandler(userId) }
        return RevenueCatCustomerSnapshot(originalAppUserId: userId, entitlement: nil)
    }

    func logOut() async throws {
        if let logOutHandler { return try await logOutHandler() }
        try logOutResult.get()
    }

    func customerInfo(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        customerInfoCallCount += 1
        if let customerInfoHandler { return try await customerInfoHandler() }
        return try customerInfoResult.get()
    }

    func offerings() async throws -> Offerings {
        throw MockError.notImplemented
    }

    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        purchasedPackageIdentifier = package.identifier
        purchaseEntitlementID = entitlementID
        onPurchase?()
        return try purchaseResult.get()
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        restoreEntitlementID = entitlementID
        onRestore?()
        return try restoreResult.get()
    }
}

@MainActor
private final class HeldBillingCustomer {
    let started = XCTestExpectation(description: "Synthetic billing response is held")
    private var continuation: CheckedContinuation<RevenueCatCustomerSnapshot, Error>?
    private var completedResult: Result<RevenueCatCustomerSnapshot, Error>?

    func wait() async throws -> RevenueCatCustomerSnapshot {
        if let completedResult {
            started.fulfill()
            return try completedResult.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func complete(_ customer: RevenueCatCustomerSnapshot) {
        resolve(.success(customer))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<RevenueCatCustomerSnapshot, Error>) {
        completedResult = result
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
