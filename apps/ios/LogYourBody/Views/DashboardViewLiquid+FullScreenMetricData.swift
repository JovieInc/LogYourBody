import SwiftUI
import Foundation

extension DashboardViewLiquid {
    func bodyScoreEntriesPayload() -> MetricEntriesPayload? {
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 0)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                guard let result = bodyScoreResult(for: metric) else { return nil }
                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: Double(result.score),
                    secondaryValue: nil,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .bodyScore,
            unitLabel: "",
            secondaryUnitLabel: nil,
            primaryFormatter: primaryFormatter,
            secondaryFormatter: nil
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    // Full-screen chart data helpers use the **entire** history and real dates
    // so that time ranges (W/M/6M/Y) can filter by date window.

    func generateFullScreenStepsChartData() -> [MetricChartDataPoint] {
        buildFullScreenStepsChartData(from: recentDailyMetrics)
    }

    func generateFullScreenWeightChartData() -> [MetricChartDataPoint] {
        buildFullScreenWeightChartData(
            from: sortedBodyMetricsAscending,
            measurementSystem: currentMeasurementSystem
        )
    }

    func generateFullScreenBodyFatChartData() -> [MetricChartDataPoint] {
        buildFullScreenBodyFatChartData(
            sortedBodyMetrics: sortedBodyMetricsAscending,
            bodyMetrics: bodyMetrics
        )
    }

    func generateFullScreenFFMIChartData() -> [MetricChartDataPoint] {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return [] }

