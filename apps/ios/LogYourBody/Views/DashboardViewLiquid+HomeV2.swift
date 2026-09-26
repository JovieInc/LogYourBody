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
            }
        )
    }
}
