import SwiftUI
import UIKit

/// Which details are rendered into an exported card.
/// Weight, body fat, FFMI, and a photo or avatar stay off until the person opts in.
struct BodyScoreShareOptions: Equatable {
    var selectedMetric: ContextualMetricKind?
    var includeObservation = true
    var includeRange = true
    var includeTrend = true
    var includeProvenance = false
    var includeWeight = false
    var includeBodyFat = false
    var includeFFMI = false
    var includeVisual = false

    static let all = BodyScoreShareOptions(
        includeWeight: true,
        includeBodyFat: true,
        includeFFMI: true,
        includeVisual: true
    )

    var hasMetrics: Bool {
        selectedMetric == nil && (includeWeight || includeBodyFat || includeFFMI)
    }

    var includedSummary: String {
        if let selectedMetric { return selectedMetric.title }
        var items = ["Body Score"]
        if includeWeight { items.append("weight") }
        if includeBodyFat { items.append("body fat") }
        if includeFFMI { items.append("FFMI") }
        if includeVisual { items.append("visual") }
        return items.joined(separator: ", ")
    }

    /// No visual means a composed score card. Metrics or a contextual detail
    /// share that card; they do not turn it into a photo caption.
    var cardComposition: ShareCardComposition {
        guard !includeVisual else { return .visualOverlay }
        if hasMetrics || selectedMetric != nil {
            return .scoreWithDetails
        }
        return .scoreOnly
    }
}

struct BodyScoreSharePayload {
    let score: Int
    let scoreText: String
    let tagline: String
    let ffmiValue: String
    let ffmiCaption: String
    let bodyFatValue: String
    let bodyFatCaption: String
    let weightValue: String
    let weightCaption: String
    let deltaText: String?
    let bodyFatPercentage: Double?
    let gender: String?
    let photoImage: UIImage?
    var contextualMetrics: [ContextualMetricSnapshot] = []
    var preferredMetric: ContextualMetricKind?
    var accountSession: AuthManager.ProfileSessionOwnership?

    func owned(by ownership: AuthManager.ProfileSessionOwnership) -> Self {
        var copy = self
        copy.accountSession = ownership
        return copy
    }

    @MainActor
    func isOwned(by owns: (AuthManager.ProfileSessionOwnership) -> Bool) -> Bool {
        guard let accountSession else { return false }
        return owns(accountSession)
    }

    var avatarMatch: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    /// Badge copy describes an opted-in visual only. An exported score is not a private delivery.
    func visualBadgeText(includeVisual: Bool) -> String {
        guard includeVisual else { return "" }
        return photoImage == nil ? avatarMatch.badgeText : "Progress photo"
    }
}

/// How the share card fills its export canvas.
enum ShareCardComposition: Equatable {
    /// Photo or avatar fills the card and the summary sits on the bottom matte.
    case visualOverlay
    /// Body Score alone. The number is the hero and the lockup stays one group.
    case scoreOnly
    /// Score plus opted-in metrics or a contextual detail line.
    case scoreWithDetails

    var isScoreComposition: Bool {
        self != .visualOverlay
    }
}

/// Preview frame drawn outside the exported artwork so the black card stays visible on the black editor.
enum BodyScoreSharePreviewGeometry {
    static let outset: CGFloat = 6

    static func artworkSize(in container: CGSize, aspect: BodyScoreShareAspect) -> CGSize {
        let available = CGSize(
            width: max(0, container.width - outset * 2),
            height: max(0, container.height - outset * 2)
        )
        return fitted(available, to: aspect.pixelSize)
    }

    static func fitted(_ container: CGSize, to target: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, target.width > 0, target.height > 0 else {
            return target
        }
        let fitted = min(container.width / target.width, container.height / target.height)
        return CGSize(width: target.width * fitted, height: target.height * fitted)
    }
}

enum BodyScoreShareAspect: String, CaseIterable, Identifiable {
    case square
    case portrait
    case story

