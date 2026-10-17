import SwiftUI

/// Stable entry identity is shared by the pager, ruler and dashboard's index adapter.
enum HomeV2TimelinePolicy {
    /// Observed supported bounds are captured with the history publication. Moving
    /// the selected moment cannot rescale this axis or alter any recorded value.
    struct WeightScale {
        let kilograms: ClosedRange<Double>?

        init(kilograms: [Double]) {
            let supported = kilograms.filter { HomeV2WeightQuality.isWithinSupportedLoggingRange($0) }
            if let lower = supported.min(), let upper = supported.max() {
                self.kilograms = lower...upper
            } else {
                self.kilograms = nil
            }
        }

        func domain(unit: String) -> ClosedRange<Double>? {
            guard let kilograms else { return nil }
            let values = [kilograms.lowerBound, kilograms.upperBound].map {
                UnitConversion.displayWeight($0, useMetric: unit != "lb")
            }
            return HomeV2ChartIntegrity.yDomain(values: values, anchorsToZero: false)
        }
    }

    /// Display-only adapter from the existing canonical metric/provenance paths.
    /// A nil value belongs to this kind and moment; it never chooses a substitute.
    struct HeroReading: Equatable {
        let kind: HomeV2ProgressMetric
        let value: String?
        let unit: String
        let detail: String
        var bodyFatFraction: Double?
        var evidence: Value?

        var source: String { evidence?.source ?? "" }
        var explanation: String { evidence?.explanation(kind.title) ?? detail }
        var accessibilitySummary: String {
            let amount = [value ?? "Unavailable", unit].filter { !$0.isEmpty }.joined(separator: " ")
            return "\(kind.title), \(amount). \(detail)"
        }

        init(
            kind: HomeV2ProgressMetric,
            value: String?,
            unit: String,
            detail: String,
            bodyFatFraction: Double? = nil,
            evidence: Value? = nil
        ) {
            self.kind = kind
            self.value = value
            self.unit = unit
            self.detail = detail
            self.evidence = evidence
            self.bodyFatFraction = bodyFatFraction.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        }

        static func unavailable(_ kind: HomeV2ProgressMetric) -> HeroReading {
            HeroReading(kind: kind, value: nil,
                        unit: kind == .steps ? "steps" : (kind == .bodyFat ? "%" : ""),
                        detail: kind == .ffmi ? "Needs weight, body fat and height" : "\(kind.title) unavailable at this time.")
        }

        /// A mismatched adapter response cannot silently change the chosen kind.
        func forRequestedMetric(_ requested: HomeV2ProgressMetric) -> HeroReading {
            kind == requested ? self : Self.unavailable(requested)
        }
    }

    struct EntryID: Hashable {
        let owner: String
        let record: String
        init(_ metric: BodyMetrics) { owner = metric.userId; record = metric.id }
    }

    struct Selection: Equatable {
        let id: EntryID
        let date: Date
        init(_ metric: BodyMetrics) { id = EntryID(metric); date = metric.date }
    }

    struct Anchor: Equatable {
        let selection: Selection
        let amount: Double
        let unit: String
        let source: String
        var id: EntryID { selection.id }
        var date: Date { selection.date }

        var explanation: String {
            "\(date.formatted(date: .abbreviated, time: .shortened)): \(String(format: "%.2f", amount)) \(unit), \(source)"
        }
    }

    /// Display-only truth. An inferred value never becomes a BodyMetrics record.
    struct Value: Equatable {
        enum Kind: String { case recorded, inferred, derived }
        let amount: Double
        let kind: Kind
        let anchors: [Anchor]
        let source: String
        var usesInference = false

        func explanation(_ label: String) -> String {
            let dates = anchors.map { $0.date.formatted(date: .abbreviated, time: .shortened) }
            if kind == .inferred {
                return "\(label) inferred between \(anchors.map(\.explanation).joined(separator: " and "))."
            }
            if kind == .derived {
                return "\(label) derived from \(source)."
            }
            return "\(label): \(source). \(dates.joined(separator: ", "))."
        }
    }

    struct Presentation {
        let selection: Selection
        let photo: BodyMetrics?
        let weight: Value?
        let bodyFat: Value?
        let ffmi: Value?

