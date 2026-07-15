import SwiftUI
import UIKit

/// Controls precisely which personal details leave the app in a rendered card.
/// The private default keeps the card to the Body Score until the person opts in.
struct BodyScoreShareOptions: Equatable {
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
        includeWeight || includeBodyFat || includeFFMI
    }

    var includedSummary: String {
        var items = ["Body Score"]
        if includeWeight { items.append("weight") }
        if includeBodyFat { items.append("body fat") }
        if includeFFMI { items.append("FFMI") }
        if includeVisual { items.append("visual") }
        return items.joined(separator: ", ")
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

    var avatarMatch: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    func visualBadgeText(includeVisual: Bool) -> String {
        guard includeVisual else { return "Private summary" }
        return photoImage == nil ? avatarMatch.badgeText : "Progress photo"
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
            let layout = ShareCardLayout(size: geometry.size, aspect: aspect, includesMetrics: options.hasMetrics)

            ZStack {
                Color.black

                visualStage(layout: layout)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

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
        .aspectRatio(aspectRatioValue, contentMode: .fit)
        .clipped()
        .dynamicTypeSize(.medium)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body Score share card. Includes \(options.includedSummary).")
        .accessibilityIdentifier("body_score_share_card")
    }

    private var aspectRatioValue: CGFloat {
        let size = aspect.pixelSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
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

                Text(payload.visualBadgeText(includeVisual: options.includeVisual))
                    .font(.system(size: layout.badgeFontSize, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("body_score_share_badge")
            }

            Spacer(minLength: 0)
        }
    }

    private func shareSummary(layout: ShareCardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.summarySpacing) {
            HStack(alignment: .lastTextBaseline, spacing: layout.scoreSpacing) {
                Text(payload.scoreText)
                    .font(.system(size: layout.scoreFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.58)
                    .accessibilityIdentifier("body_score_share_score")

                VStack(alignment: .leading, spacing: layout.scoreLabelSpacing) {
                    Text("Body Score")
                        .font(.system(size: layout.scoreLabelFontSize, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.66))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)

                    Text(payload.tagline)
                        .font(.system(size: layout.taglineFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body_score_share_tagline")

                    if let deltaText = payload.deltaText {
                        Text(deltaText)
                            .font(.system(size: layout.deltaFontSize, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.66))
                            .lineLimit(1)
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

    init(size: CGSize, aspect: BodyScoreShareAspect, includesMetrics: Bool = true) {
        self.size = size
        self.aspect = aspect
        self.includesMetrics = includesMetrics
    }

    var scale: CGFloat {
        let reference = referenceSize
        let widthScale = reference.width > 0 ? size.width / reference.width : 1
        let heightScale = reference.height > 0 ? size.height / reference.height : 1
        return min(max(min(widthScale, heightScale), 0.58), 2.8)
    }

    private var referenceSize: CGSize {
        switch aspect {
        case .square:
            return CGSize(width: 390, height: 520)
        case .portrait:
            return CGSize(width: 390, height: 620)
        case .story:
            return CGSize(width: 390, height: 760)
        }
    }

    var horizontalPadding: CGFloat { 28 * scale }
    var topPadding: CGFloat { 30 * scale }
    var bottomPadding: CGFloat { 26 * scale }
    var headerSpacing: CGFloat { 12 * scale }
    var headerTextSpacing: CGFloat { 2 * scale }
    var logoSize: CGFloat { 36 * scale }
    var logoTextSize: CGFloat { 16 * scale }
    var brandFontSize: CGFloat { 16 * scale }
    var badgeFontSize: CGFloat { 11 * scale }
    var summarySpacing: CGFloat { 17 * scale }
    var scoreSpacing: CGFloat { 13 * scale }
    var scoreLabelSpacing: CGFloat { 4 * scale }
    var scoreFontSize: CGFloat { 54 * scale }
    var scoreLabelFontSize: CGFloat { 11 * scale }
    var taglineFontSize: CGFloat { 15 * scale }
    var deltaFontSize: CGFloat { 12 * scale }
    var metricSpacing: CGFloat { 13 * scale }
    var metricTextSpacing: CGFloat { 4 * scale }
    var metricTitleFontSize: CGFloat { 10 * scale }
    var metricValueFontSize: CGFloat { 18 * scale }
    var metricCaptionFontSize: CGFloat { 10 * scale }
    var footerFontSize: CGFloat { 11 * scale }

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

    var textVisualGap: CGFloat { max(10 * scale, size.height * 0.018) }

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

struct BodyScoreShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let payload: BodyScoreSharePayload
    let onClose: (() -> Void)?

    @State private var selectedAspect: BodyScoreShareAspect
    @State private var shareOptions = BodyScoreShareOptions()
    @State private var areContentControlsExpanded = true
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var showSystemShareSheet = false

    init(payload: BodyScoreSharePayload, onClose: (() -> Void)? = nil) {
        self.payload = payload
        self.onClose = onClose
        _selectedAspect = State(initialValue: BodyScoreShareAspect.preferredExportAspect(for: payload.photoImage))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(showsIndicators: false) {
                    shareSheetContent(previewHeight: 360)
                        .padding(.vertical, JovieTokens.itemGap)
                }
            } else {
                shareSheetContent(previewHeight: nil)
            }
        }
        .background(Color.jovieCanvas.ignoresSafeArea())
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
            if let image = renderedImage {
                ShareSheet(items: [image])
                    .ignoresSafeArea()
            }
        }
        .onChange(of: selectedAspect) { _, _ in
            renderedImage = nil
        }
        .onChange(of: shareOptions) { _, _ in
            renderedImage = nil
        }
    }

    private var sheetHeader: some View {
        HStack {
            Button("Close") {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            }
            .font(theme.typography.labelMedium)
            .foregroundColor(theme.colors.text)
            .jovieTouchTarget()

            Spacer()

            Text("Share Body Score")
                .font(theme.typography.headlineSmall)
                .foregroundColor(theme.colors.text)
                .lineLimit(1)

            Spacer()

            Color.clear
                .frame(width: 72, height: 1)
        }
        .padding(.horizontal, JovieTokens.screenInset)
    }

    private var previewVerticalInset: CGFloat { 8 }

    private func shareSheetContent(previewHeight: CGFloat?) -> some View {
        VStack(spacing: JovieTokens.itemGap) {
            sheetHeader

            Picker("Format", selection: $selectedAspect) {
                ForEach(BodyScoreShareAspect.allCases) { aspect in
                    Text(aspect.displayName).tag(aspect)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, JovieTokens.screenInset)
            .accessibilityLabel("Card format")

            contentControls

            cardPreview(height: previewHeight)

            shareActions
                .disabled(isRendering)
        }
        .padding(.top, JovieTokens.itemGap)
        .padding(.bottom, JovieTokens.compactInset)
    }

    private var contentControls: some View {
        DisclosureGroup(isExpanded: $areContentControlsExpanded) {
            VStack(spacing: 0) {
                Toggle("Weight", isOn: $shareOptions.includeWeight)
                Toggle("Body fat", isOn: $shareOptions.includeBodyFat)
                Toggle("FFMI", isOn: $shareOptions.includeFFMI)
                Toggle(payload.photoImage == nil ? "Body visual" : "Progress photo", isOn: $shareOptions.includeVisual)
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
            let size = fittedSize(for: availableSize, target: selectedAspect.pixelSize)

            BodyScoreShareCardView(payload: payload, aspect: selectedAspect, options: shareOptions)
                .frame(width: size.width, height: size.height)
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

    private func fittedSize(for container: CGSize, target: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else {
            return target
        }

        let scale = min(container.width / target.width, container.height / target.height)
        return CGSize(width: target.width * scale, height: target.height * scale)
    }

    @MainActor
    private func renderImage() {
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
        if renderedImage == nil {
            renderImage()
        }
        guard renderedImage != nil else { return }
        showSystemShareSheet = true
    }

    @MainActor
    private func saveToPhotos() async {
        if renderedImage == nil {
            renderImage()
        }
        guard let image = renderedImage else { return }

        _ = await LivePhotoLibraryAdapter.shared.saveImage(image)
    }
}
