import Foundation

/// Service responsible for building weekly, monthly, and yearly buckets
/// for the global timeline scrubber.
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
        let context = makeAggregationContext(from: metrics)
        guard let mostRecentDate = context.metrics.last?.date,
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: mostRecentDate) else {
            return []
        }

        return buildBuckets(
            scale: .week,
            context: context,
            initialStartDate: weekInterval.start,
            previousStartDate: { [calendar] startDate in
                calendar.date(byAdding: .day, value: -7, to: startDate)
            },
            identifier: makeWeekIdentifier
        )
    }

    private func makeMonthlyBuckets(from metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        let context = makeAggregationContext(from: metrics)
        guard let mostRecentDate = context.metrics.last?.date,
              let monthInterval = calendar.dateInterval(of: .month, for: mostRecentDate) else {
            return []
        }

        return buildBuckets(
            scale: .month,
            context: context,
            initialStartDate: monthInterval.start,
            previousStartDate: { [calendar] startDate in
                calendar.date(byAdding: .month, value: -1, to: startDate)
            },
            identifier: makeMonthIdentifier
        )
    }

    private func makeYearlyBuckets(from metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        let context = makeAggregationContext(from: metrics)
        guard let mostRecentDate = context.metrics.last?.date,
              let yearInterval = calendar.dateInterval(of: .year, for: mostRecentDate) else {
            return []
        }

        return buildBuckets(
            scale: .year,
            context: context,
            initialStartDate: yearInterval.start,
            previousStartDate: { [calendar] startDate in
                calendar.date(byAdding: .year, value: -1, to: startDate)
            },
            identifier: makeYearIdentifier
        )
    }

    private func buildBuckets(
        scale: GlobalTimelineScale,
        context: AggregationContext,
        initialStartDate: Date,
        previousStartDate: (Date) -> Date?,
        identifier: (Date) -> String
    ) -> [GlobalTimelineBucket] {
        guard let earliestDate = context.metrics.first?.date else {
            return []
        }

        var buckets: [GlobalTimelineBucket] = []
        var startDate = initialStartDate

        while true {
            guard let endDate = bucketEndDate(for: scale, startDate: startDate) else {
                break
            }

            if endDate <= earliestDate {
                break
            }

            let rangeMetrics = metrics(in: startDate..<endDate, context: context)
            if hasAnyData(in: rangeMetrics) {
                buckets.append(
                    GlobalTimelineBucket(
                        id: identifier(startDate),
                        scale: scale,
                        startDate: startDate,
                        endDate: endDate,
                        metrics: makeSnapshot(
                            rangeMetrics: rangeMetrics,
                            allMetrics: context.metrics,
                            midpoint: midpoint(between: startDate, and: endDate)
                        )
                    )
                )
            }

            guard let nextStartDate = previousStartDate(startDate) else {
                break
            }
            startDate = nextStartDate
        }

        return buckets.sorted { $0.startDate < $1.startDate }
    }

    private func bucketEndDate(for scale: GlobalTimelineScale, startDate: Date) -> Date? {
        switch scale {
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: startDate)
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: startDate)
        case .year:
            return calendar.date(byAdding: .year, value: 1, to: startDate)
        }
    }

    private func midpoint(between startDate: Date, and endDate: Date) -> Date {
        startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2.0)
    }

    // MARK: - Aggregation helpers

    private struct AggregationContext {
        let metrics: [BodyMetrics]
        let dates: [Date]
    }

    private func makeAggregationContext(from metrics: [BodyMetrics]) -> AggregationContext {
        let targetUnit = resolvedWeightUnit(from: metrics)
        let normalizedMetrics = metrics
            .sorted { $0.date < $1.date }
            .map { normalizeWeightUnit(for: $0, targetUnit: targetUnit) }

        return AggregationContext(
            metrics: normalizedMetrics,
            dates: normalizedMetrics.map(\.date)
        )
    }

    private func resolvedWeightUnit(from metrics: [BodyMetrics]) -> String {
        metrics
            .sorted { $0.date > $1.date }
            .compactMap { metric in
                guard metric.weight != nil else { return nil }
                return metric.weightUnit
            }
            .first(where: { $0 == "kg" || $0 == "lbs" }) ?? "kg"
    }

    private func normalizeWeightUnit(for metric: BodyMetrics, targetUnit: String) -> BodyMetrics {
        guard let weight = metric.weight,
              let sourceUnit = metric.weightUnit,
              sourceUnit != targetUnit else {
            return metric
        }

        return BodyMetrics(
            id: metric.id,
            userId: metric.userId,
            date: metric.date,
            weight: MetricsFormatter.convertWeight(value: weight, from: sourceUnit, to: targetUnit),
            weightUnit: targetUnit,
            bodyFatPercentage: metric.bodyFatPercentage,
            bodyFatMethod: metric.bodyFatMethod,
            muscleMass: metric.muscleMass,
            boneMass: metric.boneMass,
            waistCm: metric.waistCm,
            hipCm: metric.hipCm,
            waistUnit: metric.waistUnit,
            notes: metric.notes,
            photoUrl: metric.photoUrl,
            dataSource: metric.dataSource,
            createdAt: metric.createdAt,
            updatedAt: metric.updatedAt
        )
    }

    private func metrics(in range: Range<Date>, context: AggregationContext) -> [BodyMetrics] {
        let startIndex = lowerBound(for: range.lowerBound, in: context.dates)
        let endIndex = lowerBound(for: range.upperBound, in: context.dates)

        guard startIndex < endIndex else {
            return []
        }

        return Array(context.metrics[startIndex..<endIndex])
    }

    private func lowerBound(for date: Date, in dates: [Date]) -> Int {
        var low = 0
        var high = dates.count

        while low < high {
            let mid = (low + high) / 2
            if dates[mid] < date {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

    private func hasAnyData(in metrics: [BodyMetrics]) -> Bool {
        metrics.contains { metric in
            let hasWeight = metric.weight != nil
            let hasBodyFat = metric.bodyFatPercentage != nil
            let hasPhoto = metric.photoUrl?.isEmpty == false
            return hasWeight || hasBodyFat || hasPhoto
        }
    }

    private func makeSnapshot(
        rangeMetrics: [BodyMetrics],
        allMetrics: [BodyMetrics],
        midpoint: Date
    ) -> GlobalTimelineMetricsSnapshot {
        let photoSelection = makePhotoSelection(rangeMetrics: rangeMetrics, midpoint: midpoint)

        return GlobalTimelineMetricsSnapshot(
            weight: makeWeightValue(rangeMetrics: rangeMetrics, allMetrics: allMetrics, midpoint: midpoint),
            bodyFat: makeBodyFatValue(rangeMetrics: rangeMetrics, allMetrics: allMetrics, midpoint: midpoint),
            ffmi: GlobalTimelineMetricValue(value: nil, presence: .missing),
            steps: GlobalTimelineMetricValue(value: nil, presence: .missing),
            canonicalPhotoId: photoSelection.canonicalPhotoId,
            hasPhotosInRange: photoSelection.hasPhotosInRange,
            bodyScore: nil,
            bodyScoreCompleteness: .none
        )
    }

    private func makeWeightValue(
        rangeMetrics: [BodyMetrics],
        allMetrics: [BodyMetrics],
        midpoint: Date
    ) -> GlobalTimelineMetricValue {
        if let directValue = median(rangeMetrics.compactMap(\.weight)) {
            return GlobalTimelineMetricValue(value: directValue, presence: .present)
        }

        if let interpolated = MetricsInterpolationService.shared.estimateWeight(for: midpoint, metrics: allMetrics) {
            let presence: MetricPresence = interpolated.isInterpolated ? .estimated : .present
            return GlobalTimelineMetricValue(value: interpolated.value, presence: presence)
        }

        return GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private func makeBodyFatValue(
        rangeMetrics: [BodyMetrics],
        allMetrics: [BodyMetrics],
        midpoint: Date
    ) -> GlobalTimelineMetricValue {
        if let directValue = median(rangeMetrics.compactMap(\.bodyFatPercentage)) {
            return GlobalTimelineMetricValue(value: directValue, presence: .present)
        }

        if let interpolated = MetricsInterpolationService.shared.estimateBodyFat(for: midpoint, metrics: allMetrics) {
            let presence: MetricPresence = interpolated.isInterpolated ? .estimated : .present
            return GlobalTimelineMetricValue(value: interpolated.value, presence: presence)
        }

        return GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private struct PhotoSelectionResult {
        let canonicalPhotoId: String?
        let hasPhotosInRange: Bool
    }

    private func makePhotoSelection(
        rangeMetrics: [BodyMetrics],
        midpoint: Date
    ) -> PhotoSelectionResult {
        let photoCandidates = rangeMetrics.filter { metric in
            guard let url = metric.photoUrl else { return false }
            return !url.isEmpty
        }

        guard !photoCandidates.isEmpty else {
            return PhotoSelectionResult(canonicalPhotoId: nil, hasPhotosInRange: false)
        }

        let selectedPhoto = photoCandidates.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(midpoint)) < abs(rhs.date.timeIntervalSince(midpoint))
        }

        return PhotoSelectionResult(
            canonicalPhotoId: selectedPhoto?.photoUrl,
            hasPhotosInRange: true
        )
    }

    // MARK: - Identifiers

    private func makeWeekIdentifier(startDate: Date) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
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
        String(format: "%04d", calendar.component(.year, from: startDate))
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }

        let sortedValues = values.sorted()
        let count = sortedValues.count
        let middleIndex = count / 2

        if count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2.0
        }

        return sortedValues[middleIndex]
    }
}
