//
// DashboardViewLiquid+HomeV2Photos.swift
// LogYourBody
//
import SwiftUI

/// Where a photo tool goes (Pencil P4–P7). Presented from the viewer; the
/// item changes in place when one tool leads to another.
enum HomeV2PhotoRoute: Identifiable, Equatable {
    case compare(HomeV2PhotoPair)
    case pickDates(HomeV2PhotoPair)
    case allPhotos
    case share(HomeV2PhotoPair)
    case timelapse

    var id: String {
        switch self {
        case .compare(let pair): return "compare-\(pair.id)"
        case .pickDates(let pair): return "pick-\(pair.id)"
        case .allPhotos: return "all"
        case .share(let pair): return "share-\(pair.id)"
        case .timelapse: return "timelapse"
        }
    }
}

extension DashboardViewLiquid {
    var homeV2Formatters: HomeV2Formatters {
        let system = currentMeasurementSystem
        return HomeV2Formatters(
            dateText: { formatHUDDate($0.date) },
            weightText: { formatTrendWeightHeadline($0, usesTrend: weightUsesTrend) },
            weightValue: { metric in
                guard let weight = metric.weight else { return nil }
                return convertWeight(weight, to: system) ?? weight
            },
            bodyFatText: { metric in
                let base = formatBodyFatValue(metric.bodyFatPercentage)
                return base == "–" ? base : "\(base)%"
            },
            weightUnit: homeV2DisplayUnit
        )
    }

    /// FFMI for one day from that day's own numbers, so compare reads "Derived".
    func homeV2FFMIValue(_ metric: BodyMetrics) -> Double? {
        guard let weight = metric.weight, let bodyFat = metric.bodyFatPercentage,
              let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
              ) else { return nil }
        return UnitConversion.calculateFFMI(weightKg: weight, bodyFatPercentage: bodyFat, heightCm: heightInches * 2.54)
    }

    var homeV2BodyFatSource: String? {
        bodyMetrics
            .filter { $0.bodyFatPercentage != nil }
            .max { $0.date < $1.date }
            .map { HomeV2Provenance.label(for: $0) }
    }

    /// The pair a tool starts from: the first photo against the selected one.
    var homeV2DefaultPair: HomeV2PhotoPair? {
        let chronological = HomeV2PhotoIndex.chronologicalPhotoIndices(in: bodyMetrics)
        guard let first = chronological.first, let last = chronological.last, first != last else { return nil }
        let after = chronological.contains(selectedIndex) && selectedIndex != first ? selectedIndex : last
        return HomeV2PhotoPair(before: first, after: after)
    }

    func openHomeV2PhotoTool(_ tool: HomeV2PhotoTool) {
        HapticManager.shared.selection()
        switch tool {
        case .compare:
            if let pair = homeV2DefaultPair { homeV2PhotoRoute = .compare(pair) }
        case .share:
            if let pair = homeV2DefaultPair { homeV2PhotoRoute = .share(pair) }
        case .allPhotos:
            homeV2PhotoRoute = .allPhotos
        case .timelapse:
            homeV2PhotoRoute = .timelapse
        case .timeline:
            break
        }
    }

    /// Presented from `photoTimelineRoot`, the same level as the menu cover, so
    /// the presentation context is the HUD's own. Tools present from here.
    var homeV2PhotoViewer: some View {
        HomeV2PhotoViewer(
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            formatters: homeV2Formatters,
            sourceLine: homeV2BodyFatSource.map { HomeV2PhotoCopy.estimatedBySource($0) },
            onClose: { isHomeV2ViewerPresented = false },
            onTool: { openHomeV2PhotoTool($0) }
        )
        .fullScreenCover(item: $homeV2PhotoRoute) { route in
            homeV2PhotoRouteView(route)
        }
    }

    @ViewBuilder
    func homeV2PhotoRouteView(_ route: HomeV2PhotoRoute) -> some View {
        switch route {
        case .compare(let pair):
            HomeV2CompareView(
                bodyMetrics: bodyMetrics,
                pair: Binding(
                    get: { pair },
                    set: { homeV2PhotoRoute = .compare($0) }
                ),
                formatters: homeV2Formatters,
                ffmiValue: { homeV2FFMIValue($0) },
                bodyFatSource: homeV2BodyFatSource,
                onClose: { homeV2PhotoRoute = nil },
                onShare: { homeV2PhotoRoute = .share($0) },
                onChangeDates: { homeV2PhotoRoute = .pickDates(pair) }
            )
        case .pickDates(let pair):
            HomeV2AllPhotosPicker(
                bodyMetrics: bodyMetrics,
                formatters: homeV2Formatters,
                onPick: { homeV2PhotoRoute = .compare($0) },
                onCancel: { homeV2PhotoRoute = .compare(pair) }
            )
        case .allPhotos:
            HomeV2AllPhotosView(
                bodyMetrics: bodyMetrics,
                formatters: homeV2Formatters,
                mode: .browse,
                onSelect: { index in
                    selectedIndex = index
                    homeV2PhotoRoute = nil
                },
                onClose: { homeV2PhotoRoute = nil }
            )
        case .share(let pair):
            HomeV2ShareView(
                bodyMetrics: bodyMetrics,
                pair: pair,
                formatters: homeV2Formatters,
                onCancel: { homeV2PhotoRoute = nil }
            )
        case .timelapse:
            HomeV2TimelapseView(
                bodyMetrics: bodyMetrics,
                formatters: homeV2Formatters,
                onClose: { homeV2PhotoRoute = nil }
            )
        }
    }

    /// All photos from Home (H2's "All photos"). A photo opens the viewer.
    var homeV2AllPhotosFromHome: some View {
        HomeV2AllPhotosView(
            bodyMetrics: bodyMetrics,
            formatters: homeV2Formatters,
            mode: .browse,
            onSelect: { index in
                selectedIndex = index
                isHomeV2AllPhotosPresented = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    isHomeV2ViewerPresented = true
                }
            },
            onClose: { isHomeV2AllPhotosPresented = false }
        )
    }
}

/// The two-tap picker Compare uses to change its dates.
struct HomeV2AllPhotosPicker: View {
    let bodyMetrics: [BodyMetrics]
    let formatters: HomeV2Formatters
    let onPick: (HomeV2PhotoPair) -> Void
    let onCancel: () -> Void

    @State private var before: Int?

    var body: some View {
        HomeV2AllPhotosView(
            bodyMetrics: bodyMetrics,
            formatters: formatters,
            mode: .pick,
            onSelect: { index in
                if let before, before != index {
                    let ordered = [before, index].sorted { bodyMetrics[$0].date < bodyMetrics[$1].date }
                    onPick(HomeV2PhotoPair(before: ordered[0], after: ordered[1]))
                } else {
                    before = index
                }
            },
            onClose: onCancel,
            pickHint: before == nil ? HomeV2PhotoCopy.chooseBefore : HomeV2PhotoCopy.chooseAfter
        )
    }
}
