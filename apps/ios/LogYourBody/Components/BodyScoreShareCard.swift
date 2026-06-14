import SwiftUI
import UIKit
import Photos

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

    var avatarMatch: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }
}

enum BodyScoreShareAspect: String, CaseIterable, Identifiable {
    case square
    case portrait
    case story

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
}

struct BodyScoreShareCardView: View {
    let payload: BodyScoreSharePayload
    let aspect: BodyScoreShareAspect

    var body: some View {
        GeometryReader { geometry in
            let layout = ShareCardLayout(size: geometry.size, aspect: aspect)

            ZStack {
                Color.black

                avatarStage(layout: layout)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.62),
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.94)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body_score_share_card")
    }

    private var aspectRatioValue: CGFloat {
        let size = aspect.pixelSize
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func avatarStage(layout: ShareCardLayout) -> some View {
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

    private func shareHeader(layout: ShareCardLayout) -> some View {
        HStack(spacing: layout.headerSpacing) {
            DSLogo(size: layout.logoSize, textSize: layout.logoTextSize)

            VStack(alignment: .leading, spacing: layout.headerTextSpacing) {
                Text("LogYourBody")
                    .font(.system(size: layout.brandFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(payload.avatarMatch.badgeText)
                    .font(.system(size: layout.badgeFontSize, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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
                    .minimumScaleFactor(0.58)

                VStack(alignment: .leading, spacing: layout.scoreLabelSpacing) {
                    Text("Body Score")
                        .font(.system(size: layout.scoreLabelFontSize, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.66))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(payload.tagline)
                        .font(.system(size: layout.taglineFontSize, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deltaText = payload.deltaText {
                        Text(deltaText)
                            .font(.system(size: layout.deltaFontSize, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.66))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: layout.metricSpacing) {
                shareMetric("Weight", payload.weightValue, payload.weightCaption, layout: layout)
                shareMetric("Body Fat", payload.bodyFatValue, payload.bodyFatCaption, layout: layout)
                shareMetric("FFMI", payload.ffmiValue, payload.ffmiCaption, layout: layout)
            }

            Text("Shared from LogYourBody")
                .font(.system(size: layout.footerFontSize, weight: .medium))
                .foregroundColor(Color.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shareMetric(
        _ title: String,
        _ value: String,
        _ caption: String,
        layout: ShareCardLayout
    ) -> some View {
        VStack(alignment: .leading, spacing: layout.metricTextSpacing) {
            Text(title)
                .font(.system(size: layout.metricTitleFontSize, weight: .bold))
                .foregroundColor(Color.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(value)
                .font(.system(size: layout.metricValueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            Text(caption)
                .font(.system(size: layout.metricCaptionFontSize, weight: .medium))
                .foregroundColor(Color.white.opacity(0.54))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareCardLayout {
    let size: CGSize
    let aspect: BodyScoreShareAspect

    private var scale: CGFloat {
        min(max(size.width / 390, 0.86), 2.8)
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
    var scoreFontSize: CGFloat { 58 * scale }
    var scoreLabelFontSize: CGFloat { 11 * scale }
    var taglineFontSize: CGFloat { 15 * scale }
    var deltaFontSize: CGFloat { 12 * scale }
    var metricSpacing: CGFloat { 13 * scale }
    var metricTextSpacing: CGFloat { 4 * scale }
    var metricTitleFontSize: CGFloat { 10 * scale }
    var metricValueFontSize: CGFloat { 20 * scale }
    var metricCaptionFontSize: CGFloat { 10 * scale }
    var footerFontSize: CGFloat { 11 * scale }

    var visualTopOffset: CGFloat {
        switch aspect {
        case .square:
            return size.height * 0.11
        case .portrait:
            return size.height * 0.10
        case .story:
            return size.height * 0.12
        }
    }

    var visualHeight: CGFloat {
        switch aspect {
        case .square:
            return size.height * 0.64
        case .portrait:
            return size.height * 0.66
        case .story:
            return size.height * 0.62
        }
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

    let payload: BodyScoreSharePayload

    @State private var selectedAspect: BodyScoreShareAspect = .square
    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var showSystemShareSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Picker("Format", selection: $selectedAspect) {
                    ForEach(BodyScoreShareAspect.allCases) { aspect in
                        Text(aspect.displayName).tag(aspect)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                GeometryReader { geometry in
                    let size = fittedSize(for: geometry.size, target: selectedAspect.pixelSize)

                    BodyScoreShareCardView(payload: payload, aspect: selectedAspect)
                        .frame(width: size.width, height: size.height)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    GlassPillButton(icon: "square.and.arrow.down", title: "Save") {
                        Task { await saveToPhotos() }
                    }
                    .accessibilityIdentifier("body_score_share_save_button")

                    GlassPillButton(icon: "square.and.arrow.up", title: "Share") {
                        Task { await shareImage() }
                    }
                    .accessibilityIdentifier("body_score_share_system_button")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .disabled(isRendering)
            }
            .background(Color.appBackground.ignoresSafeArea())
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
            .navigationTitle("Share Body Score")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("body_score_share_sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
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
        }
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
                BodyScoreShareCardView(payload: payload, aspect: selectedAspect)
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

        let status = PHPhotoLibrary.authorizationStatus()

        switch status {
        case .authorized:
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { authStatus in
                    continuation.resume(returning: authStatus)
                }
            }

            if newStatus == .authorized {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            } else if #available(iOS 14, *), newStatus == .limited {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        case .limited:
            if #available(iOS 14, *) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        default:
            return
        }
    }
}
