//
// MetricsInterpolationService.swift
// LogYourBody
//
// Service for interpolating missing body metrics based on surrounding datapoints
// Provides confidence levels and enforces maximum gap thresholds
//

import Foundation

/// Represents an interpolated metric value with metadata
struct InterpolatedMetric {
    let value: Double
    let isInterpolated: Bool
    let isLastKnown: Bool  // True if this is the last known value (for dates after final entry)
    let confidenceLevel: ConfidenceLevel?

    enum ConfidenceLevel: String {
        case high      // ≤7 days gap
        case medium    // 8-14 days gap
        case low       // 15-30 days gap
    }

    /// Helper to determine confidence level based on days gap
    static func confidence(forDaysGap days: Int) -> ConfidenceLevel? {
        switch days {
        case 0...7: return .high
        case 8...14: return .medium
        case 15...30: return .low
        default: return nil  // Gap too large, no interpolation
        }
    }
}

class MetricsInterpolationService {
    static let shared = MetricsInterpolationService()
    private init() {}

    // Maximum gap in days for interpolation (matching web implementation)
    private let maxInterpolationGapDays = 30

    // Maximum gap in days for DEXA-anchored body-fat estimates. DEXA scans are
    // typically months apart, so a wider window is allowed when both anchors
    // are measured DEXA results and the estimate is derived from scale weight.
    private let maxDexaInterpolationGapDays = 365

    final class WeightInterpolationContext {
        private let metrics: [BodyMetrics]
        private let maxGapDays: Int
        private let calendar = Calendar.current

        // Cached trend-weight series for efficiency when querying multiple dates
        private var trendWeightCache: [Date: InterpolatedMetric] = [:]
        private var trendRawValues: [Date: Double] = [:]
        private var trendLastDay: Date?
        private var trendLastValue: Double?
        // Smoothing factor for exponential moving average (EMA).
        // Higher values react more quickly to new weigh-ins.
        private let trendAlpha: Double = 0.25

        init(metrics: [BodyMetrics], maxGapDays: Int) {
            self.metrics = metrics
            self.maxGapDays = maxGapDays
        }

        /// Returns a recency-weighted "trend" weight using an exponential moving average
        /// over a daily weight series (with linear interpolation for missing days).
        func trendWeight(for date: Date) -> InterpolatedMetric? {
            guard let firstMetric = metrics.first, date >= firstMetric.date else { return nil }

            let targetDay = calendar.startOfDay(for: date)
            let firstDay = calendar.startOfDay(for: firstMetric.date)

            if targetDay < firstDay {
                return nil
            }

            if let cached = trendWeightCache[targetDay] {
                return cached
            }

            // There is no new measurement after the final metric. Walking the
            // EMA one day at a time all the way to a far-future query date can
            // block the main thread for seconds (for example, when the last
            // weigh-in is months or years before today). Process one day past
            // the final metric so timestamped final-day measurements are
            // included, then reuse that last-known trend for later dates.
            let lastMetricDay = calendar.startOfDay(for: metrics[metrics.count - 1].date)
            let processingEndDay: Date
            if targetDay > lastMetricDay {
                processingEndDay = calendar.date(byAdding: .day, value: 1, to: lastMetricDay) ?? lastMetricDay
            } else {
                processingEndDay = targetDay
            }

            let cachedAnchor = trendRawValues
                .filter { $0.key <= targetDay }
                .max { $0.key < $1.key }
            var ema = cachedAnchor?.value ?? trendLastValue
            var currentDay: Date

            if let cachedAnchor {
                currentDay = calendar.date(byAdding: .day, value: 1, to: cachedAnchor.key) ?? cachedAnchor.key
            } else if let lastDay = trendLastDay, let lastValue = ema, lastDay >= firstDay, targetDay >= lastDay {
                currentDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
                ema = lastValue
            } else {
                currentDay = firstDay
                ema = nil
            }

            while currentDay <= processingEndDay {
                // Midnight is before a weigh-in later that day. Sampling it marks
                // the weigh-in interpolated and drops it from Progress and Share.
                let sampleDate = trendSampleDate(on: currentDay, query: date)
                guard let weightResult = estimate(for: sampleDate) else {
                    // A gap larger than the interpolation limit cannot yield a
                    // result on any intervening day. Jump to the next known
                    // measurement instead of scanning every calendar day.
                    if let nextMetric = metrics.first(where: { $0.date > sampleDate }) {
                        let nextDay = calendar.startOfDay(for: nextMetric.date)
                        if nextDay > currentDay {
                            currentDay = nextDay
                            continue
                        }
                    }
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else {
                        break
                    }
                    currentDay = nextDay
                    continue
                }

                if let existingEma = ema {
                    ema = trendAlpha * weightResult.value + (1 - trendAlpha) * existingEma
                } else {
                    ema = weightResult.value
                }

                guard let emaValue = ema else { break }

                let trendMetric = InterpolatedMetric(
                    value: round(emaValue * 10) / 10,
                    isInterpolated: weightResult.isInterpolated,
                    isLastKnown: weightResult.isLastKnown,
                    confidenceLevel: weightResult.confidenceLevel
                )

                trendWeightCache[currentDay] = trendMetric
                trendRawValues[currentDay] = emaValue
                trendLastDay = currentDay
                trendLastValue = emaValue

                if currentDay == targetDay {
                    return trendMetric
                }

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else {
                    break
                }
                currentDay = nextDay
            }

            if targetDay > processingEndDay,
               let lastKnown = trendWeightCache[processingEndDay],
               let anchorValue = trendRawValues[processingEndDay],
               let days = calendar.dateComponents([.day], from: processingEndDay, to: targetDay).day,
               days > 0 {
                // Match the established estimate path for the final known
                // value. It rounds measurements to one decimal before the
                // analytical tail continues the EMA, while anchorValue stays
                // unrounded for numerical continuity.
                let finalWeight = estimate(for: metrics[metrics.count - 1].date)?.value ?? anchorValue
                let decay = pow(1 - trendAlpha, Double(days))
                return InterpolatedMetric(
                    value: round((finalWeight + (anchorValue - finalWeight) * decay) * 10) / 10,
                    isInterpolated: false,
                    isLastKnown: true,
                    confidenceLevel: nil
                )
            }

            return trendWeightCache[targetDay]
        }