        /// The chosen kind is never inferred from which values happen to exist.
        /// Evidence is the original display-only Value, including all anchor dates.
        func reading(
            for kind: HomeV2ProgressMetric, system: MeasurementSystem,
            steps: (value: String, detail: String)? = nil
        ) -> HeroReading {
            if kind == .steps {
                guard let steps else { return .unavailable(kind) }
                return HeroReading(kind: kind, value: steps.value == "—" || steps.value == "–" ? nil : steps.value,
                                   unit: "steps", detail: steps.detail)
            }
            let evidence: Value?
            switch kind {
            case .weight: evidence = weight
            case .bodyFat: evidence = bodyFat
            case .ffmi: evidence = ffmi
            case .steps: evidence = nil
            }
            guard let evidence, evidence.amount.isFinite else {
                if kind == .weight {
                    return HeroReading(kind: kind, value: nil, unit: HomeV2Copy.displayUnit(system),
                                       detail: "Weight unavailable at this time.")
                }
                return .unavailable(kind)
            }
            let amount = kind == .weight
                ? UnitConversion.displayWeight(evidence.amount, useMetric: system == .metric) : evidence.amount
            guard amount.isFinite else { return .unavailable(kind) }
            let needsReview = kind == .weight && evidence.kind == .recorded &&
                !HomeV2WeightQuality.isWithinSupportedLoggingRange(evidence.amount)
            let detail: String
            if needsReview {
                detail = HomeV2WeightQuality.reviewMessage
            } else if evidence.kind == .derived {
                detail = evidence.usesInference ? "Derived using inferred inputs" : "Derived"
            } else if evidence.kind == .inferred {
                detail = "Inferred between recorded values"
            } else if kind == .bodyFat && evidence.source == "Visual estimate" {
                detail = "Visual estimate"
            } else {
                detail = "Recorded"
            }
            return HeroReading(
                kind: kind, value: String(format: needsReview ? "%.2f" : "%.1f", amount),
                unit: kind == .weight ? HomeV2Copy.displayUnit(system) : (kind == .bodyFat ? "%" : ""),
                detail: detail, bodyFatFraction: kind == .bodyFat ? evidence.amount / 100 : nil,
                evidence: evidence
            )
        }

        func weightText(in system: MeasurementSystem) -> String {
            guard let weight else { return "–" }
            let converted = UnitConversion.displayWeight(weight.amount, useMetric: system == .metric)
            guard converted.isFinite else { return "–" }
            return String(format: "%.1f", converted)
        }

        enum HeroContent: Equatable {
            case review(Value)
            case weight(Value)
            case bodyFat(Value)
            case unavailable
        }

        /// Only this admitted moment supplies a selected value; recorded history is not a fallback.
        var heroContent: HeroContent {
            if let weight {
                if weight.kind == .recorded &&
                    !HomeV2WeightQuality.isWithinSupportedLoggingRange(weight.amount) {
                    return .review(weight)
                }
                return .weight(weight)
            }
            if let bodyFat { return .bodyFat(bodyFat) }
            return .unavailable
        }

        var bodyFatSummary: String {
            guard let bodyFat else { return "Body fat unavailable at this time." }
            let title: String
            switch bodyFat.kind {
            case .recorded: title = "Body fat"
            case .inferred: title = "Inferred body fat"
            case .derived: title = "Derived body fat"
            }
            return "\(title) \(String(format: "%.1f", bodyFat.amount))% · \(bodyFat.source)."
        }

        var provenance: HomeV2ProvenanceDetail {
            let inferred = [weight, bodyFat, ffmi].compactMap { $0 }.contains { $0.usesInference }
            let detail = [
                weight?.explanation("Weight") ?? "Weight unavailable at this time.",
                bodyFat?.explanation("Body fat") ?? "Body fat unavailable at this time.",
                ffmi?.explanation("FFMI") ?? "FFMI unavailable without weight, body fat and height."
            ].joined(separator: " ")
            return HomeV2ProvenanceDetail(
                chip: weight == nil && bodyFat == nil ? "Values unavailable" :
                    (inferred ? (ffmi == nil ? "Inferred values" : "Inferred + derived") :
                        (ffmi == nil ? "Recorded values" : "Recorded + derived")),
                title: "Values at the selected time", body: detail
            )
        }
    }

