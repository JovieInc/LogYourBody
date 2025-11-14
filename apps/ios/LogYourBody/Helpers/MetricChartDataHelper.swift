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
    private static var chartDataCache: [String: CachedChartData] = [:]

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

    /// Cache entry with timestamp for expiration
    private struct CachedChartData {
        let data: [SparklineDataPoint]
        let timestamp: Date

        var isExpired: Bool {
            // Cache expires after 5 minutes
            Date().timeIntervalSince(timestamp) > 300
        }
    }

    /// Generate cache key from parameters
    private static func cacheKey(
        userId: String,
        days: Int,
        metricType: String,
        useMetric: Bool
    ) -> String {
        return "\(userId)_\(days)_\(metricType)_\(useMetric)"
    }

    /// Clear expired cache entries
    static func clearExpiredCache() {
        chartDataCache = chartDataCache.filter { !$0.value.isExpired }
    }

    /// Clear all cache (call when data changes)
    static func clearCache() {
        chartDataCache.removeAll()
    }

    /// Clear cache for specific user
    static func clearCache(for userId: String) {
        chartDataCache = chartDataCache.filter { !$0.key.hasPrefix(userId) }
    }

    // MARK: - Steps Chart Data

    /// Generate last 7 days of steps data for sparkline chart (with caching)
    static func generateStepsChartData(for userId: String) -> [SparklineDataPoint] {
        let key = cacheKey(userId: userId, days: 7, metricType: "steps", useMetric: false)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
        }

        // Generate chart data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rawData = (0..<7).compactMap { daysAgo -> SparklineDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                let steps = dailyData.steps
                if steps > 0 {
                    return SparklineDataPoint(index: 6 - daysAgo, value: Double(steps))
                }
            }
            return nil
        }

        let data = Array(rawData.reversed())

        // Cache the result
        chartDataCache[key] = CachedChartData(data: data, timestamp: Date())

        return data
    }

    // MARK: - Weight Chart Data

    // TODO: Remove old 7-day functions - replaced by generateChartData()
    /*
    /// Generate last 7 days of weight data for sparkline chart (with caching)
    /// - Parameter useMetric: If true, returns kg; if false, returns lbs
    static func generateWeightChartData(for userId: String, useMetric: Bool) -> [SparklineDataPoint] {
        let key = cacheKey(userId: userId, days: 7, metricType: "weight", useMetric: useMetric)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
        }

        // Generate chart data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rawData = (0..<7).compactMap { daysAgo -> SparklineDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                let weightKg = dailyData.weight
                if weightKg > 0 {
                    let displayWeight = useMetric ? weightKg : weightKg * 2.20462 // Convert to lbs
                    return SparklineDataPoint(index: 6 - daysAgo, value: displayWeight)
                }
            }
            return nil
        }

        let data = Array(rawData.reversed())

        // Cache the result
        chartDataCache[key] = CachedChartData(data: data, timestamp: Date())

        return data
    }

    // MARK: - Body Fat Percentage Chart Data

    /// Generate last 7 days of body fat percentage data for sparkline chart (with caching)
    static func generateBodyFatChartData(for userId: String) -> [SparklineDataPoint] {
        let key = cacheKey(userId: userId, days: 7, metricType: "bodyFat", useMetric: false)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
        }

        // Generate chart data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rawData = (0..<7).compactMap { daysAgo -> SparklineDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                let bodyFat = dailyData.bodyFatPercentage
                if bodyFat > 0 {
                    return SparklineDataPoint(index: 6 - daysAgo, value: bodyFat)
                }
            }
            return nil
        }

        let data = Array(rawData.reversed())

        // Cache the result
        chartDataCache[key] = CachedChartData(data: data, timestamp: Date())

        return data
    }

    // MARK: - FFMI Chart Data

    /// Generate last 7 days of FFMI data for sparkline chart (with caching)
    static func generateFFMIChartData(for userId: String) -> [SparklineDataPoint] {
        let key = cacheKey(userId: userId, days: 7, metricType: "ffmi", useMetric: false)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
        }

        // Generate chart data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rawData = (0..<7).compactMap { daysAgo -> SparklineDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                // Calculate FFMI if we have weight, body fat, and height
                let weightKg = dailyData.weight
                let bodyFat = dailyData.bodyFatPercentage
                let heightCm = dailyData.height

                guard weightKg > 0, bodyFat > 0, heightCm > 0 else {
                    return nil
                }

                let ffmi = calculateFFMI(weightKg: weightKg, bodyFatPercentage: bodyFat, heightCm: heightCm)
                return SparklineDataPoint(index: 6 - daysAgo, value: ffmi)
            }
            return nil
        }

        let data = Array(rawData.reversed())

        // Cache the result
        chartDataCache[key] = CachedChartData(data: data, timestamp: Date())

        return data
    }

    // MARK: - Waist Measurement Chart Data

    /// Generate last 7 days of waist measurement data for sparkline chart (with caching)
    /// - Parameter useMetric: If true, returns cm; if false, returns inches
    /// - Note: Waist measurement is not currently tracked in Core Data
    static func generateWaistChartData(for userId: String, useMetric: Bool) -> [SparklineDataPoint] {
        // Waist measurement not currently implemented in Core Data
        return []
    }
    */

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

    // TODO: Fix Core Data property access issues
    /// Generate chart data for a specific metric over a given period (with caching)
    /// - Parameters:
    ///   - userId: User ID to fetch data for
    ///   - days: Number of days to fetch (7, 30, 90, 180, 365)
    ///   - metricType: Type of metric to fetch
    ///   - useMetric: Whether to use metric units (for weight/waist)
    static func generateChartData(
        for userId: String,
        days: Int,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool = false
    ) -> [SparklineDataPoint] {
        // Temporary stub - return empty data
        return []
        /*
        let metricTypeString = String(describing: metricType)
        let key = cacheKey(userId: userId, days: days, metricType: metricTypeString, useMetric: useMetric)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
        }

        // Generate chart data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let rawData = (0..<days).compactMap { daysAgo -> SparklineDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            guard let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) else {
                return nil
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
                return SparklineDataPoint(index: days - 1 - daysAgo, value: value)
            }
            return nil
        }

        let data = Array(rawData.reversed())

        // Apply downsampling for large datasets (>90 days)
        let finalData = days > 90 ? downsampleData(data) : data

        // Cache the result
        chartDataCache[key] = CachedChartData(data: finalData, timestamp: Date())

        return finalData
        */
    }

    // MARK: - Async Chart Data Generation

    // TODO: Re-enable async function once Core Data property access is resolved
    /*
    /// Generate chart data asynchronously for better performance
    /// - Parameters:
    ///   - userId: User ID to fetch data for
    ///   - days: Number of days to fetch (7, 30, 90, 180, 365)
    ///   - metricType: Type of metric to fetch
    ///   - useMetric: Whether to use metric units (for weight/waist)
    @MainActor
    static func generateChartDataAsync(
        for userId: String,
        days: Int,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetric: Bool = false
    ) async -> [SparklineDataPoint] {
        let metricTypeString = String(describing: metricType)
        let key = cacheKey(userId: userId, days: days, metricType: metricTypeString, useMetric: useMetric)

        // Check cache first
        if let cached = chartDataCache[key], !cached.isExpired {
            return cached.data
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
