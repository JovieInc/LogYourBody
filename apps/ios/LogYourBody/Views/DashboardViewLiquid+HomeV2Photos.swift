//
// DashboardViewLiquid+HomeV2Photos.swift
// LogYourBody
//
import SwiftUI

/// Where a photo tool goes (Pencil P4–P7). Presented from the viewer; the
/// item changes in place when one tool leads to another.
struct HomeV2PhotoRoute: Identifiable, Equatable {
    /// One existing cover lifetime; transitions retain it, a new opening gets a new nonce.
    struct Publication: Equatable {
        let id = UUID()
        let metrics: [BodyMetrics]
        let selectedPhoto: HomeV2TimelinePolicy.EntryID
        let ownership: AuthManager.ProfileSessionOwnership

        init?(
            metrics: [BodyMetrics], selectedPhoto: HomeV2TimelinePolicy.EntryID,
            ownership: AuthManager.ProfileSessionOwnership?
        ) {
            guard let ownership, !ownership.subject.isEmpty,
                  selectedPhoto.owner == ownership.subject,
                  metrics.allSatisfy({ $0.userId == ownership.subject }),
                  Set(metrics.map(HomeV2TimelinePolicy.EntryID.init)).count == metrics.count,
                  let photo = metrics.first(where: { HomeV2TimelinePolicy.EntryID($0) == selectedPhoto }),
                  PhotoTimelineHUDPolicy.hasUsablePhoto(photo) else { return nil }
            self.metrics = metrics
            self.selectedPhoto = selectedPhoto
            self.ownership = ownership
        }

        /// Reorder/insertion cannot reinterpret captured indices. Deleted/reused/changed rows revoke this cover.
        func admits(
            ownership current: AuthManager.ProfileSessionOwnership?, metrics currentMetrics: [BodyMetrics]
        ) -> Bool {
            guard let current, current == ownership else { return false }
            let rows = Dictionary(grouping: currentMetrics, by: HomeV2TimelinePolicy.EntryID.init)
            return metrics.allSatisfy { record in
                let matches = rows[HomeV2TimelinePolicy.EntryID(record)] ?? []
                return matches.count == 1 && matches[0] == record
            }
        }

        func bind(_ pair: HomeV2PhotoPair) -> Pair? {
            guard metrics.indices.contains(pair.before), metrics.indices.contains(pair.after),
                  pair.before != pair.after,
                  PhotoTimelineHUDPolicy.hasUsablePhoto(metrics[pair.before]),
                  PhotoTimelineHUDPolicy.hasUsablePhoto(metrics[pair.after]) else { return nil }
            return Pair(before: .init(metrics[pair.before]), after: .init(metrics[pair.after]))
        }

        func indices(for pair: Pair) -> HomeV2PhotoPair? {
            guard pair.before != pair.after,
                  let before = metrics.firstIndex(where: { HomeV2TimelinePolicy.EntryID($0) == pair.before }),
                  let after = metrics.firstIndex(where: { HomeV2TimelinePolicy.EntryID($0) == pair.after }),
                  PhotoTimelineHUDPolicy.hasUsablePhoto(metrics[before]),
                  PhotoTimelineHUDPolicy.hasUsablePhoto(metrics[after]) else { return nil }
            return .init(before: before, after: after)
        }

        var defaultPair: HomeV2PhotoPair? {
            guard let selected = metrics.firstIndex(where: { HomeV2TimelinePolicy.EntryID($0) == selectedPhoto }) else {
                return nil
            }
            let photos = HomeV2PhotoIndex.chronologicalPhotoIndices(in: metrics)
            guard let other = photos.first(where: { $0 != selected }) else { return nil }
            let ordered = [other, selected].sorted {
                metrics[$0].date == metrics[$1].date ? metrics[$0].id < metrics[$1].id : metrics[$0].date < metrics[$1].date
            }
            return .init(before: ordered[0], after: ordered[1])
        }
    }

    struct Pair: Equatable {
        let before: HomeV2TimelinePolicy.EntryID
        let after: HomeV2TimelinePolicy.EntryID
        var id: String { before.record + "-" + after.record }
    }

    enum Destination: Equatable {
        case compare(Pair)
        case pickDates(Pair)
        case allPhotos
        case share(Pair)
        case timelapse
        case insufficientPhotos(HomeV2PhotoTool)