        /// Latest weigh-in on `day` that does not look ahead of `query`.
        /// Days with no eligible weigh-in stay on midnight so gaps still interpolate.
        private func trendSampleDate(on day: Date, query: Date) -> Date {
            if let measured = metrics.last(where: {
                calendar.isDate($0.date, inSameDayAs: day) && $0.date <= query
            }) {
                return measured.date
            }
            return day
        }

        func estimate(for date: Date) -> InterpolatedMetric? {
            guard let firstMetric = metrics.first,
                  let lastMetric = metrics.last else {
                return nil
            }

            if date < firstMetric.date {
                return nil
            }

            if date > lastMetric.date {
                guard let lastWeight = lastMetric.weight else { return nil }
                return InterpolatedMetric(
                    value: round(lastWeight * 10) / 10,
                    isInterpolated: false,
                    isLastKnown: true,
                    confidenceLevel: nil
                )
            }

            guard let beforeIndex = indexOfLastMetric(onOrBefore: date) else {
                return nil
            }

            let beforeMetric = metrics[beforeIndex]

            if calendar.isDate(beforeMetric.date, inSameDayAs: date) {
                guard let weight = beforeMetric.weight else { return nil }
                return InterpolatedMetric(
                    value: round(weight * 10) / 10,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                )
            }

            let afterIndex = beforeIndex + 1
            guard afterIndex < metrics.count else {
                return nil
            }

            let afterMetric = metrics[afterIndex]

            guard let beforeWeight = beforeMetric.weight,
                  let afterWeight = afterMetric.weight else {
                return nil
            }

            let gapDays = calendar.dateComponents(
                [.day],
                from: beforeMetric.date,
                to: afterMetric.date
            ).day ?? 0

            guard gapDays <= maxGapDays else {
                return nil
            }

            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = totalInterval != 0 ? progressInterval / totalInterval : 0

            let estimatedWeight = beforeWeight + (afterWeight - beforeWeight) * progress
            let confidence = InterpolatedMetric.confidence(forDaysGap: gapDays)

            return InterpolatedMetric(
                value: round(estimatedWeight * 10) / 10,
                isInterpolated: true,
                isLastKnown: false,
                confidenceLevel: confidence
            )
        }

        private func indexOfLastMetric(onOrBefore date: Date) -> Int? {
            var low = 0
            var high = metrics.count

            while low < high {
                let mid = (low + high) / 2
                if metrics[mid].date <= date {
                    low = mid + 1
                } else {
                    high = mid
                }
            }

            let index = low - 1
            return index >= 0 ? index : nil
        }
    }

