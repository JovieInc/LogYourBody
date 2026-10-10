//
// HomeV2Policy.swift
// LogYourBody
//
import CoreGraphics
import Foundation

/// Gate for the photo-first Home (Pencil H2, picked 2026-09-26). Off by default
/// in production; the Statsig gate owns rollout. Debug fixtures force it on so
/// XCUITest can cover both states without a network.
enum HomeV2Policy {
    static let gateKey = "home_v2_photo_first"
    static let fixtureArgument = "-lybUITestHomeV2Fixture"
    static let photoFixtureArgument = "-lybUITestHomeV2PhotoFixture"
    /// Signed in, nothing logged yet: the H0 day-zero state.
    static let emptyFixtureArgument = "-lybUITestHomeV2EmptyFixture"
    /// The first run (Pencil O1–O4) has its own gate so sign-in and the
    /// paywall can roll out apart from Home.
    static let onboardingGateKey = "onboarding_v2_focus"
    static let onboardingFixtureArgument = "-lybUITestOnboardingV2Fixture"

    /// `isGateEnabled` defaults to the Statsig-backed analytics port; tests inject
    /// their own so the policy stays deterministic.
    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument) || arguments.contains(photoFixtureArgument) ||
            arguments.contains(emptyFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.offlineFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.healthOffFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.loadingFixtureArgument) {
            return true
        }
        #endif
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }

    @MainActor
    static func isOnboardingV2Enabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(onboardingFixtureArgument) { return true }
        #endif
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(onboardingGateKey)
    }
}

/// Copy for the v2 Home. Changes read as sentences instead of arrows and units.
enum HomeV2Copy {
    static let title = "Today"
    static let logWeight = "Log weight"
    static let done = "Done"
    static let undo = "Undo"
    static let lastThirtyDays = "Last 30 days"
    static let todayDetails = "Today’s details"
    static let viewProgress = "View progress"
    static let firstCheckInTitle = "Your first check-in"
    static let firstCheckInBody = "Track weight and body fat to follow changes in your shape over time."
    static let connectHealthInstead = "Connect Apple Health instead"
    static let logSheetTitle = "Log weight"
    static let addDetails = "Add details or photos"
    static let saveWeight = "Save weight"
    static let bodyFat = "Body fat"
    static let bodyFatPlaceholder = "Add"
    static let ghostHint = "Camera opens with a ghost of your last Front photo to match pose."
    static let poses = ["Front", "Side", "Back"]
    static let saveFailed = "Your weight could not be saved. Try again."
    static let bodyFatRangeError = "Body fat should be between 2 and 70%."
    static let addPhotoRow = "Add a progress photo"
    static let addPhotoDetail = "Optional"
    static let estimatedSubline = "Estimated"
    static let firstPhoto = "First photo"

    /// The unit as the design writes it: "lb", never "lbs".
    static func displayUnit(_ system: MeasurementSystem) -> String {
        system == .metric ? "kg" : "lb"
    }

    static func changeSentence(delta: Double?, unit: String, days: Int = 30) -> String {
        guard let delta else { return "No \(days)-day trend yet" }
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change in \(days) days" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(String(format: "%.1f", magnitude)) \(unit) in \(days) days"
    }

    /// "Down 12.8 lb since Apr 2" — change against the first photo.
    static func sinceSentence(delta: Double, unit: String, since: String) -> String {
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change since \(since)" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(String(format: "%.1f", magnitude)) \(unit) since \(since)"
    }

    static func photoPosition(_ position: Int, of total: Int) -> String {
        "Photo \(position) of \(total)"
    }

    /// Row detail: "−0.9 pts", "+0.2", "No change", "No 30-day trend".
    static func compactChange(delta: Double?, unit: String, days: Int = 30) -> String {
        guard let delta else { return "No \(days)-day trend" }
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change" }
        let sign = delta < 0 ? "−" : "+"
        let value = String(format: "%.1f", magnitude)
        return unit.isEmpty ? "\(sign)\(value)" : "\(sign)\(value) \(unit)"
    }

    static let compositionTrackingPrompt = "Track body fat beside weight to follow changes in your shape."

    /// C2: "Logged 173.4 lb for today".
    static func loggedSentence(value: String, unit: String) -> String {
        "Logged \(value) \(unit) for today"
    }

    /// H2 caption above the number: "Latest photo · Sep 25".
    static func latestPhotoCaption(date: String) -> String {
        "Latest photo · \(date)"
    }

