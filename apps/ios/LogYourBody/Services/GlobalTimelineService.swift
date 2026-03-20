import Foundation

/// Service responsible for building weekly, monthly, and yearly buckets
/// for the global timeline scrubber.
final class GlobalTimelineService {
    struct BodyScoreContext {
        let sex: BiologicalSex
        let birthYear: Int
        let heightCm: Double
        let measurementPreference: MeasurementSystem
    }

    struct BuildInput {
        let bodyMetrics: [BodyMetrics]
        let dailyMetrics: [DailyMetrics]
        let bodyScoreContext: BodyScoreContext?

        init(
            bodyMetrics: [BodyMetrics],
            dailyMetrics: [DailyMetrics] = [],
            bodyScoreContext: BodyScoreContext? = nil
        ) {
            self.bodyMetrics = bodyMetrics
            self.dailyMetrics = dailyMetrics
            self.bodyScoreContext = bodyScoreContext
        }
    }

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Public API

    func makeBuckets(for scale: GlobalTimelineScale, metrics: [BodyMetrics]) -> [GlobalTimelineBucket] {
        makeBuckets(for: scale, input: BuildInput(bodyMetrics: metrics))
    }

    func makeBuckets(for scale: GlobalTimelineScale, input: BuildInput) -> [GlobalTimelineBucket] {
        guard !input.bodyMetrics.isEmpty || !input.dailyMetrics.isEmpty else { return [] }

        switch scale {
        case .week:
            return makeWeeklyBuckets(from: input)
        case .month:
            return makeMonthlyBuckets(from: input)
        case .year:
            return makeYearlyBuckets(from: input)
        }
    }

    func makeInitialCursor(for metrics: [BodyMetrics]) -> GlobalTimelineCursor? {
        makeInitialCursor(for: BuildInput(bodyMetrics: metrics))
    }

