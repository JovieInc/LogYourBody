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

    private(set) var configuredAPIKey: String?
    private(set) var delegateWasSet = false
    private(set) var purchaseEntitlementID: String?
    private(set) var purchasedPackageIdentifier: String?
    private(set) var restoreEntitlementID: String?

    func configure(apiKey: String, delegate: PurchasesDelegate) {
        configuredAPIKey = apiKey
        delegateWasSet = true
    }

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(originalAppUserId: userId, entitlement: nil)
    }

    func logOut() async throws {
        try logOutResult.get()
    }

    func customerInfo(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        try customerInfoResult.get()
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
