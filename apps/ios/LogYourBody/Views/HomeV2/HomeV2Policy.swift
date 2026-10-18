//
// HomeV2Policy.swift
// LogYourBody
//
import CoreGraphics
import Foundation

/// Photo-first Home (Pencil H2, picked 2026-09-26). Graduated: ordinary users
/// open it by default. Evaluated through `FeatureReleaseEvaluator` (shared
/// lifecycle contract, JOV-8056). Statsig is an emergency kill switch only;
/// an unavailable or unset gate must not fall back to the legacy Home.
/// Debug fixtures explicitly choose Home V2 or rollback.
enum HomeV2Policy {
    static let gateKey = "home_v2_photo_first"
    /// Inverse-meaning emergency stop. Only a fresh `true` stops the surface.
    static let killSwitchKey = "home_v2_kill_switch"
    /// Public baseline. The positive enable gate is recorded on the descriptor
    /// and is not consulted: a missing or false gate must not hide Home.
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: gateKey,
        killSwitchKey: killSwitchKey,
        stage: .graduated,
        minimumBuild: nil
    )
    #if DEBUG
    /// Explicit legacy captures exercise rollback without changing remote gates.
    /// Rollback wins if a test accidentally supplies both fixture modes.
    static let rollbackFixtureArgument = "-lybUITestHomeRollbackFixture"
    #endif
    static let fixtureArgument = "-lybUITestHomeV2Fixture"
    static let photoFixtureArgument = "-lybUITestHomeV2PhotoFixture"
    /// Signed in, nothing logged yet: the H0 day-zero state.
    static let emptyFixtureArgument = "-lybUITestHomeV2EmptyFixture"
    /// Picks the v2 sign-in screen (Pencil O1). The first run after sign-in is
    /// the same fat-vs-muscle flow whatever this gate says.
    static let onboardingGateKey = "onboarding_v2_focus"
    static let onboardingFixtureArgument = "-lybUITestOnboardingV2Fixture"

    /// `isGateEnabled` defaults to the Statsig-backed analytics port; tests inject
    /// their own so the policy stays deterministic.
    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        actor: FeatureReleaseActor = .ordinaryCustomer,
        installedBuild: Int = installedBuildVersion,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(rollbackFixtureArgument) { return false }
        if arguments.contains(fixtureArgument) || arguments.contains(photoFixtureArgument) ||
            arguments.contains(emptyFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.offlineFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.healthOffFixtureArgument) ||
            arguments.contains(HomeV2SystemStatePolicy.loadingFixtureArgument) {
            return true
        }
        #endif
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        // Graduated Home does not consult the positive enable gate. Doing so
        // would record an exposure for a flag that no longer decides the surface.
        let killSwitchEnabled = checkGate(killSwitchKey)
        return FeatureReleaseEvaluator.evaluate(
            releaseDescriptor,
            context: FeatureReleaseContext(
                actor: actor,
                installedBuild: installedBuild,
                configState: .fresh,
                enableGate: false,
                killSwitch: killSwitchEnabled
            )
        ).isEnabled
    }

    private static var installedBuildVersion: Int {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(version ?? "") ?? 0
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
    static let logCheckIn = "Log check-in"
    static let done = "Done"
    static let undo = "Undo"
    static let lastThirtyDays = "Last 30 days"
    static let todayDetails = "Today’s details"
    static let viewProgress = "View progress"
    static let firstCheckInTitle = "Your first check-in"
    static let firstCheckInBody = "Track weight and body fat to follow changes in your shape over time."
    static let nothingLoggedToday = "Nothing logged today"
    static let earlierEntriesBody = "Your earlier entries are still in Entries. Log today’s weight when you’re ready."
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

    /// Timeline caption above the number: "Sep 25 · Apple Health".
    static func dayCaption(date: String, source: String) -> String {
        "\(date) · \(source)"
    }

    /// Selected-day body fat with provenance: "Body fat 15.8% · DEXA".
    static func dayBodyFatLine(value: String, source: String) -> String {
        "Body fat \(value)% · \(source)"
    }

    /// The editorial plate on a day without a photo.
    static let noPhotoThisDay = "No photo this day"

    /// Shown once, then gone for good.
    static let timelineCoachHint = "Swipe through your history. Drag the timeline to jump in time."
    static let coachDismissedDefaultsKey = "home_v2_timeline_coach_dismissed"

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

        let method = methodKey(latest.attributedBodyFatMethod)
        let label = measurementLabel(for: method)
        let latestText = String(format: "%.1f", latestValue)
        let earlier = readings
            .filter { $0.localDate != latest.localDate && methodKey($0.attributedBodyFatMethod) == method }
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
        unit == "kg" ? 32...300 : 70...660
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

    static func converted(_ value: Double, from sourceUnit: String, to destinationUnit: String) -> Double {
        let source = sourceUnit.lowercased()
        let destination = destinationUnit.lowercased()
        guard source != destination else { return rounded(value) }
        if source == "kg", destination == "lbs" || destination == "lb" {
            return rounded(value.kgToLbs)
        }
        if source == "lbs" || source == "lb", destination == "kg" {
            return rounded(value.lbsToKg)
        }
        return rounded(value)
    }

    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func text(_ value: Double) -> String {
        String(format: "%.1f", rounded(value))
    }
}