    func makeInitialCursor(for input: BuildInput) -> GlobalTimelineCursor? {
        guard !input.bodyMetrics.isEmpty || !input.dailyMetrics.isEmpty else { return nil }

        let weeklyBuckets = makeWeeklyBuckets(from: input)
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

    private func makeWeeklyBuckets(from input: BuildInput) -> [GlobalTimelineBucket] {
        let context = makeAggregationContext(from: input)
        guard let mostRecentDate = latestDate(in: context),
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

    private func makeMonthlyBuckets(from input: BuildInput) -> [GlobalTimelineBucket] {
        let context = makeAggregationContext(from: input)
        guard let mostRecentDate = latestDate(in: context),
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

    private func makeYearlyBuckets(from input: BuildInput) -> [GlobalTimelineBucket] {
        let context = makeAggregationContext(from: input)
        guard let mostRecentDate = latestDate(in: context),
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
        guard let earliestDate = earliestDate(in: context) else {
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
            let rangeDailyMetrics = dailyMetrics(in: startDate..<endDate, context: context)
            if hasAnyData(
                in: rangeMetrics,
                dailyMetrics: rangeDailyMetrics,
                allowDailyOnlyBucket: context.metrics.isEmpty
            ) {
                buckets.append(
                    GlobalTimelineBucket(
                        id: identifier(startDate),
                        scale: scale,
                        startDate: startDate,
                        endDate: endDate,
                        metrics: makeSnapshot(
                            scale: scale,
                            rangeMetrics: rangeMetrics,
                            rangeDailyMetrics: rangeDailyMetrics,
                            allMetrics: context.metrics,
                            normalizedWeightUnit: context.normalizedWeightUnit,
                            bodyScoreContext: context.bodyScoreContext,
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
        let metricDates: [Date]
        let dailyMetrics: [DailyMetrics]
        let dailyMetricDates: [Date]
        let normalizedWeightUnit: String
        let bodyScoreContext: BodyScoreContext?
    }

    private func makeAggregationContext(from input: BuildInput) -> AggregationContext {
        let targetUnit = resolvedWeightUnit(from: input.bodyMetrics)
        let normalizedMetrics = input.bodyMetrics
            .sorted { $0.date < $1.date }
            .map { normalizeWeightUnit(for: $0, targetUnit: targetUnit) }
        let sortedDailyMetrics = input.dailyMetrics.sorted { $0.date < $1.date }

        return AggregationContext(
            metrics: normalizedMetrics,
            metricDates: normalizedMetrics.map(\.date),
            dailyMetrics: sortedDailyMetrics,
            dailyMetricDates: sortedDailyMetrics.map(\.date),
            normalizedWeightUnit: targetUnit,
            bodyScoreContext: input.bodyScoreContext
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
        let startIndex = lowerBound(for: range.lowerBound, in: context.metricDates)
        let endIndex = lowerBound(for: range.upperBound, in: context.metricDates)

        guard startIndex < endIndex else {
            return []
        }

        return Array(context.metrics[startIndex..<endIndex])
    }

    private func dailyMetrics(in range: Range<Date>, context: AggregationContext) -> [DailyMetrics] {
        let startIndex = lowerBound(for: range.lowerBound, in: context.dailyMetricDates)
        let endIndex = lowerBound(for: range.upperBound, in: context.dailyMetricDates)

        guard startIndex < endIndex else {
            return []
        }

        return Array(context.dailyMetrics[startIndex..<endIndex])
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

    private func hasAnyData(
        in metrics: [BodyMetrics],
        dailyMetrics: [DailyMetrics],
        allowDailyOnlyBucket: Bool
    ) -> Bool {
        let hasBodyMetricData = metrics.contains { metric in
            let hasWeight = metric.weight != nil
            let hasBodyFat = metric.bodyFatPercentage != nil
            let hasPhoto = metric.photoUrl?.isEmpty == false
            return hasWeight || hasBodyFat || hasPhoto
        }

        if hasBodyMetricData {
            return true
        }

        guard allowDailyOnlyBucket else {
            return false
        }

        return dailyMetrics.contains { ($0.steps ?? 0) > 0 }
    }

    private func makeSnapshot(
        scale: GlobalTimelineScale,
        rangeMetrics: [BodyMetrics],
        rangeDailyMetrics: [DailyMetrics],
        allMetrics: [BodyMetrics],
        normalizedWeightUnit: String,
        bodyScoreContext: BodyScoreContext?,
        midpoint: Date
    ) -> GlobalTimelineMetricsSnapshot {
        let photoSelection = makePhotoSelection(rangeMetrics: rangeMetrics, midpoint: midpoint)
        let weight = makeWeightValue(rangeMetrics: rangeMetrics, allMetrics: allMetrics, midpoint: midpoint)
        let bodyFat = makeBodyFatValue(rangeMetrics: rangeMetrics, allMetrics: allMetrics, midpoint: midpoint)
        let ffmi = makeFFMIValue(
            weight: weight,
            bodyFat: bodyFat,
            normalizedWeightUnit: normalizedWeightUnit,
            bodyScoreContext: bodyScoreContext
        )
        let steps = makeStepsValue(scale: scale, rangeDailyMetrics: rangeDailyMetrics)
        let bodyScoreResult = makeBodyScoreResult(
            weight: weight,
            bodyFat: bodyFat,
            normalizedWeightUnit: normalizedWeightUnit,
            bodyScoreContext: bodyScoreContext,
            midpoint: midpoint
        )

        return GlobalTimelineMetricsSnapshot(
            weight: weight,
            bodyFat: bodyFat,
            ffmi: ffmi,
            steps: steps,
            canonicalPhotoId: photoSelection.canonicalPhotoId,
            hasPhotosInRange: photoSelection.hasPhotosInRange,
            bodyScore: bodyScoreResult?.score,
            bodyScoreCompleteness: bodyScoreCompleteness(
                weight: weight,
                bodyFat: bodyFat,
                bodyScore: bodyScoreResult
            )
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

    private func makeFFMIValue(
        weight: GlobalTimelineMetricValue,
        bodyFat: GlobalTimelineMetricValue,
        normalizedWeightUnit: String,
        bodyScoreContext: BodyScoreContext?
    ) -> GlobalTimelineMetricValue {
        guard let bodyScoreResult = makeBodyScoreResult(
            weight: weight,
            bodyFat: bodyFat,
            normalizedWeightUnit: normalizedWeightUnit,
            bodyScoreContext: bodyScoreContext,
            midpoint: nil
        ) else {
            return GlobalTimelineMetricValue(value: nil, presence: .missing)
        }

        return GlobalTimelineMetricValue(
            value: bodyScoreResult.ffmi,
            presence: combinedPresence(weight.presence, bodyFat.presence)
        )
    }

    private func makeStepsValue(
        scale: GlobalTimelineScale,
        rangeDailyMetrics: [DailyMetrics]
    ) -> GlobalTimelineMetricValue {
        let stepValues = rangeDailyMetrics.compactMap(\.steps).filter { $0 > 0 }
        guard !stepValues.isEmpty else {
            return GlobalTimelineMetricValue(value: nil, presence: .missing)
        }

        let average = Double(stepValues.reduce(0, +)) / Double(stepValues.count)
        let roundedAverage = round(average)

        if scale == .week, stepValues.count < 5 {
            return GlobalTimelineMetricValue(value: roundedAverage, presence: .estimated)
        }

        return GlobalTimelineMetricValue(value: roundedAverage, presence: .present)
    }

    private func makeBodyScoreResult(
        weight: GlobalTimelineMetricValue,
        bodyFat: GlobalTimelineMetricValue,
        normalizedWeightUnit: String,
        bodyScoreContext: BodyScoreContext?,
        midpoint: Date?
    ) -> BodyScoreResult? {
        guard let bodyScoreContext,
              let weightValue = weight.value,
              let bodyFatValue = bodyFat.value else {
            return nil
        }

        let weightKg = MetricsFormatter.convertWeight(
            value: weightValue,
            from: normalizedWeightUnit,
            to: "kg"
        )
        let input = BodyScoreInput(
            sex: bodyScoreContext.sex,
            birthYear: bodyScoreContext.birthYear,
            height: HeightValue(value: bodyScoreContext.heightCm, unit: .centimeters),
            weight: WeightValue(value: weightKg, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: bodyFatValue, source: .manualValue),
            measurementPreference: bodyScoreContext.measurementPreference,
            healthSnapshot: HealthImportSnapshot(
                heightCm: bodyScoreContext.heightCm,
                weightKg: weightKg,
                bodyFatPercentage: bodyFatValue,
                birthYear: bodyScoreContext.birthYear
            )
        )

        guard input.isReadyForCalculation else {
            return nil
        }

        let calculationDate = midpoint ?? Date()
        return try? BodyScoreCalculator().calculateScore(
            context: BodyScoreCalculationContext(input: input, calculationDate: calculationDate)
        )
    }

    private func combinedPresence(_ lhs: MetricPresence, _ rhs: MetricPresence) -> MetricPresence {
        if lhs == .missing || rhs == .missing {
            return .missing
        }

        if lhs == .estimated || rhs == .estimated {
            return .estimated
        }

        return .present
    }

    private func bodyScoreCompleteness(
        weight: GlobalTimelineMetricValue,
        bodyFat: GlobalTimelineMetricValue,
        bodyScore: BodyScoreResult?
    ) -> BodyScoreCompleteness {
        guard bodyScore != nil else {
            return .none
        }

        if weight.presence == .present && bodyFat.presence == .present {
            return .full
        }

        return .partial
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

    private func earliestDate(in context: AggregationContext) -> Date? {
        [context.metrics.first?.date, context.dailyMetrics.first?.date]
            .compactMap { $0 }
            .min()
    }

    private func latestDate(in context: AggregationContext) -> Date? {
        [context.metrics.last?.date, context.dailyMetrics.last?.date]
            .compactMap { $0 }
            .max()
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
