//
// WidgetDataManager.swift
// LogYourBody
//
import WidgetKit
import HealthKit
import UIKit

@MainActor


class WidgetDataManager: ObservableObject {
    static let shared = WidgetDataManager()
    private let sharedDefaults = UserDefaults(suiteName: "group.com.logyourbody.shared")
    private let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Update Widget Data

    func updateWidgetData() async {
        guard let userId = AuthManager.shared.currentUser?.id else { return }

        // Get latest metrics
        let latestMetrics = await fetchLatestMetrics(for: userId)
        let todaySteps = await fetchTodaySteps()

        // Update shared defaults
        sharedDefaults?.set(latestMetrics.weight ?? 0, forKey: "widget.latestWeight")
        sharedDefaults?.set(latestMetrics.bodyFat ?? 0, forKey: "widget.latestBodyFat")
        sharedDefaults?.set(todaySteps, forKey: "widget.todaySteps")
        sharedDefaults?.set(Date(), forKey: "widget.lastUpdated")

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Fetch Latest Metrics

    private func fetchLatestMetrics(for userId: String) async -> (weight: Double?, bodyFat: Double?) {
        let coreDataManager = CoreDataManager.shared

        // Get most recent body metrics
        let recentMetrics = await coreDataManager.fetchBodyMetrics(for: userId)
            .max { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }

        var weight: Double?
        var bodyFat: Double?

        if let metrics = recentMetrics {
            // Convert weight to user's preferred unit
            let weightUnit = UserDefaults.standard.string(forKey: "weightUnit") ?? "lbs"
            if metrics.weight > 0 {
                weight = weightUnit == "kg" ? metrics.weight : metrics.weight * 2.20462
            }

            bodyFat = metrics.bodyFatPercentage > 0 ? metrics.bodyFatPercentage : nil
        }

        return (weight, bodyFat)
    }

    // MARK: - Fetch Today's Steps

    private func fetchTodaySteps() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        // Check authorization
        let authStatus = healthStore.authorizationStatus(for: stepType)
        guard authStatus == .sharingAuthorized else { return 0 }

        // Create predicate for today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                guard let result = result,
                      let sum = result.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }

                let steps = Int(sum.doubleValue(for: .count()))
                continuation.resume(returning: steps)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Setup Automatic Updates

    func setupAutomaticUpdates() {
        // Update widget when app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Update widget when metrics are synced
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMetricsUpdated),
            name: NSNotification.Name("MetricsUpdated"),
            object: nil
        )

        // Set up timer for periodic updates (every 30 minutes)
        Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { _ in
            Task { @MainActor in
                await self.updateWidgetData()
            }
        }
    }

    @objc private func handleAppBecameActive() {
        Task {
            await updateWidgetData()
        }
    }

    @objc private func handleMetricsUpdated() {
        Task {
            await updateWidgetData()
        }
    }
}