    /// Rebuilt when published history changes, never on the scrub hot path.
    struct Snapshot {
        let metrics: [BodyMetrics]
        let chronologicalDates: [Date]
        let chronologicalIDs: [EntryID]
        let weightScale: WeightScale
        private let sourceOrder: [EntryID]
        private let weightChanges: [EntryID: Double]
        let ownership: AuthManager.ProfileSessionOwnership?
        private let weightAnchors: [Value]
        private let bodyFatAnchors: [Value]
        private let photos: [BodyMetrics]
        var hasAnyPhoto: Bool { !photos.isEmpty }

        init(
            metrics: [BodyMetrics] = [], owner: String? = nil, calendar: Calendar = .current,
            ownership: AuthManager.ProfileSessionOwnership? = nil
        ) {
            let admittedOwner: String?
            if let owner, !owner.isEmpty, let ownership, ownership.subject == owner {
                admittedOwner = owner
            } else {
                admittedOwner = nil
            }
            self.metrics = metrics.filter {
                guard let admittedOwner else { return false }
                return $0.userId == admittedOwner
            }.sorted {
                $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date
            }
            self.ownership = admittedOwner == nil ? nil : ownership
            weightAnchors = Self.anchors(in: self.metrics, unit: "kg") { metric in
                guard let value = metric.weight,
                      HomeV2WeightQuality.isWithinSupportedLoggingRange(value) else { return nil }
                return (value, HomeV2Provenance.label(for: metric))
            }
            bodyFatAnchors = Self.anchors(in: self.metrics, unit: "%") { metric in
                HomeV2EditorialPolicy.bodyFat(in: metric).map { ($0.percentage, $0.caption) }
            }
            var photoDates = Set<Date>()
            photos = self.metrics.filter {
                PhotoTimelineHUDPolicy.hasUsablePhoto($0) && photoDates.insert($0.date).inserted
            }.reversed()
            chronologicalDates = self.metrics.reversed().map(\.date)
            chronologicalIDs = self.metrics.reversed().map(EntryID.init)
            weightScale = WeightScale(kilograms: self.metrics.compactMap(\.weight))
            sourceOrder = metrics.map(EntryID.init)
            weightChanges = Self.weightChanges(in: self.metrics, calendar: calendar)
        }

        /// The @Published callback runs before the view model's stored array changes.
        /// Resolve its legacy index against this exact publication, never that older array.
        func sourceIndex(for id: EntryID) -> Int? { sourceOrder.firstIndex(of: id) }
        func selection(atSourceIndex index: Int) -> Selection? {
            guard sourceOrder.indices.contains(index) else { return nil }
            return metric(for: sourceOrder[index]).map(Selection.init)
        }

        /// Owner generation is a lifetime fence, not another selection authority.
        func isOwned(by current: AuthManager.ProfileSessionOwnership?) -> Bool {
            guard let ownership, let current else { return false }
            return ownership == current
        }

        func presentation(
            for selection: Selection, heightCm: Double?,
            currentOwnership: AuthManager.ProfileSessionOwnership? = nil
        ) -> Presentation? {
            guard let ownership, let currentOwnership, ownership == currentOwnership,
                  let metric = metric(for: selection.id), metric.date == selection.date else { return nil }
            let weight = metric.weight.flatMap { value -> Value? in
                guard value.isFinite else { return nil }
                let source = HomeV2Provenance.label(for: metric)
                return Value(amount: value, kind: .recorded,
                             anchors: [.init(selection: selection, amount: value, unit: "kg", source: source)],
                             source: source)
            } ?? Self.resolve(weightAnchors, at: selection.date)
            let bodyFat = HomeV2EditorialPolicy.bodyFat(in: metric).map {
                Value(amount: $0.percentage, kind: .recorded,
                      anchors: [.init(selection: selection, amount: $0.percentage, unit: "%", source: $0.caption)],
                      source: $0.caption)
            } ?? Self.resolve(bodyFatAnchors, at: selection.date)
            return Presentation(
                selection: selection,
                photo: PhotoTimelineHUDPolicy.hasUsablePhoto(metric) ? metric : nearestPhoto(to: selection.date),
                weight: weight, bodyFat: bodyFat,
                ffmi: Self.ffmi(weight: weight, bodyFat: bodyFat, heightCm: heightCm)
            )
        }