    final class BodyFatInterpolationContext {
        private let metrics: [BodyMetrics]
        private let maxGapDays: Int
        private let maxDexaGapDays: Int
        private let weightContext: WeightInterpolationContext?
        private let calendar = Calendar.current

        init(
            metrics: [BodyMetrics],
            maxGapDays: Int,
            maxDexaGapDays: Int,
            weightContext: WeightInterpolationContext?
        ) {
            self.metrics = metrics
            self.maxGapDays = maxGapDays
            self.maxDexaGapDays = maxDexaGapDays
            self.weightContext = weightContext
        }

        func estimate(for date: Date) -> InterpolatedMetric? {
            guard let firstMetric = metrics.first,
                  let lastMetric = metrics.last else {
                return nil
            }

            if date < firstMetric.date {
                return nil
            }

            if date > lastMetric.date {
                guard let lastBF = lastMetric.bodyFatPercentage else { return nil }
                return InterpolatedMetric(
                    value: round(lastBF * 10) / 10,
                    isInterpolated: false,
                    isLastKnown: true,
                    confidenceLevel: nil
                )
            }

            guard let beforeIndex = indexOfLastMetric(onOrBefore: date) else {
                return nil
            }

            let beforeMetric = metrics[beforeIndex]

            if calendar.isDate(beforeMetric.date, inSameDayAs: date) {
                guard let bf = beforeMetric.bodyFatPercentage else { return nil }
                return InterpolatedMetric(
                    value: round(bf * 10) / 10,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                )
            }

            let afterIndex = beforeIndex + 1
            guard afterIndex < metrics.count else {
                return nil
            }

            let afterMetric = metrics[afterIndex]

            guard let beforeBF = beforeMetric.bodyFatPercentage,
                  let afterBF = afterMetric.bodyFatPercentage else {
                return nil
            }

            let gapDays = calendar.dateComponents(
                [.day],
                from: beforeMetric.date,
                to: afterMetric.date
            ).day ?? 0

            if gapDays > maxGapDays {
                return dexaAnchoredEstimate(
                    for: date,
                    before: beforeMetric,
                    after: afterMetric,
                    gapDays: gapDays
                )
            }

            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = totalInterval != 0 ? progressInterval / totalInterval : 0

            let estimatedBF = beforeBF + (afterBF - beforeBF) * progress
            let confidence = InterpolatedMetric.confidence(forDaysGap: gapDays)

            return InterpolatedMetric(
                value: round(estimatedBF * 10) / 10,
                isInterpolated: true,
                isLastKnown: false,
                confidenceLevel: confidence
            )
        }

        /// Estimates body fat between two measured DEXA scans using the scale
        /// weight trend. Lean mass is interpolated linearly between the scans
        /// and fat mass is taken as the remainder of the trend weight, so the
        /// estimate tracks weigh-ins instead of a straight line between scans.
        private func dexaAnchoredEstimate(
            for date: Date,
            before: BodyMetrics,
            after: BodyMetrics,
            gapDays: Int
        ) -> InterpolatedMetric? {
            guard gapDays <= maxDexaGapDays,
                  isDexaMeasurement(before),
                  isDexaMeasurement(after),
                  let beforeBF = before.bodyFatPercentage,
                  let afterBF = after.bodyFatPercentage,
                  let weightContext else {
                return nil
            }

            guard let beforeWeight = weight(at: before),
                  let afterWeight = weight(at: after),
                  beforeWeight > 0,
                  afterWeight > 0,
                  let trend = weightContext.trendWeight(for: date),
                  trend.value > 0 else {
                return nil
            }

            let beforeLean = beforeWeight * (1 - beforeBF / 100)
            let afterLean = afterWeight * (1 - afterBF / 100)

            let totalInterval = after.date.timeIntervalSince(before.date)
            let progressInterval = date.timeIntervalSince(before.date)
            let progress = totalInterval != 0 ? progressInterval / totalInterval : 0

            let leanMass = beforeLean + (afterLean - beforeLean) * progress
            let estimatedBF = min(100, max(0, (trend.value - leanMass) / trend.value * 100))

            return InterpolatedMetric(
                value: round(estimatedBF * 10) / 10,
                isInterpolated: true,
                isLastKnown: false,
                confidenceLevel: .low
            )
        }

        private func isDexaMeasurement(_ metric: BodyMetrics) -> Bool {
            let method = metric.bodyFatMethod?.lowercased() ?? ""
            let source = metric.dataSource?.lowercased() ?? ""
            return method.contains("dexa") || source.contains("bodyspec_dexa")
        }

