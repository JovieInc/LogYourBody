//
// DashboardViewLiquid+HomeV2.swift
// LogYourBody
//
import SwiftUI

extension DashboardViewLiquid {
    /// Home owns the timeline with the pinned Ask composer and check-in dock.
    var isHomeV2CheckIn: Bool {
        HomeV2Policy.isEnabled() && selectedPhotoTimelineRootPage == .timeline && !isHomeChatExpanded
    }

    /// The plain v2 chrome (sidebar glyph, titles) on every v2 root page, Ask included.
    var isHomeV2Chrome: Bool {
        HomeV2Policy.isEnabled()
    }

    var homeV2DisplayUnit: String {
        HomeV2Copy.displayUnit(currentMeasurementSystem)
    }

    var homeV2TodayMetric: BodyMetrics? {
        bodyMetrics.first { Calendar.current.isDateInToday($0.date) }
    }

    var homeV2InsightMetrics: [BodyMetrics] {
        bodyMetrics.filter {
            $0.weight == nil || HomeV2WeightQuality.isWithinSupportedLoggingRange($0.weight)
        }
    }

    /// Photo-first Home behind `HomeV2Policy`; the legacy `LaunchTimelineSurface`
    /// keeps serving when the gate is off.
    @ViewBuilder
    func homeV2Surface(for metric: BodyMetrics) -> some View {
        let snapshot = homeV2Timeline
        let ownership = authManager.captureAccountSession()
        if let ownership, hasCurrentDashboardPublication, snapshot.isOwned(by: ownership),
           let selection = homeV2TimelineSelection,
           selection.id == HomeV2TimelinePolicy.EntryID(metric), selection.date == metric.date,
           let presentation = snapshot.presentation(
            for: selection, heightCm: authManager.currentUser?.profile?.height, currentOwnership: ownership
           ) {
            admittedHomeV2Surface(metric: metric, snapshot: snapshot, presentation: presentation, ownership: ownership)
        } else {
            HomeV2LoadingHome()
        }
    }

    private func admittedHomeV2Surface(
        metric: BodyMetrics, snapshot: HomeV2TimelinePolicy.Snapshot,
        presentation: HomeV2TimelinePolicy.Presentation, ownership: AuthManager.ProfileSessionOwnership
    ) -> some View {
        return HomeV2Surface(
            metric: metric,
            bodyMetrics: snapshot.metrics,
            timeline: snapshot,
            presentation: presentation,
            heightCm: authManager.currentUser?.profile?.height,
            isCurrent: { candidate in
                authManager.ownsAccountSession(ownership) && hasCurrentDashboardPublication &&
                snapshot.admitsPresentation(
                    candidate, selected: homeV2TimelineSelection,
                    currentOwnership: authManager.captureAccountSession(),
                    currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                )
            },
            selectedMetric: homeV2HeroMetric, system: currentMeasurementSystem,
            onSelectMetric: { homeV2HeroMetric = $0 },
            selectedID: Binding(
                get: { homeV2TimelineSelection?.id ?? presentation.selection.id },
                set: selectHomeV2TimelineEntry
            ),
            stepsValue: homeV2StepsText(for: metric).value,
            stepsDetail: homeV2StepsText(for: metric).detail,
            changeSentence: homeV2Timeline.weightChangeSentence(
                for: HomeV2TimelinePolicy.EntryID(metric), system: currentMeasurementSystem
            ),
            dateText: { formatHUDDate($0.date) },
            loggedSentence: homeV2Logged.map { $0.confirmationText },
            systemState: homeV2SystemState,
            onOpenPhoto: {
                guard !isHomeV2PhotoScrubNavigating, authManager.ownsAccountSession(ownership),
                      snapshot.admitsPhotoPresentation(
                          presentation, selected: homeV2TimelineSelection,
                          currentOwnership: authManager.captureAccountSession(),
                          currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
                      ) else { return }
                presentHomeV2PhotoViewer()
            },
            onViewProgress: { openHomeV2Progress() },
            onViewMetric: { openHomeV2Progress(metric: $0) },
            onTodayDetails: {
                guard authManager.ownsAccountSession(ownership), homeV2TimelineSelection == presentation.selection else { return }
                openHomeV2Context(on: presentation.selection.date)
            },
            onAllPhotos: { isHomeV2AllPhotosPresented = true },
            onLogWeight: {
                guard authManager.ownsAccountSession(ownership), homeV2TimelineSelection == presentation.selection else { return }
                presentHomeV2LogSheet(for: presentation.selection.date, initialTab: 1)
            },
            onConnectHealth: {
                Task { _ = await HealthKitManager.shared.requestAuthorization() }
            },
            onDone: { homeV2Logged = nil },
            onUndo: { Task { await undoHomeV2Logged() } },
            onProvenancePresentationChange: { isHomeV2MetricProvenancePresented = $0 },
            isPhotoScrubNavigating: isHomeV2PhotoScrubNavigating
        )
        .task(id: homeV2StepsRequest(on: metric.date)) {
            guard authManager.ownsAccountSession(ownership),
                  homeV2TimelineSelection == presentation.selection, homeV2Timeline.isOwned(by: ownership) else { return }
            await homeV2StepsReader.load(
                metric: metric, ownership: ownership, ownsSession: authManager.ownsAccountSession
            )
        }
        // Chart caches refresh centrally when measurements change. Phase copy
        // must also follow edits to an existing day, not just added rows.
        .task(id: snapshot.metrics) {
            guard authManager.ownsAccountSession(ownership) else { return }
            let insightMetrics = snapshot.metrics.filter {
                $0.weight == nil || HomeV2WeightQuality.isWithinSupportedLoggingRange($0.weight)
            }
            let insight = PhaseInsightPolicy.insight(for: insightMetrics)
            homeV2PhaseSentence = HomeV2Copy.phaseSentence(
                kind: insight.kind,
                weeks: HomeV2PhasePolicy.weeks(kind: insight.kind, metrics: insightMetrics)
            )
        }
    }