        var id: String {
            switch self {
            case .compare(let pair): return "compare-" + pair.id
            case .pickDates(let pair): return "pick-" + pair.id
            case .allPhotos: return "all"
            case .share(let pair): return "share-" + pair.id
            case .timelapse: return "timelapse"
            case .insufficientPhotos(let tool): return "insufficient-" + tool.id
            }
        }
    }

    let publication: Publication
    let destination: Destination
    let instanceID = UUID()
    var id: String { publication.id.uuidString + "-" + instanceID.uuidString + "-" + destination.id }

    static func destination(for tool: HomeV2PhotoTool, pair: HomeV2PhotoPair?, publication: Publication) -> Self? {
        let destination: Destination
        switch tool {
        case .compare, .share:
            if let pair {
                guard let bound = publication.bind(pair) else { return nil }
                destination = tool == .compare ? .compare(bound) : .share(bound)
            } else {
                destination = .insufficientPhotos(tool)
            }
        case .allPhotos: destination = .allPhotos
        case .timelapse: destination = .timelapse
        case .timeline: return nil
        }
        return Self(publication: publication, destination: destination)
    }

    /// Late callbacks must still own the actual current route, original receipt and captured records.
    func transition(
        to destination: Destination, currentRoute: Self?,
        ownership: AuthManager.ProfileSessionOwnership?, metrics: [BodyMetrics]
    ) -> Self? {
        guard currentRoute == self, publication.admits(ownership: ownership, metrics: metrics) else { return nil }
        switch destination {
        case .compare(let pair), .pickDates(let pair), .share(let pair):
            guard publication.indices(for: pair) != nil else { return nil }
        case .allPhotos, .timelapse, .insufficientPhotos: break
        }
        return Self(publication: publication, destination: destination)
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
        HomeV2EditorialPolicy.ffmi(
            in: metric, owner: authManager.currentUser?.id,
            heightCm: authManager.currentUser?.profile?.height
        )
    }

    var homeV2BodyFatSource: String? {
        bodyMetrics
            .filter { $0.bodyFatPercentage != nil }
            .max { $0.date < $1.date }
            .map { HomeV2Provenance.label(for: $0, field: .bodyFat) }
    }

    /// The pair a tool starts from: the first photo against the selected one.
    var homeV2DefaultPair: HomeV2PhotoPair? { captureHomeV2PhotoPublication()?.defaultPair }

    private func captureHomeV2PhotoPublication() -> HomeV2PhotoRoute.Publication? {
        let snapshot = homeV2Timeline
        guard let ownership = authManager.captureAccountSession(), snapshot.isOwned(by: ownership),
              let selected = homeV2TimelineSelection,
              let photo = snapshot.presentation(for: selected, heightCm: nil, currentOwnership: ownership)?.photo else {
            return nil
        }
        return .init(metrics: snapshot.metrics, selectedPhoto: .init(photo), ownership: ownership)
    }

    func openHomeV2PhotoTool(_ tool: HomeV2PhotoTool) {
        guard let publication = captureHomeV2PhotoPublication(),
              publication.admits(ownership: authManager.captureAccountSession(), metrics: homeV2Timeline.metrics) else {
            return
        }
        HapticManager.shared.selection()
        homeV2PhotoRoute = HomeV2PhotoRoute.destination(
            for: tool, pair: publication.defaultPair, publication: publication
        )
    }

    private func transitionHomeV2PhotoRoute(
        _ captured: HomeV2PhotoRoute, to destination: HomeV2PhotoRoute.Destination
    ) {
        guard let next = captured.transition(
            to: destination, currentRoute: homeV2PhotoRoute,
            ownership: authManager.captureAccountSession(), metrics: homeV2Timeline.metrics
        ) else { return }
        homeV2PhotoRoute = next
    }

    private func closeHomeV2PhotoRoute(_ captured: HomeV2PhotoRoute) {
        guard homeV2PhotoRoute == captured else { return }
        homeV2PhotoRoute = nil
    }

