import XCTest
@testable import LogYourBody

// swiftlint:disable single_test_class

final class DashboardMetricFormattingTests: XCTestCase {
    func testComputeRangeStatsSortsMetricsAndSkipsMissingValues() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = [
            metric(id: "latest", date: baseDate.addingTimeInterval(2 * 86_400), weight: 80),
            metric(id: "missing", date: baseDate.addingTimeInterval(86_400), weight: nil),
            metric(id: "earliest", date: baseDate, weight: 100)
        ]

        let stats = computeRangeStats(metrics: metrics, valueProvider: \.weight)

        XCTAssertEqual(stats?.startValue, 100)
        XCTAssertEqual(stats?.endValue, 80)
        XCTAssertEqual(stats?.delta, -20)
        XCTAssertEqual(stats?.average, 90)
        XCTAssertEqual(stats?.percentageChange, -20)
    }

    func testComputeRangeStatsHandlesNoValuesAndZeroBaseline() {
        XCTAssertNil(computeRangeStats(metrics: [metric(id: "missing", weight: nil)], valueProvider: \.weight))

        let stats = computeRangeStats(
            metrics: [metric(id: "zero", weight: 0), metric(id: "later", date: Date().addingTimeInterval(1), weight: 10)],
            valueProvider: \.weight
        )

        XCTAssertEqual(stats?.percentageChange, 0)
    }

    func testTrendAndDeltaFormattingCarryDirectionAndUnits() {
        let gain = makeTrend(delta: 1.26, unit: "kg", range: .month1)
        XCTAssertEqual(gain?.direction, .up)
        XCTAssertEqual(gain?.valueText, "1.3 kg")
        XCTAssertEqual(gain?.caption, "1M")

        let unchanged = makeTrend(delta: 0.0005, unit: "%", range: .week1)
        XCTAssertEqual(unchanged?.direction, .flat)
        XCTAssertEqual(unchanged?.valueText, "No change")
        XCTAssertEqual(formatDelta(delta: -2.5, unit: "%"), "–2.5%")
        XCTAssertEqual(formatAverageFootnote(value: 72, unit: "kg"), "72 kg average")
    }

    func testTimeRangeLabelsAndFormatterCacheAreStable() {
        XCTAssertEqual(TimeRange.week1.shortRelativeLabel, "7d")
        XCTAssertEqual(TimeRange.month3.shortRelativeLabel, "3M")
        XCTAssertEqual(TimeRange.year1.shortRelativeLabel, "1Y")
        XCTAssertEqual(TimeRange.all.shortRelativeLabel, "All")

        let first = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 2)
        let second = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 2)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.string(from: 1.2), "1.2")
    }

    private func metric(
        id: String,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        weight: Double?
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

final class ChartSeriesPreprocessorTests: XCTestCase {
    func testRangeMetadataDescribesEverySelectableRange() {
        XCTAssertEqual(ChartMode.trend.label, "Smoothed")
        XCTAssertEqual(ChartMode.raw.label, "Raw")
        XCTAssertEqual(TimeRange.week1.days, 7)
        XCTAssertEqual(TimeRange.month1.days, 30)
        XCTAssertEqual(TimeRange.month3.days, 90)
        XCTAssertEqual(TimeRange.month6.days, 180)
        XCTAssertEqual(TimeRange.year1.days, 365)
        XCTAssertNil(TimeRange.all.days)
    }

    func testPreprocessorSortsFiltersAndDownsamplesWhileKeepingEndpoints() throws {
        let calendar = Calendar.current
        let referenceDate = calendar.date(
            from: DateComponents(year: 2_025, month: 6, day: 30, hour: 12)
        )!
        let points = (0..<400).compactMap { offset -> MetricChartDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else {
                return nil
            }
            return MetricChartDataPoint(
                date: date,
                value: Double(offset),
                isEstimated: offset == 200
            )
        }
        let preprocessor = ChartSeriesPreprocessor(referenceDate: referenceDate)

        let series = preprocessor.seriesByRange(from: Array(points.reversed()))

        let week = try XCTUnwrap(series[.week1])
        let month = try XCTUnwrap(series[.month1])
        let year = try XCTUnwrap(series[.year1])
        let all = try XCTUnwrap(series[.all])

        XCTAssertEqual(week.count, 8)
        XCTAssertEqual(week.first?.value, 7)
        XCTAssertEqual(week.last?.value, 0)
        XCTAssertEqual(month.count, 31)
        XCTAssertEqual(month.first?.value, 30)
        XCTAssertEqual(month.last?.value, 0)
        XCTAssertEqual(year.count, 260)
        XCTAssertEqual(year.first?.value, 365)
        XCTAssertEqual(year.last?.value, 0)
        XCTAssertEqual(all.count, 320)
        XCTAssertEqual(all.first?.value, 399)
        XCTAssertEqual(all.last?.value, 0)
        XCTAssertTrue(all.allSatisfy { $0.date <= referenceDate })
    }
}

final class LocalPersistenceTests: XCTestCase {
    func testPreAuthStoreRoundTripsAndClearsInputAndResult() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreAuthOnboardingStore(userDefaults: defaults, storageKey: "pre-auth")
        let input = bodyScoreInput()
        let result = bodyScoreResult(score: 78)

        store.save(input: input, result: result)

        let loaded = store.load()
        XCTAssertEqual(loaded?.0, input)
        XCTAssertEqual(loaded?.1, result)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testBodyScoreCachePersistsResultsPerUserAcrossInstances() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = BodyScoreCache(userDefaults: defaults, storageKey: "scores")
        let firstUserResult = bodyScoreResult(score: 71)
        let secondUserResult = bodyScoreResult(score: 89)
        cache.store(firstUserResult, for: "first-user")
        cache.store(secondUserResult, for: "second-user")
        cache.store(bodyScoreResult(score: 99), for: nil)

        XCTAssertEqual(cache.latestResult(for: "first-user"), firstUserResult)
        XCTAssertEqual(cache.latestResult(for: "second-user"), secondUserResult)
        XCTAssertNil(cache.latestResult(for: nil))

        let rehydratedCache = BodyScoreCache(userDefaults: defaults, storageKey: "scores")
        XCTAssertEqual(rehydratedCache.latestResult(for: "first-user"), firstUserResult)
        XCTAssertEqual(rehydratedCache.latestResult(for: "second-user"), secondUserResult)
    }

    func testEntryVisibilityIsUserScopedAndResolvesSameHourConflictsBySourcePriority() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = EntryVisibilityManager(userDefaults: defaults, storageKey: "hidden")
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let health = metric(
            id: "health",
            date: baseDate.addingTimeInterval(15 * 60),
            dataSource: "HealthKit",
            updatedAt: baseDate.addingTimeInterval(10)
        )
        let manual = metric(
            id: "manual",
            date: baseDate.addingTimeInterval(45 * 60),
            dataSource: "manual",
            updatedAt: baseDate
        )
        let nextHour = metric(
            id: "next-hour",
            date: baseDate.addingTimeInterval(90 * 60),
            dataSource: "integration",
            updatedAt: baseDate
        )

        manager.hide(entryId: "next-hour", userId: "first-user")

        XCTAssertTrue(manager.isHidden(entryId: "next-hour", userId: "first-user"))
        XCTAssertFalse(manager.isHidden(entryId: "next-hour", userId: "second-user"))

        let firstUser = manager.prepareMetricsForDisplay([health, manual, nextHour], userId: "first-user")
        XCTAssertEqual(firstUser.hidden.map(\.id), ["next-hour"])
        XCTAssertEqual(firstUser.visible.map(\.id), ["manual"])

        let secondUser = manager.prepareMetricsForDisplay([health, manual, nextHour], userId: "second-user")
        XCTAssertEqual(secondUser.visible.map(\.id), ["next-hour", "manual"])

        manager.unhide(entryId: "next-hour", userId: "first-user")
        XCTAssertFalse(manager.isHidden(entryId: "next-hour", userId: "first-user"))
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "LogYourBodyTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        return (defaults, suiteName)
    }

    private func bodyScoreInput() -> BodyScoreInput {
        BodyScoreInput(
            sex: .female,
            birthYear: 1_990,
            height: HeightValue(value: 170, unit: .centimeters),
            weight: WeightValue(value: 65, unit: .kilograms),
            bodyFat: BodyFatValue(percentage: 24, source: .manualValue),
            measurementPreference: .metric,
            healthSnapshot: HealthImportSnapshot(
                heightCm: 170,
                weightKg: 65,
                bodyFatPercentage: 24,
                birthYear: 1_990
            )
        )
    }

    private func bodyScoreResult(score: Int) -> BodyScoreResult {
        BodyScoreResult(
            score: score,
            ffmi: 18.5,
            leanPercentile: 0.75,
            ffmiStatus: "Strong",
            targetBodyFat: .init(lowerBound: 20, upperBound: 25, label: "Healthy range"),
            statusTagline: "On track"
        )
    }

    private func metric(
        id: String,
        date: Date,
        dataSource: String,
        updatedAt: Date
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: 70,
            weightUnit: "kg",
            bodyFatPercentage: 20,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: dataSource,
            createdAt: date,
            updatedAt: updatedAt
        )
    }
}

