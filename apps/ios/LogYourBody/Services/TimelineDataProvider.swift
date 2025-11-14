//
// TimelineDataProvider.swift
// LogYourBody
//
// Data fetching and caching layer for Progress Timeline
//

import Foundation
import Combine

/// Provides data for the timeline with intelligent caching and nearest-match logic
class TimelineDataProvider: ObservableObject {
    @Published private(set) var bodyMetrics: [BodyMetrics] = []
    @Published private(set) var isLoading: Bool = false

    private let photoSearchWindow: TimeInterval = 7 * 24 * 60 * 60  // ±7 days
    private let metricSearchWindow: TimeInterval = 7 * 24 * 60 * 60  // ±7 days

    // MARK: - Data Loading

    /// Load all body metrics (would integrate with your existing data layer)
    func loadMetrics(_ metrics: [BodyMetrics]) {
        self.bodyMetrics = metrics.sorted { $0.date < $1.date }
    }

    // MARK: - Photo Mode - Find Nearest Photo and Metrics

    /// Find nearest photo and metrics for a given scrub date
    /// Returns both independently within their respective search windows
    func findDataForPhotoMode(scrubDate: Date) -> TimelineDataResult {
        let photoResult = findNearestPhoto(to: scrubDate, within: photoSearchWindow)
        let metricsResult = findNearestMetrics(to: scrubDate, within: metricSearchWindow)

        return TimelineDataResult(
            scrubDate: scrubDate,
            photo: photoResult,
            metrics: metricsResult
        )
    }

    private func findNearestPhoto(to date: Date, within window: TimeInterval) -> TimelineDataResult.PhotoResult? {
        let metricsWithPhotos = bodyMetrics.filter { metric in
            guard let photoUrl = metric.photoUrl else { return false }
            return !photoUrl.isEmpty
        }

        guard !metricsWithPhotos.isEmpty else { return nil }

        // Find nearest photo within window
        var nearest: BodyMetrics?
        var smallestDiff: TimeInterval = window

        for metric in metricsWithPhotos {
            let diff = abs(metric.date.timeIntervalSince(date))
            if diff <= window && diff < smallestDiff {
                nearest = metric
                smallestDiff = diff
            }
        }

        guard let found = nearest else { return nil }

        let days = Int(smallestDiff / (24 * 60 * 60))
        return TimelineDataResult.PhotoResult(bodyMetrics: found, daysFromScrub: days)
    }

    private func findNearestMetrics(to date: Date, within window: TimeInterval) -> TimelineDataResult.MetricsResult? {
        // First try to find exact or nearest metric date
        var nearest: BodyMetrics?
        var smallestDiff: TimeInterval = window

        for metric in bodyMetrics {
            let hasData = metric.weight != nil || metric.bodyFatPercentage != nil
            guard hasData else { continue }

            let diff = abs(metric.date.timeIntervalSince(date))
            if diff <= window && diff < smallestDiff {
                nearest = metric
                smallestDiff = diff
            }
        }

        if let found = nearest {
            let days = Int(smallestDiff / (24 * 60 * 60))
            return TimelineDataResult.MetricsResult(
                bodyMetrics: found,
                daysFromScrub: days,
                isInterpolated: false
            )
        }

        // If no direct match, try interpolation
        // (This would integrate with your existing MetricsInterpolationService)
        // For now, return nil if no match found
        return nil
    }

    // MARK: - Avatar Mode - Get All Data Dates

    /// Get all dates that have any data (weight OR BF% OR photo)
    /// Used for snap points in Avatar Mode
    func getAllDataDates() -> [Date] {
        let metricsWithData = TimelinePhotoSampler.metricsWithData(from: bodyMetrics)
        return metricsWithData.map { $0.date }.sorted()
    }

    /// Find nearest data date for snapping in Avatar Mode
    func findNearestDataDate(to scrubDate: Date) -> Date? {
        let dataDates = getAllDataDates()
        guard !dataDates.isEmpty else { return nil }

        var nearest: Date?
        var smallestDiff: TimeInterval = .infinity

        for date in dataDates {
            let diff = abs(date.timeIntervalSince(scrubDate))
            if diff < smallestDiff {
                nearest = date
                smallestDiff = diff
            }
        }

        return nearest
    }

    /// Get metric for a specific date (exact match)
    func getMetric(for date: Date) -> BodyMetrics? {
        // Find metric with matching date (within same day)
        let calendar = Calendar.current
        return bodyMetrics.first { metric in
            calendar.isDate(metric.date, inSameDayAs: date)
        }
    }

    // MARK: - Timeline Anchors Generation