    /// Presented from `photoTimelineRoot`, the same level as the menu cover, so
    /// the presentation context is the HUD's own. Tools present from here.
    @ViewBuilder
    var homeV2PhotoViewer: some View {
        let snapshot = homeV2Timeline
        let source = bodyMetrics
        let ownership = authManager.captureAccountSession()
        if let openingID = homeV2PhotoViewerOpeningID,
           let ownership, snapshot.isOwned(by: ownership), let selected = homeV2TimelineSelection,
           let presentation = snapshot.presentation(for: selected, heightCm: nil, currentOwnership: ownership),
           snapshot.admitsPhotoPresentation(
               presentation, selected: homeV2TimelineSelection,
               currentOwnership: authManager.captureAccountSession(),
               currentMetrics: source, currentSnapshot: homeV2Timeline
           ), let photo = presentation.photo,
           let displayed = snapshot.sourceIndex(for: .init(photo)), source.indices.contains(displayed),
           HomeV2TimelinePolicy.EntryID(source[displayed]) == .init(photo) {
            let admission = HomeV2TimelinePolicy.PhotoViewerAdmission(
                openingID: openingID, snapshot: snapshot, presentation: presentation
            )
            HomeV2PhotoViewer(
                bodyMetrics: source,
                selectedIndex: Binding(
                    get: { displayed },
                    set: { index in
                        guard authManager.ownsAccountSession(ownership), bodyMetrics == source,
                              admitsHomeV2PhotoViewer(admission),
                              snapshot.admitsPhotoPresentation(
                                  presentation, selected: homeV2TimelineSelection,
                                  currentOwnership: authManager.captureAccountSession(),
                                  currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                              ), source.indices.contains(index),
                              PhotoTimelineHUDPolicy.hasUsablePhoto(source[index]) else { return }
                        let id = HomeV2TimelinePolicy.EntryID(source[index])
                        guard id != HomeV2TimelinePolicy.EntryID(photo) else { return }
                        selectHomeV2TimelineEntry(id)
                    }
                ),
                formatters: homeV2Formatters,
                sourceLine: HomeV2EditorialPolicy.bodyFat(in: photo)?.caption,
                onClose: {
                    guard admitsHomeV2PhotoViewer(admission), authManager.ownsAccountSession(ownership),
                          snapshot.admitsPhotoPresentation(
                              presentation, selected: homeV2TimelineSelection,
                              currentOwnership: authManager.captureAccountSession(),
                              currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                          ) else { return }
                    homeV2PhotoViewerOpeningID = nil
                    isHomeV2ViewerPresented = false
                },
                onTool: { tool in
                    guard authManager.ownsAccountSession(ownership), bodyMetrics == source,
                          admitsHomeV2PhotoViewer(admission),
                          snapshot.admitsPhotoPresentation(
                              presentation, selected: homeV2TimelineSelection,
                              currentOwnership: authManager.captureAccountSession(),
                              currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                          ) else { return }
                    openHomeV2PhotoTool(tool)
                }
            )
            .fullScreenCover(item: $homeV2PhotoRoute) { route in
                homeV2PhotoRouteView(route)
            }
        } else {
            HomeV2LoadingHome()
        }
    }