final class MedicationAndPresentationModelTests: XCTestCase {
    func testMedicationCatalogUsesCaseInsensitiveBrandThenGenericThenFallback() {
        let wegovy = medication(brand: "wEgOvY", genericName: nil, doseUnit: nil)
        XCTAssertEqual(Glp1MedicationCatalog.doseConfig(for: wegovy).unit, "mg/week")
        XCTAssertEqual(Glp1MedicationCatalog.doseConfig(for: wegovy).doses.last, 2.4)

        let generic = medication(brand: nil, genericName: "dulaglutide", doseUnit: nil)
        XCTAssertEqual(Glp1MedicationCatalog.doseConfig(for: generic).doses, [0.75, 1.5, 3, 4.5])

        let fallback = medication(brand: "Unknown", genericName: "unknown", doseUnit: "mg/day")
        XCTAssertEqual(Glp1MedicationCatalog.doseConfig(for: fallback).unit, "mg/day")
        XCTAssertEqual(Glp1MedicationCatalog.doseConfig(for: fallback).doses, [0.25, 0.5, 1, 1.5, 2, 2.5])
    }

    func testDailyLogAndDashboardPresentationModelsDescribeAvailableData() {
        let log = DailyLog(userId: "user", date: Date(), weight: 72.45, weightUnit: "kg", stepCount: 12_345)
        XCTAssertEqual(log.formattedWeight, "72.5")
        XCTAssertEqual(log.formattedSteps, "12,345")
        XCTAssertEqual(log.displayWeightUnit, "kg")
        XCTAssertTrue(log.hasData)
        XCTAssertFalse(DailyLog(userId: "user", date: Date()).hasData)

        XCTAssertEqual(DashboardDisplayMode.photo.title, "Progress Photos")
        XCTAssertFalse(DashboardDisplayMode.photo.isChartMode)
        XCTAssertTrue(DashboardDisplayMode.ffmiChart.isChartMode)
        XCTAssertEqual(MetricType.bodyFat.unit, "%")
        XCTAssertEqual(TimelineMode.avatar.displayName, "Avatar Mode")
        XCTAssertEqual(TimelineMode.photo.icon, "photo")
    }

