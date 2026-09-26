//
// HomeV2ShareView.swift
// LogYourBody
//
import SwiftUI

/// Share progress (Pencil P6): a 4:5 before/after card the person reviews
/// before sharing. Options sit behind one disclosure; the face warning
/// never does.
struct HomeV2ShareView: View {
    let bodyMetrics: [BodyMetrics]
    let pair: HomeV2PhotoPair
    let formatters: HomeV2Formatters
    let onCancel: () -> Void

    @State private var showsOptions = false
    @State private var showsNumbers = true
    @State private var showsDates = true
    @State private var cropsAboveShoulders = false
    @State private var beforePlate: UIImage?
    @State private var afterPlate: UIImage?

    private static let cardSize = CGSize(width: 310, height: 388)
    private static let footerHeight: CGFloat = 59
    private static let cropFraction: CGFloat = 0.22

    private var before: BodyMetrics? { bodyMetrics.indices.contains(pair.before) ? bodyMetrics[pair.before] : nil }
    private var after: BodyMetrics? { bodyMetrics.indices.contains(pair.after) ? bodyMetrics[pair.after] : nil }

    private var days: Int {
        guard let before, let after else { return 0 }
        return Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 0) {
                    card
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                        .padding(.vertical, HomeV2Tokens.Space.tight)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Share card")
                        .accessibilityIdentifier("home_v2_share_card")

                    optionsDisclosure
                    if showsOptions {
                        optionRow(HomeV2PhotoCopy.showNumbers, isOn: $showsNumbers, identifier: "home_v2_share_show_numbers")
                        optionRow(
                            HomeV2PhotoCopy.cropAboveShoulders,
                            isOn: $cropsAboveShoulders,
                            identifier: "home_v2_share_crop"
                        )
                        optionRow(HomeV2PhotoCopy.showDates, isOn: $showsDates, identifier: "home_v2_share_show_dates")
                    }
                }
            }

            VStack(spacing: HomeV2Tokens.Space.row) {
                Text(cropsAboveShoulders ? HomeV2PhotoCopy.faceCropped : HomeV2PhotoCopy.faceVisible)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("home_v2_share_face_note")

                shareButton
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.tight)
            .padding(.bottom, HomeV2Tokens.Space.tight)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
        .task(id: pair.id) { await loadPlates() }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
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

            Spacer(minLength: 0)

            Text(HomeV2PhotoCopy.shareProgress)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_share")

            Spacer(minLength: 0)

            Color.clear.frame(width: 64, height: JovieTokens.minimumHitTarget)
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    /// The card is plain SwiftUI over already-loaded plates so it renders
    /// identically on screen and through ImageRenderer.
    private var card: some View {
        let paneWidth = (Self.cardSize.width - 2) / 2
        let paneHeight = Self.cardSize.height - Self.footerHeight
        return VStack(spacing: 0) {
            HStack(spacing: 2) {
                pane(beforePlate, metric: before, size: CGSize(width: paneWidth, height: paneHeight))
                pane(afterPlate, metric: after, size: CGSize(width: paneWidth, height: paneHeight))
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
    }

    private func pane(_ plate: UIImage?, metric: BodyMetrics?, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let plate {
                Image(uiImage: AspectFillCropper.crop(plate, to: size))
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .offset(y: cropsAboveShoulders ? -size.height * Self.cropFraction : 0)
                    .frame(width: size.width, height: size.height)
                    .clipped()
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
    private var shareButton: some View {
        if let image = renderedCard() {
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
        } else {
            HomeV2PrimaryButton(
                title: HomeV2PhotoCopy.preparing,
                isEnabled: false,
                identifier: "home_v2_share_action",
                action: {}
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
        guard beforePlate != nil, afterPlate != nil else { return nil }
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let rendered = renderer.uiImage else { return nil }
        return Image(uiImage: rendered)
    }

    private func loadPlates() async {
        beforePlate = await plate(for: before)
        afterPlate = await plate(for: after)
    }

    private func plate(for metric: BodyMetrics?) async -> UIImage? {
        guard let urlString = metric?.photoUrl else { return nil }
        if let cached = SubjectPlateStore.shared.cachedPlate(for: urlString) { return cached }
        guard let image = await ImageCacheService.shared.loadImage(from: urlString) else { return nil }
        return await SubjectPlateStore.shared.plate(for: urlString, image: image) ?? image
    }
}