        return buildFullScreenFFMIChartData(
            sortedBodyMetrics: sortedBodyMetricsAscending,
            bodyMetrics: bodyMetrics,
            heightInches: heightInches
        )
    }

    func generateFullScreenGlp1ChartData() -> [MetricChartDataPoint] {
        guard !glp1DoseLogs.isEmpty else { return [] }

        return glp1DoseLogs
            .sorted { $0.takenAt < $1.takenAt }
            .compactMap { log in
                guard let dose = log.doseAmount else { return nil }
                return MetricChartDataPoint(
                    date: log.takenAt,
                    value: dose
                )
            }
    }

    func generateFullScreenBodyScoreChartData() -> [MetricChartDataPoint] {
        guard !sortedBodyMetricsAscending.isEmpty else { return [] }

        return sortedBodyMetricsAscending
            .compactMap { metric in
                guard let result = bodyScoreResult(for: metric) else {
                    return nil
                }

                return MetricChartDataPoint(
                    date: metric.date,
                    value: Double(result.score),
                    isEstimated: false
                )
            }
    }

    func convertHeightToInches(height: Double?, heightUnit: String?) -> Double? {
        guard let height, height > 0 else { return nil }
        return height / 2.54
    }

    func convertWeight(_ weight: Double, to system: MeasurementSystem) -> Double? {
        switch system {
        case .metric:
            return weight
        case .imperial:
            return weight * 2.20462
        }
    }

    @MainActor
    func prewarmMetricCaches() async {
        guard !sortedBodyMetricsAscending.isEmpty || !recentDailyMetrics.isEmpty || !glp1DoseLogs.isEmpty else {
            fullChartCache = [:]
            metricEntriesCache = [:]
            return
        }

        fullChartCache = [:]
        metricEntriesCache = [:]

        let sortedMetrics = sortedBodyMetricsAscending
        let bodyMetricsSnapshot = bodyMetrics
        let recentDailySnapshot = recentDailyMetrics
        let measurementSystemSnapshot = currentMeasurementSystem
        let profileSnapshot = authManager.currentUser?.profile
        let heightSnapshot = authManager.currentUser?.profile?.height
        let heightUnitSnapshot = authManager.currentUser?.profile?.heightUnit
        let heightInchesSnapshot = convertHeightToInches(
            height: heightSnapshot,
            heightUnit: heightUnitSnapshot
        )

        let (chartCache, bodyScoreEntries) = await Task.detached(
            priority: .utility
        ) { () -> ([MetricType: [MetricChartDataPoint]], MetricEntriesPayload?) in
            var cache: [MetricType: [MetricChartDataPoint]] = [:]
            var bodyScoreEntries: MetricEntriesPayload?

            let stepsData = buildFullScreenStepsChartData(from: recentDailySnapshot)
            if !stepsData.isEmpty {
                cache[.steps] = stepsData
            }

            let weightData = buildFullScreenWeightChartData(
                from: sortedMetrics,
                measurementSystem: measurementSystemSnapshot
            )
            if !weightData.isEmpty {
                cache[.weight] = weightData
            }

            let bodyFatData = buildFullScreenBodyFatChartData(
                sortedBodyMetrics: sortedMetrics,
                bodyMetrics: bodyMetricsSnapshot
            )
            if !bodyFatData.isEmpty {
                cache[.bodyFat] = bodyFatData
            }

            if let heightInchesSnapshot {
                let ffmiData = buildFullScreenFFMIChartData(
                    sortedBodyMetrics: sortedMetrics,
                    bodyMetrics: bodyMetricsSnapshot,
                    heightInches: heightInchesSnapshot
                )
                if !ffmiData.isEmpty {
                    cache[.ffmi] = ffmiData
                }
            }

            if let profileSnapshot {
                let bodyScoreResult = buildBodyScoreChartAndEntriesData(
                    sortedBodyMetrics: sortedMetrics,
                    bodyMetrics: bodyMetricsSnapshot,
                    profile: profileSnapshot,
                    measurementSystem: measurementSystemSnapshot
                )

                if !bodyScoreResult.chartPoints.isEmpty {
                    cache[.bodyScore] = bodyScoreResult.chartPoints
                }

                bodyScoreEntries = bodyScoreResult.entriesPayload
            }

            return (cache, bodyScoreEntries)
        }.value

        fullChartCache = chartCache

        if let bodyScoreEntries {
            metricEntriesCache[.bodyScore] = bodyScoreEntries
        }
    }

    @MainActor
    func loadGlp1DoseLogs() async {
        guard let userId = authManager.currentUser?.id else {
            glp1DoseLogs = []
            await prewarmMetricCaches()
            return
        }

        do {
            // Load from local cache first for offline support
            let cachedLogs = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
            if !cachedLogs.isEmpty {
                glp1DoseLogs = cachedLogs.sorted { $0.takenAt < $1.takenAt }
            }

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
                if cachedLogs.isEmpty {
                    glp1DoseLogs = [glp1WeeklyCheckInFixtureDoseLog(userId: userId)]
                }
                await prewarmMetricCaches()
                return
            }
            #endif

            // Always attempt a remote refresh when possible
            let logs = try await SupabaseManager.shared.fetchGlp1DoseLogs(userId: userId, limit: 200)
            glp1DoseLogs = logs.sorted { $0.takenAt < $1.takenAt }
            CoreDataManager.shared.saveGlp1DoseLogs(logs, userId: userId)
        } catch {
            // Ignore errors; fall back to cached logs if available
        }

        await prewarmMetricCaches()
    }

    @MainActor
    func loadGlp1Medications() async {
        guard let userId = authManager.currentUser?.id else {
            glp1Medications = []
            return
        }

        let cached = await CoreDataManager.shared.fetchGlp1Medications(for: userId)
        if !cached.isEmpty {
            glp1Medications = cached.sorted { $0.startedAt < $1.startedAt }
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
            if cached.isEmpty {
                glp1Medications = [glp1WeeklyCheckInFixtureMedication(userId: userId)]
            }
            return
        }
        #endif

        do {
            let medications = try await SupabaseManager.shared.fetchGlp1Medications(userId: userId)
            glp1Medications = medications.sorted { $0.startedAt < $1.startedAt }
            CoreDataManager.shared.saveGlp1Medications(medications, userId: userId)
        } catch {
            // Keep cached medications when the network is unavailable.
        }
    }

    @MainActor
    func loadGlp1WeeklyCheckInData() async {
        await loadGlp1Medications()
        await loadGlp1DoseLogs()
    }

    #if DEBUG
    private func glp1WeeklyCheckInFixtureMedication(userId: String) -> Glp1Medication {
        let calendar = Calendar.current
        let now = Date()
        let startedAt = calendar.date(byAdding: .day, value: -42, to: now) ?? now

        return Glp1Medication(
            id: "ui_test_glp1_medication",
            userId: userId,
            displayName: "Zepbound",
            genericName: "tirzepatide",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.zepbound.weekly",
            startedAt: startedAt,
            endedAt: nil,
            notes: nil,
            createdAt: startedAt,
            updatedAt: now
        )
    }

    private func glp1WeeklyCheckInFixtureDoseLog(userId: String) -> Glp1DoseLog {
        let calendar = Calendar.current
        let now = Date()
        let lastDoseDate = calendar.date(byAdding: .day, value: -9, to: now) ?? now

        return Glp1DoseLog(
            id: "ui_test_glp1_dose_due",
            userId: userId,
            takenAt: calendar.startOfDay(for: lastDoseDate),
            medicationId: "ui_test_glp1_medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: "UI test weekly check-in seed",
            createdAt: lastDoseDate,
            updatedAt: now
        )
    }
    #endif
}