    func testTimelineResultUsesNearbyPhotoAndFlagsMaterialDateMismatch() {
        let now = Date()
        let photoMetric = metric(id: "photo", date: now.addingTimeInterval(-86_400))
        let oldMetric = metric(id: "metric", date: now.addingTimeInterval(-4 * 86_400))
        let result = TimelineDataResult(
            scrubDate: now,
            photo: .init(bodyMetrics: photoMetric, daysFromScrub: -1),
            metrics: .init(bodyMetrics: oldMetric, daysFromScrub: -4, isInterpolated: false)
        )

        XCTAssertEqual(result.displayDate, photoMetric.date)
        XCTAssertTrue(result.hasDateMismatch)
        XCTAssertTrue(result.formattedDateLabel().contains("Photo:"))
    }

    func testAppErrorMapsUserFacingMessagesAndSeverity() {
        let network = AppError.network(operation: "uploading your photo", underlying: nil)
        XCTAssertEqual(
            network.errorDescription,
            "A network error occurred while uploading your photo. Please check your connection and try again."
        )
        XCTAssertTrue(network.isUserFacing)
        guard case .warning = network.severity else {
            return XCTFail("Network errors should be warnings")
        }

        let unexpected = AppError.unexpected(context: "test", underlying: TestError())
        XCTAssertEqual(unexpected.errorDescription, "Something went wrong. Please try again.")
        XCTAssertFalse(unexpected.isUserFacing)
        guard case .critical = unexpected.severity else {
            return XCTFail("Unexpected errors should be critical")
        }
    }

