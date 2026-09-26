//
// HomeV2Surface.swift
// LogYourBody
//
import SwiftUI

/// Home on the focus contract (Pencil H1/H2/C2): one check-in action, the
/// number, a fixed 30-day trend, and quiet disclosures. Shows the metric-first
/// layout (H1) until the selected day has a photo. Nothing is drawn over the
/// person: the number sits below the photo.
struct HomeV2Surface: View {
    let metric: BodyMetrics
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let weightValue: String
    let weightUnit: String
    let changeSentence: String
    let phaseSentence: String?
    let loggedSentence: String?
    let latestPhotoCaption: String?
    let chartDaily: [MetricChartDataPoint]
    let chartTrend: [MetricChartDataPoint]
    let onOpenPhoto: () -> Void
    let onViewProgress: () -> Void
    let onTodayDetails: () -> Void
    let onAllPhotos: () -> Void
    let onLogWeight: () -> Void
    let onDone: () -> Void
    let onUndo: () -> Void

    private var isLogged: Bool { loggedSentence != nil }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                let hasPhoto = PhotoTimelineHUDPolicy.hasUsablePhoto(metric)
                if hasPhoto, let photoURL = metric.photoUrl {
                    photoStage(photoURL: photoURL, size: geometry.size)
                    photoNumberBlock
                } else {
                    metricFirst
                }

                Spacer(minLength: 0)

                if hasPhoto {
                    HomeV2DisclosureLink(
                        title: HomeV2PhotoCopy.allPhotos,
                        identifier: "home_v2_all_photos_row",
                        action: onAllPhotos
                    )
                    .frame(maxWidth: .infinity)
                }

                HomeV2Dock(
                    title: isLogged ? HomeV2Copy.done : HomeV2Copy.logWeight,
                    identifier: isLogged ? "home_v2_done" : "home_v2_log_weight",
                    action: isLogged ? onDone : onLogWeight
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }

    private func photoStage(photoURL: String, size: CGSize) -> some View {
        Button(action: onOpenPhoto) {
            SubjectPlateView(
                urlString: photoURL,
                size: CGSize(width: size.width, height: HomeV2Layout.stageHeight(width: size.width, height: size.height))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Progress photo")
        .accessibilityHint("Opens the photo")
        .accessibilityIdentifier("home_v2_photo_stage")
    }

    private var photoNumberBlock: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            if let latestPhotoCaption {
                Text(latestPhotoCaption)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .accessibilityIdentifier("home_v2_photo_caption")
            }

            numberRow(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .semibold, kerning: -1.2)

            Text(changeSentence)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .accessibilityIdentifier("home_v2_change_sentence")
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .padding(.top, HomeV2Tokens.Space.compact)
    }

    private func numberRow(size: CGFloat, weight: Font.Weight, kerning: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: HomeV2Tokens.Space.tight) {
            Text(weightValue)
                .scaledSystemFont(size: size, weight: weight, relativeTo: .largeTitle)
                .kerning(kerning)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("home_v2_weight_value")

            Text(weightUnit)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .title3)
                .foregroundStyle(HomeV2Tokens.Colors.muted)
        }
    }

    private var metricFirst: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: 1)
                    .accessibilityElement()
                    .accessibilityLabel(HomeV2Copy.title)
                    .accessibilityIdentifier("home_v2_metric_first")

                VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                    numberRow(size: HomeV2Tokens.TypeSize.heroMetricFirst, weight: .bold, kerning: -2.5)

                    Text(changeSentence)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .accessibilityIdentifier("home_v2_change_sentence")

                    statusLine
                }
                .padding(.top, HomeV2Tokens.Space.heroTop)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)

            HomeV2TrendChart(
                daily: chartDaily,
                trend: chartTrend,
                accent: HomeV2Tokens.Metric.weight,
                range: .constant(.month1),
                showsRangeTabs: false
            )
            .padding(.top, HomeV2Tokens.Space.margin)

            rangeRow
            todayDetailsRow
        }
    }

    private var todayDetailsRow: some View {
        Button(action: onTodayDetails) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2Copy.todayDetails)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_v2_today_details")
    }

    /// C2 replaces the phase line with what was just logged and a way back.
    @ViewBuilder
    private var statusLine: some View {
        if let loggedSentence {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(loggedSentence)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .accessibilityIdentifier("home_v2_logged_sentence")

                Spacer(minLength: HomeV2Tokens.Space.tight)

                Button(action: onUndo) {
                    Text(HomeV2Copy.undo)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_v2_undo")
            }
        } else if let phaseSentence {
            Text(phaseSentence)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.muted)
                .accessibilityIdentifier("home_v2_phase")
        }
    }

    private var rangeRow: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2Copy.lastThirtyDays)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)

            Spacer(minLength: HomeV2Tokens.Space.tight)

            HomeV2DisclosureLink(
                title: HomeV2Copy.viewProgress,
                identifier: "home_v2_view_progress",
                action: onViewProgress
            )
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(minHeight: HomeV2Tokens.rowHeight)
    }
}