private func buildFullScreenStepsChartData(from recentDailyMetrics: [DailyMetrics]) -> [MetricChartDataPoint] {
    guard !recentDailyMetrics.isEmpty else { return [] }

    return recentDailyMetrics
        .sorted { $0.date < $1.date }
        .compactMap { metric in
            guard let steps = metric.steps else { return nil }
            return MetricChartDataPoint(
                date: metric.date,
                value: Double(max(steps, 0)),
                isEstimated: false
            )
        }
}

private func buildFullScreenWeightChartData(
    from sortedBodyMetricsAscending: [BodyMetrics],
    measurementSystem: MeasurementSystem
) -> [MetricChartDataPoint] {
    return sortedBodyMetricsAscending
        .compactMap { metric in
            guard let weight = metric.weight else { return nil }

            let converted: Double
            switch measurementSystem {
            case .metric:
                converted = weight
            case .imperial:
                converted = weight * 2.20462
            }

            return MetricChartDataPoint(
                date: metric.date,
                value: converted
            )
        }
}

private func buildFullScreenBodyFatChartData(
    sortedBodyMetrics: [BodyMetrics],
    bodyMetrics: [BodyMetrics]
) -> [MetricChartDataPoint] {
    let interpolationContext = MetricsInterpolationService.shared
        .makeBodyFatInterpolationContext(for: bodyMetrics)

    return sortedBodyMetrics
        .compactMap { metric in
            if let bf = metric.bodyFatPercentage {
                return MetricChartDataPoint(
                    date: metric.date,
                    value: bf,
                    isEstimated: false
                )
            }

            if let estimated = interpolationContext?.estimate(for: metric.date) {
                return MetricChartDataPoint(
                    date: metric.date,
                    value: estimated.value,
                    isEstimated: true
                )
            }

            return nil
        }
}

private func buildFullScreenFFMIChartData(
    sortedBodyMetrics: [BodyMetrics],
    bodyMetrics: [BodyMetrics],
    heightInches: Double
) -> [MetricChartDataPoint] {
    guard let interpolationContext = MetricsInterpolationService.shared
        .makeFFMIInterpolationContext(for: bodyMetrics, heightInches: heightInches) else {
        return []
    }

    return sortedBodyMetrics
        .compactMap { metric in
            guard let ffmiResult = interpolationContext.estimate(for: metric.date) else {
                return nil
            }

            return MetricChartDataPoint(
                date: metric.date,
                value: ffmiResult.value,
                isEstimated: ffmiResult.isInterpolated
            )
        }
}

