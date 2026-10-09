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

    func testDelegateCustomerInfoDoesNotSubscribeAReplacementBillingSession() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)
        let replacement = fixture.manager.beginBillingSession(subject: "delegate-replacement")
        fixture.manager.finishBillingSession(replacement)

        fixture.manager.applyDelegateCustomerInfo(Self.activeCustomer(), appUserID: "delegate-owner")

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(replacement))
        XCTAssertFalse(fixture.manager.ownsBillingSession(owner))
    }

    func testDelegateCustomerInfoDoesNotSubscribeWhileBillingSessionIsPending() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)
        let pending = fixture.manager.beginBillingSession(subject: "delegate-pending")

        fixture.manager.applyDelegateCustomerInfo(Self.activeCustomer(), appUserID: "delegate-owner")

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertNil(fixture.manager.captureBillingSession())
        fixture.manager.finishBillingSession(pending)
    }

    func testDelegateCustomerInfoDoesNotSubscribeALoggedOutBillingSession() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let loggedOut = fixture.manager.beginBillingSession(subject: nil)
        fixture.manager.finishBillingSession(loggedOut)

        fixture.manager.applyDelegateCustomerInfo(
            Self.activeCustomer(),
            appUserID: "$RCAnonymousID:delegate-logged-out"
        )

        XCTAssertFalse(fixture.manager.isSubscribed)
        XCTAssertFalse(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(loggedOut))
    }

    func testDelegateCustomerInfoSubscribesTheMatchingBillingSession() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let owner = fixture.manager.beginBillingSession(subject: "delegate-owner")
        fixture.manager.finishBillingSession(owner)

        fixture.manager.applyDelegateCustomerInfo(Self.activeCustomer(), appUserID: "delegate-owner")

        XCTAssertTrue(fixture.manager.isSubscribed)
        XCTAssertTrue(fixture.defaults.bool(forKey: Self.isSubscribedKey))
        XCTAssertTrue(fixture.manager.ownsBillingSession(owner))
    }

    private func makeFixture() -> DelegateBillingFixture {
        let suiteName = "revenuecat-delegate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = RevenueCatManager(
            purchasesClient: IdleRevenueCatClient(),
            userDefaults: defaults
        )
        return DelegateBillingFixture(manager: manager, defaults: defaults, suiteName: suiteName)
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

    func customerInfo(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        RevenueCatCustomerSnapshot(originalAppUserId: "idle", entitlement: nil)
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
