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
        let summaries = metricTruthSummaries
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
            guard let bodyFatGoal else { return nil }
            let formatted = String(format: "%.1f%%", bodyFatGoal)
            return "Target \(formatted)"
        }()

        let ffmiGoalText: String? = {
            guard let ffmiGoal else { return nil }
            let formatted = String(format: "%.1f", ffmiGoal)
            return "Target \(formatted)"
        }()

        return DashboardMetricsSection(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            onReorder: saveMetricsOrder,
            truthSummaries: summaries,
            truthSnapshots: metricTruthSnapshots(summaries: summaries),
            truthSyncText: metricTruthSyncText,
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
        .onAppear { requestForegroundHealthRefresh() }
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
                currentDate: formatDate(dailyMetrics?.date ?? Date()),
                chartData: cachedChartData(for: .steps, generator: generateFullScreenStepsChartData),
                onAdd: nil,
                metricEntries: cachedMetricEntries(for: .steps),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .steps),
                goalValue: Double(stepGoal),
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible,
                synchronizationText: metricTruthSyncText
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: theme.colors.accentViolet,
                currentValue: currentMetric.map {
                    formatTrendWeightHeadline($0, usesTrend: weightUsesTrend)
                } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .weight, generator: generateFullScreenWeightChartData),
                trendChartData: cachedTrendChartData(
                    for: .weight,
                    generator: generateFullScreenWeightTrendChartData
                ),
                onAdd: {
                    presentAddEntrySheet(initialTab: 0)
                },
                metricEntries: cachedMetricEntries(for: .weight),
                relatedMetrics: metricDetailRelatedMetrics(excluding: .weight),
                goalValue: weightGoal.flatMap { convertWeight($0, to: currentMeasurementSystem) },
                selectedTimeRange: $selectedRange,
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible,
                initialChartMode: weightUsesTrend ? .trend : .raw,
                synchronizationText: metricTruthSyncText
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
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible,
                synchronizationText: metricTruthSyncText
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
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible,
                synchronizationText: metricTruthSyncText
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
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible
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
                selectedTimelineDate: metricDetailSelectedDateBinding,
                shareSnapshots: dashboardMetricShareSnapshots,
                isShareContextVisible: isMetricShareContextVisible
            )
        }
    }

    /// Owner state gates the receiver even when SwiftUI keeps a covered view mounted.
    var isMetricShareContextVisible: Bool {
        authManager.captureAccountSession().map { dashboardMetricsBelong(to: $0) } == true
            && !showAddEntrySheet && !showSyncDetails && !isProgressPhotoAttachPresented
            && !isPhotoTimelineSettingsPresented && !isHomeV2ViewerPresented
            && !isHomeV2ContextPresented && !isHomeV2EntriesPresented && !isHomeV2MetricProvenancePresented
            && !isHomeV2SettingsPresented && !isHomeV2HelpPresented && !isHomeV2AllPhotosPresented
            && !isShowingPhotoTimelineMenu && homeV2EditingSession == nil && !showsHomeV2UndoError
            && bodyScoreSharePayload == nil && !isHomeChatExpanded
    }

    var dashboardMetricShareSnapshots: [ContextualMetricSnapshot] {
        if MetricStatsTruthPolicy.isEnabled() {
            return metricTruthSnapshots(summaries: metricTruthSummaries).filter(\.isAvailable)
        }
        let date = currentMetric.map { formatDate($0.date) } ?? ""
        let source = currentMetric.map { HomeV2Provenance.label(for: $0, field: .bodyFat) }
        let range = selectedRange.accessibilityLabel
        var snapshots = [
            ContextualMetricSnapshot.steps(dailyMetrics, value: formatSteps(dailyMetrics?.steps), range: range),
            ContextualMetricSnapshot.weight(
                currentMetric, metrics: bodyMetrics, prefersTrend: weightUsesTrend,
                context: (unit: weightUnit, observation: date, range: range),
                formatValue: { kilograms in
                    let value = convertWeight(kilograms, to: currentMeasurementSystem) ?? kilograms
                    return String(format: "%.1f", value)
                }),
            ContextualMetricSnapshot(
                kind: .bodyFat,
                value: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "—",
                unit: "%", observation: date, range: range, trend: nil,
                provenance: currentMetric?.bodyFatPercentage == nil ? nil : source,
                evidence: ContextualMetricEvidencePolicy.label(
                    for: .bodyFat, isEstimated: currentMetric?.bodyFatPercentage == nil,
                    bodyFatMethod: currentMetric?.attributedBodyFatMethod)),
            ContextualMetricSnapshot(
                kind: .ffmi, value: currentMetric.map { formatFFMIValue($0) } ?? "—",
                unit: "", observation: date, range: range, trend: nil,
                provenance: "Weight, body fat and height", evidence: ContextualMetricEvidencePolicy.label(for: .ffmi))
        ]
        let score = bodyScoreText()
        if score.score > 0 {
            snapshots.append(ContextualMetricSnapshot(
                kind: .bodyScore, value: score.scoreText, unit: "",
                observation: date, range: range, trend: heroBodyScoreDeltaText(), provenance: nil,
                evidence: ContextualMetricEvidencePolicy.label(for: .bodyScore)))
        }
        return snapshots.filter(\.isAvailable)
    }

    var metricTruthSyncText: String {
        MetricStatsTruthPolicy.synchronizationText(
            status: syncStatusTitle, lastCloudSync: realtimeSyncManager.lastSyncDate,
            healthAccessStatus: HealthKitManager.shared.authorizationStatusText)
    }

    var metricTruthSummaries: [ContextualMetricKind: MetricObservationSummary] {
        guard MetricStatsTruthPolicy.isEnabled() else { return [:] }
        let now = Date()
        return [
            .steps: MetricObservationSummary(points: generateFullScreenStepsChartData(), range: selectedRange, now: now),
            .weight: MetricObservationSummary(
                points: generateFullScreenWeightChartData(), range: selectedRange, selectedDate: currentMetric?.date, now: now),
            .bodyFat: MetricObservationSummary(
                points: generateFullScreenBodyFatChartData(), range: selectedRange, selectedDate: currentMetric?.date, now: now),
            .ffmi: MetricObservationSummary(
                points: generateFullScreenFFMIChartData(), range: selectedRange, selectedDate: currentMetric?.date, now: now)
        ]
    }

    func metricTruthSnapshots(summaries: [ContextualMetricKind: MetricObservationSummary]) -> [ContextualMetricSnapshot] {
        summaries.compactMap { kind, summary in
            let source: String?
            switch kind {
            case .steps: source = "Apple Health"
            case .ffmi: source = "Derived from smoothed weight, body fat and height"
            default:
                let entries = kind == .weight ? weightEntriesPayload()?.entries : bodyFatEntriesPayload()?.entries
                source = ContextualMetricSourcePolicy.source(for: summary.point, entries: entries ?? [], fallback: nil)
                    ?? "Source unavailable or mixed"
            }
            return ContextualMetricSnapshot.observationSummary(
                summary, kind: kind,
                unit: kind == .steps ? "steps" : (kind == .weight ? weightUnit : (kind == .bodyFat ? "%" : "")),
                provenance: source
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
