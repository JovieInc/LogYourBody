//
// DashboardViewLiquid+HomeV2Context.swift
// LogYourBody
//
import SwiftUI

/// Record identity and account lifetime are captured together at the Edit action.
struct HomeV2EditSession: Identifiable {
    let metric: BodyMetrics
    let owner: AuthManager.ProfileSessionOwnership
    var id: String { metric.id }

    /// Compare with the sheet's displayed values, not its higher-precision source.
    /// A retained field is a nil patch; the stored raw value stays authoritative.
    func measurementReplacements(
        value: Double, bodyFat: Double?, initialDisplayedWeight: Double
    ) -> (weight: Double?, bodyFat: Double?) {
        let displayedWeight = HomeV2WeightStepPolicy.parse(HomeV2WeightStepPolicy.text(initialDisplayedWeight))
        let displayedBodyFat = metric.bodyFatPercentage.flatMap {
            HomeV2WeightStepPolicy.parse(String(format: "%.1f", $0))
        }
        return (value == displayedWeight ? nil : value, bodyFat == displayedBodyFat ? nil : bodyFat)
    }
}

extension DashboardViewLiquid {
    func homeV2Metric(on date: Date) -> BodyMetrics? {
        bodyMetrics.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func openHomeV2Context(on date: Date = Date()) {
        homeV2ContextDay = date
        HapticManager.shared.selection()
        isHomeV2ContextPresented = true
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
    var homeV2ContextView: some View {
        HomeV2ContextView(
            bodyMetrics: bodyMetrics,
            selectedDay: $homeV2ContextDay,
            detail: { homeV2DayDetail(for: $0) },
            onClose: { isHomeV2ContextPresented = false },
            onEditEntry: { metric in
                guard let owner = authManager.captureAccountSession(), owner.subject == metric.userId else { return }
                homeV2EditingSession = HomeV2EditSession(metric: metric, owner: owner)
            },
            onLogWeight: { presentHomeV2LogSheet(for: $0) },
            onAddPhoto: { presentProgressPhotoAttach(for: $0) },
            onOpenPhoto: { metric in
                if let index = bodyMetrics.firstIndex(where: { $0.id == metric.id }) {
                    selectedIndex = index
                }
                isHomeV2ViewerPresented = true
            }
        )
    }

    /// Entries (Pencil E0).
    var homeV2EntriesView: some View {
        let system = currentMeasurementSystem
        return HomeV2EntriesView(
            sections: HomeV2EntriesPolicy.sections(
                metrics: bodyMetrics,
                unit: homeV2DisplayUnit,
                weightValue: { metric in metric.weight.map { convertWeight($0, to: system) ?? $0 } },
                hasPhoto: { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }
            ),
            onSelect: { date in openHomeV2Context(on: date) },
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
                subline: HomeV2Provenance.subline(for: metric),
                value: "\(HomeV2WeightStepPolicy.text(value)) \(unit)"
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

        if let metric, let weight = metric.weight, let bodyFat = metric.bodyFatPercentage {
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

        if let steps = dailyMetricsLookup()[calendar.startOfDay(for: date)]?.steps, steps > 0 {
            rows.append(HomeV2DayEntryRow(
                id: "steps",
                label: HomeV2ContextCopy.steps,
                subline: HomeV2ContextCopy.appleHealth,
                value: FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
            ))
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
    func homeV2EditEntrySheet(for session: HomeV2EditSession) -> some View {
        let metric = session.metric
        let system = currentMeasurementSystem
        let unit = homeV2DisplayUnit
        let initial = metric.weight.map { convertWeight($0, to: system) ?? $0 }
            ?? HomeV2WeightStepPolicy.defaultValue(unit: unit)

        return HomeV2LogWeightSheet(
            mode: .edit,
            unit: unit,
            initialValue: initial,
            initialBodyFat: metric.bodyFatPercentage,
            dateText: HomeV2ContextCopy.entryDateText(metric.date),
            deleteScope: HomeV2ContextCopy.deleteBody(
                date: formatHUDDate(metric.date),
                includesPhoto: PhotoTimelineHUDPolicy.hasUsablePhoto(metric)
            ),
            existingPhotoURL: PhotoTimelineHUDPolicy.hasUsablePhoto(metric) ? metric.photoUrl : nil,
            onSave: { value, bodyFat in
                let replacement = session.measurementReplacements(
                    value: value, bodyFat: bodyFat, initialDisplayedWeight: initial
                )
                let kilograms = replacement.weight.map { system == .imperial ? $0.lbsToKg : $0 }
                return await saveHomeV2Entry(
                    weightKilograms: kilograms, bodyFat: replacement.bodyFat, session: session,
                    displayValue: value, displayUnit: unit
                )
            },
            onDelete: {
                guard authManager.ownsAccountSession(session.owner) else { return false }
                return await deleteHomeV2Entry(metric)
            },
            onAddPhoto: { _ in
                guard authManager.ownsAccountSession(session.owner) else { return }
                homeV2EditingSession = nil
                Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                    guard authManager.ownsAccountSession(session.owner), isHomeV2ContextPresented else { return }
                    presentProgressPhotoAttach(for: metric)
                }
            }
        )
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
