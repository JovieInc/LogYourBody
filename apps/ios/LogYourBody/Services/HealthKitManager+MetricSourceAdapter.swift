import Foundation
import HealthKit

extension HealthKitManager: MetricSourceAdapter {
    var capabilities: MetricSourceCapabilities {
        MetricSourceCapabilities(pushEvents: true, incrementalPull: true)
    }

    var lastSuccessfulSync: Date? {
        get async {
            await MainActor.run {
                guard let ownership = (importAuthManager ?? .shared).captureAccountSession() else { return nil }
                return userDefaults.object(
                    forKey: HealthKitDefaultsKey.lastSuccessfulSync.scoped(with: ownership.subject)
                ) as? Date
            }
        }
    }

    func idempotencyKey(for report: HKSample) -> String { report.uuid.uuidString }

    @MainActor
    func checkEntitlementAndCost() async throws {
        guard isAuthorized else { throw HealthKitError.notAuthorized }
        try metricSourceSyncGuard()
    }

    func replay(from startDate: Date?) async throws -> Bool {
        try Task.checkCancellation()
        try await checkEntitlementAndCost()
        guard let ownership = await captureImportOwnership() else { throw HealthKitError.notAuthorized }
        let succeeded = await syncAllHistoricalHealthKitData(ownership: ownership, from: startDate)
        guard succeeded else { throw HealthKitError.syncFailed }
        return true
    }

    @MainActor
    func recordSuccessfulMetricSourceSync(for ownership: AuthManager.ProfileSessionOwnership) {
        guard (importAuthManager ?? .shared).ownsAccountSession(ownership), !Task.isCancelled else { return }
        userDefaults.set(Date(), forKey: HealthKitDefaultsKey.lastSuccessfulSync.scoped(with: ownership.subject))
    }
}
