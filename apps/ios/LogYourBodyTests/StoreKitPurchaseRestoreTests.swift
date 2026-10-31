import XCTest
import StoreKit
import StoreKitTest
import RevenueCat
@testable import LogYourBody

/// Local StoreKit transactions exercise the app's billing port and entitlement consumer.
/// RevenueCat's hosted receipt validation is a separate, live-provider check.
@MainActor
final class StoreKitPurchaseRestoreTests: XCTestCase {
    /// Number of times the warm-up may retry after a signature-verification failure (bounded; never the assertions).
    private static let warmUpMaxRetries = 2
    private static var storeKitWarmedUp = false
    /// One StoreKit test session for the whole test process (LYB-231). Creating and releasing a new `SKTestSession`
    /// per test let the previous session's asynchronous teardown race the next test: in CI run 40011070495 a
    /// purchase verified, then the transaction vanished before restore ("No active subscriptions found").
    private static var sharedSession: SKTestSession?

    private enum SetUpError: Error {
        case storeKitConfigurationMissing
        case storeKitStateDidNotSettle
    }

    private static func session() throws -> SKTestSession {
        if let sharedSession { return sharedSession }
        guard let configuration = Bundle.main.url(forResource: "LogYourBody", withExtension: "storekit") else {
            throw SetUpError.storeKitConfigurationMissing
        }
        let session = try SKTestSession(contentsOf: configuration)
        sharedSession = session
        return session
    }

    override func setUp() async throws {
        try await super.setUp()
        let session = try Self.session()
        try await warmUpStoreKitTestSession(session)
        try await resetToCleanStoreKitState(session)
    }

    override func tearDown() async throws {
        if let session = Self.sharedSession {
            try await resetToCleanStoreKitState(session)
        }
        try await super.tearDown()
    }

