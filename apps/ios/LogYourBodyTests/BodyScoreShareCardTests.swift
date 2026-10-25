//
// AccountDeletionAndShareCardTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
import Vision
@testable import LogYourBody


@MainActor
final class BodyScoreShareCardTests: XCTestCase {
    func testStatsTruthCardDetailTimelineAndShareUseSameObservationContract() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selected = now.addingTimeInterval(-2 * 86_400)
        let points = [MetricChartDataPoint(date: now.addingTimeInterval(-29 * 86_400), value: 80),
                      MetricChartDataPoint(date: selected, value: 82), MetricChartDataPoint(date: now, value: 83)]
        let entries = [MetricHistoryEntry(id: "selected", date: selected, primaryValue: 82,
                                          secondaryValue: nil, source: .healthKit),
                       MetricHistoryEntry(id: "newest", date: now, primaryValue: 83,
                                          secondaryValue: nil, source: .manual)]
        let summary = MetricObservationSummary(points: points, range: .month1, selectedDate: selected, now: now)
        let card = ContextualMetricSnapshot.observationSummary(summary, kind: .weight, unit: "kg", provenance: "Apple Health")
        let detail = truthDetail(points: points, entries: entries, selected: selected, now: now)
        XCTAssertEqual(detail.observationSnapshot, card)
        XCTAssertEqual(detail.headlineValueText, "82.0")
        XCTAssertEqual(detail.headlineDateText, card.observation)
        XCTAssertEqual(detail.contextualSharePayload?.contextualMetrics, [card])
        XCTAssertEqual(detail.observationSummary.stats?.delta, summary.stats?.delta)
        let timeline = HomeV2MetricEditorial.canvas(HomeV2MetricCanvasRequest(
            metric: .weight, points: points, unit: "kg", deltaUnit: "kg", range: .month1,
            provenance: nil, target: nil, hasEnoughData: false,
            formatValue: { String(format: "%.1f", $0) }, dateText: { summary.dateText($0) },
            observationSummary: summary))
        XCTAssertEqual(timeline.comparison, summary.changeText(unit: "kg"))
        XCTAssertTrue(card.trend?.contains("Mean of 3 observations") == true)
        XCTAssertTrue(card.observation.contains("2 days ago"))
        XCTAssertFalse(card.observation.contains("Updated"))
    }

    func testStatsTruthMixedSourceAndGoalFixturesNeverBorrowSourceOrAssignProgress() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let early = MetricChartDataPoint(date: now.addingTimeInterval(-86_400), value: 82)
        let latest = MetricChartDataPoint(date: now, value: 80)
        let entries = [MetricHistoryEntry(id: "old", date: early.date, primaryValue: 82,
                                          secondaryValue: nil, source: .healthKit),
                       MetricHistoryEntry(id: "new", date: now, primaryValue: 80,
                                          secondaryValue: nil, source: .manual)]
        for goal in [nil, 70, 90, Double.nan, Double.infinity] as [Double?] {
            let detail = truthDetail(points: [latest, early], entries: entries, selected: early.date, now: now, goal: goal)
            XCTAssertEqual(detail.observationSnapshot?.provenance, "Apple Health")
            XCTAssertEqual(detail.headlineValueText, "82.0")
            XCTAssertEqual(detail.deltaColor(for: -2), Color.metricTextSecondary)
            XCTAssertEqual(detail.deltaColor(for: 2), Color.metricTextSecondary)
            if goal?.isFinite == false { XCTAssertNil(detail.plottedGoalValue) }
        }
        let conflict = MetricHistoryEntry(id: "conflict", date: early.date, primaryValue: 82,
                                          secondaryValue: nil, source: .manual)
        let ambiguous = truthDetail(points: [early, latest], entries: entries + [conflict],
                                    selected: early.date, now: now)
        XCTAssertEqual(ambiguous.observationSnapshot?.provenance, "Source unavailable or mixed")
        let stale = ContextualMetricDetailPolicy.validatedFocus(
            early, in: [latest], currentFingerprint: "refreshed", cachedFingerprint: "old")
        XCTAssertNil(stale)
    }

    func testStatsTruthFFMIUsesCanonicalJOV3331ValueAndExportsDerivedEvidence() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let metric = BodyMetrics(
            id: "ffmi-truth", userId: "synthetic", date: date,
            weight: 80, weightUnit: "kg", bodyFatPercentage: 20, bodyFatMethod: "manual",
            muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil, dataSource: "manual",
            createdAt: date, updatedAt: date)
        let expected = try XCTUnwrap(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 20, heightCm: 180))
        let canonical = try XCTUnwrap(MetricsInterpolationService.shared.estimateFFMI(
            for: date, metrics: [metric], heightInches: 180 / 2.54))
        XCTAssertEqual(canonical.value, (expected * 10).rounded() / 10, accuracy: 0.0001)
        let summary = MetricObservationSummary(
            points: [.init(date: date, value: canonical.value)], range: .month1, now: date)
        let snapshot = ContextualMetricSnapshot.observationSummary(
            summary, kind: .ffmi, unit: "", provenance: "Derived from smoothed weight, body fat and height")
        XCTAssertEqual(snapshot.value, String(format: "%.1f", expected))
        XCTAssertEqual(snapshot.evidence, "Derived estimate")
        XCTAssertEqual(snapshot.trend, "Need 2 observations at different times")
        var options = BodyScoreShareOptions(selectedMetric: .ffmi)
        options.includeProvenance = true
        let text = try renderPNGText(snapshot, aspect: .square, options: options, name: "lyb47-ffmi-truth.png")
        XCTAssertEqual(pngTruthMismatches(text, expected: SharePNGTruth(
            kind: .ffmi, value: snapshot.value, unit: "", date: nil, evidence: "Derived estimate")), [])
    }

    func testProgressCalendarDayFocusRecoversOriginalTimestampAndSourceAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let earlyDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T09:30:00Z"))
        let lateDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T10:30:00Z"))
        let early = MetricChartDataPoint(date: earlyDate, value: 82)
        let late = MetricChartDataPoint(date: lateDate, value: 82)
        let entries = [MetricHistoryEntry(id: "early", date: earlyDate, primaryValue: 82,
                                          secondaryValue: nil, source: .healthKit),
                       MetricHistoryEntry(id: "late", date: lateDate, primaryValue: 82,
                                          secondaryValue: nil, source: .manual)]
        let plot = HomeV2ChartIntegrity.plot(
            points: [early, late], anchorsToZero: false, keepsCarriedValues: false, calendar: calendar)
        let focus = try XCTUnwrap(plot.marks.first { $0.occurrence == 1 })
        XCTAssertEqual(focus.date, calendar.startOfDay(for: earlyDate))
        let selected = try XCTUnwrap(ContextualMetricProgressPolicy.selection(
            points: [early, late], focus: focus, usesCalendarDayDomain: true, calendar: calendar))
        XCTAssertEqual(selected.point.date, lateDate)
        XCTAssertEqual(selected.source(entries: entries), "Manual")
        XCTAssertNil(ContextualMetricProgressPolicy.selection(
            points: [early], focus: focus, usesCalendarDayDomain: true, calendar: calendar))
    }

    func testStatsTruthDatePrivacyAlsoHidesComparisonEndpointDatesInPNG() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = now.addingTimeInterval(-10 * 86_400)
        let summary = MetricObservationSummary(
            points: [.init(date: first, value: 80), .init(date: now, value: 82)], range: .month1, now: now)
        let snapshot = ContextualMetricSnapshot.observationSummary(summary, kind: .weight, unit: "kg", provenance: "Manual")
        var options = BodyScoreShareOptions(selectedMetric: .weight)
        options.includeObservation = false
        options.includeRange = false
        options.includeTrend = true
        let detail = snapshot.detail(options: options)
        XCTAssertFalse(detail.contains(summary.dateText(first)))
        XCTAssertFalse(detail.contains(summary.dateText(now)))
        XCTAssertTrue(detail.contains("First → last observation"))
        XCTAssertTrue(detail.contains("Mean of 2 observations"))
        let text = try renderPNGText(snapshot, aspect: .square, options: options, name: "lyb47-share-hidden-dates.png")
        let expected = SharePNGTruth(
            kind: .weight, value: "82.0", unit: "kg", date: nil, evidence: nil,
            hiddenDate: now.formatted(date: .abbreviated, time: .omitted))
        XCTAssertEqual(pngTruthMismatches(text, expected: expected), [])
        XCTAssertFalse(text.contains(first.formatted(date: .abbreviated, time: .omitted)))
    }

    private func truthDetail(points: [MetricChartDataPoint], entries: [MetricHistoryEntry], selected: Date,
                             now: Date, goal: Double? = nil) -> FullMetricChartView {
        FullMetricChartView(
            title: "Weight", icon: "figure.stand", iconColor: .blue,
            currentValue: "999", unit: "kg", currentDate: "Unrelated sync date",
            chartData: points, onAdd: nil,
            metricEntries: MetricEntriesPayload(
                config: MetricEntriesConfiguration(metricType: .weight, unitLabel: "kg", secondaryUnitLabel: nil,
                                                   primaryFormatter: NumberFormatter(), secondaryFormatter: nil),
                entries: entries),
            goalValue: goal, selectedTimeRange: .constant(.month1), selectedTimelineDate: .constant(selected),
            statsTruthEnabled: true, referenceDate: now)
    }

    func testShareSheetDefaultsToPortraitExportAspect() {
        XCTAssertEqual(BodyScoreShareAspect.defaultExportAspect, .portrait)
        XCTAssertEqual(BodyScoreShareAspect.preferredExportAspect(for: nil), .portrait)
    }

    func testShareSheetDismissesOnDownwardDragPastThreshold() {
        XCTAssertFalse(
            BodyScoreShareSheet.shouldDismiss(
                afterDragTranslation: 40,
                predictedEndTranslation: 60
            )
        )
        XCTAssertTrue(
            BodyScoreShareSheet.shouldDismiss(
                afterDragTranslation: BodyScoreShareSheet.dismissDragThreshold,
                predictedEndTranslation: 0
            )
        )
        XCTAssertTrue(
            BodyScoreShareSheet.shouldDismiss(
                afterDragTranslation: 30,
                predictedEndTranslation: BodyScoreShareSheet.dismissDragThreshold * 1.4
            )
        )
        // Upward / sideways motion must never dismiss.
        XCTAssertFalse(
            BodyScoreShareSheet.shouldDismiss(
                afterDragTranslation: -180,
                predictedEndTranslation: -300
            )
        )
    }

    /// JOV-6089: only predominantly vertical drags may drive dismissal. A
    /// diagonal drag whose vertical component passes the threshold must never
    /// dismiss, and the format-control (horizontal) axis keeps its gesture.
    func testDismissDragRequiresVerticalAxisDominance() {
        // Predominantly vertical drags stay eligible for dismissal.
        XCTAssertTrue(
            BodyScoreShareSheet.isVerticalGesture(
                translationWidth: 0,
                translationHeight: 160
            )
        )
        XCTAssertTrue(
            BodyScoreShareSheet.isVerticalGesture(
                translationWidth: 24,
                translationHeight: 180
            )
        )
        // Equal components still count as vertical; dismissal then also
        // requires the downward-threshold policy to pass.
        XCTAssertTrue(
            BodyScoreShareSheet.isVerticalGesture(
                translationWidth: 120,
                translationHeight: 120
            )
        )
        // Horizontal format-control swipes never dismiss.
        XCTAssertFalse(
            BodyScoreShareSheet.isVerticalGesture(
                translationWidth: 160,
                translationHeight: 8
            )
        )
        // A diagonal drag with the same vertical travel as a dismissing
        // vertical drag must NOT qualify once the horizontal component wins.
        XCTAssertFalse(
            BodyScoreShareSheet.isVerticalGesture(
                translationWidth: 220,
                translationHeight: 180
            )
        )
        // Axis dominance is direction-aware: an upward vertical drag is a
        // gesture-owned scroll-back, not a dismissal.
        XCTAssertFalse(
            BodyScoreShareSheet.shouldDismiss(
                afterDragTranslation: -180,
                predictedEndTranslation: 160
            )
        )
        // And a diagonal drag that would pass the threshold vertically is
        // rejected once the gesture is not vertical-dominant.
        let diagonalIsVertical = BodyScoreShareSheet.isVerticalGesture(
            translationWidth: 220,
            translationHeight: 180
        )
        XCTAssertFalse(
            diagonalIsVertical
                && BodyScoreShareSheet.shouldDismiss(
                    afterDragTranslation: 180,
                    predictedEndTranslation: 260
                )
        )
    }

    func testPhotoShareAspectTracksNativeImageShape() {
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 480, height: 640))
            ),
            .portrait
        )
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 360, height: 760))
            ),
            .story
        )
        XCTAssertEqual(
            BodyScoreShareAspect.preferredExportAspect(
                for: makeShareTestImage(size: CGSize(width: 640, height: 640))
            ),
            .square
        )
    }

    func testMetricSummaryDataPointIdentityIsStableAcrossRenders() {
        let first = MetricSummaryCard.DataPoint(index: 4, value: 181.2)
        let second = MetricSummaryCard.DataPoint(index: 4, value: 179.8)

        XCTAssertEqual(first.id, second.id)
    }

    func testMetricChartDataPointIdentityIsStableAcrossRenders() {
        let date = Date(timeIntervalSince1970: 1_771_000_000)
        let first = MetricChartDataPoint(date: date, value: 181.2, presence: .present)
        let second = MetricChartDataPoint(date: date, value: 181.2, presence: .present)
        let interpolated = MetricChartDataPoint(date: date, value: 181.2, presence: .interpolated)

        XCTAssertEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, interpolated.id)
    }

    func testShareCardLayoutScalesDownForNarrowStoryPreview() {
        let layout = ShareCardLayout(size: CGSize(width: 260, height: 462), aspect: .story)

        XCTAssertLessThan(layout.scale, 0.7)
        XCTAssertLessThan(layout.scoreFontSize, 42)
        XCTAssertLessThan(layout.metricValueFontSize, 14)
    }

    func testShareCardLayoutReservesBottomMatteForStoryPreviewText() {
        let layout = ShareCardLayout(size: CGSize(width: 260, height: 462), aspect: .story)

        XCTAssertGreaterThan(layout.summaryMatteHeight, layout.size.height * 0.44)
        XCTAssertLessThan(layout.visualTopOffset + layout.visualHeight, layout.size.height * 0.72)
    }

    func testShareCardLayoutKeepsAvatarVisualClearOfSummaryText() {
        let previewSizes: [(BodyScoreShareAspect, CGSize)] = [
            (.square, CGSize(width: 320, height: 320)),
            (.portrait, CGSize(width: 320, height: 400)),
            (.story, CGSize(width: 260, height: 462)),
            (.story, CGSize(width: 1_080, height: 1_920))
        ]

        for (aspect, size) in previewSizes {
            let layout = ShareCardLayout(size: size, aspect: aspect)
            let avatarBottom = layout.visualTopOffset + layout.visualHeight

            XCTAssertLessThanOrEqual(
                avatarBottom + layout.textVisualGap,
                layout.summaryTopY + 0.5,
                "Avatar visual overlaps text budget for \(aspect.rawValue)"
            )
            XCTAssertGreaterThanOrEqual(
                layout.summaryMatteHeight,
                layout.size.height - layout.summaryTopY,
                "Summary matte must cover the full text area for \(aspect.rawValue)"
            )
        }
    }

    func testSharePayloadUsesSameNearestAvatarBucketAsHomeHero() {
        let payload = makePayload(bodyFatPercentage: 16.4, gender: "male")

        XCTAssertEqual(payload.avatarMatch.assetName, "avatar_male_15")
        XCTAssertEqual(payload.avatarMatch.badgeText, "Male 15% body fat")
        XCTAssertEqual(payload.visualBadgeText(includeVisual: true), "Male 15% body fat")
        XCTAssertEqual(payload.visualBadgeText(includeVisual: false), "Private summary")
        XCTAssertNil(payload.photoImage)
    }

    func testPhotoBackedSharePayloadUsesProgressPhotoBadge() {
        let payload = makePayload(
            bodyFatPercentage: 16.4,
            gender: "male",
            photoImage: makeShareTestImage()
        )

        XCTAssertEqual(payload.visualBadgeText(includeVisual: true), "Progress photo")
        XCTAssertNotNil(payload.photoImage)
    }

    func testShareOptionsStartPrivateAndDescribeOnlyChosenDetails() {
        var options = BodyScoreShareOptions()

        XCTAssertFalse(options.hasMetrics)
        XCTAssertFalse(options.includeVisual)
        XCTAssertEqual(options.includedSummary, "Body Score")

        options.includeWeight = true
        options.includeVisual = true

        XCTAssertTrue(options.hasMetrics)
        XCTAssertEqual(options.includedSummary, "Body Score, weight, visual")
    }

    func testShareCardRendersRequestedExportSize() throws {
        let size = BodyScoreShareAspect.portrait.pixelSize
        let renderer = ImageRenderer(
            content: BodyScoreShareCardView(
                payload: makePayload(bodyFatPercentage: 22.4, gender: "female"),
                aspect: .portrait
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1.0

        let image = try XCTUnwrap(renderer.uiImage)

        XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
    }

    func testShareCardRendersEveryLaunchExportAspect() throws {
        for aspect in BodyScoreShareAspect.allCases {
            let size = aspect.pixelSize
            let renderer = ImageRenderer(
                content: BodyScoreShareCardView(
                    payload: makePayload(bodyFatPercentage: 18.6, gender: "male"),
                    aspect: aspect
                )
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1.0

            let image = try XCTUnwrap(renderer.uiImage, "Missing rendered image for \(aspect.rawValue)")

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        }
    }

    func testPhotoBackedShareCardRendersEveryLaunchExportAspect() throws {
        for aspect in BodyScoreShareAspect.allCases {
            let size = aspect.pixelSize
            let renderer = ImageRenderer(
                content: BodyScoreShareCardView(
                    payload: makePayload(
                        bodyFatPercentage: 18.6,
                        gender: "male",
                        photoImage: makeShareTestImage()
                    ),
                    aspect: aspect
                )
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1.0

            let image = try XCTUnwrap(renderer.uiImage, "Missing rendered photo image for \(aspect.rawValue)")

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
        }
    }

    func testContextualRoutesNeverSubstituteBodyScore() throws {
        for kind in ContextualMetricKind.allCases {
            let snapshot = contextualSnapshot(kind: kind)
            let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([snapshot], selected: kind))
            let options = BodyScoreShareOptions(selectedMetric: payload.preferredMetric)
            XCTAssertEqual(payload.snapshot(for: options), snapshot)
            XCTAssertEqual(options.includedSummary, kind.title)
            XCTAssertFalse(options.hasMetrics)
            XCTAssertFalse(options.includeVisual)
            XCTAssertNil(payload.photoImage)
            XCTAssertEqual(payload.score, 0)
        }
        XCTAssertNil(ContextualMetricKind.from(title: "GLP-1 Dose"))
        XCTAssertNil(BodyScoreSharePayload.contextual([contextualSnapshot(kind: .weight)], selected: .steps))
    }

    func testUnavailableMetricHasNoMisleadingShareFallback() {
        for missing in ["", "—", "–", "  "] {
            let snapshot = ContextualMetricSnapshot(
                kind: .steps, value: missing, unit: "steps", observation: "", range: "30 days",
                trend: nil, provenance: nil
            )
            XCTAssertNil(BodyScoreSharePayload.contextual([snapshot], selected: .steps))
        }
    }

    func testContextPrivacyDoesNotExportOtherMeasurementsOrHiddenMetadata() throws {
        let steps = contextualSnapshot(kind: .steps)
        let weight = contextualSnapshot(kind: .weight)
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([steps, weight], selected: .steps))
        var options = BodyScoreShareOptions(selectedMetric: .steps)
        options.includeWeight = true
        XCTAssertFalse(options.hasMetrics)
        XCTAssertEqual(payload.snapshot(for: options)?.value, "7,544")
        XCTAssertFalse(steps.detail(options: options).contains("Apple Health"))
        options.includeObservation = false
        options.includeRange = false
        options.includeTrend = false
        XCTAssertEqual(steps.detail(options: options), "")
        options.includeProvenance = true
        XCTAssertEqual(steps.detail(options: options), "Apple Health")
        options.selectedMetric = .weight
        XCTAssertEqual(payload.snapshot(for: options), weight)
    }

    func testHistoricalSourceIsBoundToExactObservationAndPrivacy() {
        let date = Date(timeIntervalSince1970: 1_000)
        let point = MetricChartDataPoint(date: date, value: 75)
        let entry = MetricHistoryEntry(id: "historical", date: date, primaryValue: 75, secondaryValue: nil, source: .healthKit)
        let source = ContextualMetricSourcePolicy.source(for: point, entries: [entry], fallback: "Latest scale")
        XCTAssertEqual(source, "Apple Health")
        let snapshot = ContextualMetricSnapshot(
            kind: .weight, value: "75", unit: "kg", observation: "Jan 1",
            range: "All time", trend: nil, provenance: source)
        var options = BodyScoreShareOptions(selectedMetric: .weight)
        XCTAssertFalse(snapshot.detail(options: options).contains("Apple Health"))
        options.includeProvenance = true
        XCTAssertTrue(snapshot.detail(options: options).contains("Apple Health"))
        let unknown = MetricChartDataPoint(date: date.addingTimeInterval(1), value: 75)
        XCTAssertNil(ContextualMetricSourcePolicy.source(for: unknown, entries: [entry], fallback: "Latest scale"))
        let estimate = MetricChartDataPoint(date: date, value: 75, isEstimated: true)
        XCTAssertEqual(
            ContextualMetricSourcePolicy.source(for: estimate, entries: [entry], fallback: nil), "Apple Health"
        )
        var estimated = snapshot
        estimated.evidence = "Estimated"
        options.includeProvenance = false
        XCTAssertTrue(estimated.detail(options: options).contains("Estimated"))
        XCTAssertFalse(estimated.detail(options: options).contains("Apple Health"))
    }

    func testScreenshotOfferRequiresActiveVisibleUnpresentedScreen() {
        XCTAssertTrue(ContextualMetricSharePolicy.canOfferScreenshot(isActive: true, isVisible: true, isPresenting: false))
        XCTAssertFalse(ContextualMetricSharePolicy.canOfferScreenshot(isActive: false, isVisible: true, isPresenting: false))
        XCTAssertFalse(ContextualMetricSharePolicy.canOfferScreenshot(isActive: true, isVisible: false, isPresenting: false))
        XCTAssertFalse(ContextualMetricSharePolicy.canOfferScreenshot(isActive: true, isVisible: true, isPresenting: true))
    }

    func testContextualPNGExportRetainsEveryAspectAndVisibleSelection() throws {
        let selectedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        let expectedDate = selectedDate.formatted(date: .abbreviated, time: .omitted)
        let expectations = [
            SharePNGTruth(kind: .steps, value: "7,544", unit: "steps", date: expectedDate, evidence: nil),
            SharePNGTruth(kind: .weight, value: "83.2", unit: "kg", date: expectedDate, evidence: nil),
            SharePNGTruth(kind: .bodyFat, value: "17.4", unit: "%", date: expectedDate, evidence: "Estimated"),
            SharePNGTruth(kind: .ffmi, value: "19.8", unit: "", date: expectedDate, evidence: "Derived estimate")
        ]
        for expectation in expectations {
            let kind = expectation.kind
            let snapshot = try renderingSnapshot(kind: kind)
            XCTAssertEqual(snapshot.value, expectation.value)
            XCTAssertEqual(snapshot.unit, expectation.unit)
            XCTAssertEqual(snapshot.evidence, expectation.evidence)
            XCTAssertTrue(snapshot.observation.contains(try XCTUnwrap(expectation.date)))
            let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([snapshot], selected: kind))
            let options = BodyScoreShareOptions(selectedMetric: kind)
            for aspect in BodyScoreShareAspect.allCases {
                let size = aspect.pixelSize
                let renderer = ImageRenderer(content: BodyScoreShareCardView(payload: payload, aspect: aspect, options: options)
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let png = try XCTUnwrap(image.pngData())
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "contextual-\(kind.rawValue)-\(aspect.rawValue).png"
                attachment.lifetime = .keepAlways
                add(attachment)
                let decoded = try XCTUnwrap(UIImage(data: png))
                XCTAssertEqual(decoded.size, size)
                XCTAssertGreaterThan(png.count, 1_000)
                let text = try recognizedShareText(
                    decoded, diagnosticName: "contextual-\(kind.rawValue)-\(aspect.rawValue).png")
                let expected = expectation.value.filter(\.isNumber)
                XCTAssertTrue(text.filter(\.isNumber).contains(expected), "Export must contain selected value for \(kind)")
                XCTAssertFalse(text.lowercased().contains("body score"))
                XCTAssertEqual(
                    pngTruthMismatches(text, expected: expectation), [],
                    "\(kind.rawValue)/\(aspect.rawValue): \(text)"
                )
            }
            if kind == .bodyFat || kind == .ffmi {
                // Real bad-input output calibrates the same OCR validator; not a production mutation.
                let badText = try renderPNGText(
                    contextualSnapshot(kind: kind), aspect: .portrait,
                    options: options, name: "calibration-wrong-\(kind.rawValue).png")
                let rejected = pngTruthMismatches(badText, expected: expectation)
                XCTAssertTrue(rejected.contains("value"))
                XCTAssertTrue(rejected.contains("unit"))
            }
        }
        let expected = expectations[2]
        let correct = try renderingSnapshot(kind: .bodyFat)
        let differentDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z"))
        let wrongDate = ContextualMetricSnapshot(
            kind: correct.kind, value: correct.value, unit: correct.unit,
            observation: differentDate.formatted(date: .abbreviated, time: .omitted),
            range: correct.range, trend: correct.trend,
            provenance: correct.provenance, evidence: correct.evidence)
        let text = try renderPNGText(
            wrongDate, aspect: .portrait, options: BodyScoreShareOptions(selectedMetric: .bodyFat),
            name: "calibration-wrong-selected-date.png")
        XCTAssertTrue(pngTruthMismatches(text, expected: expected).contains("date"))
    }

    func testEvidenceMeaningCannotBeHiddenBySourcePrivacy() throws {
        XCTAssertEqual(ContextualMetricEvidencePolicy.label(for: .ffmi), "Derived estimate")
        XCTAssertEqual(ContextualMetricEvidencePolicy.label(for: .bodyScore), "Derived estimate")
        XCTAssertEqual(ContextualMetricEvidencePolicy.label(for: .bodyFat, bodyFatMethod: "visual_estimate"), "Estimated")
        XCTAssertNil(ContextualMetricEvidencePolicy.label(for: .bodyFat, bodyFatMethod: "dexa"))
        XCTAssertEqual(ContextualMetricEvidencePolicy.label(for: .weight, isSmoothed: true), "Smoothed")
        var snapshot = contextualSnapshot(kind: .ffmi)
        snapshot.evidence = ContextualMetricEvidencePolicy.label(for: .ffmi)
        var options = BodyScoreShareOptions(selectedMetric: .ffmi)
        options.includeObservation = false
        options.includeRange = false
        options.includeTrend = false
        options.includeProvenance = false
        XCTAssertEqual(snapshot.detail(options: options), "Derived estimate")

        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        let average = try XCTUnwrap(ContextualMetricProgressPolicy.selection(
            points: [MetricChartDataPoint(date: date, value: 82, presence: .present)],
            averages: [MetricChartDataPoint(date: date, value: 81, presence: .present)],
            focus: .init(date: date, value: 81, kind: .sevenDayAverage)))
        let smoothed = ContextualMetricSnapshot(
            kind: .weight, value: String(format: "%.1f", average.point.value), unit: "kg",
            observation: date.formatted(date: .abbreviated, time: .shortened), range: "30 days",
            trend: nil, provenance: average.source(entries: []),
            evidence: ContextualMetricEvidencePolicy.label(for: .weight, isSmoothed: average.isSmoothed))
        let privateValue = ContextualMetricSnapshot(
            kind: .bodyScore, value: "991.7", unit: "", observation: "PRIVATE RECORD",
            range: "PRIVATE RANGE", trend: "PRIVATE TREND", provenance: "PRIVATE SOURCE")
        let snapshots = [try renderingSnapshot(kind: .bodyFat), try renderingSnapshot(kind: .ffmi), smoothed]
        let expectations = [
            SharePNGTruth(kind: .bodyFat, value: "17.4", unit: "%", date: nil, evidence: "Estimated",
                          hiddenDate: date.formatted(date: .abbreviated, time: .omitted)),
            SharePNGTruth(kind: .ffmi, value: "19.8", unit: "", date: nil, evidence: "Derived estimate",
                          hiddenDate: date.formatted(date: .abbreviated, time: .omitted)),
            SharePNGTruth(kind: .weight, value: "81.0", unit: "kg", date: nil, evidence: "Smoothed",
                          hiddenDate: date.formatted(date: .abbreviated, time: .omitted))
        ]
        for (selected, expected) in zip(snapshots, expectations) {
            var privateOptions = BodyScoreShareOptions(selectedMetric: selected.kind)
            privateOptions.includeObservation = false
            privateOptions.includeRange = false
            privateOptions.includeTrend = false
            privateOptions.includeProvenance = false
            let text = try renderPNGText(
                selected, aspect: .portrait, options: privateOptions,
                name: "contextual-privacy-\(selected.kind.rawValue).png", privateSnapshots: [privateValue])
            XCTAssertEqual(pngTruthMismatches(text, expected: expected), [])
            var stripped = selected
            stripped.evidence = nil
            let badText = try renderPNGText(
                stripped, aspect: .portrait, options: privateOptions,
                name: "calibration-hidden-evidence-\(selected.kind.rawValue).png")
            XCTAssertTrue(pngTruthMismatches(badText, expected: expected).contains("evidence"))
        }
    }

    func testStepsObservationKeepsSampleDayWhenSyncUpdatesLater() {
        let observed = Date(timeIntervalSince1970: 1_000)
        let synced = observed.addingTimeInterval(86_400 * 10)
        let daily = DailyMetrics(
            id: "day", userId: "synthetic", date: observed, steps: 7_544,
            notes: nil, createdAt: observed, updatedAt: synced)
        let snapshot = ContextualMetricSnapshot.steps(daily, value: "7,544", range: "30 days")
        XCTAssertEqual(snapshot.observation, observed.formatted(date: .abbreviated, time: .omitted))
        XCTAssertNotEqual(snapshot.observation, synced.formatted(date: .abbreviated, time: .omitted))
    }

    func testRenderedStepsRedactsUnselectedWeightAndMetadata() throws {
        let selected = contextualSnapshot(kind: .steps)
        let privateWeight = ContextualMetricSnapshot(
            kind: .weight, value: "991.7", unit: "kg",
            observation: "PRIVATE RECORD", range: "All history", trend: nil, provenance: "PRIVATE SOURCE")
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([selected, privateWeight], selected: .steps))
        var options = BodyScoreShareOptions(selectedMetric: .steps)
        options.includeWeight = true
        options.includeObservation = false
        options.includeRange = false
        options.includeTrend = false
        let size = BodyScoreShareAspect.portrait.pixelSize
        let renderer = ImageRenderer(content: BodyScoreShareCardView(payload: payload, aspect: .portrait, options: options)
            .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        let text = try recognizedShareText(XCTUnwrap(renderer.uiImage))
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertFalse(text.filter(\.isNumber).contains("9917"))
        XCTAssertFalse(text.contains("Apple Health"))
        XCTAssertTrue(text.filter(\.isNumber).contains("7544"))
    }


    func testImportedRawWeightRetainsEvidenceWhenTrendIsPreferred() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let context = (0..<7).map { shareWeightMetric(weight: 80, date: start.addingTimeInterval(Double($0) * 86_400)) }
        let flagged = shareWeightMetric(weight: 18, date: context[3].date, source: "healthkit")
        let snapshot = ContextualMetricSnapshot.weight(
            flagged, metrics: context + [flagged], prefersTrend: true,
            context: (unit: "kg", observation: "Selected record", range: "30 days"),
            formatValue: { String(format: "%.1f", $0) })
        XCTAssertEqual(snapshot.value, "18.0")
        XCTAssertEqual(snapshot.provenance, "Apple Health")
        XCTAssertEqual(snapshot.evidence, HomeV2WeightQuality.reviewMessage)
        XCTAssertFalse(snapshot.detail(options: BodyScoreShareOptions(selectedMetric: .weight)).contains("7-day"))
        var options = BodyScoreShareOptions(selectedMetric: .weight)
        options.includeProvenance = true
        XCTAssertTrue(snapshot.detail(options: options).contains("Apple Health"))
        options.includeProvenance = false
        XCTAssertFalse(snapshot.detail(options: options).contains("Apple Health"))
        XCTAssertTrue(snapshot.detail(options: options).contains(HomeV2WeightQuality.reviewMessage))
    }

    func testInvalidWeightCannotBecomeAnAvailableShareValue() {
        for invalid in [Double.nan, .infinity, -5, 0] {
            let metric = shareWeightMetric(weight: invalid, date: Date(timeIntervalSince1970: 1_700_000_000))
            let snapshot = ContextualMetricSnapshot.weight(
                metric, metrics: [metric], prefersTrend: true,
                context: (unit: "kg", observation: "Selected record", range: "30 days"),
                formatValue: { String(format: "%.1f", $0) })
            XCTAssertFalse(snapshot.isAvailable)
            XCTAssertNil(BodyScoreSharePayload.contextual([snapshot], selected: .weight))
        }
    }

    func testRecordedWeightDoesNotAcquireSmoothedEvidenceFromPreference() {
        let metric = shareWeightMetric(weight: 82, date: Date(timeIntervalSince1970: 1_700_000_000))
        let snapshot = ContextualMetricSnapshot.weight(
            metric, metrics: [metric], prefersTrend: true,
            context: (unit: "kg", observation: "Selected record", range: "30 days"),
            formatValue: { String(format: "%.1f", $0) })
        XCTAssertEqual(snapshot.value, "82.0")
        XCTAssertNil(snapshot.evidence)
        XCTAssertEqual(snapshot.provenance, HomeV2ContextCopy.typed)
    }

    func testPhotoOnlyWeightFallbackLabelsDerivedValueWithoutBorrowingPhotoSource() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let context = (0..<7).map { shareWeightMetric(weight: 80, date: start.addingTimeInterval(Double($0) * 86_400)) }
        let photo = shareWeightMetric(weight: nil, date: context[3].date, source: "photo")
        let snapshot = ContextualMetricSnapshot.weight(
            photo, metrics: context + [photo], prefersTrend: false,
            context: (unit: "kg", observation: "Selected photo", range: "30 days"),
            formatValue: { String(format: "%.1f", $0) })
        XCTAssertEqual(snapshot.value, "80.0")
        XCTAssertEqual(snapshot.evidence, "Smoothed")
        XCTAssertNil(snapshot.provenance)
    }

    func testProgressSelectedDailyValueKeepsItsHistoricalSource() throws {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = MetricChartDataPoint(date: first, value: 75, presence: .present)
        let latest = MetricChartDataPoint(date: first.addingTimeInterval(86_400), value: 80, presence: .present)
        let focus = HomeV2ChartIntegrity.Sample(date: first, value: 75)
        let selected = try XCTUnwrap(ContextualMetricProgressPolicy.selection(points: [earlier, latest], focus: focus))
        let entries = [
            MetricHistoryEntry(id: "earlier", date: earlier.date, primaryValue: 75, secondaryValue: nil, source: .healthKit),
            MetricHistoryEntry(id: "latest", date: latest.date, primaryValue: 80, secondaryValue: nil, source: .manual)
        ]
        XCTAssertEqual(selected.point.value, 75)
        XCTAssertEqual(selected.point.date, first)
        XCTAssertFalse(selected.isSmoothed)
        XCTAssertEqual(selected.source(entries: entries), "Apple Health")
        XCTAssertNil(selected.source(entries: []))
    }

    func testProgressAverageFocusKeepsActualAverageAndRejectsStaleRange() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedDate = date.formatted(date: .abbreviated, time: .omitted)
        let raw = MetricChartDataPoint(date: date, value: 82, presence: .present)
        let average = MetricChartDataPoint(date: date, value: 81, presence: .present)
        let focus = HomeV2ChartIntegrity.Sample(date: date, value: 81, kind: .sevenDayAverage)
        let selected = try XCTUnwrap(ContextualMetricProgressPolicy.selection(
            points: [raw], averages: [average], focus: focus))
        XCTAssertEqual(selected.point.value, 81)
        XCTAssertTrue(selected.isSmoothed)
        let misleadingSource = MetricHistoryEntry(
            id: "same-number", date: date, primaryValue: 81, secondaryValue: nil, source: .healthKit)
        XCTAssertNil(selected.source(entries: [misleadingSource]))
        XCTAssertNil(ContextualMetricProgressPolicy.selection(points: [raw], averages: [], focus: focus))
        XCTAssertNil(ContextualMetricProgressPolicy.selection(points: [], focus: .init(date: date, value: 82)))
        let latest = try XCTUnwrap(ContextualMetricProgressPolicy.selection(points: [raw], focus: nil))
        XCTAssertEqual(latest.point.value, 82)
        XCTAssertFalse(latest.isSmoothed)

        let rawEntry = MetricHistoryEntry(
            id: "raw", date: date, primaryValue: 82, secondaryValue: nil, source: .healthKit)
        for (name, selection, expectation) in [
            ("raw", latest, SharePNGTruth(
                kind: .weight, value: "82.0", unit: "kg", date: expectedDate, evidence: nil, source: "Apple Health")),
            ("average", selected, SharePNGTruth(
                kind: .weight, value: "81.0", unit: "kg", date: expectedDate, evidence: "Smoothed"))
        ] {
            let snapshot = ContextualMetricSnapshot(
                kind: .weight, value: String(format: "%.1f", selection.point.value), unit: "kg",
                observation: selection.point.date.formatted(date: .abbreviated, time: .shortened),
                range: "30 days", trend: nil, provenance: selection.source(entries: [rawEntry, misleadingSource]),
                evidence: ContextualMetricEvidencePolicy.label(for: .weight, isSmoothed: selection.isSmoothed))
            var options = BodyScoreShareOptions(selectedMetric: .weight)
            options.includeProvenance = true
            for aspect in BodyScoreShareAspect.allCases {
                let text = try renderPNGText(
                    snapshot, aspect: aspect, options: options,
                    name: "contextual-weight-\(name)-\(aspect.rawValue).png")
                XCTAssertEqual(pngTruthMismatches(text, expected: expectation), [])
            }
        }
        let substituted = ContextualMetricSnapshot(
            kind: .weight, value: "82.0", unit: "kg",
            observation: date.formatted(date: .abbreviated, time: .shortened),
            range: "30 days", trend: nil, provenance: "Apple Health", evidence: "Smoothed")
        var sourceVisible = BodyScoreShareOptions(selectedMetric: .weight)
        sourceVisible.includeProvenance = true
        let text = try renderPNGText(
            substituted, aspect: .portrait, options: sourceVisible,
            name: "calibration-average-borrowed-raw-source.png")
        let rejected = pngTruthMismatches(text, expected: SharePNGTruth(
            kind: .weight, value: "81.0", unit: "kg", date: expectedDate, evidence: "Smoothed"))
        XCTAssertTrue(rejected.contains("value"))
        XCTAssertTrue(rejected.contains("source"))
    }

    func testProgressPresentationRejectsDeletedRefreshedAndSparseFocus() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let daily = (0..<7).map {
            MetricChartDataPoint(date: start.addingTimeInterval(Double($0) * 86_400),
                                 value: 80 + Double($0), presence: .present)
        }
        let focus = HomeV2ChartIntegrity.Sample(date: daily[3].date, value: daily[3].value)
        let valid = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: daily, averages: [], focus: focus))
        XCTAssertTrue(valid.isFocused)
        XCTAssertEqual(valid.point.value, 83)

        var refreshed = daily
        refreshed[3] = MetricChartDataPoint(date: focus.date, value: 90, presence: .present)
        let changed = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: refreshed, averages: [], focus: focus))
        XCTAssertFalse(changed.isFocused)
        XCTAssertEqual(changed.point.value, 86, "Refresh must not retain the stale selected83")

        let deleted = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: daily.filter { $0.date != focus.date }, averages: [], focus: focus))
        XCTAssertFalse(deleted.isFocused)
        XCTAssertEqual(deleted.point.value, 86)
        let sparse = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: [daily[3]], averages: [], focus: focus))
        XCTAssertFalse(sparse.isFocused, "A hidden chart cannot keep an active playhead")
        XCTAssertEqual(sparse.point.value, 83, "The sole current record remains the headline")
        XCTAssertNil(ContextualMetricProgressPolicy.presentationSelection(
            points: [], averages: [], focus: focus))
    }

    func testProgressPresentationRejectsRemovedAverageAfterRefresh() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let daily = (0..<7).map {
            MetricChartDataPoint(date: start.addingTimeInterval(Double($0) * 86_400),
                                 value: 80 + Double($0), presence: .present)
        }
        let average = MetricChartDataPoint(date: daily[6].date, value: 83, presence: .present)
        let focus = HomeV2ChartIntegrity.Sample(date: average.date, value: 83, kind: .sevenDayAverage)
        let valid = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: daily, averages: [average], focus: focus))
        XCTAssertTrue(valid.isFocused)
        XCTAssertTrue(valid.isSmoothed)
        let refreshed = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: daily, averages: [], focus: focus))
        XCTAssertFalse(refreshed.isFocused)
        XCTAssertFalse(refreshed.isSmoothed)
        XCTAssertEqual(refreshed.point.value, 86)
    }

    func testAllShareRoutesRejectAccountReplacementAndSameSubjectNewGeneration() throws {
        let original = AuthManager.ProfileSessionOwnership(subject: "synthetic-A", generation: 1)
        let replacements: [AuthManager.ProfileSessionOwnership?] = [
            .init(subject: "synthetic-B", generation: 2), nil,
            .init(subject: "synthetic-A", generation: 3)
        ]
        var payloads = [makePayload(bodyFatPercentage: 16, gender: "male", photoImage: makeShareTestImage())]
        payloads += try ContextualMetricKind.allCases.map { kind in
            try XCTUnwrap(BodyScoreSharePayload.contextual([contextualSnapshot(kind: kind)], selected: kind))
        }
        for payload in payloads {
            for replacement in replacements {
                var current: AuthManager.ProfileSessionOwnership? = original
                var pendingOffer = AccountBoundShareCapture()
                var dashboardComposer = AccountBoundShareCapture()
                pendingOffer.freeze(payload, owner: original)
                dashboardComposer.freeze(payload, owner: original)
                XCTAssertNotNil(pendingOffer.authorizedPayload { $0 == current })
                XCTAssertNotNil(dashboardComposer.authorizedPayload { $0 == current })
                current = replacement
                XCTAssertNil(pendingOffer.authorizedPayload { $0 == current }, "A stale offer cannot be accepted")
                XCTAssertNil(dashboardComposer.authorizedPayload { $0 == current }, "A stale composer cannot render/export")
                pendingOffer.reconcile(currentOwner: replacement)
                dashboardComposer.reconcile(currentOwner: replacement)
                XCTAssertNil(pendingOffer.payload)
                XCTAssertNil(dashboardComposer.payload)
                // An old async photo completion cannot authorize itself for the replacement.
                dashboardComposer.freeze(payload, owner: original)
                XCTAssertNil(dashboardComposer.authorizedPayload { $0 == current })
                dashboardComposer.clear()
                XCTAssertNil(dashboardComposer.payload)
            }
        }
    }

    func testShareCaptureUsesAuthoritativeAuthGenerationForSameSubjectReplacement() throws {
        let suite = "ShareAccountOwnershipTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HealthImportNoNetworkProtocol.self]
        let auth = AuthManager(userDefaults: defaults, urlSession: URLSession(configuration: configuration))
        auth.authSession = .localFixture(subject: "synthetic-share", email: "share@example.invalid", accessToken: "first")
        auth.currentUser = LocalUser(
            id: "synthetic-share", email: "share@example.invalid", name: "Synthetic Share",
            avatarUrl: nil, profile: nil, onboardingCompleted: true)
        let original = try XCTUnwrap(auth.captureAccountSession())
        var capture = AccountBoundShareCapture()
        capture.freeze(makePayload(bodyFatPercentage: 16, gender: nil), owner: original)
        XCTAssertNotNil(capture.authorizedPayload(owns: auth.ownsAccountSession))
        auth.authSession = .localFixture(subject: "synthetic-share", email: "share@example.invalid", accessToken: "replacement")
        XCTAssertNotEqual(auth.captureAccountSession(), original)
        XCTAssertNil(capture.authorizedPayload(owns: auth.ownsAccountSession))
        capture.reconcile(currentOwner: auth.captureAccountSession())
        XCTAssertNil(capture.payload)
    }

    func testPhotoExportRechecksAccountAfterAuthorizationSuspends() async {
        let original = AuthManager.ProfileSessionOwnership(subject: "synthetic-A", generation: 1)
        for replacement in [
            AuthManager.ProfileSessionOwnership(subject: "synthetic-B", generation: 2),
            AuthManager.ProfileSessionOwnership(subject: "synthetic-A", generation: 3)
        ] {
            var current = original
            var writes = 0
            let saved = await LivePhotoLibraryAdapter.saveAuthorizedImage(
                makeShareTestImage(), whileOwned: { current == original },
                authorize: {
                    await Task.yield()
                    current = replacement
                    return true
                }, write: { _ in writes += 1 })
            XCTAssertFalse(saved)
            XCTAssertEqual(writes, 0, "Authorization success cannot export the previous account's health pixels")
        }
    }

    func testPhotoExportRejectsStaleAdmissionAndDeniedPermissionButSavesCurrentOwner() async {
        let image = makeShareTestImage()
        var requests = 0
        var writes = 0
        let stale = await LivePhotoLibraryAdapter.saveAuthorizedImage(
            image, whileOwned: { false }, authorize: { requests += 1; return true },
            write: { _ in writes += 1 })
        XCTAssertFalse(stale)
        XCTAssertEqual(requests, 0)
        let denied = await LivePhotoLibraryAdapter.saveAuthorizedImage(
            image, whileOwned: { true }, authorize: { requests += 1; return false },
            write: { _ in writes += 1 })
        XCTAssertFalse(denied)
        XCTAssertEqual(writes, 0)
        let saved = await LivePhotoLibraryAdapter.saveAuthorizedImage(
            image, whileOwned: { true }, authorize: { requests += 1; return true },
            write: { _ in writes += 1 })
        XCTAssertTrue(saved)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(writes, 1)
    }

    func testDetailFocusRejectsSameRangeCorrectionDeletionAndTrendReplacement() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let selected = MetricChartDataPoint(date: date, value: 82, presence: .present)
        let corrected = MetricChartDataPoint(date: date, value: 83, presence: .present)
        XCTAssertEqual(ContextualMetricDetailPolicy.validatedFocus(
            selected, in: [selected], currentFingerprint: "current", cachedFingerprint: "current")?.value, 82)
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(
            selected, in: [corrected], currentFingerprint: "current", cachedFingerprint: "current"))
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(
            selected, in: [], currentFingerprint: "current", cachedFingerprint: "current"))
        let revisedTrend = MetricChartDataPoint(date: date, value: 81, presence: .estimated)
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(
            selected, in: [revisedTrend], currentFingerprint: "current", cachedFingerprint: "current"))
    }

    func testDetailFingerprintInvalidatesInteriorRawAndTrendCorrectionsBeforeAndAfterPreprocessing() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = (0..<3).map {
            MetricChartDataPoint(date: start.addingTimeInterval(Double($0) * 86_400),
                                 value: 81 + Double($0), presence: .present)
        }
        let processor = ChartSeriesPreprocessor(referenceDate: original[2].date)
        let oldCache = try XCTUnwrap(processor.seriesByRange(from: original)[.month1])
        let oldFingerprint = ContextualMetricDetailPolicy.fingerprint(points: original, trend: original)
        for correctedPoint in [
            MetricChartDataPoint(date: original[1].date, value: 82.5, presence: .present),
            MetricChartDataPoint(date: original[1].date, value: 82, presence: .estimated)
        ] {
            var corrected = original
            corrected[1] = correctedPoint
            let rawFingerprint = ContextualMetricDetailPolicy.fingerprint(points: corrected, trend: original)
            let trendFingerprint = ContextualMetricDetailPolicy.fingerprint(points: original, trend: corrected)
            XCTAssertNotEqual(rawFingerprint, oldFingerprint, "Same endpoints/count cannot hide an interior raw correction")
            XCTAssertNotEqual(trendFingerprint, oldFingerprint, "Same endpoints/count cannot hide an interior average correction")
            for currentFingerprint in [rawFingerprint, trendFingerprint] {
                XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(
                    original[1], in: oldCache, currentFingerprint: currentFingerprint, cachedFingerprint: oldFingerprint),
                             "Pending preprocessing must not authorize the previous82point")
            }
            let newCache = try XCTUnwrap(processor.seriesByRange(from: corrected)[.month1])
            XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(
                original[1], in: newCache, currentFingerprint: rawFingerprint, cachedFingerprint: rawFingerprint))
            XCTAssertEqual(ContextualMetricDetailPolicy.validatedFocus(
                correctedPoint, in: newCache, currentFingerprint: rawFingerprint, cachedFingerprint: rawFingerprint)?.id,
                           correctedPoint.id)
        }
    }

    func testDetailAverageDoesNotBorrowEqualRawValueSourceButRestHeadlineKeepsSource() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let average = MetricChartDataPoint(date: date, value: 80, presence: .present)
        let raw = MetricHistoryEntry(
            id: "raw", date: date, primaryValue: 80, secondaryValue: nil, source: .healthKit)
        XCTAssertNil(ContextualMetricDetailPolicy.source(
            point: average, entries: [raw], fallback: "Apple Health", isSmoothed: true))
        XCTAssertEqual(ContextualMetricDetailPolicy.source(
            point: average, entries: [raw], fallback: nil, isSmoothed: false), "Apple Health")
        XCTAssertEqual(ContextualMetricDetailPolicy.source(
            point: nil, entries: [raw], fallback: "Apple Health", isSmoothed: false), "Apple Health")
    }

    private func shareWeightMetric(weight: Double?, date: Date, source: String = "manual") -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString, userId: "synthetic-share-fixture", date: date,
            weight: weight, weightUnit: "kg", bodyFatPercentage: nil, bodyFatMethod: nil,
            muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil, dataSource: source,
            createdAt: date, updatedAt: date)
    }

    private func recognizedShareText(_ image: UIImage, diagnosticName: String = "share-render") throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        let records: [[String: Any]] = observations.map { observation in
            let candidate = observation.topCandidates(1).first
            let bounds = observation.boundingBox
            return [
                "text": candidate?.string ?? "",
                "confidence": Double(candidate?.confidence ?? 0),
                "normalizedLowerLeftBoundingBox": [
                    "x": Double(bounds.origin.x), "y": Double(bounds.origin.y),
                    "width": Double(bounds.size.width), "height": Double(bounds.size.height)
                ]
            ]
        }
        let diagnostic = try JSONSerialization.data(withJSONObject: [
            "pngName": diagnosticName,
            "textUsedByAssertions": text,
            "recognitionLevelRawValue": request.recognitionLevel.rawValue,
            "revision": request.revision,
            "recognitionLanguages": request.recognitionLanguages,
            "usesLanguageCorrection": request.usesLanguageCorrection,
            "observations": records
        ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: diagnostic, uniformTypeIdentifier: "public.json")
        attachment.name = diagnosticName + ".ocr.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        return text
    }


    private struct SharePNGTruth {
        let kind: ContextualMetricKind
        let value: String
        let unit: String
        let date: String?
        let evidence: String?
        var source: String?
        var hiddenDate: String?
    }

    private func renderingSnapshot(kind: ContextualMetricKind) throws -> ContextualMetricSnapshot {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        if kind == .steps {
            let daily = DailyMetrics(
                id: "png-day", userId: "synthetic", date: date, steps: 7_544,
                notes: nil, createdAt: date, updatedAt: date.addingTimeInterval(864_000))
            return .steps(daily, value: "7,544", range: "30 days")
        }
        if kind == .weight {
            let selected = shareWeightMetric(weight: 83.2, date: date, source: "healthkit")
            let history = [
                shareWeightMetric(weight: 81, date: date.addingTimeInterval(-86_400)),
                selected,
                shareWeightMetric(weight: 84, date: date.addingTimeInterval(86_400))
            ]
            return .weight(selected, metrics: history, prefersTrend: true,
                           context: ("kg", date.formatted(date: .abbreviated, time: .omitted), "30 days"),
                           formatValue: { String(format: "%.1f", $0) })
        }
        let ffmi = try XCTUnwrap(UnitConversion.calculateFFMI(weightKg: 80, bodyFatPercentage: 20, heightCm: 180))
        let value = kind == .bodyFat ? 17.4 : ffmi
        let presence: MetricPresence = kind == .bodyFat ? .estimated : .present
        let points: [MetricChartDataPoint] = (0..<7).map { index in
            let offset = Double(index - 3)
            let pointValue = index == 3 ? value : value + offset * 0.2
            return MetricChartDataPoint(
                date: date.addingTimeInterval(offset * 86_400), value: pointValue, presence: presence)
        }
        let selected = try XCTUnwrap(ContextualMetricProgressPolicy.presentationSelection(
            points: points, averages: [],
            focus: .init(date: date, value: value, kind: .daily)))
        XCTAssertTrue(selected.isFocused)
        XCTAssertEqual(selected.point.date, date)
        XCTAssertEqual(selected.point.value, value, accuracy: 0.0001)
        let entry = MetricHistoryEntry(
            id: "png-selected", date: date, primaryValue: value, secondaryValue: nil, source: .manual)
        // BF/FFMI use the real Progress policies and initializer; no private view factory is claimed.
        return ContextualMetricSnapshot(
            kind: kind, value: String(format: "%.1f", selected.point.value),
            unit: kind == .bodyFat ? "%" : "",
            observation: selected.point.date.formatted(date: .abbreviated, time: .shortened),
            range: "30 days", trend: nil, provenance: selected.source(entries: [entry]),
            evidence: ContextualMetricEvidencePolicy.label(
                for: kind, isEstimated: selected.point.isEstimated || selected.isSmoothed,
                isSmoothed: kind == .weight && selected.isSmoothed))
    }

    private func renderPNGText(
        _ snapshot: ContextualMetricSnapshot, aspect: BodyScoreShareAspect,
        options: BodyScoreShareOptions, name: String, privateSnapshots: [ContextualMetricSnapshot] = []
    ) throws -> String {
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(
            [snapshot] + privateSnapshots, selected: snapshot.kind))
        let size = aspect.pixelSize
        let renderer = ImageRenderer(content: BodyScoreShareCardView(payload: payload, aspect: aspect, options: options)
            .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let png = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let decoded = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(decoded.size, size)
        XCTAssertGreaterThan(png.count, 1_000)
        return try recognizedShareText(decoded, diagnosticName: name)
    }

    private func pngTruthMismatches(_ text: String, expected: SharePNGTruth) -> Set<String> {
        let lower = text.lowercased()
        let compact = lower.filter { $0.isLetter || $0.isNumber }
        let normalized = lower.replacingOccurrences(of: ",", with: "")
        let numeric = NSRegularExpression.escapedPattern(for: expected.value.replacingOccurrences(of: ",", with: ""))
        var mismatches = Set<String>()
        if !compact.contains(expected.kind.title.lowercased().filter { $0.isLetter || $0.isNumber }) {
            mismatches.insert("metric")
        }
        if normalized.range(of: "(?<![0-9.])" + numeric + "(?![0-9.])", options: .regularExpression) == nil {
            mismatches.insert("value")
        }
        let hasKilograms = lower.range(of: #"\bkg\b"#, options: .regularExpression) != nil
        let stepWords = lower.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.trimmingCharacters(in: .punctuationCharacters) == "steps" }
        let hasSteps = !stepWords.isEmpty
        if expected.unit == "kg" && !hasKilograms { mismatches.insert("unit") }
        // The uppercase metric title cannot substitute for the separate steps unit label.
        if expected.unit == "steps" && stepWords.count < 2 { mismatches.insert("unit") }
        if expected.unit == "%" && !lower.contains("%") { mismatches.insert("unit") }
        if expected.unit != "kg" && hasKilograms { mismatches.insert("unit") }
        if expected.unit != "steps" && hasSteps { mismatches.insert("unit") }
        if expected.unit != "%" && lower.contains("%") { mismatches.insert("unit") }
        if let date = expected.date {
            if !compact.contains(date.lowercased().filter { $0.isLetter || $0.isNumber }) {
                mismatches.insert("date")
            }
            if !compact.contains("30days") { mismatches.insert("range") }
        } else if compact.contains("30days") || compact.contains("privatetrend") {
            mismatches.insert("privacy")
        }
        if let hiddenDate = expected.hiddenDate,
           compact.contains(hiddenDate.lowercased().filter { $0.isLetter || $0.isNumber }) {
            mismatches.insert("privacy")
        }
        if let evidence = expected.evidence {
            if !compact.contains(evidence.lowercased().filter { $0.isLetter || $0.isNumber }) {
                mismatches.insert("evidence")
            }
        } else if lower.contains("smoothed") || lower.contains("estimated") || compact.contains("derivedestimate") {
            mismatches.insert("evidence")
        }
        if let source = expected.source {
            if !compact.contains(source.lowercased().filter { $0.isLetter || $0.isNumber }) {
                mismatches.insert("source")
            }
        } else if compact.contains("applehealth") || compact.contains("manual") || compact.contains("weightbodyfatandheight") {
            mismatches.insert("source")
        }
        if compact.contains("6210") || compact.contains("bodyscore") || compact.contains("privatesource") {
            mismatches.insert("unrelated")
        }
        if normalized.range(of: #"(?<![0-9.])991\.7(?![0-9.])"#, options: .regularExpression) != nil {
            mismatches.insert("privacy")
        }
        if expected.kind != .weight && normalized.range(
            of: #"(?<![0-9.])83\.2(?![0-9.])"#, options: .regularExpression) != nil {
            mismatches.insert("value")
        }
        // Token boundaries do not mistake legitimate "Inferred" text for Infinity.
        if lower.range(of: #"(?<![a-z])(?:nan|[+-]?inf(?:inity)?)(?![a-z])"#, options: .regularExpression) != nil {
            mismatches.insert("nonfinite")
        }
        return mismatches
    }

    private func contextualSnapshot(kind: ContextualMetricKind) -> ContextualMetricSnapshot {
        ContextualMetricSnapshot(
            kind: kind, value: kind == .steps ? "7,544" : "83.2", unit: kind == .steps ? "steps" : "kg",
            observation: "Oct 14, 2026", range: "30 days", trend: "6,210 average",
            provenance: "Apple Health"
        )
    }

    private func makePayload(
        bodyFatPercentage: Double?,
        gender: String?,
        photoImage: UIImage? = nil
    ) -> BodyScoreSharePayload {
        BodyScoreSharePayload(
            score: 82,
            scoreText: "82",
            tagline: "Athletic and trending leaner",
            ffmiValue: "21.8",
            ffmiCaption: "Strong",
            bodyFatValue: "16.4",
            bodyFatCaption: "%",
            weightValue: "181.0",
            weightCaption: "lb",
            deltaText: "+4 over 30 days",
            bodyFatPercentage: bodyFatPercentage,
            gender: gender,
            photoImage: photoImage
        )
    }

    private func makeShareTestImage(size: CGSize = CGSize(width: 480, height: 640)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // swiftlint:disable:next object_literal
            UIColor(red: 0.05, green: 0.11, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // swiftlint:disable:next object_literal
            UIColor(red: 0.12, green: 0.55, blue: 1.0, alpha: 1).setFill()
            context.fill(
                CGRect(
                    x: size.width * 0.23,
                    y: size.height * 0.12,
                    width: size.width * 0.54,
                    height: size.height * 0.72
                )
            )

            UIColor.white.withAlphaComponent(0.82).setFill()
            context.fill(
                CGRect(
                    x: size.width * 0.35,
                    y: size.height * 0.19,
                    width: size.width * 0.30,
                    height: size.height * 0.50
                )
            )
        }
    }
}
