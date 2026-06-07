import Foundation

/// Service responsible for building week, month, and year buckets for the
/// global timeline. The output is intentionally explicit about measured,
/// interpolated, last-known, and missing values so UI layers do not infer
/// provenance from a plain number.
final class GlobalTimelineService {
    private let calendar: Calendar
    private let interpolationService: MetricsInterpolationService

    init(
        calendar: Calendar = .current,
        interpolationService: MetricsInterpolationService = .shared
    ) {
        self.calendar = calendar
        self.interpolationService = interpolationService
    }

    // MARK: - Public API

    func makeBuckets(
        for scale: GlobalTimelineScale,
        metrics: [BodyMetrics],
        dailyMetrics: [DailyMetrics] = [],
        heightInches: Double? = nil
    ) -> [GlobalTimelineBucket] {
        let sortedMetrics = metrics.sorted { $0.date < $1.date }
        let sortedDailyMetrics = dailyMetrics.sorted { $0.date < $1.date }

        guard let range = makeTimelineDateRange(metrics: sortedMetrics, dailyMetrics: sortedDailyMetrics),
              var bucketStart = startOfBucket(containing: range.earliest, scale: scale),
              let latestBucketStart = startOfBucket(containing: range.latest, scale: scale) else {
            return []
        }

        let contexts = InterpolationContexts(
            weight: interpolationService.makeWeightInterpolationContext(for: sortedMetrics),
            bodyFat: interpolationService.makeBodyFatInterpolationContext(for: sortedMetrics),
            ffmi: heightInches.flatMap {
                interpolationService.makeFFMIInterpolationContext(for: sortedMetrics, heightInches: $0)
            }
        )

        var buckets: [GlobalTimelineBucket] = []

        while bucketStart <= latestBucketStart {
            guard let bucketEnd = endOfBucket(startingAt: bucketStart, scale: scale) else {
                break
            }

            let bucketMetrics = sortedMetrics.filter { $0.date >= bucketStart && $0.date < bucketEnd }
            let bucketDailyMetrics = sortedDailyMetrics.filter { $0.date >= bucketStart && $0.date < bucketEnd }
            let midpoint = midpoint(start: bucketStart, end: bucketEnd)

            let snapshot = makeMetricsSnapshot(
                bucketMetrics: bucketMetrics,
                bucketDailyMetrics: bucketDailyMetrics,
                midpoint: midpoint,
                contexts: contexts,
                heightInches: heightInches
            )

            if snapshot.hasRenderableData {
                buckets.append(
                    GlobalTimelineBucket(
                        id: makeIdentifier(scale: scale, startDate: bucketStart),
                        scale: scale,
                        startDate: bucketStart,
                        endDate: bucketEnd,
                        metrics: snapshot
                    )
                )
            }

            guard let nextBucketStart = startOfNextBucket(after: bucketStart, scale: scale) else {
                break
            }
            bucketStart = nextBucketStart
        }

        return buckets
    }

    func makeInitialCursor(
        for metrics: [BodyMetrics],
        dailyMetrics: [DailyMetrics] = []
    ) -> GlobalTimelineCursor? {
        let weeklyBuckets = makeBuckets(for: .week, metrics: metrics, dailyMetrics: dailyMetrics)
        guard let mostRecentBucket = weeklyBuckets.last else {
            return nil
        }

        return GlobalTimelineCursor(
            date: mostRecentBucket.endDate,
            scale: .week,
            bucketId: mostRecentBucket.id
        )
    }

    // MARK: - Snapshot builders

    private struct TimelineDateRange {
        let earliest: Date
        let latest: Date
    }

    private struct InterpolationContexts {
        let weight: MetricsInterpolationService.WeightInterpolationContext?
        let bodyFat: MetricsInterpolationService.BodyFatInterpolationContext?
        let ffmi: MetricsInterpolationService.FFMIInterpolationContext?
    }

    private struct PhotoSelectionResult {
        let canonicalPhotoId: String?
        let canonicalPhotoDate: Date?
        let photoCount: Int

