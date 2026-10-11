//
// HomeV2ShareView.swift
// LogYourBody
//
import SwiftUI

/// Share progress (Pencil P6): a 4:5 before/after card the person reviews
/// before sharing. Options sit behind one disclosure; the privacy reminder
/// never does.
struct HomeV2ShareView: View {
    let bodyMetrics: [BodyMetrics]
    let pair: HomeV2PhotoPair
    let formatters: HomeV2Formatters
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showsOptions = false
    @State private var showsNumbers = true
    @State private var showsDates = true
    @State private var cropsPhotoTop = false
    @State private var loadAttempt = 0
    @StateObject private var photos = HomeV2SharePhotoLoader()

    private static let cardSize = CGSize(width: 310, height: 388)
    private static let footerHeight: CGFloat = 59

    private var before: BodyMetrics? { bodyMetrics.indices.contains(pair.before) ? bodyMetrics[pair.before] : nil }
    private var after: BodyMetrics? { bodyMetrics.indices.contains(pair.after) ? bodyMetrics[pair.after] : nil }

    private var days: Int {
        guard let before, let after else { return 0 }
        return Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
    }

    var body: some View {
        let image = photos.state == .ready ? renderedCard() : nil
        return VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 0) {
                    if dynamicTypeSize.isAccessibilitySize {
                        shareMessages(renderFailed: photos.state == .ready && image == nil)
                            .padding(HomeV2Tokens.Space.margin)
                    }
                    card
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                        .padding(.vertical, HomeV2Tokens.Space.tight)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Share card")
                        .accessibilityValue(cardAccessibilitySummary)
                        .accessibilityIdentifier("home_v2_share_card")

                    optionsDisclosure
                    if showsOptions {
                        optionRow(HomeV2PhotoCopy.showNumbers, isOn: $showsNumbers, identifier: "home_v2_share_show_numbers")
                        optionRow(
                            HomeV2PhotoCopy.cropPhotoTop,
                            isOn: $cropsPhotoTop,
                            identifier: "home_v2_share_crop"
                        )
                        optionRow(HomeV2PhotoCopy.showDates, isOn: $showsDates, identifier: "home_v2_share_show_dates")
                    }
                }
            }
            .accessibilityIdentifier("home_v2_share_scroll")

            VStack(spacing: HomeV2Tokens.Space.row) {
                if !dynamicTypeSize.isAccessibilitySize {
                    shareMessages(renderFailed: photos.state == .ready && image == nil)
                }
                shareButton(image: image)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.tight)
            .padding(.bottom, HomeV2Tokens.Space.tight)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .task(id: "\(pair.id)-\(before?.photoUrl ?? "")-\(after?.photoUrl ?? "")-\(loadAttempt)") {
            await photos.load(beforeURL: before?.photoUrl, afterURL: after?.photoUrl)
        }
    }

    private var topBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                    cancelButton
                    shareTitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    cancelButton
                    Spacer(minLength: 0)
                    shareTitle
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 64, height: JovieTokens.minimumHitTarget)
                }
                .frame(minHeight: JovieTokens.compactControlHeight)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            HStack(spacing: HomeV2Tokens.Space.tight / 2) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                Text(HomeV2PhotoCopy.cancel)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_v2_share_cancel")
    }

    private var shareTitle: some View {
        Text(HomeV2PhotoCopy.shareProgress)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("home_v2_share")
    }

    private func shareMessages(renderFailed: Bool) -> some View {
        VStack(spacing: HomeV2Tokens.Space.row) {
            Text(cropsPhotoTop ? HomeV2PhotoCopy.croppedPhotoNote : HomeV2PhotoCopy.reviewPhotos)
                .accessibilityIdentifier("home_v2_share_face_note")
            if photos.state == .failed || renderFailed {
                Text(photos.state == .failed ? HomeV2PhotoCopy.shareLoadFailed : HomeV2PhotoCopy.shareRenderFailed)
                    .accessibilityIdentifier("home_v2_share_error")
            }
        }
        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
        .foregroundStyle(HomeV2Tokens.Colors.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cardAccessibilitySummary: String {
        var parts: [String] = []
        if showsDates, let before, let after {
            parts.append("Before \(formatters.dateText(before)); after \(formatters.dateText(after))")
        }
        if showsNumbers {
            parts.append(HomeV2PhotoCopy.cardHeadline(delta: weightDelta, unit: formatters.weightUnit, days: days))
            if let bodyFat = HomeV2PhotoCopy.bodyFatDeltaLine(bodyFatDelta) { parts.append(bodyFat) }
        } else {
            parts.append("\(days) days between photos")
        }
        return parts.joined(separator: ". ")
    }

    /// The card is plain SwiftUI over already-loaded plates so it renders
    /// identically on screen and through ImageRenderer.
    private var card: some View {
        let paneWidth = (Self.cardSize.width - 2) / 2
        let paneHeight = Self.cardSize.height - Self.footerHeight
        return VStack(spacing: 0) {
            HStack(spacing: 2) {
                pane(photos.beforePlate, metric: before, size: CGSize(width: paneWidth, height: paneHeight))
                pane(photos.afterPlate, metric: after, size: CGSize(width: paneWidth, height: paneHeight))
            }

            HStack(alignment: .lastTextBaseline, spacing: HomeV2Tokens.Space.tight) {
                VStack(alignment: .leading, spacing: 2) {
                    if showsNumbers {
                        Text(HomeV2PhotoCopy.cardHeadline(delta: weightDelta, unit: formatters.weightUnit, days: days))
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        if let bodyFatLine = HomeV2PhotoCopy.bodyFatDeltaLine(bodyFatDelta) {
                            Text(bodyFatLine)
                                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        }
                    } else {
                        Text("\(days) days")
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                    }
                }
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Text(HomeV2PhotoCopy.brand)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            .padding(.horizontal, HomeV2Tokens.Space.compact)
            .frame(height: Self.footerHeight)
            .frame(maxWidth: .infinity)
            .background(HomeV2Tokens.Colors.card)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(HomeV2Tokens.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeV2Tokens.photoSlotRadius, style: .continuous))
        // The poster is a fixed-size export. Its accessible summary carries the
        // same values while the surrounding controls respect Dynamic Type.
        .dynamicTypeSize(.large)
    }

    private func pane(_ plate: UIImage?, metric: BodyMetrics?, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let plate {
                Image(uiImage: HomeV2ShareCropper.crop(plate, to: size, cropsTop: cropsPhotoTop))
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                HomeV2Tokens.Colors.elevated
                    .frame(width: size.width, height: size.height)
            }
            if showsDates, let metric {
                Text(FormatterCache.monthDayFormatter.string(from: metric.date))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, weight: .medium, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .padding(.horizontal, HomeV2Tokens.Space.tight)
                    .padding(.vertical, HomeV2Tokens.Space.tight / 2)
                    .background(HomeV2Tokens.Colors.canvas.opacity(0.65), in: Capsule())
                    .padding(HomeV2Tokens.Space.tight)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var optionsDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsOptions.toggle() }
        } label: {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2PhotoCopy.cardOptions)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
                    .rotationEffect(.degrees(showsOptions ? 180 : 0))
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_v2_share_options")
    }

    private func optionRow(_ title: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
        }
        .tint(HomeV2Tokens.Colors.ion)
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(minHeight: JovieTokens.minimumHitTarget)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func shareButton(image: Image?) -> some View {
        if let image {
            ShareLink(
                item: image,
                preview: SharePreview(HomeV2PhotoCopy.shareProgress, image: image)
            ) {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                    Text(HomeV2PhotoCopy.share)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                }
                .foregroundStyle(HomeV2Tokens.Colors.ctaInk)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
                .background(HomeV2Tokens.Colors.ctaFill, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_share_action")
        } else if photos.state == .loading {
            HomeV2PrimaryButton(
                title: HomeV2PhotoCopy.preparing,
                isEnabled: false,
                identifier: "home_v2_share_action",
                action: {}
            )
        } else {
            HomeV2PrimaryButton(
                title: HomeV2PhotoCopy.retryPhotos,
                identifier: "home_v2_share_retry",
                action: { loadAttempt += 1 }
            )
        }
    }

    private var weightDelta: Double? {
        guard let before, let after, let now = formatters.weightValue(after), let then = formatters.weightValue(before) else {
            return nil
        }
        return now - then
    }

    private var bodyFatDelta: Double? {
        guard let before, let after, let now = formatters.bodyFatValue(after), let then = formatters.bodyFatValue(before) else {
            return nil
        }
        return now - then
    }

    @MainActor
    private func renderedCard() -> Image? {
        guard photos.beforePlate != nil, photos.afterPlate != nil else { return nil }
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let rendered = renderer.uiImage else { return nil }
        return Image(uiImage: rendered)
    }
}

/// Draw through UIKit so preview and export use the same complete crop,
/// including EXIF orientation, with no uncovered strip at the bottom.
enum HomeV2ShareCropper {
    static func crop(_ image: UIImage, to size: CGSize, cropsTop: Bool) -> UIImage {
        guard size.width > 0, size.height > 0 else { return image }
        let rect = HomeV2ShareCropPolicy.drawRect(imageSize: image.size, in: size, cropsTop: cropsTop)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: rect)
        }
    }
}

