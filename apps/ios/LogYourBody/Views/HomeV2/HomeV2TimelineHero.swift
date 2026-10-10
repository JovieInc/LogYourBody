import SwiftUI

/// Stable entry identity is shared by the pager, ruler and dashboard's index adapter.
enum HomeV2TimelinePolicy {
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

    /// Rebuilt when published history changes, never on the scrub hot path.
    struct Snapshot {
        let metrics: [BodyMetrics]
        let chronologicalDates: [Date]
        private let sourceOrder: [EntryID]
        private let weightChanges: [EntryID: Double]

        init(metrics: [BodyMetrics] = [], owner: String? = nil, calendar: Calendar = .current) {
            self.metrics = metrics.filter { $0.userId == owner }.sorted {
                $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date
            }
            chronologicalDates = self.metrics.reversed().map(\.date)
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
                guard let weight = metric.weight, weight.isFinite, weight > 0 else { return nil }
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

/// The existing timeline pager, displaying the approved original-photo/data card.
struct HomeV2TimelinePager: View {
    let snapshot: HomeV2TimelinePolicy.Snapshot
    @Binding var selectedID: HomeV2TimelinePolicy.EntryID
    let size: CGSize
    let unit: String
    let dateText: (BodyMetrics) -> String
    let onOpenPhoto: () -> Void

    var body: some View {
        TabView(selection: $selectedID) {
            ForEach(snapshot.metrics) { metric in
                HomeV2TimelinePage(metric: metric, metrics: snapshot.metrics, size: size, unit: unit,
                                   dateText: dateText(metric), onOpenPhoto: onOpenPhoto)
                    .tag(HomeV2TimelinePolicy.EntryID(metric))
                    .accessibilityHidden(HomeV2TimelinePolicy.EntryID(metric) != selectedID)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: size.width, height: size.height)
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

/// Image bytes are displayed only for their exact owner/URL. A replacement or
/// failed load keeps the selected record's real-data fallback, never the previous photo.
private struct HomeV2TimelinePage: View {
    let metric: BodyMetrics
    let metrics: [BodyMetrics]
    let size: CGSize
    let unit: String
    let dateText: String
    let onOpenPhoto: () -> Void
    @State private var editorialPhoto: (key: String, image: UIImage?)?

    var body: some View {
        Group {
            if PhotoTimelineHUDPolicy.hasUsablePhoto(metric), let photoURL = metric.photoUrl {
                photo(url: photoURL)
            } else {
                HomeV2DataHero(metric: metric, metrics: metrics, unit: unit)
                    .frame(width: size.width, height: size.height)
                    .accessibilityIdentifier("home_v2_metric_first")
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_editorial_card")
        .id(HomeV2TimelinePolicy.EntryID(metric))
    }

    private func photo(url: String) -> some View {
        let key = metric.userId + "|" + url
        let failed = editorialPhoto?.key == key && editorialPhoto?.image == nil
        return ZStack(alignment: .top) {
            if let snapshot = editorialPhoto, snapshot.key == key, let image = snapshot.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(alignment: .bottomLeading) { compositionOverlay }
            } else {
                HomeV2DataHero(metric: metric, metrics: metrics, unit: unit)
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
                            "\(dateText). \(HomeV2TimelinePolicy.bodyFatSentence(for: metric))")
        .accessibilityHint("Open the photo")
        .accessibilityIdentifier("home_v2_photo_stage")
        .task(id: key) {
            let image = await ImageCacheService.shared.loadImage(from: url)
            guard !Task.isCancelled else { return }
            editorialPhoto = (key, image)
        }
    }

    private var compositionOverlay: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            if let reading = HomeV2EditorialPolicy.bodyFat(in: metric) {
                Text("Body fat")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .headline)
                Text(String(format: "%.1f%%", reading.percentage))
                    .scaledSystemFont(size: 60, weight: .semibold, relativeTo: .largeTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(reading.caption)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(HomeV2Tokens.Space.margin)
        .padding(.top, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
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