    var homeV2HeroShareKind: ContextualMetricKind {
        switch homeV2HeroMetric {
        case .bodyFat: return .bodyFat
        case .weight: return .weight
        case .ffmi: return .ffmi
        case .steps: return .steps
        }
    }

    /// Capture all editor options from one admitted moment; retain display-only evidence.
    var homeV2HeroShareSnapshots: [ContextualMetricSnapshot] {
        let snapshot = homeV2Timeline
        guard let ownership = authManager.captureAccountSession(), hasCurrentDashboardPublication,
              snapshot.isOwned(by: ownership), let selection = homeV2TimelineSelection,
              let metric = snapshot.metric(for: selection.id),
              let presentation = snapshot.presentation(
                  for: selection, heightCm: authManager.currentUser?.profile?.height,
                  currentOwnership: ownership
              ), snapshot.admitsPresentation(
                  presentation, selected: homeV2TimelineSelection, currentOwnership: ownership,
                  currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
              ) else { return [] }
        let steps = homeV2StepsText(for: metric)
        let stepsState = homeV2StepsReader.state(
            for: metric, ownership: ownership, ownsSession: authManager.ownsAccountSession
        )
        let stepsAreLoading: Bool
        if case .loading = stepsState { stepsAreLoading = true } else { stepsAreLoading = false }
        return HomeV2ProgressMetric.allCases.map { kind in
            let reading = presentation.reading(for: kind, system: currentMeasurementSystem, steps: steps)
            let shareKind: ContextualMetricKind
            switch kind {
            case .bodyFat: shareKind = .bodyFat
            case .weight: shareKind = .weight
            case .ffmi: shareKind = .ffmi
            case .steps: shareKind = .steps
            }
            return ContextualMetricSnapshot(
                kind: shareKind, value: reading.value ?? "—", unit: reading.unit,
                observation: selection.date.formatted(date: .abbreviated, time: .shortened),
                range: "", trend: nil,
                provenance: reading.evidence == nil ? nil : reading.explanation,
                evidence: reading.detail, isLoading: kind == .steps && stepsAreLoading
            )
        }
    }

    var isHomeV2PhotoScrubNavigating: Bool {
        isHomeV2TimelineCovered || isHomeV2ViewerPresented || homeV2PhotoRoute != nil
    }

    var isHomeV2PhotoViewerForeground: Bool {
        !isHomeV2TimelineCovered && isHomeV2ViewerPresented && homeV2PhotoRoute == nil
    }

    private var isHomeV2TimelineCovered: Bool {
        !isHomeV2PhotoHomeForeground || !isHomeV2SceneActive || hasHomeV2CompetingPresentation
    }