        private func weight(at metric: BodyMetrics) -> Double? {
            if let weight = metric.weight {
                return weight
            }
            return weightContext?.trendWeight(for: metric.date)?.value
        }

        private func indexOfLastMetric(onOrBefore date: Date) -> Int? {
            var low = 0
            var high = metrics.count

            while low < high {
                let mid = (low + high) / 2
                if metrics[mid].date <= date {
                    low = mid + 1
                } else {
                    high = mid
                }
            }

            let index = low - 1
            return index >= 0 ? index : nil
        }
    }

    final class FFMIInterpolationContext {
        private let weightContext: WeightInterpolationContext
        private let bodyFatContext: BodyFatInterpolationContext
        private let heightInches: Double

        init(weightContext: WeightInterpolationContext, bodyFatContext: BodyFatInterpolationContext, heightInches: Double) {
            self.weightContext = weightContext
            self.bodyFatContext = bodyFatContext
            self.heightInches = heightInches
        }

        func estimate(for date: Date) -> InterpolatedMetric? {
            guard let weightResult = weightContext.trendWeight(for: date),
                  let bodyFatResult = bodyFatContext.estimate(for: date),
                  let ffmi = UnitConversion.calculateFFMI(
                    weightKg: weightResult.value,
                    bodyFatPercentage: bodyFatResult.value,
                    heightCm: heightInches * 2.54
                  ) else {
                return nil
            }

            let isInterpolated = weightResult.isInterpolated || bodyFatResult.isInterpolated
            let isLastKnown = weightResult.isLastKnown || bodyFatResult.isLastKnown
            let confidence = lowestConfidence(
                weightResult.confidenceLevel,
                bodyFatResult.confidenceLevel,
                isInterpolated: isInterpolated
            )

            return InterpolatedMetric(
                value: round(ffmi * 10) / 10,
                isInterpolated: isInterpolated,
                isLastKnown: isLastKnown,
                confidenceLevel: confidence
            )
        }

        private func lowestConfidence(
            _ first: InterpolatedMetric.ConfidenceLevel?,
            _ second: InterpolatedMetric.ConfidenceLevel?,
            isInterpolated: Bool
        ) -> InterpolatedMetric.ConfidenceLevel? {
            guard isInterpolated else { return nil }
            let levels: [InterpolatedMetric.ConfidenceLevel] = [.high, .medium, .low]
            let firstIndex = first.flatMap { levels.firstIndex(of: $0) } ?? 0
            let secondIndex = second.flatMap { levels.firstIndex(of: $0) } ?? 0
            return levels[max(firstIndex, secondIndex)]
        }

        private func estimateLeanMass(for date: Date) -> InterpolatedMetric? {
            // Use trend (EMA-smoothed) weight for FFMI calculations
            guard let weightResult = weightContext.trendWeight(for: date),
                  let bodyFatResult = bodyFatContext.estimate(for: date) else {
                return nil
            }

            let leanMass = weightResult.value * (1 - bodyFatResult.value / 100)

            let isInterpolated = weightResult.isInterpolated || bodyFatResult.isInterpolated
            let isLastKnown = weightResult.isLastKnown || bodyFatResult.isLastKnown

            var confidence: InterpolatedMetric.ConfidenceLevel?
            if isInterpolated {
                if let wConf = weightResult.confidenceLevel, let bfConf = bodyFatResult.confidenceLevel {
                    let levels: [InterpolatedMetric.ConfidenceLevel] = [.high, .medium, .low]
                    let wIndex = levels.firstIndex(of: wConf) ?? 0
                    let bfIndex = levels.firstIndex(of: bfConf) ?? 0
                    confidence = levels[max(wIndex, bfIndex)]
                } else {
                    confidence = weightResult.confidenceLevel ?? bodyFatResult.confidenceLevel
                }
            }

            return InterpolatedMetric(
                value: round(leanMass * 10) / 10,
                isInterpolated: isInterpolated,
                isLastKnown: isLastKnown,
                confidenceLevel: confidence
            )
        }
    }

    func makeWeightInterpolationContext(for metrics: [BodyMetrics]) -> WeightInterpolationContext? {
        let filtered = metrics.filter { $0.weight != nil }.sorted { $0.date < $1.date }
        guard !filtered.isEmpty else { return nil }
        return WeightInterpolationContext(metrics: filtered, maxGapDays: maxInterpolationGapDays)
    }

