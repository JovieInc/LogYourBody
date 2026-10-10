//
// DashboardViewLiquid+HomeV2.swift
// LogYourBody
//
import SwiftUI

extension DashboardViewLiquid {
    /// Home v2 owns the Today page: v2 chrome, no chat composer, the check-in dock.
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

    /// Photo-first Home behind `HomeV2Policy`; the legacy `LaunchTimelineSurface`
    /// keeps serving when the gate is off.
    func homeV2Surface(for metric: BodyMetrics) -> some View {
        let unit = homeV2DisplayUnit

        return HomeV2Surface(
            metric: metric,
            bodyMetrics: homeV2Timeline.metrics,
            timeline: homeV2Timeline,
            selectedID: Binding(get: { HomeV2TimelinePolicy.EntryID(metric) }, set: selectHomeV2TimelineEntry),
            weightValue: HomeV2EditorialPolicy.displayWeight(in: metric, system: currentMeasurementSystem)
                .map { String(format: "%.1f", $0) } ?? "—",
            weightUnit: unit,
            ffmiValue: homeV2FFMIValue(metric).map { String(format: "%.1f", $0) },
            stepsValue: homeV2StepsText(for: metric).value,
            stepsDetail: homeV2StepsText(for: metric).detail,
            changeSentence: homeV2Timeline.weightChangeSentence(
                for: HomeV2TimelinePolicy.EntryID(metric), system: currentMeasurementSystem
            ),
            dateText: { formatHUDDate($0.date) },
            loggedSentence: homeV2Logged.map { HomeV2Copy.loggedSentence(value: $0.valueText, unit: $0.unit) },
            systemState: homeV2SystemState,
            onOpenPhoto: { isHomeV2ViewerPresented = true },
            onViewProgress: { openHomeV2Progress() },
            onViewMetric: { openHomeV2Progress(metric: $0) },
            onTodayDetails: { openHomeV2Context() },
            onAllPhotos: { isHomeV2AllPhotosPresented = true },
            onLogWeight: { presentHomeV2LogSheet(for: metric.date, initialTab: 1) },
            onConnectHealth: {
                Task { _ = await HealthKitManager.shared.requestAuthorization() }
            },
            onDone: { homeV2Logged = nil },
            onUndo: { Task { await undoHomeV2Logged() } }
        )
        .task(id: homeV2StepsRequest(on: metric.date)) {
            guard let ownership = authManager.captureAccountSession() else { return }
            await homeV2StepsReader.load(
                metric: metric, ownership: ownership, ownsSession: authManager.ownsAccountSession
            )
        }
        // The whole-history chart series are built off the main actor by
        // prewarmMetricCaches; never regenerate them inside body. The caches
        // reset to [:] whenever metrics change, so this re-warms on demand.
        .task(id: bodyMetrics.count) {
            if fullChartCache[.weight] == nil {
                await prewarmMetricCaches()
            }
            let insight = PhaseInsightPolicy.insight(for: bodyMetrics)
            homeV2PhaseSentence = HomeV2Copy.phaseSentence(
                kind: insight.kind,
                weeks: HomeV2PhasePolicy.weeks(kind: insight.kind, metrics: bodyMetrics)
            )
        }
    }

