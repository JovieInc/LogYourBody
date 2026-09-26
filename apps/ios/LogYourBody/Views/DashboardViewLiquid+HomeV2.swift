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

    /// The plain v2 chrome (sidebar glyph, titles) on every v2 root page.
    var isHomeV2Chrome: Bool {
        HomeV2Policy.isEnabled() && !isHomeChatExpanded
    }

    var homeV2DisplayUnit: String {
        HomeV2Copy.displayUnit(currentMeasurementSystem)
    }

    var homeV2TodayMetric: BodyMetrics? {
        bodyMetrics.first { Calendar.current.isDateInToday($0.date) }
    }

    var homeV2LatestPhotoMetric: BodyMetrics? {
        bodyMetrics
            .filter { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }
            .max { $0.date < $1.date }
    }

    /// Photo-first Home behind `HomeV2Policy`; the legacy `LaunchTimelineSurface`
    /// keeps serving when the gate is off.
    func homeV2Surface(for metric: BodyMetrics) -> some View {
        let unit = homeV2DisplayUnit

        return HomeV2Surface(
            metric: metric,
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            weightValue: formatTrendWeightHeadline(metric, usesTrend: weightUsesTrend),
            weightUnit: unit,
            changeSentence: HomeV2Copy.changeSentence(delta: heroWeightDelta30d(), unit: unit),
            phaseSentence: homeV2PhaseSentence,
            loggedSentence: homeV2Logged.map { HomeV2Copy.loggedSentence(value: $0.valueText, unit: $0.unit) },
            latestPhotoCaption: homeV2LatestPhotoMetric.map { HomeV2Copy.latestPhotoCaption(date: formatHUDDate($0.date)) },
            systemState: homeV2SystemState,
            chartDaily: fullChartCache[.weight] ?? [],
            chartTrend: fullTrendChartCache[.weight] ?? [],
            onOpenPhoto: { isHomeV2ViewerPresented = true },
            onViewProgress: { openHomeV2Progress(metric: .weight) },
            onTodayDetails: { openHomeV2Context() },
            onAllPhotos: { isHomeV2AllPhotosPresented = true },
            onLogWeight: { presentHomeV2LogSheet() },
            onConnectHealth: {
                Task { _ = await HealthKitManager.shared.requestAuthorization() }
            },
            onDone: { homeV2Logged = nil },
            onUndo: { Task { await undoHomeV2Logged() } }
        )
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
        HomeV2DayZero(
            onConnectHealth: {
                Task { _ = await HealthKitManager.shared.requestAuthorization() }
            },
            onLogWeight: { presentHomeV2LogSheet() }
        )
    }

    func presentHomeV2LogSheet(for date: Date = Date()) {
        homeV2LogSheetDate = date
        HapticManager.shared.selection()
        isHomeV2LogSheetPresented = true
    }

    /// Presented from `photoTimelineRoot` like the viewer, so the sheet's
    /// presentation context is the HUD's own.
    var homeV2LogWeightSheet: some View {
        let system = currentMeasurementSystem
        let unit = homeV2DisplayUnit
        let date = homeV2LogSheetDate
        let isToday = Calendar.current.isDateInToday(date)
        let existing = homeV2Metric(on: date)
        let latestKilograms = existing?.weight
            ?? bodyMetrics.filter { $0.weight != nil && $0.date <= date }.max { $0.date < $1.date }?.weight
        let initial = latestKilograms.map { convertWeight($0, to: system) ?? $0 }
            ?? HomeV2WeightStepPolicy.defaultValue(unit: unit)

        return HomeV2LogWeightSheet(
            unit: unit,
            initialValue: initial,
            initialBodyFat: existing?.bodyFatPercentage,
            dateText: isToday ? HomeV2Copy.todayDateText(Date()) : HomeV2ContextCopy.entryDateText(date),
            onSave: { value, bodyFat in
                await saveHomeV2Weight(value: value, bodyFat: bodyFat, on: date)
            },
            onAddPhoto: { _ in
                // ponytail: the pose-guided camera (Pencil L2) lands in the photo slice; until then the
                // existing attach sheet takes the photo for today.
                isHomeV2LogSheetPresented = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    presentProgressPhotoAttach(for: homeV2Metric(on: date))
                }
            }
        )
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