/// Manual entry and trend presentation share one adult logging range. Imported
/// samples outside it remain stored and visible with provenance for correction.
enum HomeV2WeightQuality {
    static let supportedKilograms: ClosedRange<Double> = 32...300
    static let reviewMessage = "Outside the supported logging range. Source value kept unchanged."

    static func isWithinSupportedLoggingRange(_ kilograms: Double?) -> Bool {
        guard let kilograms, kilograms.isFinite else { return false }
        return supportedKilograms.contains(kilograms)
    }

    /// Exclude flagged source measurements before interpolation and smoothing:
    /// an average containing an unsupported reading can itself look supported.
    static func trendContext(
        for metrics: [BodyMetrics]
    ) -> MetricsInterpolationService.WeightInterpolationContext? {
        MetricsInterpolationService.shared.makeWeightInterpolationContext(
            for: metrics.filter { isWithinSupportedLoggingRange($0.weight) }
        )
    }

    static func trendWeight(for metric: BodyMetrics, in metrics: [BodyMetrics]) -> Double? {
        // Keep the original flagged measurement visible for correction; do not
        // replace it with a trend from otherwise supported surrounding records.
        guard metric.weight == nil || isWithinSupportedLoggingRange(metric.weight) else { return nil }
        return trendContext(for: metrics)?.trendWeight(for: metric.date)?.value
    }
}

/// Today never falls back to the latest historical row. Earlier imports stay in
/// Entries and the selected-day Context surface.
enum HomeV2TodayPolicy {
    static func metrics(
        in metrics: [BodyMetrics],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BodyMetrics] {
        let today = BodyMetricLocalDate.key(for: now, calendar: calendar)
        return metrics.filter { $0.localDate == today }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }
}

/// Sparse recorded-weight charts label every unique sample for 0/1/2 points,
/// then only their bounds. Repeated samples on one day use times, not duplicate
/// day labels.
enum HomeV2RecordedWeightChartPolicy {
    enum LabelGranularity: Equatable {
        case day
        case time
    }

    static func axisDates(for readings: [HomeV2EditorialPolicy.WeightReading]) -> [Date] {
        let unique = readings.map(\.date).sorted().reduce(into: [Date]()) { dates, date in
            if dates.last != date { dates.append(date) }
        }
        guard unique.count > 2 else { return unique }
        return [unique[0], unique[unique.count - 1]]
    }

    static func labelGranularity(
        for readings: [HomeV2EditorialPolicy.WeightReading],
        calendar: Calendar = .current
    ) -> LabelGranularity {
        let dates = axisDates(for: readings)
        guard dates.count > 1,
              dates.allSatisfy({ calendar.isDate($0, inSameDayAs: dates[0]) }) else { return .day }
        return .time
    }
}

/// What Home needs to show C2 and to undo it.
struct HomeV2LoggedEntry: Equatable {
    let metricId: String
    let userId: String
    let date: Date
    let previousMetric: BodyMetrics?
    let valueText: String
    let unit: String
    var savedMetric: BodyMetrics?