    /// Delete only existing transaction IDs, then wait for both StoreKit views of history to empty.
    /// Repeated global clears can race a later purchase; scoped deletion cannot erase a future transaction.
    private func resetToCleanStoreKitState(_ session: SKTestSession) async throws {
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        for transaction in session.allTransactions() {
            // Deleting an original transaction also removes its restored/renewal children.
            guard session.allTransactions().contains(where: { $0.identifier == transaction.identifier }) else { continue }
            try session.deleteTransaction(identifier: transaction.identifier)
        }
        // Deletion updates the test server; refresh StoreKit's app-side history before polling it.
        // A failed refresh must stop setup rather than accepting stale transaction information.
        try await AppStore.sync()
        for _ in 0..<50 {
            if session.allTransactions().isEmpty, !(await hasStoreKitHistory()) {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit test session did not reach a clean state within 5 seconds")
        throw SetUpError.storeKitStateDidNotSettle
    }

    private func hasStoreKitHistory() async -> Bool {
        // Expired/refunded transactions are absent from currentEntitlements but still need cleanup.
        for await _ in StoreKit.Transaction.all { return true }
        return false
    }

    /// The first transaction in a fresh simulator can fail JWS verification with
    /// "StoreKit Testing in Xcode certificate is expired" (-67818, LYB-231) while the StoreKit test agent is still
    /// refreshing its signing certificate; later transactions in the same run verify fine. Make one throwaway
    /// purchase before the real lifecycle checks, retrying only this warm-up (at most `warmUpMaxRetries` times)
    /// and surfacing every retry as a warning. It asserts nothing, so a real StoreKit failure still fails the
    /// lifecycle tests below, which are unchanged.
    private func warmUpStoreKitTestSession(_ session: SKTestSession) async throws {
        guard !Self.storeKitWarmedUp else { return }
        for attempt in 0...Self.warmUpMaxRetries {
            try await resetToCleanStoreKitState(session)
            var failure = "no purchase result"
            do {
                let products = try await Product.products(for: [ProductRegistry.Paywall.annualProductID])
                if let product = products.first {
                    if case .success(let verification) = try await product.purchase() {
                        switch verification {
                        case .verified(let transaction):
                            await transaction.finish()
                            Self.storeKitWarmedUp = true
                            return
                        case .unverified(let transaction, let error):
                            await transaction.finish()
                            failure = "verification failed: \(error)"
                        }
                    }
                } else {
                    failure = "product not loaded"
                }
            } catch {
                failure = "purchase threw: \(error)"
            }
            let attempts = Self.warmUpMaxRetries + 1
            NSLog("%@", "::warning::STOREKIT_WARMUP_RETRY attempt \(attempt + 1)/\(attempts): \(failure)")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        NSLog("%@", "::warning title=StoreKit warm-up exhausted::STOREKIT_WARMUP_RETRY not verified; assertions decide")
    }

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
        let session = try Self.session()

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
            identifier: "storekit-ci", serverDescription: "Local StoreKit configuration",
            availablePackages: [package], webCheckoutUrl: nil
        )
        let purchased = await manager.purchase(packageIdentifier: package.identifier)
        XCTAssertTrue(purchased, manager.errorMessage ?? "Purchase failed")
        let transaction = try XCTUnwrap(client.purchasedTransaction)
        XCTAssertEqual(transaction.productID, productID)
        XCTAssertEqual(transaction.offer?.type, .introductory)
        XCTAssertEqual(transaction.environment, .xcode)
        let expiration = try XCTUnwrap(transaction.expirationDate)
        XCTAssertEqual(expiration.timeIntervalSince(transaction.purchaseDate), 3 * 24 * 60 * 60, accuracy: 2)
        assertAccess(manager, productID: productID)

        // Preserve the StoreKit account/history, but remove all app-side access and caches.
        manager.clearLocalSubscriptionState()
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
        XCTAssertNil(manager.currentEntitlementSnapshot)
        // Diagnostic only (LYB-231): lets a recurrence show whether StoreKit lost the transaction before restore.
        NSLog("%@", "STOREKIT_STATE_DIAG before restore: transactions=\(session.allTransactions().count)")
        let restored = await manager.restorePurchases()
        XCTAssertTrue(restored, manager.errorMessage ?? "Restore failed")
        XCTAssertEqual(client.restoreCount, 1)
        assertAccess(manager, productID: productID)

        if refund {
            let purchase = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == productID })
            try session.refundTransaction(identifier: purchase.identifier)
        } else {
            try session.expireSubscription(productIdentifier: productID)
        }
        try await waitForAccessRemoval(manager)
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
        let latestResult = await StoreKit.Transaction.latest(for: productID)
        let latest = try XCTUnwrap(latestResult).payloadValue
        if refund {
            XCTAssertNotNil(latest.revocationDate)
        } else {
            XCTAssertLessThanOrEqual(try XCTUnwrap(latest.expirationDate), Date())
        }
        let restoredAfterRemoval = await manager.restorePurchases()
        XCTAssertFalse(restoredAfterRemoval, "Restore must not resurrect expired/refunded access")
        XCTAssertFalse(manager.hasActiveSubscription)
        XCTAssertFalse(manager.cachedIsSubscribed)
    }

    private func loadTrialPackage(productID: String) async throws -> Package {
        let products = try await Product.products(for: [
            ProductRegistry.Paywall.annualProductID, ProductRegistry.Paywall.monthlyProductID
        ])
        XCTAssertEqual(Set(products.map(\.id)), [
            ProductRegistry.Paywall.annualProductID, ProductRegistry.Paywall.monthlyProductID
        ])
        let product = try XCTUnwrap(products.first { $0.id == productID })
        XCTAssertEqual(product.type, .autoRenewable)
        let subscription = try XCTUnwrap(product.subscription)
        let eligible = await subscription.isEligibleForIntroOffer
        XCTAssertTrue(eligible, "Each isolated session must be eligible for the trial")
        let offer = try XCTUnwrap(subscription.introductoryOffer)
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.price, 0)
        XCTAssertEqual(offer.period.unit, .day)
        XCTAssertEqual(offer.period.value, 3)
        XCTAssertEqual(offer.periodCount, 1)
        let annual = productID == ProductRegistry.Paywall.annualProductID
        return Package(
            identifier: annual ? ProductRegistry.Paywall.annualPackageID : ProductRegistry.Paywall.monthlyPackageID,
            packageType: annual ? .annual : .monthly,
            storeProduct: StoreProduct(sk2Product: product), offeringIdentifier: "storekit-ci", webCheckoutUrl: nil
        )
    }

    private func assertAccess(_ manager: RevenueCatManager, productID: String) {
        XCTAssertTrue(manager.hasActiveSubscription)
        XCTAssertTrue(manager.cachedIsSubscribed)
        XCTAssertTrue(manager.isInTrialPeriod)
        XCTAssertEqual(manager.currentSubscriptionProductIdentifier, productID)
        XCTAssertNotNil(manager.subscriptionExpirationDate)
    }

    private func waitForAccessRemoval(_ manager: RevenueCatManager) async throws {
        // StoreKit delivers expiration/refund asynchronously; bound the wait and fail on timeout.
        for _ in 0..<100 {
            await manager.refreshCustomerInfo()
            if !manager.hasActiveSubscription { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit expiration/refund did not remove app access within 10 seconds")
    }
}

/// Test-target-only adapter: access is derived exclusively from verified StoreKit transactions,
/// never a fixture Boolean. No SDK credentials, RevenueCat requests or App Store Connect writes.
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

    func customerInfo(entitlementID: String, read: RevenueCatCustomerInfoRead) async throws -> RevenueCatCustomerSnapshot {
        try await snapshot(entitlementID: entitlementID)
    }

    func offerings() async throws -> Offerings {
        throw LocalStoreKitError.unexpectedOfferingsRequest
    }

    func purchase(
        package: Package,
        entitlementID: String,
        verifiesOutcome: Bool
    ) async throws -> RevenueCatCustomerSnapshot {
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
            guard productIDs.contains(transaction.productID), transaction.revocationDate == nil,
                  let expiration = transaction.expirationDate, expiration > Date() else { continue }
            return RevenueCatCustomerSnapshot(
                originalAppUserId: appUserID,
                entitlement: RevenueCatEntitlementSnapshot(
                    isActive: true, expirationDate: expiration,
                    periodType: transaction.offer?.type == .introductory ? .trial : .normal,
                    willRenew: true, productIdentifier: transaction.productID, unsubscribeDetectedAt: nil
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