    /// Generate timeline anchors for rendering
    /// Uses time-weighted positioning algorithm
    func generateAnchors(mode: TimelineMode, zoomLevel: TimelineZoomLevel) -> [TimelineAnchor] {
        guard !bodyMetrics.isEmpty else { return [] }

        let sortedMetrics = bodyMetrics.sorted { $0.date < $1.date }
        guard let firstDate = sortedMetrics.first?.date,
              let lastDate = sortedMetrics.last?.date else {
            return []
        }

        // Create buckets based on zoom level
        var buckets = TimelineBucketCalculator.createBuckets(
            from: firstDate,
            to: lastDate,
            zoomLevel: zoomLevel
        )

        // Distribute metrics to buckets
        TimelineBucketCalculator.distributeToBuckets(metrics: sortedMetrics, buckets: &buckets)

        // Sample based on mode
        let sampledMetrics: [BodyMetrics]
        if mode == .photo {
            // Photo mode: sample photos, show metrics as subtle ticks
            let photoBuckets = buckets.map { bucket in
                var photoBucket = bucket
                photoBucket.candidates = TimelinePhotoSampler.metricsWithPhotos(from: bucket.candidates)
                return photoBucket
            }
            sampledMetrics = TimelinePhotoSampler.samplePhotos(
                from: photoBuckets,
                maxThumbnails: zoomLevel.maxVisibleThumbnails,
                sortedMetrics: sortedMetrics
            )
        } else {
            // Avatar mode: show all data points (may need thinning for very dense data)
            let dataBuckets = buckets.map { bucket in
                var dataBucket = bucket
                dataBucket.candidates = TimelinePhotoSampler.metricsWithData(from: bucket.candidates)
                return dataBucket
            }
            sampledMetrics = TimelinePhotoSampler.samplePhotos(
                from: dataBuckets,
                maxThumbnails: zoomLevel.maxVisibleThumbnails * 2,  // Allow more in avatar mode
                sortedMetrics: sortedMetrics
            )
        }

        // Convert to anchors with time-weighted positions
        return sampledMetrics.enumerated().map { index, metric in
            let position = calculateTimeWeightedPosition(
                for: metric.date,
                from: firstDate,
                to: lastDate
            )

            let hasPhoto = metric.photoUrl != nil && !(metric.photoUrl?.isEmpty ?? true)
            let hasMetrics = metric.weight != nil || metric.bodyFatPercentage != nil

            let anchorType: TimelineAnchor.AnchorType
            if hasPhoto && hasMetrics {
                anchorType = .photoWithMetrics
            } else if hasPhoto {
                anchorType = .photo
            } else {
                anchorType = .metricsOnly
            }

            let importance = calculateImportance(for: metric.date)

            return TimelineAnchor(
                id: metric.id,
                date: metric.date,
                position: position,
                bodyMetrics: metric,
                anchorType: anchorType,
                importance: importance
            )
        }
    }

    // MARK: - Time-Weighted Positioning

    /// Calculate time-weighted position (0.0 to 1.0)
    /// Last 30 days get 70% of space, next 11 months get 20%, older gets 10%
    private func calculateTimeWeightedPosition(for date: Date, from startDate: Date, to endDate: Date) -> Double {
        let totalRange = endDate.timeIntervalSince(startDate)
        guard totalRange > 0 else { return 0.5 }

        let now = endDate
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now

        if date >= thirtyDaysAgo {
            // Last 30 days: 0.3 to 1.0 (70% of space)
            let rangeStart = thirtyDaysAgo.timeIntervalSince(startDate)
            let rangeSize = now.timeIntervalSince(thirtyDaysAgo)
            let offset = date.timeIntervalSince(thirtyDaysAgo)
            return 0.3 + (offset / rangeSize) * 0.7
        } else if date >= oneYearAgo {
            // 30 days to 1 year: 0.1 to 0.3 (20% of space)
            let rangeSize = thirtyDaysAgo.timeIntervalSince(oneYearAgo)
            let offset = date.timeIntervalSince(oneYearAgo)
            return 0.1 + (offset / rangeSize) * 0.2
        } else {
            // Older than 1 year: 0.0 to 0.1 (10% of space)
            let rangeSize = oneYearAgo.timeIntervalSince(startDate)
            guard rangeSize > 0 else { return 0.05 }
            let offset = date.timeIntervalSince(startDate)
            return (offset / rangeSize) * 0.1
        }
    }

    private func calculateImportance(for date: Date) -> TimelineAnchor.TimelineImportance {
        let now = Date()
        let daysDiff = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0

        if daysDiff <= 7 {
            return .daily
        } else if daysDiff <= 30 {
            return .weekly
        } else if daysDiff <= 365 {
            return .monthly
        } else {
            return .yearly
        }
    }

    // MARK: - Date Conversion

    /// Convert timeline position (0.0-1.0) back to date using time weighting
    func dateFromPosition(_ position: Double, from startDate: Date, to endDate: Date) -> Date {
        let now = endDate
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now

        if position >= 0.3 {
            // Last 30 days zone
            let normalized = (position - 0.3) / 0.7
            let interval = now.timeIntervalSince(thirtyDaysAgo)
            return thirtyDaysAgo.addingTimeInterval(normalized * interval)
        } else if position >= 0.1 {
            // 30 days to 1 year zone
            let normalized = (position - 0.1) / 0.2
            let interval = thirtyDaysAgo.timeIntervalSince(oneYearAgo)
            return oneYearAgo.addingTimeInterval(normalized * interval)
        } else {
            // Older than 1 year zone
            let normalized = position / 0.1
            let interval = oneYearAgo.timeIntervalSince(startDate)
            return startDate.addingTimeInterval(normalized * interval)
        }
    }
}