        var hasPhotosInRange: Bool {
            photoCount > 0
        }
    }

    private func makeMetricsSnapshot(
        bucketMetrics: [BodyMetrics],
        bucketDailyMetrics: [DailyMetrics],
        midpoint: Date,
        contexts: InterpolationContexts,
        heightInches: Double?
    ) -> GlobalTimelineMetricsSnapshot {
        let weight = makeBodyMetricValue(
            directValues: bucketMetrics.compactMap { $0.weight },
            interpolated: contexts.weight?.estimate(for: midpoint)
        )
        let bodyFat = makeBodyMetricValue(
            directValues: bucketMetrics.compactMap { $0.bodyFatPercentage },
            interpolated: contexts.bodyFat?.estimate(for: midpoint)
        )
        let ffmi = makeFFMIValue(
            weight: weight,
            bodyFat: bodyFat,
            interpolated: contexts.ffmi?.estimate(for: midpoint),
            heightInches: heightInches
        )
        let steps = makeStepsValue(bucketDailyMetrics: bucketDailyMetrics)
        let photoSelection = makePhotoSelection(metrics: bucketMetrics, midpoint: midpoint)

        return GlobalTimelineMetricsSnapshot(
            weight: weight,
            bodyFat: bodyFat,
            ffmi: ffmi,
            steps: steps,
            canonicalPhotoId: photoSelection.canonicalPhotoId,
            canonicalPhotoDate: photoSelection.canonicalPhotoDate,
            hasPhotosInRange: photoSelection.hasPhotosInRange,
            photoCount: photoSelection.photoCount,
            bodyScore: nil,
            bodyScoreCompleteness: .none
        )
    }

    private func makeBodyMetricValue(
        directValues: [Double],
        interpolated: InterpolatedMetric?
    ) -> GlobalTimelineMetricValue {
        if let directValue = median(directValues) {
            return GlobalTimelineMetricValue(value: directValue, presence: .present)
        }

        return makeInterpolatedValue(interpolated)
    }

    private func makeFFMIValue(
        weight: GlobalTimelineMetricValue,
        bodyFat: GlobalTimelineMetricValue,
        interpolated: InterpolatedMetric?,
        heightInches: Double?
    ) -> GlobalTimelineMetricValue {
        guard let heightInches, heightInches > 0 else {
            return missingValue()
        }

        if weight.presence == .present,
           bodyFat.presence == .present,
           let weightKg = weight.value,
           let bodyFatPercentage = bodyFat.value {
            let heightMeters = heightInches * 0.0254
            let leanMassKg = weightKg * (1 - bodyFatPercentage / 100)
            let ffmi = leanMassKg / (heightMeters * heightMeters)

            return GlobalTimelineMetricValue(
                value: roundedOneDecimal(ffmi),
                presence: .present
            )
        }

        return makeInterpolatedValue(interpolated)
    }

    private func makeStepsValue(bucketDailyMetrics: [DailyMetrics]) -> GlobalTimelineMetricValue {
        let stepValues = bucketDailyMetrics.compactMap { metric -> Int? in
            guard let steps = metric.steps, steps > 0 else { return nil }
            return steps
        }

        guard !stepValues.isEmpty else {
            return missingValue()
        }

        return GlobalTimelineMetricValue(
            value: Double(stepValues.reduce(0, +)),
            presence: .present
        )
    }

    private func makeInterpolatedValue(_ metric: InterpolatedMetric?) -> GlobalTimelineMetricValue {
        guard let metric else {
            return missingValue()
        }

        if metric.isInterpolated {
            return GlobalTimelineMetricValue(
                value: metric.value,
                presence: .interpolated,
                confidence: makeConfidence(metric.confidenceLevel)
            )
        }

        if metric.isLastKnown {
            return GlobalTimelineMetricValue(
                value: metric.value,
                presence: .lastKnown
            )
        }

        return GlobalTimelineMetricValue(value: metric.value, presence: .present)
    }

