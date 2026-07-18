import Foundation

/// Service responsible for building weekly, monthly, and yearly buckets
/// for the global timeline scrubber. Aggregation rules are defined in
/// TIMELINE_SPEC.md and will be implemented incrementally.
final class GlobalTimelineService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Public API

    func makeBuckets(for scale: GlobalTimelineScale, metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        guard !metrics.isEmpty else { return [] }

        switch scale {
        case .week:
            return makeWeeklyBuckets(from: metrics)
        case .month:
            return makeMonthlyBuckets(from: metrics)
        case .year:
            return makeYearlyBuckets(from: metrics)
        }
    }

    func makeInitialCursor(for metrics: [BodyMetrics]) -> GlobalTimelineCursor? {
        guard !metrics.isEmpty else { return nil }

        let weeklyBuckets = makeWeeklyBuckets(from: metrics)
        guard let mostRecentBucket = weeklyBuckets.last else {
            return nil
        }

        return GlobalTimelineCursor(
            date: mostRecentBucket.endDate,
            scale: .week,
            bucketId: mostRecentBucket.id
        )
    }

    // MARK: - Bucket builders

    private func makeWeeklyBuckets(from metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        let sortedMetrics = metrics.sorted { $0.date < $1.date }
        guard let mostRecentDate = sortedMetrics.last?.date else {
            return []
        }

        guard let recentWeekInterval = calendar.dateInterval(of: .weekOfYear, for: mostRecentDate) else {
            return []
        }

        let interpolationService = MetricsInterpolationService.shared
        let maxWeeks = 4
        var buckets: [GlobalTimelineBucket] = []

        let earliestDate = sortedMetrics.first?.date ?? mostRecentDate
        var weekStart = recentWeekInterval.start

        while buckets.count < maxWeeks {
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }

            // Stop if this entire week is before the first metric
            if weekEnd <= earliestDate {
                break
            }

            let weekMetrics = sortedMetrics.filter { metric in
                metric.date >= weekStart && metric.date < weekEnd
            }

            let hasAnyData = weekMetrics.contains { metric in
                let hasWeight = metric.weight != nil
                let hasBodyFat = metric.bodyFatPercentage != nil
                let hasPhoto = metric.photoUrl != nil && !(metric.photoUrl?.isEmpty ?? true)
                return hasWeight || hasBodyFat || hasPhoto
            }

            if hasAnyData {
                let midpoint = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart

                let weight = makeWeeklyWeightValue(
                    weekMetrics: weekMetrics,
                    allMetrics: sortedMetrics,
                    midpoint: midpoint,
                    interpolationService: interpolationService
                )

                let bodyFat = makeWeeklyBodyFatValue(
                    weekMetrics: weekMetrics,
                    allMetrics: sortedMetrics,
                    midpoint: midpoint,
                    interpolationService: interpolationService
                )

                let ffmi = GlobalTimelineMetricValue(value: nil, presence: .missing)
                let steps = GlobalTimelineMetricValue(value: nil, presence: .missing)

                let photoSelection = makeWeeklyPhotoSelection(weekMetrics: weekMetrics, midpoint: midpoint)

                let snapshot = GlobalTimelineMetricsSnapshot(
                    weight: weight,
                    bodyFat: bodyFat,
                    ffmi: ffmi,
                    steps: steps,
                    canonicalPhotoId: photoSelection.canonicalPhotoId,
                    hasPhotosInRange: photoSelection.hasPhotosInRange,
                    bodyScore: nil,
                    bodyScoreCompleteness: .none
                )

                let bucketId = makeWeekIdentifier(startDate: weekStart)
                let bucket = GlobalTimelineBucket(
                    id: bucketId,
                    scale: .week,
                    startDate: weekStart,
                    endDate: weekEnd,
                    metrics: snapshot
                )

                buckets.append(bucket)
            }

            guard let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) else {
                break
            }
            weekStart = previousWeekStart
        }

        return buckets.sorted { $0.startDate < $1.startDate }
    }

    private func makeMonthlyBuckets(from metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        guard let zoneStart = monthlyZoneStart(for: metrics) else {
            return []
        }

        let intervals = (1...6).reversed().compactMap { offset -> DateInterval? in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: zoneStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }

        return makeAggregateBuckets(
            intervals: intervals,
            scale: .month,
            metrics: metrics,
            identifier: makeMonthIdentifier,
            maximumInterpolatedGap: 2
        )
    }

    private func makeYearlyBuckets(from metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        guard let zoneStart = monthlyZoneStart(for: metrics),
              let earliestDate = metrics.map(\.date).min() else {
            return []
        }

        let earliestYear = calendar.component(.year, from: earliestDate)
        let firstYearOutsideTheMonthlyZone = calendar.component(.year, from: zoneStart)
        guard earliestYear < firstYearOutsideTheMonthlyZone else {
            return []
        }

        let intervals = (earliestYear..<firstYearOutsideTheMonthlyZone).compactMap { year -> DateInterval? in
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        }

        return makeAggregateBuckets(
            intervals: intervals,
            scale: .year,
            metrics: metrics,
            identifier: makeYearIdentifier,
            maximumInterpolatedGap: 2
        )
    }

    private func monthlyZoneStart(for metrics: [BodyMetrics]) -> Date? {
        guard let oldestWeeklyBucket = makeWeeklyBuckets(from: metrics).first,
              let monthInterval = calendar.dateInterval(of: .month, for: oldestWeeklyBucket.startDate) else {
            return nil
        }
        return monthInterval.start
    }

    private struct AggregateBucketDraft {
        let id: String
        let scale: GlobalTimelineScale
        let startDate: Date
        let endDate: Date
        var weight: GlobalTimelineMetricValue
        var bodyFat: GlobalTimelineMetricValue
        let canonicalPhotoId: String?
        let hasPhotosInRange: Bool

        var hasMeaningfulData: Bool {
            weight.value != nil || bodyFat.value != nil || hasPhotosInRange
        }

        var bucket: GlobalTimelineBucket {
            GlobalTimelineBucket(
                id: id,
                scale: scale,
                startDate: startDate,
                endDate: endDate,
                metrics: GlobalTimelineMetricsSnapshot(
                    weight: weight,
                    bodyFat: bodyFat,
                    ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
                    steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
                    canonicalPhotoId: canonicalPhotoId,
                    hasPhotosInRange: hasPhotosInRange,
                    bodyScore: nil,
                    bodyScoreCompleteness: .none
                )
            )
        }
    }

    private func makeAggregateBuckets(
        intervals: [DateInterval],
        scale: GlobalTimelineScale,
        metrics: [BodyMetrics],
        identifier: (Date) -> String,
        maximumInterpolatedGap: Int
    ) -> [GlobalTimelineBucket] {
        guard !intervals.isEmpty else { return [] }

        var drafts = intervals.map { interval in
            let intervalMetrics = metrics.filter { metric in
                metric.date >= interval.start && metric.date < interval.end
            }
            let midpoint = interval.start.addingTimeInterval(interval.duration / 2)
            let photoSelection = makeWeeklyPhotoSelection(weekMetrics: intervalMetrics, midpoint: midpoint)

            return AggregateBucketDraft(
                id: identifier(interval.start),
                scale: scale,
                startDate: interval.start,
                endDate: interval.end,
                weight: aggregateMetricValue(intervalMetrics.compactMap(\.weight)),
                bodyFat: aggregateMetricValue(intervalMetrics.compactMap(\.bodyFatPercentage)),
                canonicalPhotoId: photoSelection.canonicalPhotoId,
                hasPhotosInRange: photoSelection.hasPhotosInRange
            )
        }

        interpolateMissingValues(
            in: &drafts,
            keyPath: \.weight,
            maximumGap: maximumInterpolatedGap
        )
        interpolateMissingValues(
            in: &drafts,
            keyPath: \.bodyFat,
            maximumGap: maximumInterpolatedGap
        )

        return drafts
            .filter(\.hasMeaningfulData)
            .map(\.bucket)
    }

    private func aggregateMetricValue(_ values: [Double]) -> GlobalTimelineMetricValue {
        guard let value = median(values) else {
            return GlobalTimelineMetricValue(value: nil, presence: .missing)
        }
        return GlobalTimelineMetricValue(value: value, presence: .present)
    }

    private func interpolateMissingValues(
        in drafts: inout [AggregateBucketDraft],
        keyPath: WritableKeyPath<AggregateBucketDraft, GlobalTimelineMetricValue>,
        maximumGap: Int
    ) {
        let knownIndexes = drafts.indices.filter { index in
            let metric = drafts[index][keyPath: keyPath]
            guard metric.value != nil else { return false }
            if case .present = metric.presence {
                return true
            }
            return false
        }

        guard knownIndexes.count > 1 else { return }

        for (leftIndex, rightIndex) in zip(knownIndexes, knownIndexes.dropFirst()) {
            let gap = rightIndex - leftIndex - 1
            guard gap > 0, gap <= maximumGap,
                  let leftValue = drafts[leftIndex][keyPath: keyPath].value,
                  let rightValue = drafts[rightIndex][keyPath: keyPath].value else {
                continue
            }

            for index in (leftIndex + 1)..<rightIndex where drafts[index][keyPath: keyPath].value == nil {
                let progress = Double(index - leftIndex) / Double(rightIndex - leftIndex)
                let value = leftValue + (rightValue - leftValue) * progress
                drafts[index][keyPath: keyPath] = GlobalTimelineMetricValue(
                    value: value,
                    presence: .estimated
                )
            }
        }
    }

    // MARK: - Weekly helpers

    private func makeWeeklyWeightValue(
        weekMetrics: [BodyMetrics],
        allMetrics: [BodyMetrics],
        midpoint: Date,
        interpolationService: MetricsInterpolationService
    ) -> GlobalTimelineMetricValue {
        let weekWeights = weekMetrics.compactMap { $0.weight }

        if let directValue = median(weekWeights) {
            return GlobalTimelineMetricValue(value: directValue, presence: .present)
        }

        if let interpolated = interpolationService.estimateWeight(for: midpoint, metrics: allMetrics) {
            let presence: MetricPresence = interpolated.isInterpolated ? .estimated : .present
            return GlobalTimelineMetricValue(value: interpolated.value, presence: presence)
        }

        return GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private func makeWeeklyBodyFatValue(
        weekMetrics: [BodyMetrics],
        allMetrics: [BodyMetrics],
        midpoint: Date,
        interpolationService: MetricsInterpolationService
    ) -> GlobalTimelineMetricValue {
        let weekBodyFat = weekMetrics.compactMap { $0.bodyFatPercentage }

        if let directValue = median(weekBodyFat) {
            return GlobalTimelineMetricValue(value: directValue, presence: .present)
        }

        if let interpolated = interpolationService.estimateBodyFat(for: midpoint, metrics: allMetrics) {
            let presence: MetricPresence = interpolated.isInterpolated ? .estimated : .present
            return GlobalTimelineMetricValue(value: interpolated.value, presence: presence)
        }

        return GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private struct WeeklyPhotoSelectionResult {
        let canonicalPhotoId: String?
        let hasPhotosInRange: Bool
    }

    private func makeWeeklyPhotoSelection(
        weekMetrics: [BodyMetrics],
        midpoint: Date
    ) -> WeeklyPhotoSelectionResult {
        let photoCandidates = weekMetrics.filter { metric in
            guard let url = metric.photoUrl else { return false }
            return !url.isEmpty
        }

        guard !photoCandidates.isEmpty else {
            return WeeklyPhotoSelectionResult(canonicalPhotoId: nil, hasPhotosInRange: false)
        }

        let selected = photoCandidates.min { lhs, rhs in
            let lhsDiff = abs(lhs.date.timeIntervalSince(midpoint))
            let rhsDiff = abs(rhs.date.timeIntervalSince(midpoint))
            if lhsDiff == rhsDiff {
                return lhs.id < rhs.id
            }
            return lhsDiff < rhsDiff
        }

        return WeeklyPhotoSelectionResult(canonicalPhotoId: selected?.photoUrl, hasPhotosInRange: true)
    }

    private func makeWeekIdentifier(startDate: Date) -> String {
        let components = calendar.dateComponents([
            .yearForWeekOfYear,
            .weekOfYear
        ], from: startDate)

        let year = components.yearForWeekOfYear ?? calendar.component(.year, from: startDate)
        let week = components.weekOfYear ?? calendar.component(.weekOfYear, from: startDate)

        return String(format: "%04d-W%02d", year, week)
    }

    private func makeMonthIdentifier(startDate: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: startDate)
        let year = components.year ?? calendar.component(.year, from: startDate)
        let month = components.month ?? calendar.component(.month, from: startDate)
        return String(format: "%04d-%02d", year, month)
    }

    private func makeYearIdentifier(startDate: Date) -> String {
        String(calendar.component(.year, from: startDate))
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }

        let sortedValues = values.sorted()
        let count = sortedValues.count
        let middleIndex = count / 2

        if count.isMultiple(of: 2) {
            let lower = sortedValues[middleIndex - 1]
            let upper = sortedValues[middleIndex]
            return (lower + upper) / 2.0
        } else {
            return sortedValues[middleIndex]
        }
    }
}
