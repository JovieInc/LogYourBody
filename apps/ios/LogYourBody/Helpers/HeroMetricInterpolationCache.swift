//
// HeroMetricInterpolationCache.swift
// LogYourBody
//
// Caches the reusable MetricsInterpolationService contexts used to compute the
// dashboard hero's weight / body-fat / FFMI values while scrubbing the timeline.
//
// Previously `updateAnimatedValues(for:)` called
// `MetricsInterpolationService.estimate{Weight,BodyFat,FFMI}` on every scrub index
// change. Each call rebuilt an interpolation context (filter + sort), and FFMI
// additionally walked an EMA "trend weight" day-by-day — so scrubbing recomputed
// all of that per frame.
//
// The contexts depend only on the metrics array (plus height for FFMI), so we build
// them once per data change — keyed by a content fingerprint — and reuse them across
// scrubs. Reusing the same context instances also preserves their internal per-day
// caches (notably the FFMI trend-weight cache), so revisiting an index is cheap.
//
// The values produced are identical to the previous per-call path — see
// HeroMetricInterpolationCacheTests, which asserts value-exactness against
// MetricsInterpolationService.estimate{Weight,BodyFat,FFMI} across many indices.
//

import Foundation

final class HeroMetricInterpolationCache {
    /// Raw interpolated values (kg / %, before any unit conversion). A `nil` field
    /// means "no value available"; callers should leave the displayed value
    /// unchanged, matching the prior behavior.
    struct Values: Equatable {
        var weight: Double?
        var bodyFat: Double?
        var ffmi: Double?
    }

    private let service: MetricsInterpolationService
    private var fingerprint: Int?
    private var weightContext: MetricsInterpolationService.WeightInterpolationContext?
    private var bodyFatContext: MetricsInterpolationService.BodyFatInterpolationContext?
    private var ffmiContext: MetricsInterpolationService.FFMIInterpolationContext?

    init(service: MetricsInterpolationService = .shared) {
        self.service = service
    }

    /// Interpolated values for `metric`, rebuilding the cached contexts only when
    /// the underlying metrics/height change.
    func values(for metric: BodyMetrics, in metrics: [BodyMetrics], heightInches: Double?) -> Values {
        refreshContextsIfNeeded(metrics: metrics, heightInches: heightInches)

        var result = Values()

        // Weight & body fat prefer the metric's own recorded value (matching the
        // previous logic), otherwise fall back to interpolation.
        if let weight = metric.weight {
            result.weight = weight
        } else {
            result.weight = weightContext?.estimate(for: metric.date)?.value
        }

        if let bodyFat = metric.bodyFatPercentage {
            result.bodyFat = bodyFat
        } else {
            result.bodyFat = bodyFatContext?.estimate(for: metric.date)?.value
        }

        // FFMI is always interpolated (uses EMA trend weight), never the raw metric.
        result.ffmi = ffmiContext?.estimate(for: metric.date)?.value

        return result
    }

    private func refreshContextsIfNeeded(metrics: [BodyMetrics], heightInches: Double?) {
        let newFingerprint = Self.fingerprint(metrics: metrics, heightInches: heightInches)
        guard newFingerprint != fingerprint else { return }

        fingerprint = newFingerprint
        weightContext = service.makeWeightInterpolationContext(for: metrics)
        bodyFatContext = service.makeBodyFatInterpolationContext(for: metrics)
        if let heightInches, heightInches > 0 {
            ffmiContext = service.makeFFMIInterpolationContext(for: metrics, heightInches: heightInches)
        } else {
            ffmiContext = nil
        }
    }

    /// Content fingerprint over exactly the inputs that determine the contexts:
    /// each metric's date, weight and body-fat, plus the height used for FFMI.
    static func fingerprint(metrics: [BodyMetrics], heightInches: Double?) -> Int {
        var hasher = Hasher()
        hasher.combine(metrics.count)
        for metric in metrics {
            hasher.combine(metric.date)
            hasher.combine(metric.weight)
            hasher.combine(metric.bodyFatPercentage)
        }
        hasher.combine(heightInches)
        return hasher.finalize()
    }
}
