//
//  DashboardViewLiquid+MetricViews.swift
//  LogYourBody
//

import SwiftUI

extension DashboardViewLiquid {
    var metricDetailSelectedDateBinding: Binding<Date?> {
        Binding(
            get: {
                currentMetric?.date
            },
            set: { newDate in
                guard let newDate else { return }
                selectClosestMetric(to: newDate)
            }
        )
    }

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
                iconColor: theme.colors.accentOrange,
                currentValue: formatSteps(dailyMetrics?.steps),
                unit: "steps",
                currentDate: formatDate(dailyMetrics?.updatedAt ?? Date()),
                chartData: cachedChartData(for: .steps, generator: generateFullScreenStepsChartData),
                onAdd: nil,
                metricEntries: cachedMetricEntries(for: .steps),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .steps),
                goalValue: Double(stepGoal),
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: theme.colors.accentViolet,
                currentValue: currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .weight, generator: generateFullScreenWeightChartData),
                onAdd: {
                    presentAddEntrySheet(initialTab: 0)
                },
                metricEntries: cachedMetricEntries(for: .weight),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .weight),
                goalValue: weightGoal,
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
            )

        case .bodyFat:
            FullMetricChartView(
                title: "Body Fat %",
                icon: "percent",
                iconColor: theme.colors.accentPink,
                currentValue: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–",
                unit: "%",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyFat, generator: generateFullScreenBodyFatChartData),
                onAdd: {
                    presentAddEntrySheet(initialTab: 1)
                },
                metricEntries: cachedMetricEntries(for: .bodyFat),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .bodyFat),
                goalValue: bodyFatGoal,
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
            )

        case .ffmi:
            FullMetricChartView(
                title: "FFMI",
                icon: "figure.arms.open",
                iconColor: theme.colors.accentTeal,
                currentValue: currentMetric.map { formatFFMIValue($0) } ?? "–",
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .ffmi, generator: generateFullScreenFFMIChartData),
                onAdd: nil,
                metricEntries: cachedMetricEntries(for: .ffmi),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .ffmi),
                goalValue: ffmiGoal,
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
            )

        case .bodyScore:
            let bodyScore = bodyScoreText()
            FullMetricChartView(
                title: "Body Score",
                icon: "star.fill",
                iconColor: theme.colors.primary,
                currentValue: bodyScore.scoreText,
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyScore, generator: generateFullScreenBodyScoreChartData),
                onAdd: nil,
                metricEntries: cachedMetricEntries(for: .bodyScore),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .bodyScore),
                goalValue: nil,
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
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
                iconColor: theme.colors.primary,
                currentValue: currentValue,
                unit: unit,
                currentDate: currentDate,
                chartData: cachedChartData(for: .glp1, generator: generateFullScreenGlp1ChartData),
                onAdd: {
                    presentAddEntrySheet(initialTab: 3, includesGlp1Entry: true)
                },
                metricEntries: nil,
                relatedMetrics: metricDetailRelatedMetrics(excluding: .glp1),
                goalValue: nil,
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding
            )
        }
    }

    func metricDetailRelatedMetrics(excluding selected: MetricType) -> [MetricDetailRelatedMetric] {
        guard let currentMetric else { return [] }

        var items: [MetricDetailRelatedMetric] = []

        func append(
            _ metricType: MetricType,
            id: String,
            title: String,
            value: String,
            caption: String,
            systemImageName: String
        ) {
            guard metricType != selected else { return }
            items.append(
                MetricDetailRelatedMetric(
                    id: id,
                    title: title,
                    value: value,
                    caption: caption,
                    systemImageName: systemImageName
                )
            )
        }

        let latestSteps = latestStepsSnapshot()
        append(
            .steps,
            id: "steps",
            title: "Steps",
            value: formatSteps(latestSteps.value),
            caption: formatCardDateOnly(latestSteps.date) ?? "No steps yet",
            systemImageName: "flame.fill"
        )

        append(
            .weight,
            id: "weight",
            title: "Weight",
            value: "\(formatTrendWeightHeadline(currentMetric, usesTrend: weightUsesTrend)) \(weightUnit)",
            caption: formatCardDate(currentMetric.date),
            systemImageName: "figure.stand"
        )

        append(
            .bodyFat,
            id: "body_fat",
            title: "Body Fat",
            value: "\(formatBodyFatValue(currentMetric.bodyFatPercentage))%",
            caption: formatCardDate(currentMetric.date),
            systemImageName: "percent"
        )

        append(
            .ffmi,
            id: "ffmi",
            title: "FFMI",
            value: formatFFMIValue(currentMetric),
            caption: formatCardDate(currentMetric.date),
            systemImageName: "figure.arms.open"
        )

        if let bodyScore = bodyScoreResult(for: currentMetric) {
            append(
                .bodyScore,
                id: "body_score",
                title: "Body Score",
                value: "\(bodyScore.score)",
                caption: bodyScore.statusTagline,
                systemImageName: "star.fill"
            )
        }

        return items
    }
}