    private func medication(brand: String?, genericName: String?, doseUnit: String?) -> Glp1Medication {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Glp1Medication(
            id: UUID().uuidString,
            userId: "user",
            displayName: brand ?? genericName ?? "Unknown",
            genericName: genericName,
            drugClass: nil,
            brand: brand,
            route: nil,
            frequency: nil,
            doseUnit: doseUnit,
            isCompounded: false,
            hkIdentifier: nil,
            startedAt: date,
            endedAt: nil,
            notes: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private func metric(id: String, date: Date) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private struct TestError: Error {}
}

final class GlobalTimelineServiceTests: XCTestCase {
    func testMonthlyBucketsAggregateDirectValuesAndInterpolateShortGaps() {
        let service = GlobalTimelineService(calendar: calendar)
        let metrics = recentWeeklyMetrics + [
            metric(id: "july-1", date: date("2025-07-10"), weight: 70),
            metric(id: "july-2", date: date("2025-07-20"), weight: 74),
            metric(id: "september", date: date("2025-09-15"), weight: 76)
        ]

        let buckets = service.makeBuckets(for: .month, metrics: metrics)

        XCTAssertEqual(buckets.map(\.id), ["2025-07", "2025-08", "2025-09"])
        XCTAssertEqual(buckets[0].metrics.weight, GlobalTimelineMetricValue(value: 72, presence: .present))
        XCTAssertEqual(buckets[1].metrics.weight, GlobalTimelineMetricValue(value: 74, presence: .estimated))
        XCTAssertEqual(buckets[2].metrics.weight, GlobalTimelineMetricValue(value: 76, presence: .present))
    }

    func testYearlyBucketsAggregateOlderHistoryAndInterpolateBridgeYear() {
        let service = GlobalTimelineService(calendar: calendar)
        let metrics = recentWeeklyMetrics + [
            metric(id: "2022", date: date("2022-06-15"), weight: 80),
            metric(id: "2024", date: date("2024-06-15"), weight: 70)
        ]

        let buckets = service.makeBuckets(for: .year, metrics: metrics)

        XCTAssertEqual(buckets.map(\.id), ["2022", "2023", "2024"])
        XCTAssertEqual(buckets[0].metrics.weight, GlobalTimelineMetricValue(value: 80, presence: .present))
        XCTAssertEqual(buckets[1].metrics.weight, GlobalTimelineMetricValue(value: 75, presence: .estimated))
        XCTAssertEqual(buckets[2].metrics.weight, GlobalTimelineMetricValue(value: 70, presence: .present))
    }

    func testWeeklyBucketsSelectPhotoDeterministicallyWhenDatesTie() {
        let service = GlobalTimelineService(calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: date("2025-12-17"))!
        let midpoint = week.start.addingTimeInterval(3 * 86_400)
        let metrics = [
            metric(id: "z-photo", date: midpoint, photoURL: "https://example.com/z.jpg"),
            metric(id: "a-photo", date: midpoint, photoURL: "https://example.com/a.jpg")
        ]

        guard let bucket = service.makeBuckets(for: .week, metrics: metrics).first else {
            return XCTFail("Expected a weekly bucket for photo metrics")
        }

        XCTAssertEqual(bucket.metrics.canonicalPhotoId, "https://example.com/a.jpg")
        XCTAssertTrue(bucket.metrics.hasPhotosInRange)
    }

    func testInitialCursorUsesMostRecentWeeklyBucketAndEmptyInputsHaveNoBuckets() {
        let service = GlobalTimelineService(calendar: calendar)

        XCTAssertTrue(service.makeBuckets(for: .week, metrics: []).isEmpty)
        XCTAssertNil(service.makeInitialCursor(for: []))

        let cursor = service.makeInitialCursor(for: recentWeeklyMetrics)
        let weeklyBuckets = service.makeBuckets(for: .week, metrics: recentWeeklyMetrics)
        XCTAssertEqual(cursor?.bucketId, weeklyBuckets.last?.id)
        XCTAssertEqual(cursor?.date, weeklyBuckets.last?.endDate)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var recentWeeklyMetrics: [BodyMetrics] {
        [
            metric(id: "dec-20", date: date("2025-12-20"), weight: 80),
            metric(id: "dec-10", date: date("2025-12-10"), weight: 79),
            metric(id: "dec-03", date: date("2025-12-03"), weight: 78),
            metric(id: "nov-26", date: date("2025-11-26"), weight: 77)
        ]
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)!
    }

    private func metric(
        id: String,
        date: Date,
        weight: Double? = nil,
        photoURL: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoURL,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

@MainActor
final class GlobalTimelineStoreTests: XCTestCase {
    func testStoreBuildsAllZonesAndCanReturnToTheMostRecentWeek() {
        let service = GlobalTimelineService(calendar: calendar)
        let store = GlobalTimelineStore(service: service)
        let metrics = [
            metric(id: "recent", date: date("2025-12-20"), weight: 80),
            metric(id: "recent-2", date: date("2025-12-10"), weight: 79),
            metric(id: "recent-3", date: date("2025-12-03"), weight: 78),
            metric(id: "recent-4", date: date("2025-11-26"), weight: 77),
            metric(id: "old", date: date("2024-06-15"), weight: 70)
        ]

        store.updateMetrics(metrics)

        let initialCursor = store.cursor
        XCTAssertEqual(initialCursor?.scale, .week)
        XCTAssertNotNil(initialCursor.flatMap { store.bucket(for: $0) })
        XCTAssertFalse(store.yearlyBuckets.isEmpty)

        if let yearly = store.yearlyBuckets.first {
            store.updateCursor(GlobalTimelineCursor(date: yearly.endDate, scale: .year, bucketId: yearly.id))
        }
        store.selectToday()

        XCTAssertEqual(store.cursor?.scale, .week)
        XCTAssertEqual(store.cursor?.bucketId, store.weeklyBuckets.last?.id)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)!
    }

    private func metric(id: String, date: Date, weight: Double) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

@MainActor
final class OnboardingStateManagerTests: XCTestCase {
    func testCompletionStateTracksVersionAndPostsChanges() async {
        let suiteName = "LogYourBodyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = OnboardingStateManager(defaults: defaults, currentVersion: 2)
        let changed = expectation(forNotification: OnboardingStateManager.onboardingStateDidChange, object: nil)

        XCTAssertFalse(manager.hasCompletedCurrentVersion)
        manager.markCompleted()

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertTrue(manager.hasCompletedCurrentVersion)
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 2)

        manager.resetForNextVersion(newVersion: 3)
        XCTAssertFalse(manager.hasCompletedCurrentVersion)
        XCTAssertEqual(defaults.integer(forKey: Constants.onboardingCompletedVersionKey), 2)

        manager.updateCompletionStatus(false)
        XCTAssertFalse(defaults.bool(forKey: Constants.hasCompletedOnboardingKey))
        XCTAssertEqual(defaults.object(forKey: Constants.onboardingCompletedVersionKey) as? Int, nil)
    }
}

final class TestRuntimeIsolationTests: XCTestCase {
    func testAppRecognizesTheUnitTestHost() {
        XCTAssertTrue(LogYourBodyApp.isRunningUnitTests)
    }
}

final class OnboardingProgressIndicatorTests: XCTestCase {
    func testFillWidthPreservesMinimumAndClampsToContainer() {
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: 100, fraction: 0),
            12
        )
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: 100, fraction: 0.5),
            50
        )
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: 8, fraction: 0.1),
            8
        )
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: 100, fraction: 2),
            100
        )
    }

    func testFillWidthRejectsInvalidContainerAndFractionValues() {
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: -1, fraction: 0.5),
            0
        )
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: .infinity, fraction: 0.5),
            0
        )
        XCTAssertEqual(
            OnboardingProgressIndicator.fillWidth(containerWidth: 100, fraction: .nan),
            0
        )
    }
}