    var isHomeV2PhotoHomeForeground: Bool {
        selectedPhotoTimelineRootPage == .timeline && !isHomeChatExpanded
    }

    var hasHomeV2CompetingPresentation: Bool {
            isShowingPhotoTimelineMenu || isHomeV2ContextPresented ||
            isHomeV2EntriesPresented || isHomeV2AllPhotosPresented || isHomeV2SettingsPresented ||
            isHomeV2HelpPresented || showAddEntrySheet || isMetricDetailActive || isStatsDestinationActive ||
            bodyScoreSharePayload != nil || showsScreenshotShareChoice || showSyncDetails ||
            isProgressPhotoAttachPresented || isPhotoTimelineSettingsPresented || homeV2EditingMetric != nil ||
            showsHomeV2UndoError
    }

    /// Each real opening gets its own identity before SwiftUI presents the cover.
    func presentHomeV2PhotoViewer() {
        guard !isHomeV2PhotoScrubNavigating, hasCurrentDashboardPublication,
              let ownership = authManager.captureAccountSession(),
              let selection = homeV2TimelineSelection,
              let presentation = homeV2Timeline.presentation(
                  for: selection, heightCm: nil, currentOwnership: ownership
              ), homeV2Timeline.admitsPhotoPresentation(
                  presentation, selected: selection, currentOwnership: ownership,
                  currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
              ) else { return }
        homeV2PhotoViewerOpeningID = UUID()
        isHomeV2ViewerPresented = true
    }

    func admitsHomeV2PhotoViewer(_ admission: HomeV2TimelinePolicy.PhotoViewerAdmission) -> Bool {
        admission.admits(
            currentOpeningID: homeV2PhotoViewerOpeningID,
            visibility: .init(
                isPresented: isHomeV2ViewerPresented,
                isHomeForeground: isHomeV2PhotoHomeForeground,
                isActive: isHomeV2SceneActive,
                hasCompetingPresentation: hasHomeV2CompetingPresentation,
                hasChildRoute: homeV2PhotoRoute != nil,
                hasCurrentDashboardPublication: hasCurrentDashboardPublication
            ),
            currentSelection: homeV2TimelineSelection,
            currentOwnership: authManager.captureAccountSession(),
            currentMetrics: bodyMetrics, currentSnapshot: homeV2Timeline
        )
    }

    /// The ID remains authoritative when a background refresh inserts, reorders or deletes rows.
    func reconcileHomeV2Timeline(with metrics: [BodyMetrics]) {
        guard layoutMode == .photoTimelineHUD, HomeV2Policy.isEnabled() else { return }
        let ownership = authManager.captureAccountSession()
        let snapshot = HomeV2TimelinePolicy.Snapshot(
            metrics: metrics, owner: ownership?.subject, ownership: ownership
        )
        let selected = snapshot.reconcile(homeV2TimelineSelection)
        homeV2Timeline = snapshot
        homeV2TimelineSelection = selected
        selectedIndex = selected.flatMap { snapshot.sourceIndex(for: $0.id) } ?? 0
    }

    func recordHomeV2TimelineSelection(at index: Int) {
        guard layoutMode == .photoTimelineHUD, HomeV2Policy.isEnabled(),
              let ownership = authManager.captureAccountSession(), homeV2Timeline.isOwned(by: ownership),
              let selection = homeV2Timeline.selection(atSourceIndex: index),
              selection.id.owner == authManager.currentUser?.id else { return }
        homeV2TimelineSelection = selection
    }

    func selectHomeV2TimelineEntry(_ id: HomeV2TimelinePolicy.EntryID) {
        guard let ownership = authManager.captureAccountSession(),
              homeV2Timeline.isOwned(by: ownership), id.owner == ownership.subject,
              let index = homeV2Timeline.sourceIndex(for: id),
              let selection = homeV2Timeline.selection(atSourceIndex: index) else { return }
        homeV2TimelineSelection = selection
        selectedIndex = index
    }