    @ViewBuilder
    func homeV2PhotoRouteView(_ route: HomeV2PhotoRoute) -> some View {
        if homeV2PhotoRoute == route,
           route.publication.admits(
            ownership: authManager.captureAccountSession(), metrics: homeV2Timeline.metrics
           ) {
        switch route.destination {
        case .compare(let bound):
            if let pair = route.publication.indices(for: bound) {
            HomeV2CompareView(
                bodyMetrics: route.publication.metrics,
                pair: Binding(
                    get: { pair },
                    set: { pair in
                        guard let bound = route.publication.bind(pair) else { return }
                        transitionHomeV2PhotoRoute(route, to: .compare(bound))
                    }
                ),
                formatters: homeV2Formatters,
                ffmiValue: { homeV2FFMIValue($0) },
                onClose: { closeHomeV2PhotoRoute(route) },
                onShare: { pair in
                    guard let bound = route.publication.bind(pair) else { return }
                    transitionHomeV2PhotoRoute(route, to: .share(bound))
                },
                onChangeDates: { transitionHomeV2PhotoRoute(route, to: .pickDates(bound)) }
            )
            }
        case .pickDates(let bound):
            HomeV2AllPhotosPicker(
                bodyMetrics: route.publication.metrics,
                formatters: homeV2Formatters,
                onPick: { pair in
                    guard let bound = route.publication.bind(pair) else { return }
                    transitionHomeV2PhotoRoute(route, to: .compare(bound))
                },
                onCancel: { transitionHomeV2PhotoRoute(route, to: .compare(bound)) }
            )
        case .allPhotos:
            HomeV2AllPhotosView(
                bodyMetrics: route.publication.metrics,
                formatters: homeV2Formatters,
                mode: .browse,
                onSelect: { index in
                    guard homeV2PhotoRoute == route,
                          route.publication.admits(
                            ownership: authManager.captureAccountSession(), metrics: homeV2Timeline.metrics
                          ), route.publication.metrics.indices.contains(index) else { return }
                    let metric = route.publication.metrics[index]
                    guard PhotoTimelineHUDPolicy.hasUsablePhoto(metric) else { return }
                    selectHomeV2TimelineEntry(.init(metric))
                    closeHomeV2PhotoRoute(route)
                },
                onClose: { closeHomeV2PhotoRoute(route) }
            )
        case .share(let bound):
            if let pair = route.publication.indices(for: bound) {
            HomeV2ShareView(
                bodyMetrics: route.publication.metrics,
                pair: pair,
                formatters: homeV2Formatters,
                onCancel: { closeHomeV2PhotoRoute(route) }
            )
            }
        case .insufficientPhotos(let tool):
            VStack(spacing: HomeV2Tokens.Space.margin) {
                ScrollView {
                    VStack(spacing: HomeV2Tokens.Space.margin) {
                        Text(HomeV2PhotoCopy.insufficientPhotos(for: tool))
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .semibold, relativeTo: .title2)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("home_v2_photos_needed")
                        Text(HomeV2PhotoCopy.needsAnotherPhoto)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    }
                    .padding(.top, HomeV2Tokens.Space.margin)
                }
                .scrollBounceBehavior(.basedOnSize)
                HomeV2PrimaryButton(
                    title: "Back to photo",
                    identifier: "home_v2_photos_needed_back",
                    action: { closeHomeV2PhotoRoute(route) }
                )
            }
            .multilineTextAlignment(.center)
            .padding(HomeV2Tokens.Space.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        case .timelapse:
            HomeV2TimelapseView(
                bodyMetrics: route.publication.metrics,
                formatters: homeV2Formatters,
                onClose: { closeHomeV2PhotoRoute(route) }
            )
        }
        } else {
            VStack(spacing: HomeV2Tokens.Space.margin) {
                Text(HomeV2PhotoCopy.notEnoughPhotos)
                HomeV2PrimaryButton(
                    title: "Back to photo", identifier: "home_v2_photos_needed_back",
                    action: { closeHomeV2PhotoRoute(route) }
                )
            }
            .padding(HomeV2Tokens.Space.margin)
        }
    }

    /// All photos from Home (H2's "All photos"). A photo opens the viewer.
    @ViewBuilder
    var homeV2AllPhotosFromHome: some View {
        let snapshot = homeV2Timeline
        let source = bodyMetrics
        let originalSelection = homeV2TimelineSelection
        if let ownership = authManager.captureAccountSession(), hasCurrentDashboardPublication,
           snapshot.isOwned(by: ownership) {
            HomeV2AllPhotosView(
                bodyMetrics: source,
                formatters: homeV2Formatters,
                mode: .browse,
                onSelect: { index in
                    guard isHomeV2AllPhotosPresented, authManager.ownsAccountSession(ownership),
                          hasCurrentDashboardPublication, bodyMetrics == source,
                          homeV2TimelineSelection == originalSelection,
                          homeV2Timeline.isOwned(by: ownership), source.indices.contains(index),
                          PhotoTimelineHUDPolicy.hasUsablePhoto(source[index]),
                          snapshot.metric(for: .init(source[index])) == source[index] else { return }
                    selectHomeV2TimelineEntry(.init(source[index]))
                    guard let selected = homeV2TimelineSelection,
                          let presentation = snapshot.presentation(
                              for: selected, heightCm: nil, currentOwnership: ownership
                          ), snapshot.admitsPhotoPresentation(
                              presentation, selected: selected, currentOwnership: ownership,
                              currentMetrics: source, currentSnapshot: homeV2Timeline
                          ) else { return }
                    isHomeV2AllPhotosPresented = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled, authManager.ownsAccountSession(ownership),
                              hasCurrentDashboardPublication, bodyMetrics == source,
                              !isHomeV2PhotoScrubNavigating,
                              snapshot.admitsPhotoPresentation(
                                  presentation, selected: homeV2TimelineSelection,
                                  currentOwnership: authManager.captureAccountSession(),
                                  currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                              ) else { return }
                        presentHomeV2PhotoViewer()
                    }
                },
                onClose: { isHomeV2AllPhotosPresented = false }
            )
        }
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
