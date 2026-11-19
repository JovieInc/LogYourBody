import Foundation
import CoreData

/// One body-metric repair scan per store-repair generation, on a background context.
///
/// Bump `storeRepairGeneration` when the repair rules change. A receipt for the
/// current generation means the library was already scanned, so the next launch
/// does not fetch body metrics.
enum BodyMetricLaunchRepair {
    static let storeRepairGeneration = 1
    static let receiptDefaultsKey = "lyb.bodyMetricStoreRepair.receipt"

    /// Counts `CachedBodyMetrics` fetches inside this repair. A matching receipt never increments it.
    static var bodyMetricFetchCount = 0

    struct Receipt: Codable, Equatable {
        var generation: Int
        var completedAt: Date
    }

    struct RunResult: Equatable {
        var repairedCount: Int
        var didFetchBodyMetrics: Bool
        var repairContextID: ObjectIdentifier?
        var repairContextIsViewContext: Bool
        var repairConcurrency: NSManagedObjectContextConcurrencyType?
    }

    static func runOnBackgroundContext(
        container: NSPersistentContainer,
        defaults: UserDefaults = .standard,
        generation: Int = storeRepairGeneration,
        now: Date = Date()
    ) async -> RunResult {
        if receipt(in: defaults)?.generation == generation {
            PerfSignpost.event(PerfSignpostContract.launchRepair, "skipped")
            return RunResult(
                repairedCount: 0,
                didFetchBodyMetrics: false,
                repairContextID: nil,
                repairContextIsViewContext: false,
                repairConcurrency: nil
            )
        }

        let context = makeBackgroundContext(container)
        let token = PerfSignpost.begin(PerfSignpostContract.launchRepair)
        let scan = await context.perform { () -> Scan in
            do {
                let metrics = try fetchAllBodyMetrics(in: context)
                let repairedCount = repair(metrics, now: now)
                if context.hasChanges {
                    try context.save()
                }
                return Scan(repairedCount: repairedCount, fetched: true)
            } catch {
                context.rollback()
                return Scan(repairedCount: 0, fetched: false)
            }
        }
        PerfSignpost.end(token)

        if scan.fetched {
            store(Receipt(generation: generation, completedAt: now), in: defaults)
        }

        return RunResult(
            repairedCount: scan.repairedCount,
            didFetchBodyMetrics: scan.fetched,
            repairContextID: ObjectIdentifier(context),
            repairContextIsViewContext: context === container.viewContext,
            repairConcurrency: context.concurrencyType
        )
    }

    static func makeBackgroundContext(_ container: NSPersistentContainer) -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    static func fetchAllBodyMetrics(in context: NSManagedObjectContext) throws -> [CachedBodyMetrics] {
        bodyMetricFetchCount += 1
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        return try context.fetch(request)
    }

    static func receipt(in defaults: UserDefaults) -> Receipt? {
        guard let data = defaults.data(forKey: receiptDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(Receipt.self, from: data)
    }

    private struct Scan {
        var repairedCount: Int
        var fetched: Bool
    }

    private static func repair(_ metrics: [CachedBodyMetrics], now: Date) -> Int {
        var repairedCount = 0
        for metric in metrics {
            var wasRepaired = false
            if metric.date == nil {
                metric.date = now
                wasRepaired = true
            }
            if metric.createdAt == nil {
                metric.createdAt = metric.date ?? now
                wasRepaired = true
            }
            if metric.updatedAt == nil {
                metric.updatedAt = metric.lastModified ?? metric.date ?? now
                wasRepaired = true
            }
            if metric.localDate == nil, let date = metric.date {
                metric.localDate = BodyMetricLocalDate.key(for: date)
                wasRepaired = true
            }
            if wasRepaired {
                repairedCount += 1
            }
        }
        return repairedCount
    }

    private static func store(_ receipt: Receipt, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        defaults.set(data, forKey: receiptDefaultsKey)
    }
}