        private static func anchors(
            in metrics: [BodyMetrics], unit: String, reading: (BodyMetrics) -> (Double, String)?
        ) -> [Value] {
            var seen = Set<Date>()
            return metrics.compactMap { metric -> Value? in
                guard let (value, source) = reading(metric), seen.insert(metric.date).inserted else { return nil }
                return Value(amount: value, kind: .recorded,
                             anchors: [.init(selection: Selection(metric), amount: value, unit: unit, source: source)],
                             source: source)
            }.reversed()
        }

        /// Exact timestamps win. No same-day substitution, carry-forward or extrapolation.
        private static func resolve(_ anchors: [Value], at date: Date) -> Value? {
            var lower = 0, upper = anchors.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if anchors[middle].anchors[0].date < date { lower = middle + 1 } else { upper = middle }
            }
            if lower < anchors.count, anchors[lower].anchors[0].date == date { return anchors[lower] }
            guard lower > 0, lower < anchors.count else { return nil }
            let before = anchors[lower - 1], after = anchors[lower]
            let start = before.anchors[0].date, end = after.anchors[0].date
            // Local presentation arithmetic keeps decimal source anchors exact at a rounding tie.
            // It neither rounds/persists a measurement nor changes the global interpolation service.
            let locale = Locale(identifier: "en_US_POSIX")
            let first = NSDecimalNumber(string: String(before.amount), locale: locale)
            let last = NSDecimalNumber(string: String(after.amount), locale: locale)
            let elapsed = NSDecimalNumber(string: String(date.timeIntervalSince(start)), locale: locale)
            let duration = NSDecimalNumber(string: String(end.timeIntervalSince(start)), locale: locale)
            guard duration.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }
            let decimalAmount = first.adding(last.subtracting(first).multiplying(by: elapsed).dividing(by: duration))
            let amount = decimalAmount.doubleValue
            guard amount.isFinite else { return nil }
            return Value(amount: amount, kind: .inferred, anchors: before.anchors + after.anchors,
                         source: "Time-weighted interpolation", usesInference: true)
        }

        private static func ffmi(weight: Value?, bodyFat: Value?, heightCm: Double?) -> Value? {
            guard let weight, let bodyFat, let heightCm, heightCm.isFinite,
                  HomeV2WeightQuality.isWithinSupportedLoggingRange(weight.amount),
                  let value = UnitConversion.calculateFFMI(
                    weightKg: weight.amount, bodyFatPercentage: bodyFat.amount, heightCm: heightCm
                  ), value.isFinite else { return nil }
            let inputs = [
                "\(weight.kind.rawValue) weight \(String(format: "%.2f kg", weight.amount)) (\(weight.source))",
                "\(bodyFat.kind.rawValue) body fat \(String(format: "%.2f %%", bodyFat.amount)) (\(bodyFat.source))",
                "\(String(format: "%.2f cm", heightCm)) profile height"
            ].joined(separator: ", ")
            return Value(amount: value, kind: .derived, anchors: weight.anchors + bodyFat.anchors,
                         source: inputs, usesInference: weight.usesInference || bodyFat.usesInference)
        }

        private func nearestPhoto(to date: Date) -> BodyMetrics? {
            guard !photos.isEmpty else { return nil }
            var lower = 0, upper = photos.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if photos[middle].date < date { lower = middle + 1 } else { upper = middle }
            }
            if lower == 0 { return photos[0] }
            if lower == photos.count { return photos[lower - 1] }
            let older = photos[lower - 1], newer = photos[lower]
            return date.timeIntervalSince(older.date) < newer.date.timeIntervalSince(date) ? older : newer
        }

        func weightDeltaKilograms30d(for id: EntryID) -> Double? { weightChanges[id] }

        func weightChangeSentence(for id: EntryID, system: MeasurementSystem) -> String {
            let delta = weightChanges[id].map { system == .imperial ? $0 * 2.20462 : $0 }
            return HomeV2Copy.changeSentence(
                delta: delta.flatMap { $0.isFinite ? $0 : nil }, unit: HomeV2Copy.displayUnit(system)
            )
        }

        /// Two moving bounds cache each selected date's actual 30-day readings in
        /// one pass after the history sort. Future weights can never enter its window.
        private static func weightChanges(in metrics: [BodyMetrics], calendar: Calendar) -> [EntryID: Double] {
            let weights = metrics.reversed().compactMap { metric -> HomeV2EditorialPolicy.WeightReading? in
                guard let weight = metric.weight,
                      HomeV2WeightQuality.isWithinSupportedLoggingRange(weight) else { return nil }
                return .init(id: metric.id, date: metric.date, kilograms: weight)
            }
            var changes: [EntryID: Double] = [:]
            var lower = 0, upper = 0
            for metric in metrics.reversed() {
                guard let start = calendar.date(byAdding: .day, value: -30, to: metric.date) else { continue }
                while upper < weights.count, weights[upper].date <= metric.date { upper += 1 }
                while lower < upper, weights[lower].date < start { lower += 1 }
                guard upper - lower >= 2 else { continue }
                let delta = weights[upper - 1].kilograms - weights[lower].kilograms
                if delta.isFinite { changes[EntryID(metric)] = delta }
            }
            return changes
        }

        func reconcile(_ previous: Selection?) -> Selection? {
            guard let latest = metrics.first else { return nil }
            guard let previous, previous.id.owner == latest.userId else { return Selection(latest) }
            if let retained = metrics.first(where: { EntryID($0) == previous.id }) { return Selection(retained) }
            // On deletion, retain the closest surviving date; an equal-distance tie goes newer.
            return metrics.min {
                abs($0.date.timeIntervalSince(previous.date)) < abs($1.date.timeIntervalSince(previous.date))
            }.map(Selection.init)
        }

        /// A non-photo page uses the same owner, selection and raw-publication
        /// fence. A present photo must additionally retain its captured row/URL.
        func admitsPresentation(
            _ presentation: Presentation, selected currentSelection: Selection?,
            currentOwnership: AuthManager.ProfileSessionOwnership?,
            currentMetrics: [BodyMetrics], currentSnapshot: Snapshot
        ) -> Bool {
            guard let ownership, currentOwnership == ownership,
                  isOwned(by: ownership), currentSnapshot.isOwned(by: ownership),
                  currentSnapshot.metrics == metrics,
                  currentSelection == presentation.selection,
                  let selected = metric(for: presentation.selection.id),
                  selected.date == presentation.selection.date else { return false }
            if let photo = presentation.photo {
                guard let url = photo.photoUrl, !url.isEmpty,
                      PhotoTimelineHUDPolicy.hasUsablePhoto(photo),
                      metric(for: EntryID(photo)) == photo else { return false }
            }
            let liveOwned = currentMetrics.filter { $0.userId == ownership.subject }
            guard liveOwned.count == metrics.count else { return false }
            let rows = Dictionary(grouping: liveOwned, by: EntryID.init)
            return metrics.allSatisfy { captured in
                let matches = rows[EntryID(captured)] ?? []
                return matches.count == 1 && matches[0] == captured
            }
        }

        /// Preserve the frozen photo-only API: no-photo presentations cannot
        /// authorize any image cache access, rendering or publication.
        func admitsPhotoPresentation(
            _ presentation: Presentation, selected currentSelection: Selection?,
            currentOwnership: AuthManager.ProfileSessionOwnership?,
            currentMetrics: [BodyMetrics], currentSnapshot: Snapshot
        ) -> Bool {
            guard presentation.photo != nil else { return false }
            return admitsPresentation(
                presentation, selected: currentSelection, currentOwnership: currentOwnership,
                currentMetrics: currentMetrics, currentSnapshot: currentSnapshot
            )
        }

        func metric(for id: EntryID) -> BodyMetrics? { metrics.first { EntryID($0) == id } }
        func index(for id: EntryID) -> Int? { metrics.firstIndex { EntryID($0) == id } }
        func chronologicalPosition(for id: EntryID) -> Int {
            index(for: id).map { metrics.count - 1 - $0 } ?? 0
        }
        func id(atChronologicalPosition position: Int) -> EntryID? {
            guard chronologicalDates.indices.contains(position) else { return nil }
            return EntryID(metrics[metrics.count - 1 - position])
        }
        func adjusted(_ id: EntryID, newer: Bool) -> EntryID? {
            guard index(for: id) != nil else { return nil }
            let position = chronologicalPosition(for: id) + (newer ? 1 : -1)
            return self.id(atChronologicalPosition: position)
        }
    }

    struct PhotoViewerVisibility {
        let isPresented: Bool
        let isHomeForeground: Bool
        let isActive: Bool
        let hasCompetingPresentation: Bool
        let hasChildRoute: Bool
        let hasCurrentDashboardPublication: Bool
    }

    /// A callback belongs to one visible viewer opening, even when a later
    /// opening has the same account, rows, photo and selected moment.
    struct PhotoViewerAdmission {
        private let openingID: UUID
        private let snapshot: Snapshot
        private let presentation: Presentation

        init(openingID: UUID, snapshot: Snapshot, presentation: Presentation) {
            self.openingID = openingID
            self.snapshot = snapshot
            self.presentation = presentation
        }

        func admits(
            currentOpeningID: UUID?, visibility: PhotoViewerVisibility,
            currentSelection: Selection?,
            currentOwnership: AuthManager.ProfileSessionOwnership?,
            currentMetrics: [BodyMetrics], currentSnapshot: Snapshot
        ) -> Bool {
            guard let currentOpeningID, currentOpeningID == openingID,
                  visibility.isPresented, visibility.isHomeForeground, visibility.isActive,
                  !visibility.hasCompetingPresentation, !visibility.hasChildRoute,
                  visibility.hasCurrentDashboardPublication else { return false }
            return snapshot.admitsPhotoPresentation(
                presentation, selected: currentSelection,
                currentOwnership: currentOwnership,
                currentMetrics: currentMetrics, currentSnapshot: currentSnapshot
            )
        }
    }

    @MainActor
    @discardableResult
    static func performPhotoOperation(ifCurrent: () -> Bool, operation: () -> Void) -> Bool {
        guard !Task.isCancelled, ifCurrent() else { return false }
        operation()
        return true
    }

    static func chronologicalIndices(in bodyMetrics: [BodyMetrics]) -> [Int] {
        bodyMetrics.indices.sorted {
            let first = bodyMetrics[$0], second = bodyMetrics[$1]
            return first.date == second.date ? first.id < second.id : first.date < second.date
        }
    }
    static func chronologicalPosition(of index: Int, in bodyMetrics: [BodyMetrics]) -> Int {
        chronologicalIndices(in: bodyMetrics).firstIndex(of: index) ?? 0
    }
    static func index(at position: Int, in bodyMetrics: [BodyMetrics]) -> Int? {
        let order = chronologicalIndices(in: bodyMetrics)
        return order.indices.contains(position) ? order[position] : nil
    }

    static func bodyFatSentence(for metric: BodyMetrics) -> String {
        guard let reading = HomeV2EditorialPolicy.bodyFat(in: metric) else {
            return "Body fat not logged for this day."
        }
        return "Body fat \(String(format: "%.1f", reading.percentage))% · \(reading.caption)"
    }
}