    var confirmationText: String {
        valueText.isEmpty ? "Entry saved." : HomeV2Copy.loggedSentence(value: valueText, unit: unit)
    }
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
    /// Recorded values only. Current profile height is canonical centimeters;
    /// another account's profile or an interpolated BF value cannot supply FFMI.
    static func ffmi(in metric: BodyMetrics, owner: String?, heightCm: Double?) -> Double? {
        guard metric.userId == owner, let weight = weight(in: metric),
              let bodyFat = bodyFat(in: metric), let heightCm,
              heightCm.isFinite, heightCm > 0,
              let value = UnitConversion.calculateFFMI(
                weightKg: weight, bodyFatPercentage: bodyFat.percentage, heightCm: heightCm
              ), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func weight(in metric: BodyMetrics) -> Double? {
        guard let value = metric.weight, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func displayWeight(in metric: BodyMetrics, system: MeasurementSystem) -> Double? {
        guard let weight = weight(in: metric) else { return nil }
        let value = system == .imperial ? weight.kgToLbs : weight
        return value.isFinite ? value : nil
    }

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
        let method = metric.attributedBodyFatMethod?.lowercased()
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
                  let weight = metric.weight,
                  HomeV2WeightQuality.isWithinSupportedLoggingRange(weight) else { return nil }
            return WeightReading(id: metric.id, date: metric.date, kilograms: weight)
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

/// Display-only body fat for one selected moment. A stored reading wins.
/// Inside two stored readings the value is time-weighted and labeled inferred.
/// Nothing here is saved, and the slope stops at the outer readings.
enum HomeV2SelectedMomentPolicy {
    enum Kind: Equatable { case measured, inferred, lastKnown, unavailable }

    struct Anchor {
        let metric: BodyMetrics
        let reading: HomeV2EditorialPolicy.BodyFatReading
    }

    struct Presentation {
        let kind: Kind
        let sentence: String
        let percentage: Double?
        let older: BodyMetrics?
        let newer: BodyMetrics?
        let olderReading: HomeV2EditorialPolicy.BodyFatReading?
        let newerReading: HomeV2EditorialPolicy.BodyFatReading?
    }

    static func sentence(for metric: BodyMetrics, in history: [BodyMetrics]) -> String {
        presentation(for: metric, in: history).sentence
    }

    static func presentation(for metric: BodyMetrics, in history: [BodyMetrics]) -> Presentation {
        if let reading = HomeV2EditorialPolicy.bodyFat(in: metric) {
            return Presentation(
                kind: .measured,
                sentence: HomeV2TimelinePolicy.bodyFatSentence(for: metric),
                percentage: reading.percentage,
                older: nil, newer: nil, olderReading: nil, newerReading: nil
            )
        }
        let bracket = anchors(around: metric, in: history)
        if let older = bracket.older, let newer = bracket.newer,
           let inferred = inferredPresentation(selected: metric, older: older, newer: newer) {
            return inferred
        }
        if let older = bracket.older, bracket.newer == nil {
            return lastKnownPresentation(older)
        }
        return unavailablePresentation()
    }

    static func inferredPresentation(selected: BodyMetrics, older: Anchor, newer: Anchor) -> Presentation? {
        guard let value = interpolatedBodyFat(
            olderDate: older.metric.date, olderValue: older.reading.percentage,
            newerDate: newer.metric.date, newerValue: newer.reading.percentage, at: selected.date
        ) else { return nil }
        return Presentation(
            kind: .inferred,
            sentence: "Inferred body fat \(oneDecimal(value))%.",
            percentage: value,
            older: older.metric, newer: newer.metric,
            olderReading: older.reading, newerReading: newer.reading
        )
    }

    static func interpolatedBodyFat(
        olderDate: Date, olderValue: Double, newerDate: Date, newerValue: Double, at date: Date
    ) -> Double? {
        let span = newerDate.timeIntervalSince(olderDate)
        guard span > 0 else { return nil }
        let fraction = date.timeIntervalSince(olderDate) / span
        guard fraction > 0, fraction < 1 else { return nil }
        let value = olderValue + (newerValue - olderValue) * fraction
        guard value.isFinite, value > 0, value < 100 else { return nil }
        return value
    }

    static func displayFFMI(
        for metric: BodyMetrics, in history: [BodyMetrics], owner: String?, heightCm: Double?
    ) -> Double? {
        if let measured = HomeV2EditorialPolicy.ffmi(in: metric, owner: owner, heightCm: heightCm) {
            return measured
        }
        let moment = presentation(for: metric, in: history)
        guard metric.userId == owner, moment.kind == .inferred, let percentage = moment.percentage,
              let weight = HomeV2EditorialPolicy.weight(in: metric),
              let heightCm, heightCm.isFinite, heightCm > 0 else { return nil }
        return UnitConversion.calculateFFMI(
            weightKg: weight, bodyFatPercentage: percentage, heightCm: heightCm
        )
    }

    static func displayPhoto(for metric: BodyMetrics, in history: [BodyMetrics]) -> BodyMetrics? {
        if PhotoTimelineHUDPolicy.hasUsablePhoto(metric) { return metric }
        let photos = history.filter { candidate in
            candidate.userId == metric.userId && PhotoTimelineHUDPolicy.hasUsablePhoto(candidate)
        }
        return photos.min { lhs, rhs in
            let left = abs(lhs.date.timeIntervalSince(metric.date))
            let right = abs(rhs.date.timeIntervalSince(metric.date))
            if left != right { return left < right }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
    }

    static func provenanceSentence(for presentation: Presentation, heightCm: Double?) -> String {
        guard presentation.kind == .inferred, let older = presentation.older, let newer = presentation.newer,
              let olderReading = presentation.olderReading,
              let newerReading = presentation.newerReading else {
            return presentation.sentence
        }
        let olderText = "\(mediumDate(older.date)) \(anchorPercent(olderReading.percentage)) \(olderReading.caption)"
        let newerText = "\(mediumDate(newer.date)) \(anchorPercent(newerReading.percentage)) \(newerReading.caption)"
        return "Inferred from \(olderText) and \(newerText). Height \(heightText(heightCm)) cm."
    }

    private static func anchors(
        around metric: BodyMetrics, in history: [BodyMetrics]
    ) -> (older: Anchor?, newer: Anchor?) {
        let readings = history.compactMap { candidate -> Anchor? in
            guard candidate.userId == metric.userId, candidate.id != metric.id,
                  candidate.date != metric.date,
                  let reading = HomeV2EditorialPolicy.bodyFat(in: candidate) else { return nil }
            return Anchor(metric: candidate, reading: reading)
        }
        let older = ordered(readings.filter { $0.metric.date < metric.date }, newestFirst: true).first
        let newer = ordered(readings.filter { $0.metric.date > metric.date }, newestFirst: false).first
        return (older, newer)
    }

    private static func ordered(_ readings: [Anchor], newestFirst: Bool) -> [Anchor] {
        readings.sorted { lhs, rhs in
            if lhs.metric.date != rhs.metric.date {
                return newestFirst ? lhs.metric.date > rhs.metric.date : lhs.metric.date < rhs.metric.date
            }
            return lhs.metric.id < rhs.metric.id
        }
    }

    private static func lastKnownPresentation(_ older: Anchor) -> Presentation {
        let shown = oneDecimal(older.reading.percentage)
        return Presentation(
            kind: .lastKnown,
            sentence: "Last known body fat \(shown)% on \(mediumDate(older.metric.date)).",
            percentage: older.reading.percentage,
            older: older.metric, newer: nil, olderReading: older.reading, newerReading: nil
        )
    }

    private static func unavailablePresentation() -> Presentation {
        Presentation(
            kind: .unavailable, sentence: "Body fat not logged for this day.",
            percentage: nil, older: nil, newer: nil, olderReading: nil, newerReading: nil
        )
    }

    private static func oneDecimal(_ value: Double) -> String {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 1, raiseOnExactness: false,
            raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let parsed = NSDecimalNumber(
            string: String(format: "%.4f", value), locale: Locale(identifier: "en_US_POSIX")
        )
        let tenths = parsed.rounding(accordingToBehavior: handler)
            .multiplying(by: NSDecimalNumber(string: "10", locale: Locale(identifier: "en_US_POSIX")))
            .intValue
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    private static func anchorPercent(_ value: Double) -> String {
        String(format: "%.2f %%", value)
    }

    private static func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func heightText(_ heightCm: Double?) -> String {
        guard let heightCm, heightCm.isFinite, heightCm > 0 else { return "not recorded" }
        if heightCm == heightCm.rounded() { return String(format: "%.0f", heightCm) }
        return String(format: "%.1f", heightCm)
    }
}
