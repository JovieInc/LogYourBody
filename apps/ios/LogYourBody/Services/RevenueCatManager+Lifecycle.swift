import Foundation

enum AuthBillingSession: Equatable {
    case restoring
    case authenticated(AuthManager.ProfileSessionOwnership)
    case signedOut(generation: UInt64)
}

@MainActor
protocol AuthBillingLifecycle: AnyObject {
    func authenticationDidChange(_ session: AuthBillingSession)
}

final class BillingIdentityCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
final class BillingIdentityRequest {
    let ownership: RevenueCatManager.BillingSessionOwnership
    let cancellation = BillingIdentityCancellation()
    var finished = false

    init(ownership: RevenueCatManager.BillingSessionOwnership) {
        self.ownership = ownership
    }
}

extension RevenueCatManager: AuthBillingLifecycle {
    func authenticationDidChange(_ session: AuthBillingSession) {
        guard lastAuthBillingSession != session else { return }
        lastAuthBillingSession = session
        switch session {
        case .restoring:
            _ = beginBillingSession(subject: nil)
            desiredBillingIdentity = nil
            completeBillingIdentityWaiters()
            clearPublishedBillingAccess()
        case .authenticated(let owner):
            requestBillingIdentity(subject: owner.subject)
        case .signedOut:
            requestBillingIdentity(subject: nil)
        }
    }

    @discardableResult
    func requestBillingIdentity(subject: String?) -> BillingIdentityRequest {
        let ownership = beginBillingSession(subject: subject)
        // Superseded callers finish immediately; the SDK operation itself is not cancelled.
        completeBillingIdentityWaiters()
        let request = BillingIdentityRequest(ownership: ownership)
        desiredBillingIdentity = request
        if let subject {
            restoreCachedBillingAccess(for: subject)
        } else {
            clearPublishedBillingAccess()
            clearLocalSubscriptionState()
        }
        errorMessage = nil
        startBillingIdentityWorkerIfNeeded()
        return request
    }

    func restoreCachedBillingAccess(for subject: String) {
        let ownsCache = userDefaults.string(forKey: DefaultsKey.subscriptionOwner) == subject
        let subscribed = ownsCache && cachedIsSubscribed
        clearPublishedBillingAccess()
        if !ownsCache { clearLocalSubscriptionState() }
        isSubscribed = subscribed
    }

    private func clearPublishedBillingAccess() {
        customerInfo = nil
        currentEntitlementSnapshot = nil
        currentOffering = nil
        isSubscribed = false
        isPurchasing = false
    }

    func startBillingIdentityWorkerIfNeeded() {
        guard isConfigured, billingIdentityWorker == nil,
              let desiredBillingIdentity, desiredBillingIdentity.ownership != attemptedBillingIdentity else { return }
        billingIdentityWorker = Task { @MainActor in
            await reconcileBillingIdentity()
            billingIdentityWorker = nil
        }
    }

    private func reconcileBillingIdentity() async {
        while let desired = desiredBillingIdentity, desired.ownership != attemptedBillingIdentity {
            attemptedBillingIdentity = desired.ownership
            await reconcileBillingIdentity(desired)
        }
    }

    private func reconcileBillingIdentity(_ request: BillingIdentityRequest) async {
        let ownership = request.ownership
        defer {
            request.finished = true
            completeBillingIdentityWaiters(generation: ownership.generation)
        }
        do {
            if let subject = ownership.subject {
                let customer = try await purchasesClient.logIn(userId: subject, entitlementID: proEntitlementID)
                guard ownsBillingSession(ownership) else { return }
                if !request.cancellation.isCancelled { updateSubscriptionStatus(customer: customer) }
            } else {
                try await purchasesClient.logOut()
                guard ownsBillingSession(ownership) else { return }
                clearLocalSubscriptionState()
            }
            finishBillingSession(ownership)
        } catch {
            guard ownsBillingSession(ownership), !request.cancellation.isCancelled else { return }
            // Keep the owner pending: the SDK might still be the previous account.
            let operation = ownership.subject == nil ? "logoutUser" : "identifyUser"
            ErrorReporter.shared.capture(
                AppError.billing(operation: operation, underlying: error),
                context: ErrorContext(feature: "billing", operation: operation, screen: nil, userId: ownership.subject)
            )
            if ownership.subject != nil {
                errorMessage = "Failed to link account: \(error.localizedDescription)"
            }
        }
    }

    func waitForBillingIdentity(_ request: BillingIdentityRequest) async {
        let ownership = request.ownership
        guard isConfigured, ownsBillingSession(ownership), !request.finished else { return }
        let cancellation = request.cancellation
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !cancellation.isCancelled, ownsBillingSession(ownership), !request.finished else {
                    continuation.resume()
                    return
                }
                billingIdentityWaiters[ownership.generation, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.completeBillingIdentityWaiter(generation: ownership.generation, waiterID: waiterID)
            }
        }
    }

    private func completeBillingIdentityWaiter(generation: UInt64, waiterID: UUID) {
        let waiter = billingIdentityWaiters[generation]?.removeValue(forKey: waiterID)
        if billingIdentityWaiters[generation]?.isEmpty == true {
            billingIdentityWaiters.removeValue(forKey: generation)
        }
        waiter?.resume()
    }

    func retryPendingBillingIdentityIfNeeded() async {
        guard billingIdentityWorker == nil, let desired = desiredBillingIdentity,
              desired.ownership.subject != nil, ownsBillingSession(desired.ownership) else { return }
        let retry = requestBillingIdentity(subject: desired.ownership.subject)
        await waitForBillingIdentity(retry)
    }

    func waitForBillingReconciliation() async {
        await billingIdentityWorker?.value
    }

    private func completeBillingIdentityWaiters(generation: UInt64? = nil) {
        if let generation {
            let waiters = billingIdentityWaiters.removeValue(forKey: generation) ?? [:]
            waiters.values.forEach { $0.resume() }
        } else {
            let waiters = billingIdentityWaiters.values.flatMap { Array($0.values) }
            billingIdentityWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}