    static let defaultExportAspect: BodyScoreShareAspect = .portrait

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .square:
            return "1:1"
        case .portrait:
            return "4:5"
        case .story:
            return "9:16"
        }
    }

    var pixelSize: CGSize {
        switch self {
        case .square:
            return CGSize(width: 1_080, height: 1_080)
        case .portrait:
            return CGSize(width: 1_080, height: 1_350)
        case .story:
            return CGSize(width: 1_080, height: 1_920)
        }
    }

    static func preferredExportAspect(for image: UIImage?) -> BodyScoreShareAspect {
        guard let image,
              image.size.width > 0,
              image.size.height > 0 else {
            return defaultExportAspect
        }

        let ratio = image.size.width / image.size.height
        if ratio > 0.86 {
            return .square
        }

        if ratio < 0.66 {
            return .story
        }

        return .portrait
    }
}

struct BodyScoreShareCardView: View {
    let payload: BodyScoreSharePayload
    let aspect: BodyScoreShareAspect
    let options: BodyScoreShareOptions

    init(
        payload: BodyScoreSharePayload,
        aspect: BodyScoreShareAspect,
        options: BodyScoreShareOptions = .all
    ) {
        self.payload = payload
        self.aspect = aspect
        self.options = options
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = ShareCardLayout(
                size: geometry.size,
                aspect: aspect,
                includesMetrics: options.hasMetrics,
                composition: options.cardComposition
            )

            ZStack {
                Color.black

                if layout.composition == .visualOverlay {
                    visualOverlay(layout: layout)
                } else {
                    scoreComposition(layout: layout)
                }
            }
        }
        .aspectRatio(aspectRatioValue, contentMode: .fit)
        .clipped()
        .dynamicTypeSize(.medium)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Share card. Includes \(options.includedSummary).")
        .accessibilityIdentifier("body_score_share_card")
    }

    private var aspectRatioValue: CGFloat {
        let size = aspect.pixelSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func visualOverlay(layout: ShareCardLayout) -> some View {
        ZStack {
            visualStage(layout: layout)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .top)

            shareScrims(layout: layout)

            VStack(spacing: 0) {
                shareHeader(layout: layout)

                Spacer(minLength: layout.bottomOverlayHeight * 0.08)

                shareSummary(layout: layout)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
        }
    }

    /// Header, hero score, and footer stay one group. Extra canvas becomes space around that group.
    private func scoreComposition(layout: ShareCardLayout) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: layout.compositionSpacing) {
                shareHeader(layout: layout)
                scoreCompositionSummary(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.safeMargin)
        .padding(.vertical, layout.safeMargin)
    }

    private func visualStage(layout: ShareCardLayout) -> some View {
        Group {
            if options.includeVisual, let photoImage = payload.photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .center)
                    .clipped()
                    .accessibilityLabel("Progress photo")
                    .accessibilityIdentifier("body_score_share_photo_visual")
            } else if options.includeVisual {
                VStack(spacing: 0) {
                    Spacer(minLength: layout.visualTopOffset)

                    AvatarBodyRenderer(
                        bodyFatPercentage: payload.bodyFatPercentage,
                        gender: payload.gender,
                        height: layout.visualHeight,
                        padding: 0,
                        verticalPadding: 0,
                        horizontalFillScale: 1.04,
                        alignment: .bottom,
                        renderMode: .fillWidth
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("body_score_share_avatar_visual")

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func shareHeader(layout: ShareCardLayout) -> some View {
        HStack(spacing: layout.headerSpacing) {
            DSLogo(size: layout.logoSize, showText: false)

            VStack(alignment: .leading, spacing: layout.headerTextSpacing) {
                Text("LogYourBody")
                    .font(.system(size: layout.brandFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier("body_score_share_brand")

                let badge = payload.visualBadgeText(includeVisual: options.includeVisual)
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: layout.badgeFontSize, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.62))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.72)
                        .accessibilityIdentifier("body_score_share_badge")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func scoreCompositionSummary(layout: ShareCardLayout) -> some View {
        let snapshot = payload.snapshot(for: options)
        let detail = snapshot.map { $0.detail(options: options) } ?? payload.deltaText
        let supporting = snapshot?.unit ?? payload.tagline

        return VStack(alignment: .leading, spacing: layout.heroStackSpacing) {
            HStack(alignment: .lastTextBaseline, spacing: layout.scoreLabelSpacing) {
                Text(snapshot?.value ?? payload.scoreText)
                    .font(.system(size: layout.scoreFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("body_score_share_score")

                if snapshot?.unit == "%" {
                    Text("%")
                        .font(.system(size: layout.scoreFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .accessibilityIdentifier("body_score_share_unit")
                }
            }

            Text(options.selectedMetric?.title ?? "Body Score")
                .font(.system(size: layout.scoreLabelFontSize, weight: .bold))
                .foregroundColor(Color.white.opacity(0.66))
                .textCase(.uppercase)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)

            if snapshot?.unit != "%" && !supporting.isEmpty {
                Text(supporting)
                    .font(.system(size: layout.taglineFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body_score_share_tagline")
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: layout.deltaFontSize, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.66))
                    .lineLimit(options.selectedMetric == nil ? 1 : 4)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body_score_share_delta")
            }

            if options.hasMetrics {
                shareMetrics(layout: layout)
            }

            Text("Shared from LogYourBody")
                .font(.system(size: layout.footerFontSize, weight: .medium))
                .foregroundColor(Color.white.opacity(0.58))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.74)
                .accessibilityIdentifier("body_score_share_footer")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body_score_share_summary")
    }

    private func shareSummary(layout: ShareCardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.summarySpacing) {
            HStack(alignment: .lastTextBaseline, spacing: layout.scoreSpacing) {
                HStack(alignment: .lastTextBaseline, spacing: layout.scoreLabelSpacing) {
                    Text(payload.snapshot(for: options)?.value ?? payload.scoreText)
                        .font(.system(size: layout.scoreFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.58)
                        .accessibilityIdentifier("body_score_share_score")

                    // A tagline-sized "%" is dropped by Vision when the detail line is long.
                    // Keep the score identifier on the number and draw the percent with it.
                    if payload.snapshot(for: options)?.unit == "%" {
                        Text("%")
                            .font(.system(size: layout.scoreFontSize, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .accessibilityIdentifier("body_score_share_unit")
                    }
                }

                VStack(alignment: .leading, spacing: layout.scoreLabelSpacing) {
                    Text(options.selectedMetric?.title ?? "Body Score")
                        .font(.system(size: layout.scoreLabelFontSize, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.66))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)

                    if payload.snapshot(for: options)?.unit != "%" {
                        Text(payload.snapshot(for: options)?.unit ?? payload.tagline)
                            .font(.system(size: layout.taglineFontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("body_score_share_tagline")
                    }

                    if let deltaText = payload.snapshot(for: options).map({ $0.detail(options: options) }) ?? payload.deltaText {
                        Text(deltaText)
                            .font(.system(size: layout.deltaFontSize, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.66))
                            .lineLimit(options.selectedMetric == nil ? 1 : 4)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier("body_score_share_delta")
                    }
                }

                Spacer(minLength: 0)
            }

            if options.hasMetrics {
                shareMetrics(layout: layout)
            }

            Text("Shared from LogYourBody")
                .font(.system(size: layout.footerFontSize, weight: .medium))
                .foregroundColor(Color.white.opacity(0.58))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.74)
                .accessibilityIdentifier("body_score_share_footer")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body_score_share_summary")
    }

    private func shareScrims(layout: ShareCardLayout) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.98),
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.headerMatteHeight)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    Color.black,
                    Color.black,
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.summaryMatteHeight)
        }
    }

    private func shareMetric(
        _ title: String,
        _ value: String,
        _ caption: String,
        identifier: String,
        layout: ShareCardLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: layout.metricTextSpacing) {
            Text(title)
                .font(.system(size: layout.metricTitleFontSize, weight: .bold))
                .foregroundColor(Color.white.opacity(0.58))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.68)

            Text(value)
                .font(.system(size: layout.metricValueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.58)

            Text(caption)
                .font(.system(size: layout.metricCaptionFontSize, weight: .medium))
                .foregroundColor(Color.white.opacity(0.54))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body_score_share_metric_\(identifier)")
    }

    @ViewBuilder
    private func shareMetrics(layout: ShareCardLayout) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: layout.metricSpacing) {
                if options.includeWeight {
                    shareMetric("Weight", payload.weightValue, payload.weightCaption, identifier: "weight", layout: layout)
                }
                if options.includeBodyFat {
                    shareMetric("Body Fat", payload.bodyFatValue, payload.bodyFatCaption, identifier: "body_fat", layout: layout)
                }
                if options.includeFFMI {
                    shareMetric("FFMI", payload.ffmiValue, payload.ffmiCaption, identifier: "ffmi", layout: layout)
                }
            }
            .accessibilityIdentifier("body_score_share_metrics")

            VStack(alignment: .leading, spacing: layout.metricSpacing * 0.55) {
                if options.includeWeight {
                    shareMetric("Weight", payload.weightValue, payload.weightCaption, identifier: "weight", layout: layout)
                }
                if options.includeBodyFat {
                    shareMetric("Body Fat", payload.bodyFatValue, payload.bodyFatCaption, identifier: "body_fat", layout: layout)
                }
                if options.includeFFMI {
                    shareMetric("FFMI", payload.ffmiValue, payload.ffmiCaption, identifier: "ffmi", layout: layout)
                }
            }
            .accessibilityIdentifier("body_score_share_metrics_stacked")
        }
    }
}

struct ShareCardLayout {
    let size: CGSize
    let aspect: BodyScoreShareAspect
    let includesMetrics: Bool
    let composition: ShareCardComposition

    init(
        size: CGSize,
        aspect: BodyScoreShareAspect,
        includesMetrics: Bool = true,
        composition: ShareCardComposition = .visualOverlay
    ) {
        self.size = size
        self.aspect = aspect
        self.includesMetrics = includesMetrics
        self.composition = composition
    }

    /// Fit into the export canvas. Preview and export share this scale with no clamp.
    var scale: CGFloat {
        let export = aspect.pixelSize
        guard export.width > 0, export.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / export.width, size.height / export.height)
    }

    /// Photo-overlay type stays at the size the export used before the canonical
    /// space moved to export pixels, so avatar clearance does not shift.
    private var overlayExportScale: CGFloat {
        switch aspect {
        case .square:
            return 1_080.0 / 520.0
        case .portrait:
            return 1_350.0 / 620.0
        case .story:
            return 1_920.0 / 760.0
        }
    }

    private func overlay(_ base: CGFloat) -> CGFloat {
        base * overlayExportScale * scale
    }

    private func px(_ exportPixels: CGFloat) -> CGFloat {
        exportPixels * scale
    }

    var safeMargin: CGFloat { horizontalPadding }

    var compositionSpacing: CGFloat {
        px(composition == .scoreOnly ? 48 : 24)
    }

    var heroStackSpacing: CGFloat { px(8) }

    var horizontalPadding: CGFloat {
        if composition.isScoreComposition {
            return px(aspect == .story ? 96 : 72)
        }
        return overlay(28)
    }
    var topPadding: CGFloat { overlay(30) }
    var bottomPadding: CGFloat { overlay(26) }
    var headerSpacing: CGFloat { composition.isScoreComposition ? px(14) : overlay(12) }
    var headerTextSpacing: CGFloat { composition.isScoreComposition ? px(2) : overlay(2) }
    var logoSize: CGFloat { composition.isScoreComposition ? px(52) : overlay(36) }
    var logoTextSize: CGFloat { composition.isScoreComposition ? px(32) : overlay(16) }
    var brandFontSize: CGFloat { composition.isScoreComposition ? px(32) : overlay(16) }
    var badgeFontSize: CGFloat { composition.isScoreComposition ? px(22) : overlay(11) }
    var summarySpacing: CGFloat { composition.isScoreComposition ? px(20) : overlay(17) }
    var scoreSpacing: CGFloat { composition.isScoreComposition ? px(12) : overlay(13) }
    var scoreLabelSpacing: CGFloat { composition.isScoreComposition ? px(6) : overlay(4) }
    var scoreFontSize: CGFloat {
        switch composition {
        case .visualOverlay:
            return overlay(54)
        case .scoreOnly:
            return px(min(aspect.pixelSize.height * 0.24, 360))
        case .scoreWithDetails:
            return px(min(aspect.pixelSize.height * 0.16, 240))
        }
    }
    var scoreLabelFontSize: CGFloat { composition.isScoreComposition ? px(24) : overlay(11) }
    var taglineFontSize: CGFloat { composition.isScoreComposition ? px(30) : overlay(15) }
    var deltaFontSize: CGFloat { composition.isScoreComposition ? px(24) : overlay(12) }
    var metricSpacing: CGFloat { composition.isScoreComposition ? px(16) : overlay(13) }
    var metricTextSpacing: CGFloat { composition.isScoreComposition ? px(4) : overlay(4) }
    var metricTitleFontSize: CGFloat { composition.isScoreComposition ? px(16) : overlay(10) }
    var metricValueFontSize: CGFloat { composition.isScoreComposition ? px(34) : overlay(18) }
    var metricCaptionFontSize: CGFloat { composition.isScoreComposition ? px(16) : overlay(10) }
    var footerFontSize: CGFloat { composition.isScoreComposition ? px(22) : overlay(11) }

    var visualTopOffset: CGFloat {
        switch aspect {
        case .square:
            return size.height * 0.12
        case .portrait:
            return size.height * 0.08
        case .story:
            return size.height * 0.08
        }
    }

    var visualHeight: CGFloat {
        let baseHeight: CGFloat
        switch aspect {
        case .square:
            baseHeight = size.height * 0.60
        case .portrait:
            baseHeight = size.height * 0.66
        case .story:
            baseHeight = size.height * 0.62
        }

        let maximumBottom = summaryTopY - textVisualGap
        return max(0, min(baseHeight, maximumBottom - visualTopOffset))
    }

    var textVisualGap: CGFloat { max(overlay(10), size.height * 0.018) }

    var estimatedSummaryContentHeight: CGFloat {
        let scoreLabelStack = scoreLabelFontSize + taglineFontSize * 2.6 + deltaFontSize + scoreLabelSpacing * 3
        let scoreRow = max(scoreFontSize * 1.02, scoreLabelStack)
        let metricRow = metricTitleFontSize + metricValueFontSize + metricCaptionFontSize + metricTextSpacing * 2
        let metricHeight = includesMetrics ? summarySpacing + metricRow * 1.12 : 0
        return scoreRow + metricHeight + summarySpacing + footerFontSize * 1.2
    }

    var summaryTopY: CGFloat {
        max(headerMatteHeight + textVisualGap, size.height - bottomPadding - estimatedSummaryContentHeight)
    }

    var headerMatteHeight: CGFloat {
        switch aspect {
        case .square:
            return size.height * 0.25
        case .portrait:
            return size.height * 0.20
        case .story:
            return size.height * 0.18
        }
    }

    var summaryMatteHeight: CGFloat {
        let minimumHeight = size.height - summaryTopY + bottomPadding
        let baseHeight: CGFloat
        switch aspect {
        case .square:
            baseHeight = size.height * 0.60
        case .portrait:
            baseHeight = size.height * 0.54
        case .story:
            baseHeight = size.height * 0.46
        }
        return max(baseHeight, minimumHeight)
    }

    var bottomOverlayHeight: CGFloat {
        switch aspect {
        case .square:
            return size.height * 0.36
        case .portrait:
            return size.height * 0.33
        case .story:
            return size.height * 0.28
        }
    }
}

struct BodyScoreSharePreviewChrome: View {
    let payload: BodyScoreSharePayload
    let aspect: BodyScoreShareAspect
    let options: BodyScoreShareOptions
    let artworkSize: CGSize

    var body: some View {
        BodyScoreShareCardView(payload: payload, aspect: aspect, options: options)
            .frame(width: artworkSize.width, height: artworkSize.height)
            .padding(BodyScoreSharePreviewGeometry.outset)
            .background(Color.white.opacity(0.16))
            .overlay(
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
            )
            // An identifier here replaces the card's own accessibility identifier.
    }
}

struct BodyScoreShareSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let payload: BodyScoreSharePayload
    let onClose: (() -> Void)?

    @State private var selectedAspect: BodyScoreShareAspect
    @State private var shareOptions = BodyScoreShareOptions()
    @State private var areContentControlsExpanded = false
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var exportFailure: String?
    @State private var showSystemShareSheet = false
    @State private var dragOffsetY: CGFloat = 0

    /// Minimum downward drag distance required to dismiss the overlay share sheet.
    static let dismissDragThreshold: CGFloat = 120

    init(payload: BodyScoreSharePayload, onClose: (() -> Void)? = nil) {
        self.payload = payload
        self.onClose = onClose
        _shareOptions = State(initialValue: BodyScoreShareOptions(selectedMetric: payload.preferredMetric))
        _selectedAspect = State(initialValue: BodyScoreShareAspect.preferredExportAspect(for: payload.photoImage))
    }

    var body: some View {
        ZStack {
            sheetSurface
        }
        .worldClassScreen(.shareBodyScore)
    }

    private var sheetSurface: some View {
        Group {
            if !payload.isOwned(by: authManager.ownsAccountSession) {
                Color.clear
            } else if dynamicTypeSize.isAccessibilitySize {
                ScrollView(showsIndicators: false) {
                    shareSheetContent(previewHeight: 420)
                        .padding(.vertical, JovieTokens.itemGap)
                }
            } else {
                shareSheetContent(previewHeight: nil)
                    // The accessibility ScrollView branch owns vertical content
                    // scrolling; do not also bind the dismiss drag to this branch.
                    .gesture(dismissDragGesture)
            }
        }
        // Keep content inside the safe area so Close stays tappable under Dynamic Island / notch.
        .padding(.top, JovieTokens.compactInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.jovieCanvas.ignoresSafeArea())
        .offset(y: max(0, dragOffsetY))
        .opacity(dismissDragOpacity)
        .overlay {
            if isRendering {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
        }
        .sheet(isPresented: $showSystemShareSheet) {
            if payload.isOwned(by: authManager.ownsAccountSession), let image = renderedImage {
                ShareSheet(items: [image])
                    .ignoresSafeArea()
            }
        }
        .alert("Unable to export card", isPresented: Binding(
            get: { exportFailure != nil },
            set: { if !$0 { exportFailure = nil } }
        )) {
            Button("OK", role: .cancel) { exportFailure = nil }
        } message: {
            Text(exportFailure ?? "Try again.")
        }
        .onChange(of: authManager.captureAccountSession()) { _, _ in
            guard !payload.isOwned(by: authManager.ownsAccountSession) else { return }
            invalidatePrivateExport()
            closeShareSheet()
        }
        .onDisappear { invalidatePrivateExport() }
        .onChange(of: payload.contextualMetrics) { _, _ in renderedImage = nil }
        .onChange(of: selectedAspect) { _, _ in
            renderedImage = nil
        }
        .onChange(of: shareOptions) { _, _ in
            renderedImage = nil
        }
        // Hardware Escape / keyboard dismiss path for the full-screen overlay presentation.
        .onKeyPress(.escape) {
            closeShareSheet()
            return .handled
        }
        .accessibilityAction(.escape) {
            closeShareSheet()
        }
    }

    private var dismissDragOpacity: Double {
        guard dragOffsetY > 0 else { return 1 }
        let progress = min(1, Double(dragOffsetY / (Self.dismissDragThreshold * 2)))
        return max(0.45, 1 - progress * 0.55)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                // Only predominantly vertical drags may pull the sheet; horizontal
                // format-control swipes must not move or dismiss it.
                guard !isRendering,
                      Self.isVerticalGesture(
                        translationWidth: value.translation.width,
                        translationHeight: value.translation.height
                      ) else { return }
                dragOffsetY = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isRendering else {
                    dragOffsetY = 0
                    return
                }

                // A diagonal or horizontal gesture never dismisses, even when its
                // vertical component passes the threshold; the surface springs back.
                let isVertical = Self.isVerticalGesture(
                    translationWidth: value.translation.width,
                    translationHeight: value.translation.height
                )

                if isVertical, Self.shouldDismiss(
                    afterDragTranslation: value.translation.height,
                    predictedEndTranslation: value.predictedEndTranslation.height
                ) {
                    closeShareSheet()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dragOffsetY = 0
                    }
                }
            }
    }

    /// Pure axis-dominance policy so unit tests can lock which gesture owns the
    /// surface without a UI harness: only predominantly vertical drags may drive
    /// dismissal; horizontal format-control swipes and diagonal drags never do.
    static func isVerticalGesture(
        translationWidth: CGFloat,
        translationHeight: CGFloat
    ) -> Bool {
        abs(translationHeight) >= abs(translationWidth)
    }

    /// Pure dismiss-threshold policy so unit tests can lock the escape path without UI harness.
    static func shouldDismiss(
        afterDragTranslation translationY: CGFloat,
        predictedEndTranslation: CGFloat,
        threshold: CGFloat = dismissDragThreshold
    ) -> Bool {
        translationY >= threshold || predictedEndTranslation >= threshold * 1.4
    }

    private func closeShareSheet() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
        dragOffsetY = 0
    }

    private var sheetHeader: some View {
        HStack {
            Button(action: closeShareSheet) {
                Text("Close")
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.text)
            }
            .jovieTouchTarget()
            .accessibilityIdentifier("body_score_share_close_button")
            .accessibilityLabel("Close share sheet")
            .accessibilityHint("Dismisses the body score share view")

            Spacer()

            Text("Share \(shareOptions.selectedMetric?.title ?? "Body Score")")
                .font(theme.typography.headlineSmall)
                .foregroundColor(theme.colors.text)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 72, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, JovieTokens.screenInset)
    }

    private var previewVerticalInset: CGFloat { 4 }

    private func shareSheetContent(previewHeight: CGFloat?) -> some View {
        VStack(spacing: JovieTokens.itemGap) {
            sheetHeader

            VStack(spacing: JovieTokens.itemGap) {
                Picker("Format", selection: $selectedAspect) {
                    ForEach(BodyScoreShareAspect.allCases) { aspect in
                        Text(aspect.displayName).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, JovieTokens.screenInset)
                .accessibilityLabel("Card format")

                if !payload.contextualMetrics.isEmpty {
                    Picker("Metric", selection: $shareOptions.selectedMetric) {
                        if payload.score > 0 { Text("Body Score").tag(Optional<ContextualMetricKind>.none) }
                        ForEach(payload.contextualMetrics) { snapshot in
                            Text(snapshot.kind.title).tag(Optional(snapshot.kind))
                        }
                    }
                    .accessibilityIdentifier("contextual_share_metric_picker")
                }

                contentControls

                cardPreview(height: previewHeight)

                shareActions
                    .disabled(isRendering)
            }
            // The content is a real sibling of Close/title under the world screen root.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("body_score_share_sheet")
        }
        .padding(.top, JovieTokens.itemGap)
        .padding(.bottom, JovieTokens.compactInset)
    }

    private var contentControls: some View {
        DisclosureGroup(isExpanded: $areContentControlsExpanded) {
            VStack(spacing: 0) {
                if shareOptions.selectedMetric != nil {
                    Toggle("Date", isOn: $shareOptions.includeObservation)
                    Toggle("Range", isOn: $shareOptions.includeRange)
                    Toggle("Trend", isOn: $shareOptions.includeTrend)
                    Toggle("Source", isOn: $shareOptions.includeProvenance)
                } else {
                Toggle("Weight", isOn: $shareOptions.includeWeight)
                Toggle("Body fat", isOn: $shareOptions.includeBodyFat)
                Toggle("FFMI", isOn: $shareOptions.includeFFMI)
                Toggle(payload.photoImage == nil ? "Body visual" : "Progress photo", isOn: $shareOptions.includeVisual)
                }
            }
            .font(theme.typography.bodyMedium)
            .tint(theme.colors.info)
            .padding(.top, theme.spacing.xs)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Included on card")
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)

                Text(shareOptions.includedSummary)
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(theme.spacing.sm)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .padding(.horizontal, JovieTokens.screenInset)
        .accessibilityIdentifier("body_score_share_content_controls")
    }

    private func cardPreview(height: CGFloat?) -> some View {
        GeometryReader { geometry in
            let verticalInset = previewVerticalInset
            let availableSize = CGSize(
                width: geometry.size.width,
                height: max(0, geometry.size.height - verticalInset * 2)
            )
            let artwork = BodyScoreSharePreviewGeometry.artworkSize(in: availableSize, aspect: selectedAspect)

            BodyScoreSharePreviewChrome(
                payload: payload,
                aspect: selectedAspect,
                options: shareOptions,
                artworkSize: artwork
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.vertical, verticalInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: height)
        .padding(.horizontal, JovieTokens.screenInset)
    }

    private var shareActions: some View {
        HStack(spacing: JovieTokens.itemGap) {
            shareActionButton(title: "Save", icon: "square.and.arrow.down") {
                Task { await saveToPhotos() }
            }
            .accessibilityIdentifier("body_score_share_save_button")

            shareActionButton(title: "Share", icon: "square.and.arrow.up") {
                Task { await shareImage() }
            }
            .accessibilityIdentifier("body_score_share_system_button")
        }
        .padding(.horizontal, JovieTokens.screenInset)
    }

    private func shareActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(theme.typography.labelLarge)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.compactControlHeight)
        }
        .buttonStyle(.plain)
        .foregroundColor(Color.jovieActionText)
        .background(theme.colors.interactive)
        .clipShape(Capsule())
        .accessibilityHint("Renders a card containing \(shareOptions.includedSummary)")
    }

    private func invalidatePrivateExport() {
        renderedImage = nil
        showSystemShareSheet = false
        exportFailure = nil
    }

    @MainActor
    private func renderImage() {
        guard payload.isOwned(by: authManager.ownsAccountSession) else {
            invalidatePrivateExport()
            return
        }
        isRendering = true
        defer { isRendering = false }

        let size = selectedAspect.pixelSize
        let renderer = ImageRenderer(
            content:
                BodyScoreShareCardView(payload: payload, aspect: selectedAspect, options: shareOptions)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1.0
        renderedImage = renderer.uiImage
    }

    @MainActor
    private func shareImage() async {
        guard payload.isOwned(by: authManager.ownsAccountSession) else {
            invalidatePrivateExport()
            return
        }
        if renderedImage == nil {
            renderImage()
        }
        guard renderedImage != nil else {
            exportFailure = "The card could not be rendered. Try again."
            return
        }
        showSystemShareSheet = true
    }

    @MainActor
    private func saveToPhotos() async {
        guard payload.isOwned(by: authManager.ownsAccountSession) else {
            invalidatePrivateExport()
            return
        }
        if renderedImage == nil {
            renderImage()
        }
        guard let image = renderedImage else {
            exportFailure = "The card could not be rendered. Try again."
            return
        }

        let saved = await LivePhotoLibraryAdapter.shared.saveImage(
            image, whileOwned: { payload.isOwned(by: authManager.ownsAccountSession) })
        guard payload.isOwned(by: authManager.ownsAccountSession) else {
            invalidatePrivateExport()
            return
        }
        if !saved {
            exportFailure = "Photos access is unavailable. Allow access in Settings or use Share to export the card."
        }
    }
}