    func makeBodyFatInterpolationContext(for metrics: [BodyMetrics]) -> BodyFatInterpolationContext? {
        let filtered = metrics.filter { $0.bodyFatPercentage != nil }.sorted { $0.date < $1.date }
        guard !filtered.isEmpty else { return nil }
        return BodyFatInterpolationContext(
            metrics: filtered,
            maxGapDays: maxInterpolationGapDays,
            maxDexaGapDays: maxDexaInterpolationGapDays,
            weightContext: makeWeightInterpolationContext(for: metrics)
        )
    }

    func makeFFMIInterpolationContext(for metrics: [BodyMetrics], heightInches: Double) -> FFMIInterpolationContext? {
        guard let weightContext = makeWeightInterpolationContext(for: metrics),
              let bodyFatContext = makeBodyFatInterpolationContext(for: metrics) else {
            return nil
        }
        return FFMIInterpolationContext(
            weightContext: weightContext,
            bodyFatContext: bodyFatContext,
            heightInches: heightInches
        )
    }

    // MARK: - Weight Interpolation

    /// Estimate weight for a given date based on nearby entries
    /// Returns nil if gap is >30 days or no data available
    func estimateWeight(for date: Date, metrics: [BodyMetrics]) -> InterpolatedMetric? {
        let sortedMetrics = metrics.filter { $0.weight != nil }.sorted { $0.date < $1.date }
        guard !sortedMetrics.isEmpty else { return nil }
        guard let lastMetric = sortedMetrics.last else { return nil }

        // Check if date is before first entry
        if date < sortedMetrics[0].date {
            return nil  // No data before first entry
        }

        // Check if date is after last entry - return last known value
        if date > lastMetric.date {
            guard let lastWeight = lastMetric.weight else { return nil }
            return InterpolatedMetric(
                value: round(lastWeight * 10) / 10,
                isInterpolated: false,
                isLastKnown: true,
                confidenceLevel: nil
            )
        }

        // Find metrics before and after the date
        let before = sortedMetrics.last { $0.date <= date }
        let after = sortedMetrics.first { $0.date > date }

        // Exact match - return actual value
        if let exactMatch = before, Calendar.current.isDate(exactMatch.date, inSameDayAs: date) {
            guard let weight = exactMatch.weight else { return nil }
            return InterpolatedMetric(
                value: round(weight * 10) / 10,
                isInterpolated: false,
                isLastKnown: false,
                confidenceLevel: nil
            )
        }

        // Interpolate between two points
        if let beforeMetric = before, let afterMetric = after,
           let beforeWeight = beforeMetric.weight, let afterWeight = afterMetric.weight {
            // Check gap size
            let gapDays = Calendar.current.dateComponents([.day], from: beforeMetric.date, to: afterMetric.date).day ?? 0
            guard gapDays <= maxInterpolationGapDays else { return nil }

            // Linear interpolation
            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = progressInterval / totalInterval

            let estimatedWeight = beforeWeight + (afterWeight - beforeWeight) * progress
            let confidence = InterpolatedMetric.confidence(forDaysGap: gapDays)

            return InterpolatedMetric(
                value: round(estimatedWeight * 10) / 10,
                isInterpolated: true,
                isLastKnown: false,
                confidenceLevel: confidence
            )
        }

        return nil
    }

    // MARK: - Body Fat Interpolation

    /// Estimate body fat percentage for a given date based on nearby entries.
    /// Returns nil if gap is >30 days unless both anchors are measured DEXA
    /// scans, in which case scale weight carries the estimate between them.
    func estimateBodyFat(for date: Date, metrics: [BodyMetrics]) -> InterpolatedMetric? {
        makeBodyFatInterpolationContext(for: metrics)?.estimate(for: date)
    }

    // MARK: - Lean Mass Calculation

