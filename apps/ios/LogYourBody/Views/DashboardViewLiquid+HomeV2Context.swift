//
// DashboardViewLiquid+HomeV2Context.swift
// LogYourBody
//
import SwiftUI
#if DEBUG
import OSLog
#endif

/// Record identity and account lifetime are captured together at the Edit action.
struct HomeV2EditSession: Identifiable {
    let metric: BodyMetrics
    let owner: AuthManager.ProfileSessionOwnership
    var id: String { metric.id }

    /// The body-fat figure the sheet shows. Equality with that figure is "unchanged".
    var displayedBodyFat: Double? {
        metric.bodyFatPercentage.flatMap {
            HomeV2WeightStepPolicy.parse(String(format: "%.1f", $0))
        }
    }

    /// Compare with the sheet's displayed values, not its higher-precision source.
    /// A retained field is a nil patch; the stored raw value stays authoritative.
    func measurementReplacements(
        value: Double?, bodyFat: Double?, initialDisplayedWeight: Double
    ) -> (weight: Double?, bodyFat: Double?) {
        let displayedWeight = HomeV2WeightStepPolicy.parse(HomeV2WeightStepPolicy.text(initialDisplayedWeight))
        return (value == displayedWeight ? nil : value, bodyFat == displayedBodyFat ? nil : bodyFat)
    }
}

extension DashboardViewLiquid {
    func homeV2Metric(on date: Date) -> BodyMetrics? {
        let snapshot = homeV2Timeline
        if isHomeV2ContextPresented {
            guard let route = homeV2ContextRoute, isHomeV2ContextRouteCurrent(route),
                  let metric = route.metric, metric.localDate == BodyMetricLocalDate.key(for: date) else { return nil }
            return metric
        }
        guard let ownership = snapshot.ownership, authManager.ownsAccountSession(ownership),
              snapshot.isOwned(by: ownership),
              let metric = HomeV2EntriesPolicy.contextMetric(
                on: date, selected: homeV2TimelineSelection, metrics: snapshot.metrics,
                ownership: ownership, currentOwnership: authManager.captureAccountSession()
              ) else { return nil }
        return HomeV2EntriesPolicy.admittedMetric(
            metric, metrics: bodyMetrics, ownership: ownership,
            currentOwnership: authManager.captureAccountSession()
        )
    }

    func openHomeV2Context(on date: Date = Date()) {
        let snapshot = homeV2Timeline
        guard let ownership = snapshot.ownership, authManager.ownsAccountSession(ownership),
              snapshot.isOwned(by: ownership) else { return }
        let metric = HomeV2EntriesPolicy.contextMetric(
            on: date, selected: homeV2TimelineSelection, metrics: snapshot.metrics,
            ownership: ownership, currentOwnership: authManager.captureAccountSession()
        )
        if let metric {
            guard HomeV2EntriesPolicy.admittedMetric(
                metric, metrics: bodyMetrics, ownership: ownership,
                currentOwnership: authManager.captureAccountSession()
            ) != nil else { return }
        }
        homeV2CorrectionReturnBridge = nil
        homeV2ContextRoute = HomeV2ContextRoute(metric: metric, ownership: ownership)
        homeV2ContextDay = date
        HapticManager.shared.selection()
        isHomeV2ContextPresented = true
    }

