//
// TimelinePhotoSampler.swift
// LogYourBody
//
// Milestone-based photo sampling for dense periods in timeline
//

import Foundation

/// Samples photos from dense periods using milestone-based prioritization
class TimelinePhotoSampler {
    /// Select the best representative photo from a bucket of candidates
    /// Priority: milestones > complete metrics > most recent
    static func selectRepresentative(from bucket: TimelineBucket, previousMetric: BodyMetrics?) -> BodyMetrics? {
        guard !bucket.candidates.isEmpty else { return nil }

        // If only one candidate, return it
        if bucket.candidates.count == 1 {
            return bucket.candidates.first
        }

        // Score each candidate
        let scoredCandidates = bucket.candidates.map { candidate in
            (metric: candidate, score: calculateScore(for: candidate, previous: previousMetric))
        }

        // Return highest scoring candidate
        return scoredCandidates.max(by: { $0.score < $1.score })?.metric
    }

    /// Calculate priority score for a metric
    /// Higher score = higher priority for display
    private static func calculateScore(for metric: BodyMetrics, previous: BodyMetrics?) -> Int {
        var score = 0

        // Priority 1: Metric milestones (100 points each)
        if let prev = previous {
            // Significant weight change (>2%)
            if let currentWeight = metric.weight, let prevWeight = prev.weight {
                let weightChange = abs((currentWeight - prevWeight) / prevWeight)
                if weightChange > 0.02 {
                    score += 100
                }
            }

            // Significant body fat change (>1%)
            if let currentBF = metric.bodyFatPercentage, let prevBF = prev.bodyFatPercentage {
                let bfChange = abs(currentBF - prevBF)
                if bfChange > 1.0 {
                    score += 100
                }
            }
        }

        // Priority 2: Complete metrics (50 points)
        let hasCompleteMetrics = metric.weight != nil && metric.bodyFatPercentage != nil
        if hasCompleteMetrics {
            score += 50
        }

        // Priority 3: Has photo (30 points)
        if metric.photoUrl != nil && !(metric.photoUrl?.isEmpty ?? true) {
            score += 30
        }

        // Priority 4: Has individual metrics (10 points each)
        if metric.weight != nil {
            score += 10
        }
        if metric.bodyFatPercentage != nil {
            score += 10
        }

        // Priority 5: Recency (1-5 points based on position in bucket)
        // More recent = higher score
        score += 5  // Default for being in the bucket

        return score
    }

    /// Sample photos from all buckets, respecting max thumbnail limit
    static func samplePhotos(
        from buckets: [TimelineBucket],
        maxThumbnails: Int,
        sortedMetrics: [BodyMetrics]
    ) -> [BodyMetrics] {
        var sampled: [BodyMetrics] = []
        var bucketsWithCandidates = buckets.filter { !$0.candidates.isEmpty }

        // If fewer buckets than max, take one from each
        if bucketsWithCandidates.count <= maxThumbnails {
            for (index, bucket) in bucketsWithCandidates.enumerated() {
                let previousMetric = index > 0 ? sampled.last : nil
                if let selected = selectRepresentative(from: bucket, previousMetric: previousMetric) {
                    sampled.append(selected)
                }
            }
            return sampled
        }

        // Otherwise, need to thin out buckets
        // Strategy: Keep milestone buckets, sample evenly from others
        let stride = Double(bucketsWithCandidates.count) / Double(maxThumbnails)
        var indices: [Int] = []

        for i in 0..<maxThumbnails {
            let index = Int(Double(i) * stride)
            if index < bucketsWithCandidates.count {
                indices.append(index)
            }
        }

        for (arrayIndex, bucketIndex) in indices.enumerated() {
            let bucket = bucketsWithCandidates[bucketIndex]
            let previousMetric = arrayIndex > 0 ? sampled.last : nil
            if let selected = selectRepresentative(from: bucket, previousMetric: previousMetric) {
                sampled.append(selected)
            }
        }

        return sampled
    }

    /// Filter metrics that have photos
    static func metricsWithPhotos(from metrics: [BodyMetrics]) -> [BodyMetrics] {
        return metrics.filter { metric in
            guard let photoUrl = metric.photoUrl else { return false }
            return !photoUrl.isEmpty
        }
    }

    /// Filter metrics that have any data (weight OR BF% OR photo)
    static func metricsWithData(from metrics: [BodyMetrics]) -> [BodyMetrics] {
        return metrics.filter { metric in
            let hasWeight = metric.weight != nil
            let hasBF = metric.bodyFatPercentage != nil
            let hasPhoto = metric.photoUrl != nil && !(metric.photoUrl?.isEmpty ?? true)
            return hasWeight || hasBF || hasPhoto
        }
    }
}