    /// Loading, offline or Apple Health off, in that order; nil when all is well.
    var homeV2SystemState: HomeV2SystemState? {
        let isAuthorized = HealthKitManager.shared.isAuthorized
        HomeV2SystemStatePolicy.recordAuthorization(isAuthorized)
        return HomeV2SystemStatePolicy.state(
            hasLoadedInitialData: hasLoadedCurrentDashboardData,
            isOnline: realtimeSyncManager.isOnline,
            healthSyncEnabled: UserDefaults.standard.object(forKey: Constants.healthKitSyncEnabledKey) as? Bool ?? true,
            healthAuthorized: isAuthorized,
            healthEverAuthorized: UserDefaults.standard.bool(forKey: HomeV2SystemStatePolicy.everAuthorizedKey),
            hasHealthData: bodyMetrics.contains { $0.metricSource == .healthKit }
        )
    }

    /// H0, shown instead of the legacy empty state while the gate is on.
    var homeV2DayZero: some View {
        let date = Date()
        let steps = homeV2StepsText(on: date)
        return HomeV2DayZero(
            stepsValue: steps.value,
            stepsDetail: steps.detail,
            onViewSteps: { openHomeV2Progress(metric: .steps) },
            onConnectHealth: {
                Task { _ = await HealthKitManager.shared.requestAuthorization() }
            },
            onLogWeight: { presentHomeV2LogSheet(initialTab: 1) }
        )
        .task(id: homeV2StepsRequest(on: date)) {
            guard let ownership = authManager.captureAccountSession() else { return }
            await homeV2StepsReader.load(
                date: date, ownership: ownership, ownsSession: authManager.ownsAccountSession
            )
        }
    }

    struct HomeV2StepsRequest: Hashable {
        let key: HomeV2DailyStepsReader.Key?
        let revisions: [String]
    }

    /// Refresh after a real daily-row publication, including a corrected same-day total.
    func homeV2StepsRequest(on date: Date) -> HomeV2StepsRequest {
        let ownership = authManager.captureAccountSession()
        let rows = recentDailyMetrics + (dailyMetrics.map { [$0] } ?? [])
        return HomeV2StepsRequest(
            key: homeV2StepsReader.key(for: date, ownership: ownership),
            revisions: rows.filter {
                $0.userId == ownership?.subject && Calendar.current.isDate($0.date, inSameDayAs: date)
            }.map { "\($0.id)|\($0.steps.map(String.init) ?? "nil")|\($0.updatedAt.timeIntervalSince1970)" }.sorted()
        )
    }

    func homeV2StepsText(for metric: BodyMetrics) -> (value: String, detail: String) {
        let state = homeV2StepsReader.state(
            for: metric, ownership: authManager.captureAccountSession(), ownsSession: authManager.ownsAccountSession
        )
        return homeV2StepsText(state)
    }

    func homeV2StepsText(on date: Date) -> (value: String, detail: String) {
        let state = homeV2StepsReader.state(
            for: date, ownership: authManager.captureAccountSession(), ownsSession: authManager.ownsAccountSession
        )
        return homeV2StepsText(state)
    }

    private func homeV2StepsText(_ state: HomeV2DailyStepsReader.State) -> (value: String, detail: String) {
        switch state {
        case .loading: return ("—", "Loading steps…")
        case .missing: return ("—", "No step data")
        case .value(let value): return (value.formatted(), "Daily total")
        }
    }

    func presentHomeV2LogSheet(for date: Date = Date(), initialTab: Int = 0) {
        let existing = homeV2Metric(on: date)
        let latestKilograms = existing?.weight.flatMap {
            HomeV2WeightQuality.isWithinSupportedLoggingRange($0) ? $0 : nil
        } ?? bodyMetrics.filter {
            $0.date <= date && HomeV2WeightQuality.isWithinSupportedLoggingRange($0.weight)
        }.max { $0.date < $1.date }?.weight
        let initial = latestKilograms.map { convertWeight($0, to: currentMeasurementSystem) ?? $0 }
            ?? HomeV2WeightStepPolicy.defaultValue(unit: homeV2DisplayUnit)
        HapticManager.shared.selection()
        presentAddEntrySheet(
            initialTab: initialTab,
            date: date,
            weight: HomeV2WeightStepPolicy.text(initial),
            bodyFat: existing?.bodyFatPercentage,
            bodyFatMethod: existing?.bodyFatMethod,
            isHomeV2LoggingWeight: true
        )
    }