    private func isHomeV2ContextRouteCurrent(_ route: HomeV2ContextRoute) -> Bool {
        guard isHomeV2ContextPresented, homeV2ContextRoute == route,
              authManager.ownsAccountSession(route.ownership), homeV2Timeline.isOwned(by: route.ownership) else { return false }
        if let bridge = homeV2CorrectionReturnBridge, bridge.destination == route {
            guard (try? HomeV2CorrectionPolicy.storedMetric(bridge.stored, store: .shared)) != nil else { return false }
            return bridge.admits(
                current: homeV2ContextRoute, metrics: homeV2Timeline.metrics,
                currentOwnership: authManager.captureAccountSession()
            ) && bridge.admits(
                current: homeV2ContextRoute, metrics: bodyMetrics,
                currentOwnership: authManager.captureAccountSession()
            )
        }
        guard route.metric != nil else { return true }
        return HomeV2EntriesPolicy.admittedDestination(
            route, current: homeV2ContextRoute, metrics: homeV2Timeline.metrics,
            currentOwnership: authManager.captureAccountSession()
        ) != nil && HomeV2EntriesPolicy.admittedDestination(
            route, current: homeV2ContextRoute, metrics: bodyMetrics,
            currentOwnership: authManager.captureAccountSession()
        ) != nil
    }

    private func dismissStaleHomeV2Context() {
        guard let route = homeV2ContextRoute, !isHomeV2ContextRouteCurrent(route) else { return }
        isHomeV2ContextPresented = false
        homeV2ContextRoute = nil
        homeV2CorrectionReturnBridge = nil
    }

    /// The menu offers Entries only while the gate is on.
    var homeV2OpenEntriesAction: (() -> Void)? {
        guard HomeV2Policy.isEnabled() else { return nil }
        return {
            isShowingPhotoTimelineMenu = false
            isHomeV2EntriesPresented = true
        }
    }

    /// Context (Pencil N2). Pushed from `photoTimelineRoot`; the viewer and
    /// sheets it opens are presented from the root as well.
    @ViewBuilder
    var homeV2ContextView: some View {
        Group {
            if let route = homeV2ContextRoute, isHomeV2ContextRouteCurrent(route) {
                HomeV2ContextView(
                    bodyMetrics: homeV2Timeline.metrics,
                    selectedDay: Binding(get: { homeV2ContextDay }, set: { day in
                        guard isHomeV2ContextRouteCurrent(route) else { return }
                        let metric = HomeV2EntriesPolicy.contextMetric(
                            on: day, selected: nil, metrics: homeV2Timeline.metrics,
                            ownership: route.ownership, currentOwnership: authManager.captureAccountSession()
                        )
                        if let metric {
                            guard HomeV2EntriesPolicy.admittedMetric(
                                metric, metrics: bodyMetrics, ownership: route.ownership,
                                currentOwnership: authManager.captureAccountSession()
                            ) != nil else { return }
                        }
                        homeV2ContextDay = day
                        homeV2CorrectionReturnBridge = nil
                        homeV2ContextRoute = HomeV2ContextRoute(metric: metric, ownership: route.ownership)
                    }),
                    detail: { date in
                        guard isHomeV2ContextRouteCurrent(route) else {
                            return HomeV2DayDetail(date: date, metric: nil, rows: [], note: nil, photoURL: nil)
                        }
                        return homeV2DayDetail(for: date)
                    },
                    onClose: {
                        guard homeV2ContextRoute?.id == route.id else { return }
                        isHomeV2ContextPresented = false
                        homeV2ContextRoute = nil
                        homeV2CorrectionReturnBridge = nil
                    },
                    onEditEntry: { metric in
                        #if DEBUG
                        recordHomeEditTransition("callback.begin")
                        #endif
                        guard isHomeV2ContextRouteCurrent(route), route.metric == metric else { return }
                        homeV2EditingMetric = metric
                        #if DEBUG
                        recordHomeEditTransition("callback.assigned")
                        #endif
                    },
                    onLogWeight: { date in
                        guard isHomeV2ContextRouteCurrent(route), date == homeV2ContextDay else { return }
                        presentHomeV2LogSheet(for: date)
                    },
                    onAddPhoto: { metric in
                        guard isHomeV2ContextRouteCurrent(route), route.metric == metric else { return }
                        presentProgressPhotoAttach(for: metric)
                    },
                    onOpenPhoto: { metric in
                        openHomeV2PhotoFromContext(metric, route: route)
                    }
                )
                #if DEBUG
                .safeAreaInset(edge: .top) {
                    if let graph = correctionFixtureGraph, homeV2EditingMetric == nil {
                        HomeV2CorrectionFixturePanel(graph: graph, liveRoute: route, scope: "context")
                    }
                }
                .onAppear { correctionFixtureGraph?.observeContext(route, visible: true) }
                .onDisappear { correctionFixtureGraph?.observeContext(route, visible: false) }
                #endif
            }
        }
        .onChange(of: authManager.captureAccountSession()) { _, _ in dismissStaleHomeV2Context() }
        .onChange(of: bodyMetrics) { _, _ in dismissStaleHomeV2Context() }
        .onChange(of: homeV2Timeline.metrics) { _, _ in dismissStaleHomeV2Context() }
    }