    /// H1 status line: "Cutting for 9 weeks." Nothing is claimed about pace
    /// without a target, and nothing at all before there is a trend.
    static func phaseSentence(kind: PhaseInsightKind, weeks: Int) -> String? {
        let verb: String
        switch kind {
        case .cutting: verb = "Cutting"
        case .gaining: verb = "Gaining"
        case .maintaining: verb = "Maintaining"
        case .insufficientData: return nil
        }
        guard weeks >= 1 else { return "\(verb)." }
        return "\(verb) for \(weeks) week\(weeks == 1 ? "" : "s")."
    }

    static func weightRangeError(unit: String) -> String {
        let range = HomeV2WeightStepPolicy.range(unit: unit)
        return "Enter a weight between \(Int(range.lowerBound)) and \(Int(range.upperBound)) \(unit)."
    }

    static func todayDateText(_ date: Date, formatter: DateFormatter = timeFormatter) -> String {
        "Today, \(formatter.string(from: date))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Uses recorded body-fat readings only; interpolated estimates stay out of the home headline.
enum HomeV2CompositionPolicy {
    static func headline(
        metrics: [BodyMetrics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let readings = metrics.filter { metric in
            guard let value = metric.bodyFatPercentage else { return false }
            return value.isFinite && metric.date >= start && metric.date <= now
        }

        guard let latest = readings.max(by: { $0.date < $1.date }),
              let latestValue = latest.bodyFatPercentage else {
            return HomeV2Copy.compositionTrackingPrompt
        }

        let method = methodKey(latest.bodyFatMethod)
        let label = measurementLabel(for: method)
        let latestText = String(format: "%.1f", latestValue)
        let earlier = readings
            .filter { $0.localDate != latest.localDate && methodKey($0.bodyFatMethod) == method }
            .max(by: { $0.date < $1.date })

        guard let earlier, let earlierValue = earlier.bodyFatPercentage else {
            return "\(label) \(latestText)% · trend starts with another check-in"
        }

        let days = max(1, calendar.dateComponents([.day], from: earlier.date, to: latest.date).day ?? 1)
        let delta = latestValue - earlierValue
        let change = abs(delta) < 0.05
            ? "no change"
            : "\(delta < 0 ? "Down" : "Up") \(String(format: "%.1f", abs(delta))) pts"
        return "\(label) \(latestText)% · \(change) in \(days) days"
    }

    private static func methodKey(_ method: String?) -> String {
        let normalized = method?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.contains("visual_estimate") { return "visual_estimate" }
        if normalized.contains("inbody") { return "inbody" }
        if normalized.contains("dexa") { return "dexa" }
        return normalized
    }

    private static func measurementLabel(for method: String) -> String {
        switch method {
        case "visual_estimate": "Estimated body fat"
        case "dexa": "DEXA body fat"
        case "inbody": "InBody body fat"
        default: "Body fat"
        }
    }
}

/// How long the current phase has run, in whole weeks, for the Home status line.
enum HomeV2PhasePolicy {
    static let maximumWeeks = 52
    /// Mirrors PhaseInsightPolicy's 0.25%/week threshold for "no real change".
    static let maintenanceTolerancePerWeek = 0.0025

    /// Consecutive 7-day buckets, ending at the latest weight, whose average
    /// kept moving the phase's way. The current week always counts.
    /// ponytail: one noisy week ends the count; smooth over two weeks if it undercounts in practice.
    static func weeks(kind: PhaseInsightKind, metrics: [BodyMetrics], calendar: Calendar = .current) -> Int {
        guard kind != .insufficientData else { return 0 }
        let weighted = metrics
            .compactMap { metric in metric.weight.map { (date: metric.date, weight: $0) } }
            .sorted { $0.date < $1.date }
        guard let latest = weighted.last else { return 0 }

        var averages: [Double] = []
        var end = latest.date
        for _ in 0..<maximumWeeks {
            guard let start = calendar.date(byAdding: .day, value: -7, to: end) else { break }
            let bucket = weighted.filter { $0.date > start && $0.date <= end }.map(\.weight)
            guard !bucket.isEmpty else { break }
            averages.append(bucket.reduce(0, +) / Double(bucket.count))
            end = start
        }
        guard averages.count > 1 else { return averages.count }

        var weeks = 1
        for index in 0..<(averages.count - 1) {
            let recent = averages[index]
            let older = averages[index + 1]
            let delta = recent - older
            let holds: Bool
            switch kind {
            case .cutting: holds = delta < 0
            case .gaining: holds = delta > 0
            case .maintaining: holds = abs(delta) <= maintenanceTolerancePerWeek * older
            case .insufficientData: holds = false
            }
            guard holds else { break }
            weeks += 1
        }
        return min(weeks, maximumWeeks)
    }
}

/// The −/+ stepper and typed input in the log sheet: 0.1 steps, clamped to a
/// range no real weight falls outside of.
enum HomeV2WeightStepPolicy {
    static let step = 0.1
    static let bodyFatRange: ClosedRange<Double> = 2...70

    static func range(unit: String) -> ClosedRange<Double> {
        unit == "kg" ? 20...500 : 44...1_100
    }

    static func defaultValue(unit: String) -> Double {
        unit == "kg" ? 70 : 150
    }

    static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    static func clamped(_ value: Double, unit: String) -> Double {
        let bounds = range(unit: unit)
        return rounded(min(max(value, bounds.lowerBound), bounds.upperBound))
    }

    static func stepped(_ value: Double, by direction: Int, unit: String) -> Double {
        clamped(value + Double(direction) * step, unit: unit)
    }

    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func text(_ value: Double) -> String {
        String(format: "%.1f", rounded(value))
    }
}

/// What Home needs to show C2 and to undo it.
struct HomeV2LoggedEntry: Equatable {
    let metricId: String
    let date: Date
    let existedBefore: Bool
    let previousWeightKilograms: Double?
    let previousBodyFat: Double?
    let valueText: String
    let unit: String
}

/// Geometry that must hold on every iPhone: the photo stays full width at 4:5
/// when it fits, and gives up height (never width) on short screens so the
/// number and the check-in action stay on screen.
enum HomeV2Layout {
    /// Caption, number, change sentence, the All photos row and the dock below the photo.
    static let belowPhotoHeight: CGFloat = 224
    static let minimumStageHeight: CGFloat = 200

    static func stageHeight(width: CGFloat, height: CGFloat) -> CGFloat {
        let fourByFive = width / HomeV2Tokens.photoAspectRatio
        let available = max(minimumStageHeight, height - belowPhotoHeight)
        return min(fourByFive, available)
    }
}

/// Values for the editorial fallback come from stored readings, never photo
/// appearance, a target, or interpolated chart caches.
enum HomeV2EditorialPolicy {
    struct BodyFatReading: Equatable {
        let percentage: Double
        let caption: String
    }

    struct WeightReading: Identifiable, Equatable {
        let id: String
        let date: Date
        let kilograms: Double
    }

    static func bodyFat(in metric: BodyMetrics?) -> BodyFatReading? {
        guard let metric, let value = metric.bodyFatPercentage,
              value.isFinite, value > 0, value < 100 else { return nil }
        let method = metric.bodyFatMethod?.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ") ?? ""
        // Synthetic estimates must not be presented as recorded body fat.
        guard !method.contains("interpolat"), !method.contains("derived") else { return nil }
        let caption: String
        // Only known stored methods establish provenance. Free-form or negated
        // labels must not become scan claims merely because they mention one.
        switch method {
        case "visual_estimate": caption = "Visual estimate"
        case "inbody": caption = "From your InBody scan"
        case "dexa", "dexa (bodyspec)", "bodyspec_dexa": caption = "From your DEXA scan"
        case "manual", "typed": caption = "Entered by you"
        case "healthkit", "apple_health": caption = "From Apple Health"
        case "body_scan": caption = "Body scan estimate"
        case "bia_scale", "bioelectrical": caption = "Bioelectrical estimate"
        case "caliper", "calipers": caption = "Caliper estimate"
        default: caption = "Source not recorded"
        }
        return BodyFatReading(percentage: value, caption: caption)
    }

    static func supportsWeightComparison(in metrics: [BodyMetrics], selected: BodyMetrics?) -> Bool {
        weights(in: metrics, selected: selected).count >= 2
    }

    static func weights(
        in metrics: [BodyMetrics],
        selected: BodyMetrics?,
        calendar: Calendar = .current
    ) -> [WeightReading] {
        guard let selected,
              let start = calendar.date(byAdding: .day, value: -30, to: selected.date) else { return [] }
        return metrics.compactMap { metric in
            guard metric.userId == selected.userId,
                  metric.date >= start, metric.date <= selected.date,
                  let weight = metric.weight, weight.isFinite, weight > 0 else { return nil }
            return WeightReading(id: metric.id, date: metric.date, kilograms: weight)
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