@MainActor
final class HomeV2SharePhotoLoader: ObservableObject {
    enum State { case loading, ready, failed }

    @Published private(set) var state: State = .loading
    @Published private(set) var beforePlate: UIImage?
    @Published private(set) var afterPlate: UIImage?
    private var requestID = UUID()

    func load(
        beforeURL: String?,
        afterURL: String?,
        plate: (String) async -> UIImage? = HomeV2SharePhotoLoader.plate
    ) async {
        let request = UUID()
        requestID = request
        state = .loading
        beforePlate = nil
        afterPlate = nil
        guard let beforeURL, let afterURL else {
            state = .failed
            return
        }
        let before = await plate(beforeURL)
        guard !Task.isCancelled, request == requestID else { return }
        let after = await plate(afterURL)
        guard !Task.isCancelled, request == requestID else { return }
        beforePlate = before
        afterPlate = after
        state = before != nil && after != nil ? .ready : .failed
    }

    private static func plate(for urlString: String) async -> UIImage? {
        if let cached = SubjectPlateStore.shared.cachedPlate(for: urlString) { return cached }
        guard let image = await ImageCacheService.shared.loadImage(from: urlString) else { return nil }
        return await SubjectPlateStore.shared.plate(for: urlString, image: image) ?? image
    }
}
