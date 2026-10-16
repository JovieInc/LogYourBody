import RevenueCat
import StoreKit
import StoreKitTest
import XCTest
@testable import LogYourBody

/// Simulator StoreKit configuration evidence for both pro1 3-day-trial subscriptions.
/// The test target adapter reads verified Xcode transactions only. It does not
/// configure RevenueCat, call App Store Connect, or use a signed TestFlight build.
@MainActor
final class StoreKitPurchaseRestoreTests: XCTestCase {
    func testAnnualTrialPurchaseRestoreExpiration() async throws {
        try await checkLifecycle(productID: ProductRegistry.Paywall.annualProductID, refund: false)
    }

    func testMonthlyTrialPurchaseRestoreExpiration() async throws {
        try await checkLifecycle(productID: ProductRegistry.Paywall.monthlyProductID, refund: false)
    }

    func testAnnualTrialPurchaseRestoreRefund() async throws {
        try await checkLifecycle(productID: ProductRegistry.Paywall.annualProductID, refund: true)
    }

    func testMonthlyTrialPurchaseRestoreRefund() async throws {
        try await checkLifecycle(productID: ProductRegistry.Paywall.monthlyProductID, refund: true)
    }

    private func checkLifecycle(productID: String, refund: Bool) async throws {
        let configuration = try storeKitConfigurationURL()
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.timeRate = .realTime
        defer {
            session.clearTransactions()
            session.resetToDefaultState()
        }

        let suite = "StoreKitPurchaseRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = LocalStoreKitPurchasesClient()
        let manager = RevenueCatManager(purchasesClient: client, userDefaults: defaults)
        manager.markAsConfigured()
        await manager.identifyUser(userId: client.appUserID)
        XCTAssertFalse(manager.hasActiveSubscription)

        let package = try await loadTrialPackage(productID: productID)
        manager.currentOffering = Offering(
            identifier: "storekit-ci",
            serverDescription: "Local StoreKit configuration",
            availablePackages: [package],
            webCheckoutUrl: nil
        )
        let purchased = await manager.purchase(packageIdentifier: package.identifier)
        XCTAssertTrue(purchased, manager.errorMessage ?? "Purchase failed")
        let transaction = try XCTUnwrap(client.purchasedTransaction)
        XCTAssertEqual(transaction.productID, productID)
        XCTAssertEqual(transaction.offer?.type, .introductory)
        XCTAssertEqual(transaction.environment, .xcode)
        let expiration = try XCTUnwrap(transaction.expirationDate)
        let threeDays: TimeInterval = 3 * 24 * 60 * 60
        XCTAssertEqual(expiration.timeIntervalSince(transaction.purchaseDate), threeDays, accuracy: 60)
        assertAccess(manager, productID: productID)

        manager.clearLocalSubscriptionState()
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
        XCTAssertNil(manager.currentEntitlementSnapshot)
        let restored = await manager.restorePurchases()
        XCTAssertTrue(restored, manager.errorMessage ?? "Restore failed")
        XCTAssertEqual(client.restoreCount, 1)
        assertAccess(manager, productID: productID)

        try removeAccess(session: session, productID: productID, refund: refund)
        try await waitForAccessRemoval(manager)
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
        let latest = try XCTUnwrap(await StoreKit.Transaction.latest(for: productID)).payloadValue
        if refund {
            XCTAssertNotNil(latest.revocationDate)
        } else {
            XCTAssertLessThanOrEqual(try XCTUnwrap(latest.expirationDate), Date())
        }
        let restoredAfterRemoval = await manager.restorePurchases()
        XCTAssertFalse(restoredAfterRemoval, "Restore must not resurrect expired or refunded access")
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
    }

