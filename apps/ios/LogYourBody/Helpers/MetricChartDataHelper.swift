//
// MetricChartDataHelper.swift
// LogYourBody
//
// Helper functions for generating chart data for dashboard metric cards
//

import Foundation
import CoreData

/// Helper functions to generate sparkline chart data for metric cards
struct MetricChartDataHelper {
    // MARK: - Cache Infrastructure

    /// Cache for chart data to avoid redundant computations
    private static let chartDataCache = LRUCache<ChartCacheKey, [SparklineDataPoint]>(capacity: 50)

    /// Setup Core Data change notifications for automatic cache invalidation
    static func setupCacheInvalidation() {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: CoreDataManager.shared.viewContext,
            queue: .main
        ) { notification in
            // Check if any CachedDailyMetrics were inserted, updated, or deleted
            if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>,
               insertedObjects.contains(where: { $0 is CachedDailyMetrics }) {
                clearCache()
                return
            }
            if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>,
               updatedObjects.contains(where: { $0 is CachedDailyMetrics }) {
                clearCache()
                return
            }

            if let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>,
               deletedObjects.contains(where: { $0 is CachedDailyMetrics }) {
                clearCache()
                return
            }
        }
    }

    // MARK: - Cache Helpers

    private struct ChartCacheKey: Hashable {
        let userId: String
        let days: Int?
        let metricIdentifier: String
        let useMetric: Bool
        let dataFingerprint: Int
    }

    private struct DailyMetricsSnapshot {
        let index: Int
        let value: Double
        let referenceDate: Date
        let lastModified: Date
    }

    private struct DailyMetricValue {
        let steps: Int
        let lastModified: Date
    }

    // MARK: - Local Fetch Helpers

    private static func bodyMetricsFetchRequest(
        for userId: String,
        from startDate: Date?,
        to endDate: Date?
    ) -> NSFetchRequest<CachedBodyMetrics> {
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()

        var predicates: [NSPredicate] = [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "isMarkedDeleted == %@", NSNumber(value: false))
        ]

        if let startDate {
            predicates.append(NSPredicate(format: "date >= %@", startDate as NSDate))
        }

        if let endDate {
            predicates.append(NSPredicate(format: "date <= %@", endDate as NSDate))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchBatchSize = 20
        request.returnsObjectsAsFaults = true

        return request
    }

    private static func bodyMetrics(for userId: String, from startDate: Date?, to endDate: Date?) -> [BodyMetrics] {
        let context = CoreDataManager.shared.viewContext
        var results: [BodyMetrics] = []

        context.performAndWait {
            let request = bodyMetricsFetchRequest(for: userId, from: startDate, to: endDate)
            let fetched = (try? context.fetch(request)) ?? []
            results = fetched.compactMap { $0.toBodyMetrics() }
        }

        return EntryVisibilityManager.shared.resolvedVisibleMetrics(results, userId: userId)
    }

    private static func bodyMetricsAsync(for userId: String, from startDate: Date?, to endDate: Date?) async -> [BodyMetrics] {
        let context = CoreDataManager.shared.viewContext

        let metrics = await context.perform {
            let request = bodyMetricsFetchRequest(for: userId, from: startDate, to: endDate)
            let fetched = (try? context.fetch(request)) ?? []
            return fetched.compactMap { $0.toBodyMetrics() }
        }

        return EntryVisibilityManager.shared.resolvedVisibleMetrics(metrics, userId: userId)
    }

    private static func dailyMetric(for userId: String, date: Date) -> DailyMetricValue? {
        let context = CoreDataManager.shared.viewContext
        var result: DailyMetricValue?

        context.performAndWait {
            let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

            request.predicate = NSPredicate(
                format: "userId == %@ AND date >= %@ AND date < %@ AND isMarkedDeleted == %@",
                userId,
                startOfDay as NSDate,
                endOfDay as NSDate,
                NSNumber(value: false)
            )
            request.fetchLimit = 1

            if let metric = try? context.fetch(request).first {
                let steps = Int(metric.steps)
                guard steps > 0 else { return }
                let lastModified = metric.lastModified ?? metric.updatedAt ?? date
                result = DailyMetricValue(steps: steps, lastModified: lastModified)
            }
        }

        return result
    }

    private static func metricIdentifier(for metricType: DashboardViewLiquid.DashboardMetricKind) -> String {
        switch metricType {
        case .steps: return "steps"
        case .weight: return "weight"
        case .bodyFat: return "bodyFat"
        case .ffmi: return "ffmi"
        case .waist: return "waist"
        }
    }

    private static func stepsFingerprint(from snapshots: [DailyMetricsSnapshot]) -> Int {
        guard !snapshots.isEmpty else { return 0 }
        var hasher = Hasher()
        hasher.combine(snapshots.count)
        for snapshot in snapshots.sorted(by: { $0.index < $1.index }) {
            hasher.combine(snapshot.index)
            hasher.combine(snapshot.value)
            hasher.combine(snapshot.referenceDate.timeIntervalSinceReferenceDate)
            hasher.combine(snapshot.lastModified.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    private static func metricFingerprint(
        for metrics: [BodyMetrics],
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool,
        profile: UserProfile?
    ) -> Int? {
        guard !metrics.isEmpty else { return nil }

        var hasher = Hasher()
        hasher.combine(metricIdentifier(for: metricType))
        hasher.combine(useMetric)

        if metricType == .ffmi {
            hasher.combine(profile?.height ?? 0)
            hasher.combine(profile?.heightUnit ?? "")
        }

        for metric in metrics {
            hasher.combine(metric.id)
            hasher.combine(metric.date.timeIntervalSinceReferenceDate)
            hasher.combine(metric.updatedAt.timeIntervalSinceReferenceDate)

            switch metricType {
            case .steps:
                break
            case .weight:
                hasher.combine(metric.weight != nil)
                if let weight = metric.weight { hasher.combine(weight) }
                hasher.combine(metric.weightUnit ?? "")
            case .bodyFat:
                hasher.combine(metric.bodyFatPercentage != nil)
                if let bodyFat = metric.bodyFatPercentage { hasher.combine(bodyFat) }
            case .ffmi:
                hasher.combine(metric.weight != nil)
                if let weight = metric.weight { hasher.combine(weight) }
                hasher.combine(metric.bodyFatPercentage != nil)
                if let bodyFat = metric.bodyFatPercentage { hasher.combine(bodyFat) }
            case .waist:
                hasher.combine(metric.muscleMass != nil)
                if let muscleMass = metric.muscleMass { hasher.combine(muscleMass) }
            }
        }

        return hasher.finalize()
    }

    /// Clear all cache (call when data changes)
    static func clearCache() {
        chartDataCache.removeAll()
    }

    /// Clear cache for specific user
    static func clearCache(for userId: String) {
        chartDataCache.removeAll { key, _ in
            key.userId == userId
        }
    }

    // MARK: - Steps Chart Data

    /// Generate last 7 days of steps data for sparkline chart (with caching)
    static func generateStepsChartData(for userId: String) -> [SparklineDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var snapshots: [DailyMetricsSnapshot] = []

        for daysAgo in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                continue
            }

            guard let dailyData = dailyMetric(for: userId, date: date) else {
                continue
            }

            snapshots.append(
                DailyMetricsSnapshot(
                    index: 6 - daysAgo,
                    value: Double(dailyData.steps),
                    referenceDate: date,
                    lastModified: dailyData.lastModified
                )
            )
        }

        let fingerprint = stepsFingerprint(from: snapshots)
        let cacheKey = ChartCacheKey(
            userId: userId,
            days: 7,
            metricIdentifier: metricIdentifier(for: .steps),
            useMetric: false,
            dataFingerprint: fingerprint
        )

        if let cached = chartDataCache.value(for: cacheKey) {
            return cached
        }

        let data = snapshots
            .sorted { $0.index < $1.index }
            .map { SparklineDataPoint(index: $0.index, value: $0.value) }

        chartDataCache.setValue(data, for: cacheKey)

        return data
    }

    // MARK: - Weight Chart Data

    // Old 7-day sparkline helpers have been removed in favor of generateChartData().

    static func generateWeightChartData(for userId: String, useMetric: Bool, profile: UserProfile? = nil) -> [SparklineDataPoint] {
        generateChartData(for: userId, days: 7, metricType: .weight, useMetric: useMetric, profile: profile)
    }

    static func generateBodyFatChartData(for userId: String, profile: UserProfile? = nil) -> [SparklineDataPoint] {
        generateChartData(for: userId, days: 7, metricType: .bodyFat, useMetric: true, profile: profile)
    }

    static func generateFFMIChartData(for userId: String, profile: UserProfile?) -> [SparklineDataPoint] {
        generateChartData(for: userId, days: 7, metricType: .ffmi, useMetric: true, profile: profile)
    }

    static func generateWaistChartData(for userId: String, useMetric: Bool, profile: UserProfile? = nil) -> [SparklineDataPoint] {
        generateChartData(for: userId, days: 7, metricType: .waist, useMetric: useMetric, profile: profile)
    }

    // MARK: - FFMI Calculation

    /// Calculate Fat Free Mass Index
    /// FFMI = (weight × (1 - body fat %)) / height² + 6.1 × (1.8 - height)
    private static func calculateFFMI(weightKg: Double, bodyFatPercentage: Double, heightCm: Double) -> Double {
        let heightM = heightCm / 100.0
        let fatFreeMassKg = weightKg * (1 - bodyFatPercentage / 100)
        let ffmi = (fatFreeMassKg / (heightM * heightM)) + 6.1 * (1.8 - heightM)
        return ffmi
    }

    // MARK: - Data Downsampling

    /// Downsample data points to reduce rendering load for large datasets
    /// - Parameters:
    ///   - data: Array of data points to downsample
    ///   - targetCount: Target number of points (default: 150)
    /// - Returns: Downsampled array of data points
    private static func downsampleData(_ data: [SparklineDataPoint], targetCount: Int = 150) -> [SparklineDataPoint] {
        guard data.count > targetCount else { return data }

        let step = Double(data.count) / Double(targetCount)
        var downsampled: [SparklineDataPoint] = []

        for i in 0..<targetCount {
            let index = Int(Double(i) * step)
            if index < data.count {
                downsampled.append(data[index])
            }
        }

        return downsampled
    }

    // MARK: - Generic Period-Based Chart Data

    /// Generate chart data for a specific metric over a given period (with caching)
    /// - Parameters:
    ///   - userId: User ID to fetch data for
    ///   - days: Number of days to fetch (7, 30, 90, 180, 365)
    ///   - metricType: Type of metric to fetch
    ///   - useMetric: Whether to use metric units (for weight/waist)
    static func generateChartData(
        for userId: String,
        days: Int?,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool = false,
        profile: UserProfile? = nil
    ) -> [SparklineDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate: Date?

        if let days = days {
            startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        } else {
            startDate = nil
        }

        let metrics = bodyMetrics(for: userId, from: startDate, to: today)
        return composeChartData(
            for: userId,
            days: days,
            metricType: metricType,
            useMetric: useMetric,
            profile: profile,
            metrics: metrics,
            startDate: startDate
        )
    }

    /// Async version for generating chart data using non-blocking Core Data fetches
    static func generateChartDataAsync(
        for userId: String,
        days: Int?,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool = false,
        profile: UserProfile? = nil
    ) async -> [SparklineDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate: Date?

        if let days = days {
            startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today)
        } else {
            startDate = nil
        }

        let metrics = await bodyMetricsAsync(for: userId, from: startDate, to: today)

        return composeChartData(
            for: userId,
            days: days,
            metricType: metricType,
            useMetric: useMetric,
            profile: profile,
            metrics: metrics,
            startDate: startDate
        )
    }

    private static func composeChartData(
        for userId: String,
        days: Int?,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool,
        profile: UserProfile?,
        metrics: [BodyMetrics],
        startDate: Date?
    ) -> [SparklineDataPoint] {
        guard !metrics.isEmpty else { return [] }

        let filteredMetrics: [BodyMetrics]
        if let startDate {
            filteredMetrics = metrics.filter { $0.date >= startDate }
        } else {
            filteredMetrics = metrics
        }

        guard !filteredMetrics.isEmpty else { return [] }

        guard let fingerprint = metricFingerprint(
            for: filteredMetrics,
            metricType: metricType,
            useMetric: useMetric,
            profile: profile
        ) else {
            return []
        }

        let cacheKey = ChartCacheKey(
            userId: userId,
            days: days,
            metricIdentifier: metricIdentifier(for: metricType),
            useMetric: useMetric,
            dataFingerprint: fingerprint
        )

        if let cached = chartDataCache.value(for: cacheKey) {
            return cached
        }

        let dataPoints = filteredMetrics.enumerated().compactMap { index, metric -> SparklineDataPoint? in
            switch metricType {
            case .steps:
                guard let value = dailyMetric(for: userId, date: metric.date)?.steps else { return nil }
                return SparklineDataPoint(index: index, value: Double(value))
            case .weight:
                guard let weight = metric.weight else { return nil }
                let targetSystem: MeasurementSystem = useMetric ? .metric : .imperial
                let converted = convertWeight(weight, to: targetSystem)
                return SparklineDataPoint(index: index, value: converted)
            case .bodyFat:
                if let value = metric.bodyFatPercentage {
                    return SparklineDataPoint(index: index, value: value)
                }
                return MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: metrics).map {
                    SparklineDataPoint(index: index, value: $0.value, isEstimated: $0.isInterpolated)
                }
            case .ffmi:
                let heightInches = convertHeightToInches(height: profile?.height, heightUnit: profile?.heightUnit)
                guard let ffmi = MetricsInterpolationService.shared.estimateFFMI(for: metric.date, metrics: metrics, heightInches: heightInches) else {
                    return nil
                }
                return SparklineDataPoint(index: index, value: ffmi.value, isEstimated: ffmi.isInterpolated)
            case .waist:
                return nil
            }
        }

        guard !dataPoints.isEmpty else { return [] }

        let finalData: [SparklineDataPoint]
        if let days, days > 90 {
            finalData = downsampleData(dataPoints)
        } else {
            finalData = dataPoints
        }

        chartDataCache.setValue(finalData, for: cacheKey)

        return finalData
    }

    // MARK: - Conversion Helpers

    private static func convertWeight(_ weight: Double, to system: MeasurementSystem) -> Double {
        switch system {
        case .metric:
            return weight
        case .imperial:
            return weight * 2.20462
        }
    }

    private static func convertHeightToInches(height: Double?, heightUnit: String?) -> Double? {
        guard let height else { return nil }
        if heightUnit?.lowercased() == "cm" {
            return height / 2.54
        }
        return height
    }

    // MARK: - Async Chart Data Generation

    // TODO: Re-enable async function once Core Data property access is resolved
    /*
     /// Generate chart data asynchronously for better performance
     /// - Parameters:
     }

     // Generate chart data asynchronously using batch fetch
     let calendar = Calendar.current
     let today = calendar.startOfDay(for: Date())
     guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
     return []
     }

     // Batch fetch all daily metrics for the date range (much faster than individual queries)
     let dailyMetrics = await CoreDataManager.shared.fetchDailyMetricsBatch(
     for: userId,
     startDate: startDate,
     endDate: today
     )

     // Create a dictionary for fast lookup by date
     var metricsByDate: [Date: CachedDailyMetrics] = [:]
     for metric in dailyMetrics {
     guard let metricDate = metric.date else { continue }
     let dayStart = calendar.startOfDay(for: metricDate)
     metricsByDate[dayStart] = metric
     }

     var dataPoints: [SparklineDataPoint] = []

     for daysAgo in 0..<days {
     guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
     continue
     }

     // Look up data from batch fetch results
     guard let dailyData = metricsByDate[date] else {
     continue
     }

     let value: Double?

     switch metricType {
     case .steps:
     let steps = dailyData.steps
     value = steps > 0 ? Double(steps) : nil
     case .weight:
     let weightKg = dailyData.weight
     if weightKg > 0 {
     value = useMetric ? weightKg : weightKg * 2.20462
     } else {
     value = nil
     }
     case .bodyFat:
     let bodyFat = dailyData.bodyFatPercentage
     value = bodyFat > 0 ? bodyFat : nil
     case .ffmi:
     let weightKg = dailyData.weight
     let bodyFat = dailyData.bodyFatPercentage
     let heightCm = dailyData.height
     if weightKg > 0 && bodyFat > 0 && heightCm > 0 {
     value = calculateFFMI(weightKg: weightKg, bodyFatPercentage: bodyFat, heightCm: heightCm)
     } else {
     value = nil
     }
     case .waist:
     // Waist measurement not currently stored in Core Data
     value = nil
     }

     if let value = value, value > 0 {
     dataPoints.append(SparklineDataPoint(index: days - 1 - daysAgo, value: value))
     }
     }

     let data = Array(dataPoints.reversed())

     // Apply downsampling for large datasets (>90 days)
     let finalData = days > 90 ? downsampleData(data) : data

     // Cache the result
     chartDataCache[key] = CachedChartData(data: finalData, timestamp: Date())

     return finalData
     }
     */
}
