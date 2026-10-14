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
        for kind in [ContextualMetricKind.steps, .weight, .bodyFat, .ffmi] {
            let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([contextualSnapshot(kind: kind)], selected: kind))
            let options = BodyScoreShareOptions(selectedMetric: kind)
            for aspect in BodyScoreShareAspect.allCases {
                let size = aspect.pixelSize
                let renderer = ImageRenderer(content: BodyScoreShareCardView(payload: payload, aspect: aspect, options: options)
                    .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let png = try XCTUnwrap(image.pngData())
                let decoded = try XCTUnwrap(UIImage(data: png))
                XCTAssertEqual(decoded.size, size)
                XCTAssertGreaterThan(png.count, 1_000)
                let text = try recognizedShareText(decoded)
                let expected = contextualSnapshot(kind: kind).value.filter(\.isNumber)
                XCTAssertTrue(text.filter(\.isNumber).contains(expected), "Export must contain selected value for \(kind)")
                XCTAssertFalse(text.lowercased().contains("body score"))
            }
        }
    }

    func testEvidenceMeaningCannotBeHiddenBySourcePrivacy() {
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
        XCTAssertEqual(ContextualMetricDetailPolicy.validatedFocus(selected, in: [selected])?.value, 82)
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(selected, in: [corrected]))
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(selected, in: []))
        let revisedTrend = MetricChartDataPoint(date: date, value: 81, presence: .estimated)
        XCTAssertNil(ContextualMetricDetailPolicy.validatedFocus(selected, in: [revisedTrend]))
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

    private func recognizedShareText(_ image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
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
