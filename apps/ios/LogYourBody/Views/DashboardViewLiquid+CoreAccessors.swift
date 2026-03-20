import SwiftUI

enum GlobalTimelineSelectionResolver {
    static func cursor(
        for metricDate: Date,
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket]
    ) -> GlobalTimelineCursor? {
        let candidateBuckets = [weeklyBuckets, monthlyBuckets, yearlyBuckets]

        for buckets in candidateBuckets {
            if let bucket = buckets.first(where: { contains(metricDate, in: $0) }) {
                return GlobalTimelineCursor(
                    date: bucket.endDate,
                    scale: bucket.scale,
                    bucketId: bucket.id
                )
            }
        }

        return nil
    }

    static func metricIndex(
        for cursor: GlobalTimelineCursor,
        metrics: [BodyMetrics],
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket]
    ) -> Int? {
        guard let bucket = bucket(
            for: cursor,
            weeklyBuckets: weeklyBuckets,
            monthlyBuckets: monthlyBuckets,
            yearlyBuckets: yearlyBuckets
        ) else {
            return nil
        }

        let metricsInBucket = metrics.enumerated().filter {
            contains($0.element.date, in: bucket)
        }
        guard !metricsInBucket.isEmpty else {
            return nil
        }

        if let canonicalPhotoId = bucket.metrics.canonicalPhotoId,
           let photoMatch = metricsInBucket.first(where: {
               $0.element.photoUrl == canonicalPhotoId
           }) {
            return photoMatch.offset
        }

        let midpoint = bucket.startDate.addingTimeInterval(
            bucket.endDate.timeIntervalSince(bucket.startDate) / 2.0
        )

        return metricsInBucket.min {
            abs($0.element.date.timeIntervalSince(midpoint)) < abs($1.element.date.timeIntervalSince(midpoint))
        }?.offset
    }

    private static func bucket(
        for cursor: GlobalTimelineCursor,
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket]
    ) -> GlobalTimelineBucket? {
        switch cursor.scale {
        case .week:
            return weeklyBuckets.first { $0.id == cursor.bucketId }
        case .month:
            return monthlyBuckets.first { $0.id == cursor.bucketId }
        case .year:
            return yearlyBuckets.first { $0.id == cursor.bucketId }
        }
    }

    private static func contains(_ date: Date, in bucket: GlobalTimelineBucket) -> Bool {
        date >= bucket.startDate && date < bucket.endDate
    }
}

extension DashboardViewLiquid {
    // MARK: - Goal Helpers

    /// Returns the FFMI goal based on custom setting or gender-based default
    var ffmiGoal: Double {
        if let custom = customFFMIGoal {
            return custom
        }
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        return gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.FFMI.femaleIdealValue :
            Constants.BodyComposition.FFMI.maleIdealValue
    }

    /// Returns the body fat % goal based on custom setting or gender-based default
    var bodyFatGoal: Double {
        if let custom = customBodyFatGoal {
            return custom
        }
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        return gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.BodyFat.femaleIdealValue :
            Constants.BodyComposition.BodyFat.maleIdealValue
    }

    /// Returns the weight goal (optional, nil if not set)
    var weightGoal: Double? {
        customWeightGoal
    }

    var currentMeasurementSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    var weightUnit: String {
        currentMeasurementSystem.weightUnit
    }

    var bodyMetrics: [BodyMetrics] {
        viewModel.bodyMetrics
    }

    var sortedBodyMetricsAscending: [BodyMetrics] {
        viewModel.sortedBodyMetricsAscending
    }

    var recentDailyMetrics: [DailyMetrics] {
        viewModel.recentDailyMetrics
    }

    var dailyMetrics: DailyMetrics? {
        viewModel.dailyMetrics
    }

    /// Calculate age from date of birth
    func calculateAge(from dateOfBirth: Date?) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year
    }

    var currentMetric: BodyMetrics? {
        let metrics = viewModel.bodyMetrics
        guard !metrics.isEmpty, selectedIndex >= 0, selectedIndex < metrics.count else { return nil }
        return metrics[selectedIndex]
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