/// Ordinary paging is independent of the optional long-press photo scrub mode.
/// The decision carries direction only; the existing ID binding owns the moment.
enum HomeV2TimelineSwipePolicy {
    static func hasHorizontalIntent(velocity: CGPoint) -> Bool {
        velocity.x.isFinite && velocity.y.isFinite && abs(velocity.x) > abs(velocity.y)
    }

    static func newer(
        translation: CGPoint, velocity: CGPoint, width: CGFloat, isRightToLeft: Bool = false
    ) -> Bool? {
        guard width.isFinite, width > 0,
              translation.x.isFinite, translation.y.isFinite,
              velocity.x.isFinite, velocity.y.isFinite,
              abs(translation.x) > abs(translation.y) else { return nil }
        let threshold = min(64, max(24, width * 0.12))
        let fast = hasHorizontalIntent(velocity: velocity) && abs(velocity.x) >= 350 && abs(translation.x) >= 12
        guard abs(translation.x) >= threshold || fast else { return nil }
        let direction = fast ? velocity.x : translation.x
        // Preserve newest-first pager semantics: right advances toward newer.
        return (isRightToLeft ? -direction : direction) > 0
    }
}

/// One admitted Presentation is shared by all content in the current page.
/// Short axis-locked swipes page adjacent IDs; long-press scrubbing stays optional.
struct HomeV2TimelinePager: View {
    let snapshot: HomeV2TimelinePolicy.Snapshot
    @Binding var selectedID: HomeV2TimelinePolicy.EntryID
    let size: CGSize
    let unit: String
    let dateText: (BodyMetrics) -> String
    let onOpenPhoto: () -> Void
    let selectedPresentation: HomeV2TimelinePolicy.Presentation
    let heightCm: Double?
    let isCurrent: (HomeV2TimelinePolicy.Presentation) -> Bool
    let selectedMetric: HomeV2ProgressMetric
    let system: MeasurementSystem
    let steps: (value: String, detail: String)?
    var isNavigating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        HomeV2PhotoScrubber(
            values: snapshot.chronologicalIDs,
            selection: $selectedID, width: size.width,
            canActivate: selectedPresentation.photo != nil,
            isNavigating: isNavigating, identifier: "home_v2_photo"
        ) { isScrubbing in
            if let metric = snapshot.metric(for: selectedPresentation.selection.id) {
                HomeV2TimelinePage(
                    metric: metric, metrics: snapshot.metrics, size: size, unit: unit,
                    dateText: dateText, onOpenPhoto: onOpenPhoto,
                    presentation: selectedPresentation, ownership: snapshot.ownership,
                    isCurrent: { candidate in isCurrent(candidate) && selectedID == candidate.selection.id },
                    selectedMetric: selectedMetric, system: system, steps: steps,
                    fixedWeightDomain: snapshot.weightScale.domain(unit: unit)
                )
                .contentShape(Rectangle())
                .gesture(HomeV2TimelineSwipeGesture(
                    isEnabled: !isScrubbing && !isNavigating && snapshot.metrics.count > 1,
                    width: size.width, isRightToLeft: layoutDirection == .rightToLeft,
                    onMove: { newer in adjust(newer: newer) }
                ))
            }
        }
        .frame(width: size.width, height: size.height)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body timeline")
        .accessibilityValue("Entry \(snapshot.chronologicalPosition(for: selectedID) + 1) of \(snapshot.metrics.count)")
        .accessibilityHint("Adjust up for newer entries or down for older entries")
        .accessibilityIdentifier("home_v2_timeline_pager")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(newer: true)
            case .decrement: adjust(newer: false)
            @unknown default: break
            }
        }
    }

    private func adjust(newer: Bool) {
        if let next = snapshot.adjusted(selectedID, newer: newer) { selectedID = next }
    }
}

