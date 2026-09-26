//
// DashboardViewLiquid+HomeV2.swift
// LogYourBody
//
import SwiftUI

extension DashboardViewLiquid {
    /// Photo-first Home behind `HomeV2Policy`; the legacy `LaunchTimelineSurface`
    /// keeps serving when the gate is off.
    func homeV2Surface(for metric: BodyMetrics) -> some View {
        let unit = currentMeasurementSystem.weightUnit

        return HomeV2Surface(
            metric: metric,
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            weightValue: formatTrendWeightHeadline(metric, usesTrend: weightUsesTrend),
            weightUnit: unit,
            changeSentence: HomeV2Copy.changeSentence(delta: heroWeightDelta30d(), unit: unit),
            bodyFatValue: heroBodyFatValue(),
            bodyFatDetail: HomeV2Copy.compactChange(delta: heroBodyFatDelta30d(), unit: "pts"),
            ffmiValue: heroFFMIValue(),
            ffmiDetail: HomeV2Copy.compactChange(delta: heroFFMIDelta30d(), unit: ""),
            onAddPhoto: { presentProgressPhotoAttach(for: metric) },
            onTapBodyFat: {
                selectedMetricType = .bodyFat
                isMetricDetailActive = true
            },
            onTapFFMI: {
                selectedMetricType = .ffmi
                isMetricDetailActive = true
            },
            onOpenPhoto: { isHomeV2ViewerPresented = true },
            chartDaily: fullChartCache[.weight] ?? [],
            chartTrend: fullTrendChartCache[.weight] ?? [],
            selectedRange: $selectedRange
        )
        // The whole-history chart series are built off the main actor by
        // prewarmMetricCaches; never regenerate them inside body. The caches
        // reset to [:] whenever metrics change, so this re-warms on demand.
        .task(id: bodyMetrics.count) {
            if fullChartCache[.weight] == nil {
                await prewarmMetricCaches()
            }
        }
    }

    /// Presented from `photoTimelineRoot`, the same level as the menu cover, so
    /// the presentation context is the HUD's own.
    var homeV2PhotoViewer: some View {
        HomeV2PhotoViewer(
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            formatters: homeV2Formatters(unit: currentMeasurementSystem.weightUnit),
            onClose: { isHomeV2ViewerPresented = false }
        )
    }

    private func homeV2Formatters(unit: String) -> HomeV2Formatters {
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
            weightUnit: unit
        )
    }
}