final class TimelineDataProviderTests: XCTestCase {
    func testPhotoModeFindsNearestPhotoAndMetricAtSearchWindowBoundary() {
        let provider = TimelineDataProvider()
        let scrubDate = Date(timeIntervalSince1970: 1_700_000_000)
        let boundaryDate = scrubDate.addingTimeInterval(7 * 86_400)
        provider.loadMetrics([
            metric(id: "empty-photo", date: scrubDate, photoURL: ""),
            metric(id: "boundary", date: boundaryDate, weight: 75, photoURL: "https://example.com/photo.jpg")
        ])

        let result = provider.findDataForPhotoMode(scrubDate: scrubDate)

        XCTAssertEqual(result.photo?.bodyMetrics.id, "boundary")
        XCTAssertEqual(result.photo?.daysFromScrub, 7)
        XCTAssertEqual(result.metrics?.bodyMetrics.id, "boundary")
        XCTAssertFalse(result.metrics?.isInterpolated ?? true)
    }

    func testAvatarDatesAndAnchorsFilterEmptyEntriesAndDescribeDataType() {
        let provider = TimelineDataProvider()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let photoOnly = metric(id: "photo", date: base.addingTimeInterval(-14 * 86_400), photoURL: "https://example.com/photo.jpg")
        let metricOnly = metric(id: "metric", date: base.addingTimeInterval(-7 * 86_400), weight: 70)
        let both = metric(id: "both", date: base, weight: 69, photoURL: "https://example.com/both.jpg")
        provider.loadMetrics([both, metric(id: "empty", date: base.addingTimeInterval(-21 * 86_400)), metricOnly, photoOnly])

        XCTAssertEqual(provider.getAllDataDates(), [photoOnly.date, metricOnly.date, both.date])
        XCTAssertEqual(provider.findNearestDataDate(to: metricOnly.date.addingTimeInterval(1)), metricOnly.date)
        XCTAssertEqual(provider.getMetric(for: metricOnly.date)?.id, "metric")

        let photoAnchors = provider.generateAnchors(mode: .photo, zoomLevel: .week)
        XCTAssertEqual(Set(photoAnchors.map(\.id)), Set(["photo", "both"]))
        XCTAssertTrue(photoAnchors.allSatisfy { $0.position >= 0 && $0.position <= 1 })

        let avatarAnchors = provider.generateAnchors(mode: .avatar, zoomLevel: .week)
        XCTAssertEqual(Set(avatarAnchors.map(\.id)), Set(["photo", "metric", "both"]))
        XCTAssertEqual(anchorType(for: "photo", in: avatarAnchors), .photo)
        XCTAssertEqual(anchorType(for: "metric", in: avatarAnchors), .metricsOnly)
        XCTAssertEqual(anchorType(for: "both", in: avatarAnchors), .photoWithMetrics)
    }

