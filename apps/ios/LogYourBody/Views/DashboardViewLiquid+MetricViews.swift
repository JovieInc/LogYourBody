//
//  DashboardViewLiquid+MetricViews.swift
//  LogYourBody
//

import SwiftUI

extension DashboardViewLiquid {
    var metricsView: some View {
        let stepsGoalText: String? = {
            let formatted = FormatterCache.stepsFormatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal)"
            return "Goal \(formatted) steps"
        }()

        let weightGoalText: String? = {
            guard let goal = weightGoal else { return nil }
            let system = currentMeasurementSystem
            let converted = convertWeight(goal, to: system) ?? goal
            let formatted = String(format: "%.1f", converted)
            return "Target \(formatted) \(weightUnit)"
        }()

        let bodyFatGoalText: String? = {
            let formatted = String(format: "%.1f%%", bodyFatGoal)
            return "Target \(formatted)"
        }()

        let ffmiGoalText: String? = {
            let formatted = String(format: "%.1f", ffmiGoal)
            return "Target \(formatted)"
        }()

        return DashboardMetricsSection(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            onReorder: saveMetricsOrder,
            selectedRange: $selectedRange,
            selectedMetricType: $selectedMetricType,
            isMetricDetailActive: $isMetricDetailActive,
            currentMetric: currentMetric,
            bodyMetrics: bodyMetrics,
            dailyMetrics: dailyMetrics,
            weightUnit: weightUnit,
            stepsGoalText: stepsGoalText,
            weightGoalText: weightGoalText,
            bodyFatGoalText: bodyFatGoalText,
            ffmiGoalText: ffmiGoalText,
            generateStepsChartData: generateStepsChartData,
            generateWeightChartData: generateWeightChartData,
            generateBodyFatChartData: generateBodyFatChartData,
            generateFFMIChartData: generateFFMIChartData,
            weightRangeStats: weightRangeStats,
            bodyFatRangeStats: bodyFatRangeStats,
            ffmiRangeStats: ffmiRangeStats,
            formatSteps: formatSteps,
            formatWeightValue: formatWeightValue,
            formatBodyFatValue: formatBodyFatValue,
            formatFFMIValue: formatFFMIValue,
            makeTrend: makeTrend,
            formatAverageFootnote: formatAverageFootnote,
            formatCardDateOnly: formatCardDateOnly,
            formatCardDate: formatCardDate,
            latestStepsSnapshot: latestStepsSnapshot,
            weightUsesTrend: $weightUsesTrend,
            formatTrendWeightHeadline: formatTrendWeightHeadline
        )
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    var fullMetricChartView: some View {
        switch selectedMetricType {
        case .steps:
            FullMetricChartView(
                title: "Steps",
                icon: "flame.fill",
                iconColor: Color.metricAccentSteps,
                currentValue: formatSteps(dailyMetrics?.steps),
                unit: "steps",
                currentDate: formatDate(dailyMetrics?.updatedAt ?? Date()),
                chartData: cachedChartData(for: .steps, generator: generateFullScreenStepsChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .steps),
                goalValue: Double(stepGoal),
                selectedTimeRange: $selectedRange
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: Color.metricAccentWeight,
                currentValue: currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .weight, generator: generateFullScreenWeightChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .weight),
                goalValue: weightGoal,
                selectedTimeRange: $selectedRange
            )

        case .bodyFat:
            FullMetricChartView(
                title: "Body Fat %",
                icon: "percent",
                iconColor: Color.metricAccentBodyFat,
                currentValue: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–",
                unit: "%",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyFat, generator: generateFullScreenBodyFatChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .bodyFat),
                goalValue: bodyFatGoal,
                selectedTimeRange: $selectedRange
            )

        case .ffmi:
            FullMetricChartView(
                title: "FFMI",
                icon: "figure.arms.open",
                iconColor: Color.metricAccentFFMI,
                currentValue: currentMetric.map { formatFFMIValue($0) } ?? "–",
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .ffmi, generator: generateFullScreenFFMIChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .ffmi),
                goalValue: ffmiGoal,
                selectedTimeRange: $selectedRange
            )

        case .bodyScore:
            let bodyScore = bodyScoreText()
            FullMetricChartView(
                title: "Body Score",
                icon: "star.fill",
                iconColor: Color.metricAccent,
                currentValue: bodyScore.scoreText,
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyScore, generator: generateFullScreenBodyScoreChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .bodyScore),
                goalValue: nil,
                selectedTimeRange: $selectedRange
            )

        case .glp1:
            let sortedLogs = glp1DoseLogs.sorted { $0.takenAt < $1.takenAt }
            let latestLog = sortedLogs.last
            let currentDose = latestLog?.doseAmount
            let currentValue = currentDose.map { String(format: "%.1f", $0) } ?? "–"
            let unit = latestLog?.doseUnit ?? "mg"
            let currentDate = latestLog.map { formatDate($0.takenAt) } ?? formatDate(Date())

            FullMetricChartView(
                title: "GLP-1 Dose",
                icon: "syringe",
                iconColor: Color.metricAccent,
                currentValue: currentValue,
                unit: unit,
                currentDate: currentDate,
                chartData: cachedChartData(for: .glp1, generator: generateFullScreenGlp1ChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: nil,
                goalValue: nil,
                selectedTimeRange: $selectedRange
            )
        }
    }
}