    /// The ID remains authoritative when a background refresh inserts, reorders or deletes rows.
    func reconcileHomeV2Timeline(with metrics: [BodyMetrics]) {
        guard layoutMode == .photoTimelineHUD, HomeV2Policy.isEnabled() else { return }
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: metrics, owner: authManager.currentUser?.id)
        let selected = snapshot.reconcile(homeV2TimelineSelection)
        homeV2Timeline = snapshot
        homeV2TimelineSelection = selected
        selectedIndex = selected.flatMap { snapshot.sourceIndex(for: $0.id) } ?? 0
    }

    func recordHomeV2TimelineSelection(at index: Int) {
        guard layoutMode == .photoTimelineHUD, HomeV2Policy.isEnabled(),
              let selection = homeV2Timeline.selection(atSourceIndex: index),
              selection.id.owner == authManager.currentUser?.id else { return }
        homeV2TimelineSelection = selection
    }

    func selectHomeV2TimelineEntry(_ id: HomeV2TimelinePolicy.EntryID) {
        guard id.owner == authManager.currentUser?.id,
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
            hasLoadedInitialData: viewModel.hasLoadedInitialData,
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
        homeV2LogSheetDate = date
        let existing = homeV2Metric(on: date)
        let latestKilograms = existing?.weight
            ?? bodyMetrics.filter { $0.weight != nil && $0.date <= date }.max { $0.date < $1.date }?.weight
        let initial = latestKilograms.map { convertWeight($0, to: currentMeasurementSystem) ?? $0 }
            ?? HomeV2WeightStepPolicy.defaultValue(unit: homeV2DisplayUnit)
        homeV2LogHadExistingEntry = existing != nil
        homeV2LogPreviousWeightKilograms = existing?.weight
        homeV2LogPreviousBodyFat = existing?.bodyFatPercentage
        HapticManager.shared.selection()
        presentAddEntrySheet(
            initialTab: initialTab,
            date: date,
            weight: HomeV2WeightStepPolicy.text(initial),
            bodyFat: existing?.bodyFatPercentage,
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
    func handleHomeV2WeightEntrySaved(_ saved: BodyMetrics) {
        guard isHomeV2LoggingWeight else { return }
        if Calendar.current.isDateInToday(homeV2LogSheetDate), let userId = authManager.currentUser?.id {
            let value = saved.weight.map { convertWeight($0, to: currentMeasurementSystem) ?? $0 } ?? 0
            homeV2Logged = HomeV2LoggedEntry(
                metricId: saved.id,
                date: saved.date,
                existedBefore: homeV2LogHadExistingEntry,
                previousWeightKilograms: homeV2LogPreviousWeightKilograms,
                previousBodyFat: homeV2LogPreviousBodyFat,
                valueText: HomeV2WeightStepPolicy.text(value),
                unit: homeV2DisplayUnit
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
        let before = homeV2Metric(on: date)

        do {
            let saved = try await PhotoMetadataService.shared.createOrUpdateMetrics(
                for: date,
                weight: kilograms,
                bodyFatPercentage: bodyFat,
                bodyFatMethod: bodyFat == nil ? nil : BodyFatEntryMethod.bioelectrical.rawValue,
                userId: userId
            )
            RealtimeSyncManager.shared.syncIfNeeded()
            BodyScoreCache.shared.invalidate(for: userId)
            BodyScoreRecalculationService.shared.scheduleRecalculation()
            HapticManager.shared.successAction()

            if Calendar.current.isDateInToday(date) {
                homeV2Logged = HomeV2LoggedEntry(
                    metricId: saved.id,
                    date: saved.date,
                    existedBefore: before != nil,
                    previousWeightKilograms: before?.weight,
                    previousBodyFat: before?.bodyFatPercentage,
                    valueText: HomeV2WeightStepPolicy.text(value),
                    unit: homeV2DisplayUnit
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
        guard let logged = homeV2Logged, let userId = authManager.currentUser?.id else { return }
        homeV2Logged = nil

        if logged.existedBefore {
            // ponytail: createOrUpdate cannot clear a field, so a day that had no weight keeps the new one.
            _ = try? await PhotoMetadataService.shared.createOrUpdateMetrics(
                for: logged.date,
                weight: logged.previousWeightKilograms,
                bodyFatPercentage: logged.previousBodyFat,
                userId: userId
            )
        } else {
            await RealtimeSyncManager.shared.deleteBodyMetric(id: logged.metricId)
        }

        RealtimeSyncManager.shared.syncIfNeeded()
        BodyScoreCache.shared.invalidate(for: userId)
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
