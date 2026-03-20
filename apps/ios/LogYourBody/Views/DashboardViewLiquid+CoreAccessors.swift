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

enum GlobalTimelineMetricAdapter {
    static func bucketDateText(_ bucket: GlobalTimelineBucket) -> String {
        switch bucket.scale {
        case .week:
            return "Week of \(bucket.startDate.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return bucket.startDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return bucket.startDate.formatted(.dateTime.year())
        }
    }

    static func displayWeightValue(
        from snapshot: GlobalTimelineMetricValue,
        metrics: [BodyMetrics],
        preferredUnit: String
    ) -> Double? {
        guard let value = snapshot.value else {
            return nil
        }

        let sourceUnit = metrics
            .sorted { $0.date > $1.date }
            .compactMap { metric in
                guard metric.weight != nil else { return nil }
                return metric.weightUnit
            }
            .first(where: { $0 == "kg" || $0 == "lbs" }) ?? "kg"

        return MetricsFormatter.convertWeight(value: value, from: sourceUnit, to: preferredUnit)
    }

    static func displayWeightDelta(
        current: GlobalTimelineMetricValue,
        previous: GlobalTimelineMetricValue,
        metrics: [BodyMetrics],
        preferredUnit: String
    ) -> Double? {
        guard let currentValue = displayWeightValue(
            from: current,
            metrics: metrics,
            preferredUnit: preferredUnit
        ), let previousValue = displayWeightValue(
            from: previous,
            metrics: metrics,
            preferredUnit: preferredUnit
        ) else {
            return nil
        }

        return currentValue - previousValue
    }

    static func delta(
        current: GlobalTimelineMetricValue,
        previous: GlobalTimelineMetricValue
    ) -> Double? {
        guard let currentValue = current.value,
              let previousValue = previous.value else {
            return nil
        }

        return currentValue - previousValue
    }

    static func comparisonCaption(for scale: GlobalTimelineScale) -> String {
        switch scale {
        case .week:
            return "last week"
        case .month:
            return "last month"
        case .year:
            return "last year"
        }
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

    var selectedTimelineBucket: GlobalTimelineBucket? {
        guard isGlobalTimelineEnabled,
              let cursor = globalTimelineStore.cursor else {
            return nil
        }

        return globalTimelineStore.bucket(for: cursor)
    }

    var previousTimelineBucket: GlobalTimelineBucket? {
        guard isGlobalTimelineEnabled,
              let cursor = globalTimelineStore.cursor else {
            return nil
        }

        return globalTimelineStore.previousBucket(for: cursor)
    }

    var selectedMetricTimestampText: String? {
        if let selectedTimelineBucket {
            return GlobalTimelineMetricAdapter.bucketDateText(selectedTimelineBucket)
        }

        return formatCardDateOnly(currentMetric?.date)
    }

    var selectedMetricDateText: String {
        if let selectedTimelineBucket {
            return GlobalTimelineMetricAdapter.bucketDateText(selectedTimelineBucket)
        }

        return formatDate(currentMetric?.date ?? Date())
    }

    var selectedWeightMetricValueText: String {
        if let selectedTimelineBucket {
            if let value = GlobalTimelineMetricAdapter.displayWeightValue(
                from: selectedTimelineBucket.metrics.weight,
                metrics: bodyMetrics,
                preferredUnit: weightUnit
            ) {
                return MetricsFormatter.formatWeight(value: value, unit: weightUnit)
            }

            return "–"
        }

        return currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–"
    }

    var selectedBodyFatMetricValueText: String {
        if let selectedTimelineBucket {
            if let value = selectedTimelineBucket.metrics.bodyFat.value {
                return MetricsFormatter.formatDecimal(value)
            }

            return "–"
        }

        return currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–"
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