struct HomeV2Hairline: View {
    var body: some View {
        Rectangle()
            .fill(HomeV2Tokens.Colors.border)
            .frame(height: HomeV2Tokens.Space.hairline)
            .allowsHitTesting(false)
    }
}

/// Full-width table row: 20pt insets, hairline divider, value right-aligned.
struct HomeV2TableRow: View {
    let label: String
    var subline: String?
    let detail: String
    let value: String?
    var leadingSystemImage: String?
    var showsChevron = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HomeV2Tokens.Space.row) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HomeV2Tokens.Colors.muted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)

                    if let subline {
                        Text(subline)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                            .foregroundStyle(HomeV2Tokens.Colors.quiet)
                    }
                }

                Spacer(minLength: HomeV2Tokens.Space.tight)

                Text(detail)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
                    .lineLimit(1)

                if let value {
                    Text(value)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .lineLimit(1)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeV2Tokens.Colors.quiet)
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .frame(minHeight: subline == nil ? HomeV2Tokens.rowHeight : HomeV2Tokens.rowHeightWithSubline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { HomeV2Hairline() }
        .accessibilityLabel([label, subline, detail, value].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Thumbnails of every day with a photo. Tapping one selects that day.
struct HomeV2Filmstrip: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int

    private var photoIndices: [Int] {
        bodyMetrics.indices.filter { PhotoTimelineHUDPolicy.hasUsablePhoto(bodyMetrics[$0]) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    ForEach(photoIndices, id: \.self) { index in
                        thumb(at: index)
                    }
                }
                .padding(.horizontal, HomeV2Tokens.Space.inset)
                .padding(.top, HomeV2Tokens.Space.row)
                .padding(.bottom, HomeV2Tokens.Space.tight)
            }
            .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
            .onChange(of: selectedIndex) { _, index in
                withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .frame(height: HomeV2Tokens.thumbSize.height + HomeV2Tokens.Space.row + HomeV2Tokens.Space.tight)
        .accessibilityIdentifier("home_v2_filmstrip")
    }

    private func thumb(at index: Int) -> some View {
        let isSelected = index == selectedIndex
        let shape = RoundedRectangle(cornerRadius: HomeV2Tokens.thumbRadius, style: .continuous)

        return Button {
            selectedIndex = index
        } label: {
            CachedAsyncImage(urlString: bodyMetrics[index].photoUrl ?? "") { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                HomeV2Tokens.Colors.card
            }
            .frame(width: HomeV2Tokens.thumbSize.width, height: HomeV2Tokens.thumbSize.height)
            .clipShape(shape)
            .overlay(shape.stroke(isSelected ? HomeV2Tokens.Colors.ink : .clear, lineWidth: 1.5))
            .opacity(isSelected ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityLabel(isSelected ? "Selected photo" : "Photo")
    }
}

/// Loads the photo, shows it dimmed immediately, then swaps in the plate once
/// it is rendered. The image is cropped to the stage before display so nothing
/// overflows the frame: the layout, the clip and the accessibility frame agree.
struct SubjectPlateView: View {
    let urlString: String
    let size: CGSize

    @State private var plate: UIImage?
    @State private var original: UIImage?

    var body: some View {
        ZStack {
            HomeV2Tokens.Colors.shell

            if let plate {
                stagePhoto(plate)
            } else if let original {
                stagePhoto(original)
                    .overlay(Color.black.opacity(0.35))
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: urlString) { await load() }
    }

    private func stagePhoto(_ image: UIImage) -> some View {
        Image(uiImage: AspectFillCropper.crop(image, to: size))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
    }

    private func load() async {
        if let cached = SubjectPlateStore.shared.cachedPlate(for: urlString) {
            plate = cached
            return
        }

        plate = nil
        guard let image = await ImageCacheService.shared.loadImage(from: urlString), !Task.isCancelled else {
            return
        }
        original = image

        let rendered = await SubjectPlateStore.shared.plate(for: urlString, image: image)
        guard !Task.isCancelled else { return }
        plate = rendered
    }
}

/// Aspect-fill crop in points. Drawing through UIKit also normalises EXIF
/// orientation, so the crop rect is computed in display space.
enum AspectFillCropper {
    static func fillRect(imageSize: CGSize, in target: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else {
            return CGRect(origin: .zero, size: target)
        }
        let scale = max(target.width / imageSize.width, target.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (target.width - drawn.width) / 2,
            y: (target.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    static func crop(_ image: UIImage, to target: CGSize) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        let rect = fillRect(imageSize: image.size, in: target)
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: rect)
        }
    }
}