    private func missingValue() -> GlobalTimelineMetricValue {
        GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private func makePhotoSelection(metrics: [BodyMetrics], midpoint: Date) -> PhotoSelectionResult {
        let photoCandidates = metrics.filter { metric in
            guard let url = metric.photoUrl else { return false }
            return !url.isEmpty
        }

        guard !photoCandidates.isEmpty else {
            return PhotoSelectionResult(canonicalPhotoId: nil, canonicalPhotoDate: nil, photoCount: 0)
        }

        let selected = photoCandidates.min { lhs, rhs in
            let lhsDiff = abs(lhs.date.timeIntervalSince(midpoint))
            let rhsDiff = abs(rhs.date.timeIntervalSince(midpoint))
            return lhsDiff < rhsDiff
        }

        return PhotoSelectionResult(
            canonicalPhotoId: selected?.photoUrl,
            canonicalPhotoDate: selected?.date,
            photoCount: photoCandidates.count
        )
    }

    // MARK: - Date helpers

    private func makeTimelineDateRange(metrics: [BodyMetrics], dailyMetrics: [DailyMetrics]) -> TimelineDateRange? {
        let bodyDates = metrics.compactMap { metric -> Date? in
            let hasWeight = metric.weight != nil
            let hasBodyFat = metric.bodyFatPercentage != nil
            let hasPhoto = metric.photoUrl?.isEmpty == false
            return hasWeight || hasBodyFat || hasPhoto ? metric.date : nil
        }
        let dailyDates = dailyMetrics.compactMap { metric -> Date? in
            guard let steps = metric.steps, steps > 0 else { return nil }
            return metric.date
        }
        let dates = bodyDates + dailyDates

        guard let earliest = dates.min(), let latest = dates.max() else {
            return nil
        }

        return TimelineDateRange(earliest: earliest, latest: latest)
    }

    private func startOfBucket(containing date: Date, scale: GlobalTimelineScale) -> Date? {
        switch scale {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start
        }
    }

    private func endOfBucket(startingAt startDate: Date, scale: GlobalTimelineScale) -> Date? {
        startOfNextBucket(after: startDate, scale: scale)
    }

    private func startOfNextBucket(after startDate: Date, scale: GlobalTimelineScale) -> Date? {
        switch scale {
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: startDate)
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: startDate)
        case .year:
            return calendar.date(byAdding: .year, value: 1, to: startDate)
        }
    }

    private func midpoint(start: Date, end: Date) -> Date {
        start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }

    private func makeIdentifier(scale: GlobalTimelineScale, startDate: Date) -> String {
        switch scale {
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
            let year = components.yearForWeekOfYear ?? calendar.component(.year, from: startDate)
            let week = components.weekOfYear ?? calendar.component(.weekOfYear, from: startDate)
            return String(format: "%04d-W%02d", year, week)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: startDate)
            let year = components.year ?? calendar.component(.year, from: startDate)
            let month = components.month ?? calendar.component(.month, from: startDate)
            return String(format: "%04d-M%02d", year, month)
        case .year:
            let year = calendar.component(.year, from: startDate)
            return String(format: "%04d", year)
        }
    }

    // MARK: - Value helpers

    private func makeConfidence(
        _ confidence: InterpolatedMetric.ConfidenceLevel?
    ) -> GlobalTimelineMetricConfidence? {
        switch confidence {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        case nil:
            return nil
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }

        let sortedValues = values.sorted()
        let count = sortedValues.count
        let middleIndex = count / 2

        let value: Double
        if count.isMultiple(of: 2) {
            let lower = sortedValues[middleIndex - 1]
            let upper = sortedValues[middleIndex]
            value = (lower + upper) / 2.0
        } else {
            value = sortedValues[middleIndex]
        }

        return roundedOneDecimal(value)
    }

    private func roundedOneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

private extension GlobalTimelineMetricsSnapshot {
    var hasRenderableData: Bool {
        weight.presence != .missing ||
            bodyFat.presence != .missing ||
            ffmi.presence != .missing ||
            steps.presence != .missing ||
            hasPhotosInRange
    }
}