    /// Pop Context before the viewer factory runs. The retained route UUID is a
    /// receipt for this handoff; a replacement Context invalidates the delayed action.
    private func openHomeV2PhotoFromContext(_ metric: BodyMetrics, route: HomeV2ContextRoute) {
        let snapshot = homeV2Timeline
        let source = bodyMetrics
        guard isHomeV2ContextRouteCurrent(route), route.metric == metric,
              PhotoTimelineHUDPolicy.hasUsablePhoto(metric) else { return }
        selectHomeV2TimelineEntry(.init(metric))
        guard let selection = homeV2TimelineSelection,
              let presentation = snapshot.presentation(
                  for: selection, heightCm: nil, currentOwnership: route.ownership
              ), snapshot.admitsPhotoPresentation(
                  presentation, selected: selection, currentOwnership: route.ownership,
                  currentMetrics: source, currentSnapshot: homeV2Timeline
              ) else { return }
        isHomeV2ContextPresented = false
        // Entries may have opened Context from Progress. This explicit photo
        // action returns to the shared selected Home moment before presenting.
        isHomeV2EntriesPresented = false
        selectedPhotoTimelineRootPage = .timeline
        isHomeChatExpanded = false
        homeV2CorrectionReturnBridge = nil
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled, homeV2ContextRoute == route, !isHomeV2ContextPresented,
                  homeV2EditingMetric == nil, authManager.ownsAccountSession(route.ownership),
                  hasCurrentDashboardPublication, bodyMetrics == source, !isHomeV2PhotoScrubNavigating,
                  snapshot.admitsPhotoPresentation(
                      presentation, selected: homeV2TimelineSelection,
                      currentOwnership: authManager.captureAccountSession(),
                      currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                  ) else { return }
            homeV2ContextRoute = nil
            presentHomeV2PhotoViewer()
        }
    }

    /// Entries (Pencil E0).
    var homeV2EntriesView: some View {
        let system = currentMeasurementSystem
        let snapshot = homeV2Timeline
        let ownership = snapshot.ownership
        let isCurrent = ownership.map { authManager.ownsAccountSession($0) } ?? false
        return HomeV2EntriesView(
            sections: HomeV2EntriesPolicy.sections(
                metrics: isCurrent && snapshot.isOwned(by: ownership) ? snapshot.metrics : [],
                unit: homeV2DisplayUnit,
                weightValue: { metric in metric.weight.map { convertWeight($0, to: system) ?? $0 } },
                hasPhoto: { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }
            ),
            onSelect: { captured in
                guard let ownership, authManager.ownsAccountSession(ownership),
                      homeV2Timeline.isOwned(by: ownership), homeV2Timeline.metrics == snapshot.metrics,
                      HomeV2EntriesPolicy.admittedMetric(
                        captured, metrics: snapshot.metrics, ownership: ownership,
                        currentOwnership: authManager.captureAccountSession()
                      ) != nil,
                      let metric = HomeV2EntriesPolicy.admittedMetric(
                        captured, metrics: bodyMetrics, ownership: ownership,
                        currentOwnership: authManager.captureAccountSession()
                      ) else { return }
                selectHomeV2TimelineEntry(.init(metric))
                guard homeV2TimelineSelection == HomeV2TimelinePolicy.Selection(metric) else { return }
                openHomeV2Context(on: metric.date)
            },
            onBack: { isHomeV2EntriesPresented = false }
        )
    }

    /// Everything Context shows for a day. Derived values say so.
    func homeV2DayDetail(for date: Date) -> HomeV2DayDetail {
        let calendar = Calendar.current
        let system = currentMeasurementSystem
        let unit = homeV2DisplayUnit
        let metric = homeV2Metric(on: date)
        var rows: [HomeV2DayEntryRow] = []

        if let metric, let weight = metric.weight {
            let value = convertWeight(weight, to: system) ?? weight
            rows.append(HomeV2DayEntryRow(
                id: "weight",
                label: HomeV2ContextCopy.weight,
                subline: HomeV2Provenance.weightSubline(for: metric),
                value: HomeV2Provenance.weightText(displayValue: value, metric: metric, unit: unit)
            ))
        }

        if let metric, let bodyFat = metric.bodyFatPercentage {
            rows.append(HomeV2DayEntryRow(
                id: "body_fat",
                label: HomeV2ContextCopy.bodyFat,
                subline: HomeV2Provenance.bodyFatSubline(for: metric),
                value: String(format: "%.1f%%", bodyFat)
            ))
        }

        if let metric, let weight = metric.weight,
           HomeV2WeightQuality.isWithinSupportedLoggingRange(weight), let bodyFat = metric.bodyFatPercentage {
            let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
            )
            if let heightInches,
               let ffmi = UnitConversion.calculateFFMI(
                weightKg: weight,
                bodyFatPercentage: bodyFat,
                heightCm: heightInches * 2.54
               ) {
                rows.append(HomeV2DayEntryRow(
                    id: "ffmi",
                    label: HomeV2ContextCopy.ffmi,
                    subline: HomeV2ContextCopy.estimated,
                    value: String(format: "%.1f", ffmi)
                ))
            }
            if let lean = UnitConversion.calculateLeanMass(
                weightKg: weight,
                bodyFatPercentage: bodyFat,
                useMetric: system == .metric
            ) {
                rows.append(HomeV2DayEntryRow(
                    id: "lean_mass",
                    label: HomeV2ContextCopy.leanMass,
                    subline: HomeV2ContextCopy.estimated,
                    value: "\(HomeV2WeightStepPolicy.text(lean)) \(unit)"
                ))
            }
        }

        if let row = HomeV2DayEntryRow.steps(
            dailyMetricsLookup()[calendar.startOfDay(for: date)]?.steps
        ) {
            rows.append(row)
        }

        let note = metric?.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HomeV2DayDetail(
            date: date,
            metric: metric,
            rows: rows,
            note: (note?.isEmpty == false) ? note : nil,
            photoURL: metric.flatMap { PhotoTimelineHUDPolicy.hasUsablePhoto($0) ? $0.photoUrl : nil }
        )
    }

    /// Edit entry (Pencil E1) with the delete confirmation (E2) inside.
    func homeV2EditEntrySheet(for metric: BodyMetrics) -> some View {
        let system = currentMeasurementSystem
        let unit = homeV2DisplayUnit
        let returnDestination = homeV2ContextRoute
        let initial = metric.weight.map { convertWeight($0, to: system) ?? $0 }
            ?? HomeV2WeightStepPolicy.defaultValue(unit: unit)

        return HomeV2LogWeightSheet(
            mode: .edit,
            unit: unit,
            initialValue: initial,
            initialBodyFat: metric.bodyFatPercentage,
            initialWeightIsMissing: metric.weight == nil,
            initialBodyFatMethod: metric.attributedBodyFatMethod,
            correctionOwnership: authManager.captureAccountSession(),
            correctionReturnDestination: returnDestination,
            onCorrectionReturnEnded: { receipt in
                guard homeV2CorrectionReturnBridge?.receipt == receipt else { return }
                homeV2CorrectionReturnBridge = nil
                dismissStaleHomeV2Context()
            },
            ownsCorrectionSession: { authManager.ownsAccountSession($0) },
            dateText: HomeV2ContextCopy.entryDateText(metric.date),
            deleteScope: HomeV2ContextCopy.deleteBody(
                date: formatHUDDate(metric.date),
                includesPhoto: PhotoTimelineHUDPolicy.hasUsablePhoto(metric)
            ),
            existingPhotoURL: PhotoTimelineHUDPolicy.hasUsablePhoto(metric) ? metric.photoUrl : nil,
            onSave: { _, _ in false },
            onCorrectionSave: { changes, ownership, receipt, editorIsCurrent in
                await saveHomeV2Correction(
                    metric, changes: changes, ownership: ownership,
                    returnReceipt: receipt, editorIsCurrent: editorIsCurrent
                )
            },
            onDelete: {
                guard let destination = returnDestination, isHomeV2ContextRouteCurrent(destination),
                      destination.metric == metric else { return false }
                return await deleteHomeV2Entry(metric)
            },
            onAddPhoto: { _ in
                guard let destination = returnDestination, isHomeV2ContextRouteCurrent(destination),
                      destination.metric == metric else { return }
                homeV2EditingMetric = nil
                Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                    guard homeV2EditingMetric == nil, homeV2ContextRoute == destination,
                          isHomeV2ContextRouteCurrent(destination) else { return }
                    presentProgressPhotoAttach(for: metric)
                }
            }
        )
    }

    @MainActor
    func saveHomeV2Correction(
        _ original: BodyMetrics, changes: HomeV2CorrectionPolicy.Changes,
        ownership: AuthManager.ProfileSessionOwnership?,
        returnReceipt: HomeV2CorrectionReturnReceipt?,
        editorIsCurrent: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard let ownership, let returnReceipt, editorIsCurrent(),
              returnReceipt.destination.metric == original,
              returnReceipt.destination.ownership == ownership,
              isHomeV2ContextRouteCurrent(returnReceipt.destination) else { return false }
        if changes.isEmpty { return true }
        var didReturn = false
        let canReturn: @MainActor () -> Bool = {
            guard !Task.isCancelled, editorIsCurrent(), authManager.ownsAccountSession(ownership),
                  isHomeV2ContextPresented else { return false }
            if let bridge = homeV2CorrectionReturnBridge {
                return bridge.owns(returnReceipt) && isHomeV2ContextRouteCurrent(bridge.destination)
            }
            return isHomeV2ContextRouteCurrent(returnReceipt.destination)
        }
        defer {
            // Never clear a newer editor's bridge or destination.
            if homeV2CorrectionReturnBridge?.receipt == returnReceipt {
                homeV2CorrectionReturnBridge = nil
                dismissStaleHomeV2Context()
            }
        }
        let saved = await HomeV2CorrectionPolicy.save(
            original, changes: changes, ownership: ownership,
            ownsSession: { authManager.ownsAccountSession($0) && canReturn() },
            persist: { corrected, admission in
                #if DEBUG
                await correctionFixtureHold?.waitBeforeWriter(returnReceipt)
                let writerObserver: (@MainActor (Result<Void, Error>) -> Void)? = correctionFixtureHold.map { held in
                    { result in held.recordWriterAdmission(result, receipt: returnReceipt) }
                }
                #else
                let writerObserver: (@MainActor (Result<Void, Error>) -> Void)? = nil
                #endif
                _ = try await HomeV2CorrectionPolicy.persistCorrectionReturningStored(
                    corrected, replacing: original, changes: changes, store: .shared,
                    admission: admission, onStored: { stored in
                        #if DEBUG
                        correctionFixtureHold?.recordStored(stored, receipt: returnReceipt)
                        #endif
                        guard canReturn() else { throw CancellationError() }
                        let bridge = HomeV2CorrectionReturnBridge(receipt: returnReceipt, stored: stored)
                        homeV2CorrectionReturnBridge = bridge
                        homeV2ContextRoute = bridge.destination
                    }, onCommitted: { result in
                        guard canReturn(), let previous = result.previousMetric else { throw CancellationError() }
                        homeV2Logged = HomeV2LoggedEntry.correction(
                            previous: previous, stored: result.metrics, ownership: ownership,
                            system: currentMeasurementSystem
                        )
                    }, onWriterAdmission: writerObserver
                )
            },
            didSave: { _, canPublish in
                guard canPublish(), canReturn(), let bridge = homeV2CorrectionReturnBridge,
                      bridge.owns(returnReceipt) else { return }
                realtimeSyncManager.syncIfNeeded()
                BodyScoreCache.shared.invalidate(for: original.userId)
                BodyScoreRecalculationService.shared.scheduleRecalculation()
                guard canPublish(), canReturn() else { return }
                await viewModel.refreshData(
                    authManager: authManager, realtimeSyncManager: realtimeSyncManager,
                    expectedOwnership: ownership
                )
                // The current VM retains the original ownership through actual refresh publication.
                guard canPublish(), canReturn() else { return }
                refreshGlobalTimelineStore()
                reconcileHomeV2Timeline(with: bodyMetrics)
                guard canPublish(), canReturn(),
                      (try? HomeV2CorrectionPolicy.storedMetric(bridge.stored, store: .shared)) != nil,
                      bridge.completed(
                        current: homeV2ContextRoute, metrics: bodyMetrics,
                        currentOwnership: authManager.captureAccountSession()
                      ),
                      bridge.completed(
                        current: homeV2ContextRoute, metrics: homeV2Timeline.metrics,
                        currentOwnership: authManager.captureAccountSession()
                      ) else { return }
                // The destination already holds the actual stored revision. Retire only this bridge.
                didReturn = true
                #if DEBUG
                correctionFixtureHold?.recordPublicationReturned(returnReceipt)
                #endif
                HapticManager.shared.successAction()
            }
        )
        return saved && didReturn
    }

    @MainActor
    func deleteHomeV2Entry(_ metric: BodyMetrics) async -> Bool {
        let deleted = await RealtimeSyncManager.shared.deleteBodyMetric(id: metric.id)
        guard deleted else { return false }
        if let userId = authManager.currentUser?.id {
            BodyScoreCache.shared.invalidate(for: userId)
        }
        HapticManager.shared.successAction()
        await refreshHomeV2AfterWrite(selecting: nil)
        return true
    }
}

#if DEBUG
extension DashboardViewLiquid {
    /// Observe only this explicitly selected XCTest fixture, without recording account or measurement data.
    @MainActor
    func recordHomeEditTransition(_ event: String) {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("-lybUITestHomeEditPresentationDiagnostic"),
              process.arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
              process.arguments.contains("-lybUITestHomeV2PhotoFixture"),
              let session = process.environment["XCTestSessionIdentifier"],
              UUID(uuidString: session) != nil,
              let bundle = process.environment["XCTestBundlePath"],
              bundle.hasSuffix("/LogYourBodyUITests.xctest") else { return }
        let state = "event=\(event) context=\(isHomeV2ContextPresented) " +
            "item=\(homeV2EditingMetric != nil) addEntry=\(showAddEntrySheet) " +
            "photoAttach=\(isProgressPhotoAttachPresented) viewer=\(isHomeV2ViewerPresented) " +
            "allPhotos=\(isHomeV2AllPhotosPresented) menu=\(isShowingPhotoTimelineMenu) help=\(isHomeV2HelpPresented)"
        Logger(subsystem: "com.logyourbody.home-edit-transition-diagnostic", category: "fixture")
            .notice("\(state, privacy: .public)")
    }
}
#endif