private func buildBodyScoreChartAndEntriesData(
    sortedBodyMetrics: [BodyMetrics],
    bodyMetrics: [BodyMetrics],
    profile: UserProfile,
    measurementSystem: MeasurementSystem
) -> (chartPoints: [MetricChartDataPoint], entriesPayload: MetricEntriesPayload?) {
    guard !sortedBodyMetrics.isEmpty else {
        return ([], nil)
    }

    let genderString = profile.gender?.lowercased() ?? ""
    let sex: BiologicalSex
    if genderString.contains("female") || genderString.contains("woman") {
        sex = .female
    } else if genderString.contains("male") || genderString.contains("man") {
        sex = .male
    } else {
        return ([], nil)
    }

    let calendar = Calendar.current
    guard let dateOfBirth = profile.dateOfBirth else {
        return ([], nil)
    }
    let birthYear = calendar.component(.year, from: dateOfBirth)

    guard let heightCm = profile.height, heightCm > 0 else {
        return ([], nil)
    }

    let heightValue = HeightValue(value: heightCm, unit: .centimeters)

    let interpolationService = MetricsInterpolationService.shared
    let weightContext = interpolationService.makeWeightInterpolationContext(for: bodyMetrics)
    let bodyFatContext = interpolationService.makeBodyFatInterpolationContext(for: bodyMetrics)

    let calculator = BodyScoreCalculator()

    var chartPoints: [MetricChartDataPoint] = []
    var entries: [MetricHistoryEntry] = []

    for metric in sortedBodyMetrics {
        let bodyFat: Double
        if let direct = metric.bodyFatPercentage {
            bodyFat = direct
        } else if let estimated = bodyFatContext?.estimate(for: metric.date)?.value {
            bodyFat = estimated
        } else {
            continue
        }

        let trendWeightValue = weightContext?.trendWeight(for: metric.date)?.value
        let weightKg: Double
        if let trend = trendWeightValue {
            weightKg = trend
        } else if let raw = metric.weight {
            weightKg = raw
        } else {
            continue
        }

        let weightValue = WeightValue(value: weightKg, unit: .kilograms)
        let bodyFatValue = BodyFatValue(percentage: bodyFat, source: .manualValue)
        let healthSnapshot = HealthImportSnapshot(
            heightCm: heightCm,
            weightKg: weightKg,
            bodyFatPercentage: bodyFat,
            birthYear: birthYear
        )

        let input = BodyScoreInput(
            sex: sex,
            birthYear: birthYear,
            height: heightValue,
            weight: weightValue,
            bodyFat: bodyFatValue,
            measurementPreference: measurementSystem,
            healthSnapshot: healthSnapshot
        )

        guard input.isReadyForCalculation else {
            continue
        }

        let context = BodyScoreCalculationContext(input: input, calculationDate: metric.date)

        guard let result = try? calculator.calculateScore(context: context) else {
            continue
        }

        let scoreValue = Double(result.score)

        chartPoints.append(
            MetricChartDataPoint(
                date: metric.date,
                value: scoreValue,
                isEstimated: false
            )
        )

        let normalizedSource = metric.dataSource?.lowercased() ?? ""
        let sourceType: MetricEntrySourceType
        if normalizedSource.contains("healthkit") || normalizedSource.contains("health") {
            sourceType = .healthKit
        } else if normalizedSource.isEmpty || normalizedSource == "manual" {
            sourceType = .manual
        } else {
            sourceType = .integration(id: metric.dataSource)
        }

        let entry = MetricHistoryEntry(
            id: metric.id,
            date: metric.date,
            primaryValue: scoreValue,
            secondaryValue: nil,
            source: sourceType
        )
        entries.append(entry)
    }

    guard !chartPoints.isEmpty else {
        return ([], nil)
    }

    let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 0)

    let config = MetricEntriesConfiguration(
        metricType: .bodyScore,
        unitLabel: "",
        secondaryUnitLabel: nil,
        primaryFormatter: primaryFormatter,
        secondaryFormatter: nil
    )

    let payload: MetricEntriesPayload? = entries.isEmpty ? nil : MetricEntriesPayload(config: config, entries: entries)

    return (chartPoints, payload)
}
