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