/// Reject vertical intent before recognition so the enclosing scroll view can
/// win. A completed horizontal pan requests one adjacent ID, including no-photo
/// entries. The long-press wrapper disables this recognizer while scrubbing.
private struct HomeV2TimelineSwipeGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let width: CGFloat
    let isRightToLeft: Bool
    let onMove: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .ended,
              let newer = HomeV2TimelineSwipePolicy.newer(
                translation: recognizer.translation(in: recognizer.view),
                velocity: recognizer.velocity(in: recognizer.view), width: width,
                isRightToLeft: isRightToLeft
              ) else { return }
        onMove(newer)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            return HomeV2TimelineSwipePolicy.hasHorizontalIntent(velocity: pan.velocity(in: pan.view))
        }
    }
}

/// Image bytes are displayed only for their exact owner/URL. A replacement or
/// failed load keeps the selected record's real-data fallback, never the previous photo.
private struct HomeV2TimelinePage: View {
    let metric: BodyMetrics
    let metrics: [BodyMetrics]
    let size: CGSize
    let unit: String
    let dateText: (BodyMetrics) -> String
    let onOpenPhoto: () -> Void
    let presentation: HomeV2TimelinePolicy.Presentation?
    let ownership: AuthManager.ProfileSessionOwnership?
    let isCurrent: (HomeV2TimelinePolicy.Presentation) -> Bool
    let selectedMetric: HomeV2ProgressMetric
    let system: MeasurementSystem
    let steps: (value: String, detail: String)?
    let fixedWeightDomain: ClosedRange<Double>?
    @State private var editorialPhoto: (key: String, image: UIImage?)?