    @MainActor
    func handleHomeV2BodyFatEntrySaved(_ saved: BodyMetrics) {
        guard isHomeV2LoggingWeight, saved.userId == authManager.currentUser?.id else { return }
        // Body fat has its own save; a prior weight receipt must not describe it.
        homeV2Logged = nil
        Task { @MainActor in
            await refreshHomeV2AfterWrite(selecting: saved.id)
        }
    }

    @MainActor
    func handleHomeV2WeightEntrySaved(_ result: PhotoMetricsUpdateResult) {
        let saved = result.metrics
        guard isHomeV2LoggingWeight, saved.userId == authManager.currentUser?.id else { return }
        if Calendar.current.isDateInToday(saved.date), let userId = authManager.currentUser?.id {
            let value = saved.weight.map { convertWeight($0, to: currentMeasurementSystem) ?? $0 } ?? 0
            homeV2Logged = HomeV2LoggedEntry(
                metricId: saved.id,
                userId: userId,
                date: saved.date,
                previousMetric: result.previousMetric,
                valueText: HomeV2WeightStepPolicy.text(value),
                unit: homeV2DisplayUnit,
                savedMetric: saved
            )
            BodyScoreCache.shared.invalidate(for: userId)
        }

        Task { @MainActor in
            await refreshHomeV2AfterWrite(selecting: saved.id)
        }
    }

    /// Saves a weight (and optional body fat) for a day. Today gets the C2
    /// logged state with Undo; other days just save and refresh.
    @MainActor
    func saveHomeV2Weight(value: Double, bodyFat: Double?, on date: Date = Date()) async -> Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        let kilograms = currentMeasurementSystem == .imperial ? value.lbsToKg : value

        do {
            let result = try await PhotoMetadataService.shared.createOrUpdateMetricsWithResult(
                for: date,
                weight: kilograms,
                bodyFatPercentage: bodyFat,
                bodyFatMethod: bodyFat == nil ? nil : BodyFatEntryMethod.bioelectrical.rawValue,
                userId: userId
            )
            let saved = result.metrics
            RealtimeSyncManager.shared.syncIfNeeded()
            BodyScoreCache.shared.invalidate(for: userId)
            BodyScoreRecalculationService.shared.scheduleRecalculation()
            HapticManager.shared.successAction()

            if Calendar.current.isDateInToday(saved.date) {
                homeV2Logged = HomeV2LoggedEntry(
                    metricId: saved.id,
                    userId: userId,
                    date: saved.date,
                    previousMetric: result.previousMetric,
                    valueText: HomeV2WeightStepPolicy.text(value),
                    unit: homeV2DisplayUnit,
                    savedMetric: saved
                )
            }
            await refreshHomeV2AfterWrite(selecting: saved.id)
            return true
        } catch {
            return false
        }
    }

    /// C2 Undo: put the day back the way it was. A day that existed keeps its
    /// entry with the previous numbers; a day created by this log is deleted.
    @MainActor
    func undoHomeV2Logged() async {
        guard !isHomeV2Undoing, let logged = homeV2Logged,
              let userId = authManager.currentUser?.id, logged.userId == userId else { return }
        isHomeV2Undoing = true
        defer { isHomeV2Undoing = false }

        do {
            if let previous = logged.previousMetric {
                try await PhotoMetadataService.shared.restoreMeasurements(
                    id: logged.metricId,
                    userId: userId,
                    previous: previous,
                    replacing: logged.savedMetric
                )
            } else {
                guard await RealtimeSyncManager.shared.deleteBodyMetric(id: logged.metricId) else {
                    showsHomeV2UndoError = true
                    return
                }
            }
        } catch {
            showsHomeV2UndoError = true
            return
        }

        if homeV2Logged == logged { homeV2Logged = nil }
        RealtimeSyncManager.shared.syncIfNeeded()
        BodyScoreCache.shared.invalidate(for: userId)
        BodyScoreRecalculationService.shared.scheduleRecalculation()
        HapticManager.shared.selection()
        await refreshHomeV2AfterWrite(selecting: nil)
    }

    @MainActor
    func refreshHomeV2AfterWrite(selecting id: String?) async {
        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: realtimeSyncManager
        )
        refreshGlobalTimelineStore()

        if let id, let index = bodyMetrics.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
            updateAnimatedValues(for: index)
        } else if !bodyMetrics.isEmpty {
            selectedIndex = min(selectedIndex, bodyMetrics.count - 1)
            updateAnimatedValues(for: selectedIndex)
        }
    }
}