    func testDateFromPositionClampsToTimelineBounds() {
        let provider = TimelineDataProvider()
        let end = Date()
        let start = end.addingTimeInterval(-10 * 86_400)

        XCTAssertEqual(provider.dateFromPosition(-0.5, from: start, to: end), start)
        XCTAssertEqual(provider.dateFromPosition(1.5, from: start, to: end), end)
        XCTAssertEqual(provider.dateFromPosition(0.5, from: end, to: start), end)
    }

    func testTimeWeightedPositionKeepsUnanchoredMetricsInsideTheScrubberRange() {
        let provider = TimelineDataProvider()
        let start = Date(timeIntervalSince1970: 86_400)
        let end = start.addingTimeInterval(9 * 86_400)

        let position = provider.position(for: start, from: start, to: end)

        XCTAssertGreaterThanOrEqual(position, 0)
        XCTAssertLessThanOrEqual(position, 1)
        XCTAssertEqual(
            provider.dateFromPosition(position, from: start, to: end).timeIntervalSince1970,
            start.timeIntervalSince1970,
            accuracy: 1
        )
    }

    private func anchorType(
        for id: String,
        in anchors: [TimelineAnchor]
    ) -> TimelineAnchor.AnchorType? {
        anchors.first { $0.id == id }?.anchorType
    }

