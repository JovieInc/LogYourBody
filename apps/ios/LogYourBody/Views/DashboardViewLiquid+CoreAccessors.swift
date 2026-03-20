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

    static func displayStepsValue(from snapshot: GlobalTimelineMetricValue) -> Int? {
        guard let value = snapshot.value else {
            return nil
        }

        return Int(value.rounded())
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

enum DashboardPhotosPresentation {
    static let emptyBucketMessage = "No photo near this date yet"
    static let emptyBucketActionTitle = "Add Photo"

    static func showsStandaloneScrubber(isGlobalTimelineEnabled: Bool) -> Bool {
        !isGlobalTimelineEnabled
    }

    static func emptyStateMessage(
        isGlobalTimelineEnabled: Bool,
        selectedTimelineBucket: GlobalTimelineBucket?
    ) -> String? {
        guard isGlobalTimelineEnabled,
              let selectedTimelineBucket,
              !selectedTimelineBucket.metrics.hasPhotosInRange else {
            return nil
        }

        return emptyBucketMessage
    }
}

enum DashboardBodyScorePresentation {
    static func deltaText(
        currentScore: Int,
        previousScore: Int,
        comparison: String
    ) -> String {
        let delta = Double(currentScore - previousScore)
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(Int(delta)) \(comparison)"
    }
}

enum DashboardFFMIPresentation {
    static func valueText(
        selectedTimelineBucket: GlobalTimelineBucket?,
        fallbackValue: String
    ) -> String {
        guard let selectedTimelineBucket else {
            return fallbackValue
        }

        guard let value = selectedTimelineBucket.metrics.ffmi.value else {
            return "–"
        }

        return MetricsFormatter.formatDecimal(value)
    }
}

enum DashboardMetricCardTrendPresentation {
    static func weightTrend(
        selectedTimelineBucket: GlobalTimelineBucket?,
        previousTimelineBucket: GlobalTimelineBucket?,
        metrics: [BodyMetrics],
        preferredUnit: String,
        fallbackTrend: MetricSummaryCard.Trend?
    ) -> MetricSummaryCard.Trend? {
        guard let selectedTimelineBucket,
              let previousTimelineBucket,
              let delta = GlobalTimelineMetricAdapter.displayWeightDelta(
                  current: selectedTimelineBucket.metrics.weight,
                  previous: previousTimelineBucket.metrics.weight,
                  metrics: metrics,
                  preferredUnit: preferredUnit
              ) else {
            return fallbackTrend
        }

        return makeTrend(
            delta: delta,
            unit: preferredUnit,
            caption: GlobalTimelineMetricAdapter.comparisonCaption(for: selectedTimelineBucket.scale)
        )
    }

    static func metricTrend(
        current: GlobalTimelineMetricValue,
        previous: GlobalTimelineMetricValue,
        selectedTimelineBucket: GlobalTimelineBucket?,
        unit: String,
        fallbackTrend: MetricSummaryCard.Trend?
    ) -> MetricSummaryCard.Trend? {
        guard let selectedTimelineBucket,
              let delta = GlobalTimelineMetricAdapter.delta(
                  current: current,
                  previous: previous
              ) else {
            return fallbackTrend
        }

        return makeTrend(
            delta: delta,
            unit: unit,
            caption: GlobalTimelineMetricAdapter.comparisonCaption(for: selectedTimelineBucket.scale)
        )
    }
}

enum DashboardMetricSparklinePresentation {
    static func trailingBuckets(
        buckets: [GlobalTimelineBucket],
        currentBucketId: String,
        maxCount: Int = 7
    ) -> [GlobalTimelineBucket] {
        guard let currentIndex = buckets.firstIndex(where: { $0.id == currentBucketId }) else {
            return Array(buckets.suffix(maxCount))
        }

        let startIndex = max(0, currentIndex - (maxCount - 1))
        return Array(buckets[startIndex...currentIndex])
    }

    static func points(
        buckets: [GlobalTimelineBucket],
        valueProvider: (GlobalTimelineBucket) -> Double?
    ) -> [MetricDataPoint] {
        buckets
            .compactMap(valueProvider)
            .enumerated()
            .map { index, value in
                MetricDataPoint(index: index, value: value)
            }
    }
}

struct MetricHeadlineChangePresentation: Equatable {
    let title: String
    let delta: Double
}

enum DashboardMetricDetailChangePresentation {
    static func comparisonTitle(for scale: GlobalTimelineScale) -> String {
        "Change vs \(GlobalTimelineMetricAdapter.comparisonCaption(for: scale))"
    }

    static func weightChange(
        selectedTimelineBucket: GlobalTimelineBucket?,
        previousTimelineBucket: GlobalTimelineBucket?,
        metrics: [BodyMetrics],
        preferredUnit: String
    ) -> MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let previousTimelineBucket,
              let delta = GlobalTimelineMetricAdapter.displayWeightDelta(
                  current: selectedTimelineBucket.metrics.weight,
                  previous: previousTimelineBucket.metrics.weight,
                  metrics: metrics,
                  preferredUnit: preferredUnit
              ) else {
            return nil
        }

        return MetricHeadlineChangePresentation(
            title: comparisonTitle(for: selectedTimelineBucket.scale),
            delta: delta
        )
    }

    static func metricChange(
        current: GlobalTimelineMetricValue,
        previous: GlobalTimelineMetricValue,
        selectedTimelineBucket: GlobalTimelineBucket?
    ) -> MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let delta = GlobalTimelineMetricAdapter.delta(
                  current: current,
                  previous: previous
              ) else {
            return nil
        }

        return MetricHeadlineChangePresentation(
            title: comparisonTitle(for: selectedTimelineBucket.scale),
            delta: delta
        )
    }

    static func bodyScoreChange(
        currentScore: Int?,
        previousScore: Int?,
        selectedTimelineBucket: GlobalTimelineBucket?
    ) -> MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let currentScore,
              let previousScore else {
            return nil
        }

        return MetricHeadlineChangePresentation(
            title: comparisonTitle(for: selectedTimelineBucket.scale),
            delta: Double(currentScore - previousScore)
        )
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

    var shouldShowStandaloneTimelineScrubber: Bool {
        DashboardPhotosPresentation.showsStandaloneScrubber(
            isGlobalTimelineEnabled: isGlobalTimelineEnabled
        )
    }

    var selectedTimelineEmptyPhotoMessage: String? {
        DashboardPhotosPresentation.emptyStateMessage(
            isGlobalTimelineEnabled: isGlobalTimelineEnabled,
            selectedTimelineBucket: selectedTimelineBucket
        )
    }

    var currentTimelineBodyScoreContext: GlobalTimelineService.BodyScoreContext? {
        guard let profile = authManager.currentUser?.profile,
              let heightCm = profile.height,
              heightCm > 0,
              let dateOfBirth = profile.dateOfBirth else {
            return nil
        }

        let genderString = profile.gender?.lowercased() ?? ""
        let sex: BiologicalSex
        if genderString.contains("female") || genderString.contains("woman") {
            sex = .female
        } else if genderString.contains("male") || genderString.contains("man") {
            sex = .male
        } else {
            return nil
        }

        let birthYear = Calendar.current.component(.year, from: dateOfBirth)
        return GlobalTimelineService.BodyScoreContext(
            sex: sex,
            birthYear: birthYear,
            heightCm: heightCm,
            measurementPreference: currentMeasurementSystem
        )
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

    var selectedFFMIMetricValueText: String {
        DashboardFFMIPresentation.valueText(
            selectedTimelineBucket: selectedTimelineBucket,
            fallbackValue: currentMetric.map { formatFFMIValue($0) } ?? "–"
        )
    }

    var selectedStepsMetricValue: Int? {
        if let selectedTimelineBucket {
            return GlobalTimelineMetricAdapter.displayStepsValue(
                from: selectedTimelineBucket.metrics.steps
            )
        }

        return latestStepsSnapshot().value
    }

    var selectedStepsMetricValueText: String {
        formatSteps(selectedStepsMetricValue)
    }

    var selectedStepsMetricTimestampText: String? {
        if selectedTimelineBucket != nil {
            return selectedMetricTimestampText
        }

        return formatCardDateOnly(latestStepsSnapshot().date)
    }

    var selectedStepsMetricDateText: String {
        if selectedTimelineBucket != nil {
            return selectedMetricDateText
        }

        return formatDate(latestStepsSnapshot().date ?? Date())
    }

    var selectedWeightMetricTrend: MetricSummaryCard.Trend? {
        let fallbackTrend = weightRangeStats().flatMap {
            makeTrend($0.delta, weightUnit, selectedRange)
        }

        return DashboardMetricCardTrendPresentation.weightTrend(
            selectedTimelineBucket: selectedTimelineBucket,
            previousTimelineBucket: previousTimelineBucket,
            metrics: bodyMetrics,
            preferredUnit: weightUnit,
            fallbackTrend: fallbackTrend
        )
    }

    var selectedBodyFatMetricTrend: MetricSummaryCard.Trend? {
        let fallbackTrend = bodyFatRangeStats().flatMap {
            makeTrend($0.delta, "%", selectedRange)
        }

        guard let selectedTimelineBucket,
              let previousTimelineBucket else {
            return fallbackTrend
        }

        return DashboardMetricCardTrendPresentation.metricTrend(
            current: selectedTimelineBucket.metrics.bodyFat,
            previous: previousTimelineBucket.metrics.bodyFat,
            selectedTimelineBucket: selectedTimelineBucket,
            unit: "%",
            fallbackTrend: fallbackTrend
        )
    }

    var selectedFFMIMetricTrend: MetricSummaryCard.Trend? {
        let fallbackTrend = ffmiRangeStats().flatMap {
            makeTrend($0.delta, "", selectedRange)
        }

        guard let selectedTimelineBucket,
              let previousTimelineBucket else {
            return fallbackTrend
        }

        return DashboardMetricCardTrendPresentation.metricTrend(
            current: selectedTimelineBucket.metrics.ffmi,
            previous: previousTimelineBucket.metrics.ffmi,
            selectedTimelineBucket: selectedTimelineBucket,
            unit: "",
            fallbackTrend: fallbackTrend
        )
    }

    var bucketsAtSelectedScale: [GlobalTimelineBucket]? {
        guard isGlobalTimelineEnabled,
              let cursor = globalTimelineStore.cursor else {
            return nil
        }

        switch cursor.scale {
        case .week:
            return globalTimelineStore.weeklyBuckets
        case .month:
            return globalTimelineStore.monthlyBuckets
        case .year:
            return globalTimelineStore.yearlyBuckets
        }
    }

    var trailingSelectedScaleBuckets: [GlobalTimelineBucket]? {
        guard let selectedTimelineBucket,
              let bucketsAtSelectedScale else {
            return nil
        }

        return DashboardMetricSparklinePresentation.trailingBuckets(
            buckets: bucketsAtSelectedScale,
            currentBucketId: selectedTimelineBucket.id
        )
    }

    var selectedWeightHeadlineChange: MetricHeadlineChangePresentation? {
        DashboardMetricDetailChangePresentation.weightChange(
            selectedTimelineBucket: selectedTimelineBucket,
            previousTimelineBucket: previousTimelineBucket,
            metrics: bodyMetrics,
            preferredUnit: weightUnit
        )
    }

    var selectedBodyFatHeadlineChange: MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let previousTimelineBucket else {
            return nil
        }

        return DashboardMetricDetailChangePresentation.metricChange(
            current: selectedTimelineBucket.metrics.bodyFat,
            previous: previousTimelineBucket.metrics.bodyFat,
            selectedTimelineBucket: selectedTimelineBucket
        )
    }

    var selectedFFMIHeadlineChange: MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let previousTimelineBucket else {
            return nil
        }

        return DashboardMetricDetailChangePresentation.metricChange(
            current: selectedTimelineBucket.metrics.ffmi,
            previous: previousTimelineBucket.metrics.ffmi,
            selectedTimelineBucket: selectedTimelineBucket
        )
    }

    var selectedStepsHeadlineChange: MetricHeadlineChangePresentation? {
        guard let selectedTimelineBucket,
              let previousTimelineBucket else {
            return nil
        }

        return DashboardMetricDetailChangePresentation.metricChange(
            current: selectedTimelineBucket.metrics.steps,
            previous: previousTimelineBucket.metrics.steps,
            selectedTimelineBucket: selectedTimelineBucket
        )
    }

    var selectedBodyScoreHeadlineChange: MetricHeadlineChangePresentation? {
        DashboardMetricDetailChangePresentation.bodyScoreChange(
            currentScore: selectedTimelineBucket?.metrics.bodyScore,
            previousScore: previousTimelineBucket?.metrics.bodyScore,
            selectedTimelineBucket: selectedTimelineBucket
        )
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