    var body: some View {
        let admitted = presentation.map(isCurrent) ?? false
        let reading = admitted ? presentation?.reading(for: selectedMetric, system: system, steps: steps) : nil
        Group {
            if admitted, let photo = presentation?.photo, let photoURL = photo.photoUrl {
                self.photo(url: photoURL, photo: photo, admitted: admitted, reading: reading ?? .unavailable(selectedMetric))
            } else {
                HomeV2DataHero(
                    metric: metric,
                    metrics: metrics,
                    unit: unit,
                    presentation: admitted ? presentation : nil,
                    selectedMetric: selectedMetric,
                    system: system,
                    steps: steps,
                    fixedWeightDomain: fixedWeightDomain
                )
                .frame(width: size.width, height: size.height)
                    .accessibilityIdentifier("home_v2_metric_first")
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_editorial_card")
    }

    private func metricOverlay(_ reading: HomeV2TimelinePolicy.HeroReading) -> some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text(reading.kind.title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .headline)
            Text([reading.value ?? "—", reading.unit].filter { !$0.isEmpty }.joined(separator: " "))
                .scaledSystemFont(size: 60, weight: .semibold, relativeTo: .largeTitle)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(reading.detail)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(HomeV2Tokens.Space.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    private func photo(url: String, photo: BodyMetrics, admitted: Bool, reading: HomeV2TimelinePolicy.HeroReading) -> some View {
        let key = photo.userId + "|" + photo.id + "|" + url + "|" +
            String(ownership?.generation ?? 0) + "|" + metric.id + "|" +
            String(presentation?.selection.date.timeIntervalSince1970 ?? 0) + "|" +
            String(photo.updatedAt.timeIntervalSince1970) + (admitted ? "|selected" : "|inactive")
        let failed = admitted && editorialPhoto?.key == key && editorialPhoto?.image == nil
        return ZStack(alignment: .top) {
            if admitted, let snapshot = editorialPhoto, snapshot.key == key, let image = snapshot.image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(alignment: .bottomLeading) { metricOverlay(reading) }
            } else {
                HomeV2DataHero(
                    metric: metric,
                    metrics: metrics,
                    unit: unit,
                    presentation: admitted ? presentation : nil,
                    selectedMetric: selectedMetric,
                    system: system,
                    steps: steps,
                    fixedWeightDomain: fixedWeightDomain
                )
                Text(failed ? "Photo unavailable" : "Loading photo…")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .padding(HomeV2Tokens.Space.tight)
                    .background(HomeV2Tokens.Colors.shell)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(HomeV2PhotoTap(onTap: onOpenPhoto))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpenPhoto)
        .accessibilityLabel((failed ? "Photo unavailable. Saved measurements shown. " : "Progress photo, ") +
                            "\(dateText(photo)). Actual photo date. Selected time \(presentation?.selection.date.formatted(date: .complete, time: .shortened) ?? ""). \(reading.accessibilitySummary)")
        .accessibilityHint("Open the photo")
        .accessibilityIdentifier("home_v2_photo_stage")
        .task(id: key) {
            guard !Task.isCancelled, let presentation, isCurrent(presentation) else { return }
            let stillCurrent = { isCurrent(presentation) }
            var cached: UIImage?
            guard HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: stillCurrent, operation: {
                cached = SubjectPlateStore.shared.cachedPlate(for: url)
            }) else { return }
            if let cached {
                let focus = SubjectPlateStore.shared.cachedFocus(for: url)
                let cropped = AspectFillCropper.crop(cached, to: size, anchor: focus)
                guard HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: stillCurrent, operation: {
                    editorialPhoto = (key, cropped)
                }) else { return }
            }

            let image = await ImageCacheService.shared.loadImage(from: url)
            guard !Task.isCancelled, stillCurrent() else { return }
            guard let image else {
                if cached == nil {
                    HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: stillCurrent) { editorialPhoto = (key, nil) }
                }
                return
            }
            let focus = await SubjectPlateStore.shared.focus(for: url, image: image)
            guard !Task.isCancelled, stillCurrent() else { return }
            let plate = await SubjectPlateStore.shared.plate(for: url, image: image) ?? image
            guard !Task.isCancelled, stillCurrent() else { return }
            let cropped = AspectFillCropper.crop(plate, to: size, anchor: focus)
            HomeV2TimelinePolicy.performPhotoOperation(ifCurrent: stillCurrent) { editorialPhoto = (key, cropped) }
        }
    }
}

/// A real tap recognizer fails when the finger drags. A plain button can activate
/// at release during a horizontal card gesture before the pager has taken over.
private struct HomeV2PhotoTap: UIGestureRecognizerRepresentable {
    let onTap: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        UITapGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { onTap() }
    }
}

/// One-time coach mark for the signature interactions (JOV-6016): it teaches
/// swipe and scrub once, then leaves the surface permanently. Dismissal is
/// stored in AppStorage by the surface.
struct HomeV2TimelineCoachMark: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Text(HomeV2Copy.timelineCoachHint)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HomeV2Copy.timelineCoachHint)
        .accessibilityHint("Double tap to dismiss")
        .accessibilityIdentifier("home_v2_timeline_coach")
    }
}