    private func metric(
        id: String,
        date: Date,
        weight: Double? = nil,
        photoURL: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: photoURL,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }
}

final class PhotoMetadataServiceTests: XCTestCase {
    override func tearDown() {
        PhotoMetadataService.shared.clearEstimationCache()
        super.tearDown()
    }

    func testClosestMetricsUsesDistanceThenStableDateAndIdentifierTieBreakers() {
        let service = PhotoMetadataService.shared
        let target = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = metric(id: "z-earlier", date: target.addingTimeInterval(-86_400), weight: 70)
        let later = metric(id: "a-later", date: target.addingTimeInterval(86_400), weight: 71)
        let sameDateLaterID = metric(id: "z", date: target, weight: 72)
        let sameDateEarlierID = metric(id: "a", date: target, weight: 73)

        XCTAssertEqual(service.findClosestMetrics(for: target, in: [later, earlier])?.id, "z-earlier")
        XCTAssertEqual(service.findClosestMetrics(for: target, in: [sameDateLaterID, sameDateEarlierID])?.id, "a")
        XCTAssertNil(service.findClosestMetrics(for: target, in: [earlier], maxDaysDifference: 0))
    }

    func testWeightAndBodyFatEstimatesInterpolateAndRefreshWhenMetricUpdates() {
        let service = PhotoMetadataService.shared
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let target = start.addingTimeInterval(5 * 86_400)
        let first = metric(id: "first", date: start, weight: 70, bodyFat: 20, updatedAt: start)
        let second = metric(id: "second", date: start.addingTimeInterval(10 * 86_400), weight: 80, bodyFat: 30, updatedAt: start)

        XCTAssertEqual(service.estimateWeight(for: target, metrics: [second, first])?.value, 75)
        XCTAssertEqual(service.estimateBodyFat(for: target, metrics: [second, first])?.value, 25)

        let updatedSecond = metric(
            id: "second",
            date: second.date,
            weight: 80,
            bodyFat: 40,
            updatedAt: second.updatedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(service.estimateBodyFat(for: target, metrics: [first, updatedSecond])?.value, 30)
        XCTAssertEqual(service.estimateWeight(for: target, metrics: [first])?.value, 70)
        XCTAssertNil(service.estimateBodyFat(for: target, metrics: []))
    }

    private func metric(
        id: String,
        date: Date,
        weight: Double?,
        bodyFat: Double? = nil,
        updatedAt: Date? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user",
            date: date,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: updatedAt ?? date
        )
    }
}

// swiftlint:enable single_test_class