    private func storeKitConfigurationURL() throws -> URL {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "LogYourBody", withExtension: "storekit"),
            "LogYourBody.storekit must be in the app bundle"
        )
        XCTAssertEqual(url.lastPathComponent, "LogYourBody.storekit")
        return url
    }

    private func loadTrialPackage(productID: String) async throws -> Package {
        let products = try await Product.products(for: [
            ProductRegistry.Paywall.annualProductID,
            ProductRegistry.Paywall.monthlyProductID
        ])
        XCTAssertEqual(Set(products.map(\.id)), [
            ProductRegistry.Paywall.annualProductID,
            ProductRegistry.Paywall.monthlyProductID
        ])
        let product = try XCTUnwrap(products.first { $0.id == productID })
        XCTAssertEqual(product.type, .autoRenewable)
        let subscription = try XCTUnwrap(product.subscription)
        let annual = productID == ProductRegistry.Paywall.annualProductID
        XCTAssertEqual(subscription.subscriptionPeriod.unit, annual ? .year : .month)
        XCTAssertEqual(subscription.subscriptionPeriod.value, 1)
        let eligible = await subscription.isEligibleForIntroOffer
        XCTAssertTrue(eligible, "Each isolated session must be eligible for the trial")
        let offer = try XCTUnwrap(subscription.introductoryOffer)
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.price, 0)
        XCTAssertEqual(offer.period.unit, .day)
        XCTAssertEqual(offer.period.value, 3)
        XCTAssertEqual(offer.periodCount, 1)
        return Package(
            identifier: annual ? ProductRegistry.Paywall.annualPackageID : ProductRegistry.Paywall.monthlyPackageID,
            packageType: annual ? .annual : .monthly,
            storeProduct: StoreProduct(sk2Product: product),
            offeringIdentifier: "storekit-ci",
            webCheckoutUrl: nil
        )
    }

    private func assertAccess(_ manager: RevenueCatManager, productID: String) {
        XCTAssertTrue(manager.hasActiveSubscription)
        XCTAssertTrue(manager.cachedIsSubscribed)
        XCTAssertTrue(manager.isInTrialPeriod)
        XCTAssertEqual(manager.currentSubscriptionProductIdentifier, productID)
        XCTAssertNotNil(manager.subscriptionExpirationDate)
    }

    private func removeAccess(session: SKTestSession, productID: String, refund: Bool) throws {
        if refund {
            let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == productID })
            try session.refundTransaction(identifier: purchase.identifier)
        } else {
            try session.expireSubscription(productIdentifier: productID)
        }
    }

    private func waitForAccessRemoval(_ manager: RevenueCatManager) async throws {
        for _ in 0..<300 {
            await manager.refreshCustomerInfo()
            if !manager.hasActiveSubscription { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit expiration or refund did not remove app access within 30 seconds")
    }
}

/// Access comes only from verified StoreKit transactions in the Xcode test environment.
@MainActor
private final class LocalStoreKitPurchasesClient: RevenueCatPurchasesProtocol {
    let appUserID = "storekit-ci-user"
    private(set) var purchasedTransaction: StoreKit.Transaction?
    private(set) var restoreCount = 0

    func configure(apiKey: String, delegate: PurchasesDelegate) {
        XCTFail("Local StoreKit tests must not configure the hosted RevenueCat SDK")
    }

    func logIn(userId: String, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        XCTAssertEqual(userId, appUserID)
        return try await snapshot(entitlementID: entitlementID)
    }

    func logOut() async throws {}

    func customerInfo(
        entitlementID: String,
        read: RevenueCatCustomerInfoRead
    ) async throws -> RevenueCatCustomerSnapshot {
        // Cached and current reads both observe the live Xcode StoreKit session.
        _ = read
        return try await snapshot(entitlementID: entitlementID)
    }

    func offerings() async throws -> Offerings {
        throw LocalStoreKitError.unexpectedOfferingsRequest
    }

    func purchase(package: Package, entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        let product = try XCTUnwrap(package.storeProduct.sk2Product)
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verification.payloadValue
            purchasedTransaction = transaction
            await transaction.finish()
            return try await snapshot(entitlementID: entitlementID)
        case .userCancelled:
            throw RevenueCatPurchasingError.purchaseCancelled
        case .pending:
            throw LocalStoreKitError.pendingPurchase
        @unknown default:
            throw LocalStoreKitError.unexpectedPurchaseResult
        }
    }

    func restorePurchases(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        restoreCount += 1
        try await AppStore.sync()
        return try await snapshot(entitlementID: entitlementID)
    }

    private func snapshot(entitlementID: String) async throws -> RevenueCatCustomerSnapshot {
        XCTAssertEqual(entitlementID, ProductRegistry.Paywall.entitlementID)
        let productIDs = [ProductRegistry.Paywall.annualProductID, ProductRegistry.Paywall.monthlyProductID]
        for await result in StoreKit.Transaction.currentEntitlements {
            let transaction = try result.payloadValue
            guard productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  let expiration = transaction.expirationDate,
                  expiration > Date() else { continue }
            return RevenueCatCustomerSnapshot(
                originalAppUserId: appUserID,
                entitlement: RevenueCatEntitlementSnapshot(
                    isActive: true,
                    expirationDate: expiration,
                    periodType: transaction.offer?.type == .introductory ? .trial : .normal,
                    willRenew: true,
                    productIdentifier: transaction.productID,
                    unsubscribeDetectedAt: nil
                )
            )
        }
        return RevenueCatCustomerSnapshot(originalAppUserId: appUserID, entitlement: nil)
    }
}

private enum LocalStoreKitError: Error {
    case unexpectedOfferingsRequest
    case pendingPurchase
    case unexpectedPurchaseResult
}