    /// Calculate or estimate lean mass for a given date
    /// Lean mass = weight * (1 - bodyFat% / 100)
    func estimateLeanMass(for date: Date, metrics: [BodyMetrics]) -> InterpolatedMetric? {
        // Use trend (EMA-smoothed) weight combined with body fat (actual or interpolated)
        guard let weightContext = makeWeightInterpolationContext(for: metrics),
              let trendWeightResult = weightContext.trendWeight(for: date),
              let bodyFatResult = estimateBodyFat(for: date, metrics: metrics) else {
            return nil
        }

        // Calculate lean mass
        let leanMass = trendWeightResult.value * (1 - bodyFatResult.value / 100)

        // Result is interpolated if either weight or body fat was interpolated
        let isInterpolated = trendWeightResult.isInterpolated || bodyFatResult.isInterpolated
        let isLastKnown = trendWeightResult.isLastKnown || bodyFatResult.isLastKnown

        // Use the lower confidence level of the two inputs
        var confidence: InterpolatedMetric.ConfidenceLevel?
        if isInterpolated {
            if let wConf = trendWeightResult.confidenceLevel, let bfConf = bodyFatResult.confidenceLevel {
                // Use lower confidence
                let confidenceLevels: [InterpolatedMetric.ConfidenceLevel] = [.high, .medium, .low]
                let wIndex = confidenceLevels.firstIndex(of: wConf) ?? 0
                let bfIndex = confidenceLevels.firstIndex(of: bfConf) ?? 0
                confidence = confidenceLevels[max(wIndex, bfIndex)]
            } else {
                confidence = trendWeightResult.confidenceLevel ?? bodyFatResult.confidenceLevel
            }
        }

        return InterpolatedMetric(
            value: round(leanMass * 10) / 10,
            isInterpolated: isInterpolated,
            isLastKnown: isLastKnown,
            confidenceLevel: confidence
        )
    }

    /// Estimate trend (EMA-smoothed) weight for a given date
    /// This builds on the WeightInterpolationContext so that callers can
    /// access the same trend series used for FFMI/lean-mass calculations.
    func estimateTrendWeight(for date: Date, metrics: [BodyMetrics]) -> InterpolatedMetric? {
        guard let context = makeWeightInterpolationContext(for: metrics) else {
            return nil
        }
        return context.trendWeight(for: date)
    }

    // MARK: - FFMI Calculation

    /// Calculate or estimate FFMI for a given date
    /// FFMI follows the canonical normalized formula in `UnitConversion` so
    /// Home, Stats, charts, and Body Score agree for the same selected date.
    /// Requires height to be provided
    func estimateFFMI(for date: Date, metrics: [BodyMetrics], heightInches: Double?) -> InterpolatedMetric? {
        guard let heightInches = heightInches, heightInches > 0 else { return nil }

        guard let weightResult = estimateTrendWeight(for: date, metrics: metrics),
              let bodyFatResult = estimateBodyFat(for: date, metrics: metrics),
              let ffmi = UnitConversion.calculateFFMI(
                weightKg: weightResult.value,
                bodyFatPercentage: bodyFatResult.value,
                heightCm: heightInches * 2.54
              ) else {
            return nil
        }

        let isInterpolated = weightResult.isInterpolated || bodyFatResult.isInterpolated
        let isLastKnown = weightResult.isLastKnown || bodyFatResult.isLastKnown
        let confidence: InterpolatedMetric.ConfidenceLevel?
        if isInterpolated {
            let levels: [InterpolatedMetric.ConfidenceLevel] = [.high, .medium, .low]
            let weightIndex = weightResult.confidenceLevel.flatMap { levels.firstIndex(of: $0) } ?? 0
            let bodyFatIndex = bodyFatResult.confidenceLevel.flatMap { levels.firstIndex(of: $0) } ?? 0
            confidence = levels[max(weightIndex, bodyFatIndex)]
        } else {
            confidence = nil
        }

        return InterpolatedMetric(
            value: round(ffmi * 10) / 10,
            isInterpolated: isInterpolated,
            isLastKnown: isLastKnown,
            confidenceLevel: confidence
        )
    }

    // MARK: - Legacy Photo Metadata Methods (kept for backward compatibility)

    /// Find closest body metrics entry for a given date
    func findClosestMetrics(for date: Date, in metrics: [BodyMetrics], maxDaysDifference: Int = 7) -> BodyMetrics? {
        guard !metrics.isEmpty else { return nil }

        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: date)

        // Find metrics within the max days difference
        let closeMetrics = metrics.filter { metric in
            let metricStartOfDay = BodyMetricLocalDate.startOfDay(for: metric.localDate, calendar: calendar) ??
                calendar.startOfDay(for: metric.date)
            let daysDifference = abs(calendar.dateComponents([.day], from: targetStartOfDay, to: metricStartOfDay).day ?? Int.max)
            return daysDifference <= maxDaysDifference
        }

        // Return the closest one
        return closeMetrics.min { metric1, metric2 in
            abs(metric1.date.timeIntervalSince(date)) < abs(metric2.date.timeIntervalSince(date))
        }
    }
}
