//
// BillingProviderAdmission.swift
// LogYourBody
//
// Purchase and restore admit one provider call before they await.
//

import Foundation
import RevenueCat

@MainActor
final class BillingProviderAdmission {
    enum Operation: Equatable {
        case purchase
        case restore
    }

    enum Decision {
        case started(Task<Bool, Never>)
        case shared(Task<Bool, Never>)
        case busy
    }

    private(set) var isInFlight = false
    private(set) var shareCount = 0
    private var operation: Operation?
    private var leader: Task<Bool, Never>?
    private var token: UUID?

    /// Sets the in-flight flag before returning. The work closure runs later, on the leader task.
    func admit(
        _ operation: Operation,
        work: @escaping @MainActor () async -> Bool
    ) -> Decision {
        if let leader, self.operation == operation {
            shareCount += 1
            return .shared(leader)
        }
        if isInFlight {
            return .busy
        }
        isInFlight = true
        self.operation = operation
        let token = UUID()
        self.token = token
        let task = Task { @MainActor in
            let result = await work()
            self.finish(token)
            return result
        }
        leader = task
        return .started(task)
    }

    private func finish(_ token: UUID) {
        guard self.token == token else { return }
        leader = nil
        self.token = nil
        operation = nil
        isInFlight = false
    }
}

extension RevenueCatManager {
    /// Purchase a package. The in-flight flag is set before any await so a second tap shares this call.
    func purchase(package: Package) async -> Bool {
        let decision = billingAdmission.admit(.purchase) {
            let verifiesOutcome = self.purchaseVerificationEnabled()
            let result = await self.performPurchase(package, verifiesOutcome: verifiesOutcome)
            self.isPurchasing = false
            return result
        }
        switch decision {
        case .busy:
            return false
        case .shared(let task):
            return await task.value
        case .started(let task):
            isPurchasing = true
            errorMessage = nil
            InteractionSignpost.emitPurchaseAdmit()
            return await task.value
        }
    }

    /// Restore purchases. The in-flight flag is set before any await so a second tap shares this call.
    func restorePurchases() async -> Bool {
        let decision = billingAdmission.admit(.restore) {
            let result = await self.performRestore()
            self.isPurchasing = false
            return result
        }
        switch decision {
        case .busy:
            return false
        case .shared(let task):
            return await task.value
        case .started(let task):
            isPurchasing = true
            errorMessage = nil
            InteractionSignpost.emitPurchaseAdmit()
            return await task.value
        }
    }

    func performPurchase(_ package: Package, verifiesOutcome: Bool) async -> Bool {
        guard let ownership = captureBillingSession() else {
            isPurchasing = false
            return false
        }

        do {
            let customer = try await purchasesClient.purchase(
                package: package,
                entitlementID: proEntitlementID,
                verifiesOutcome: verifiesOutcome
            )

            guard ownsBillingSession(ownership), !Task.isCancelled else {
                isPurchasing = false
                return false
            }

            updateSubscriptionStatus(customer: customer)
            isPurchasing = false

            if verifiesOutcome && !isSubscribed {
                errorMessage = "Your subscription is not active yet. "
                    + "Try Restore Purchases, or contact support if you were charged."
                return false
            }
            return true
        } catch let error as RevenueCatPurchasingError {
            guard ownsBillingSession(ownership), !Task.isCancelled else {
                isPurchasing = false
                return false
            }
            if error != .purchaseCancelled {
                ErrorReporter.shared.capture(
                    AppError.billing(operation: "purchase", underlying: error),
                    context: ErrorContext(
                        feature: "billing",
                        operation: "purchase",
                        screen: "PaywallView",
                        userId: ownership.subject
                    )
                )
            }
            isPurchasing = false
            switch error {
            case .purchaseCancelled:
                break
            case .storeProblem:
                errorMessage = "There was a problem with the App Store. Please try again."
            case .purchaseNotAllowed:
                errorMessage = "Purchases are not allowed on this device."
            case .purchaseInvalid:
                errorMessage = "Purchase failed. Please try again."
            case .unexpected(let message):
                errorMessage = "Purchase failed: \(message)"
            }
            return false
        } catch {
            guard ownsBillingSession(ownership), !Task.isCancelled else {
                isPurchasing = false
                return false
            }
            ErrorReporter.shared.capture(
                AppError.billing(operation: "purchase", underlying: error),
                context: ErrorContext(
                    feature: "billing",
                    operation: "purchase",
                    screen: "PaywallView",
                    userId: ownership.subject
                )
            )
            isPurchasing = false
            errorMessage = "An unexpected error occurred"
            return false
        }
    }

    func performRestore() async -> Bool {
        guard isConfigured else {
            isPurchasing = false
            errorMessage = "Service not ready. Please try again."
            return false
        }

        guard let ownership = captureBillingSession() else {
            isPurchasing = false
            return false
        }

        do {
            let customer = try await purchasesClient.restorePurchases(entitlementID: proEntitlementID)
            guard ownsBillingSession(ownership), !Task.isCancelled else {
                isPurchasing = false
                return false
            }
            updateSubscriptionStatus(customer: customer)
            isPurchasing = false
            if isSubscribed {
                return true
            }
            errorMessage = "No active subscriptions found"
            return false
        } catch {
            guard ownsBillingSession(ownership), !Task.isCancelled else {
                isPurchasing = false
                return false
            }
            ErrorReporter.shared.capture(
                AppError.billing(operation: "restorePurchases", underlying: error),
                context: ErrorContext(
                    feature: "billing",
                    operation: "restorePurchases",
                    screen: "PaywallView",
                    userId: ownership.subject
                )
            )
            isPurchasing = false
            errorMessage = "Failed to restore purchases"
            return false
        }
    }
}
