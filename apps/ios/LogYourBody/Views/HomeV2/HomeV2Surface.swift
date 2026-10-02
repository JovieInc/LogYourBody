//
// HomeV2Surface.swift
// LogYourBody
//
import SwiftUI

/// Home is the body timeline (JOV-6016): a full-width 4:5 visual for the
/// selected day — the photo when one exists, the editorial plate when it does
/// not — with the day's numbers below and the scrubber above the dock.
/// Swiping the stage and dragging the scrubber resolve to the same
/// `selectedIndex`, so photo, date and metrics always move together.
struct HomeV2Surface: View {
    let metric: BodyMetrics
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let weightValue: String
    let weightUnit: String
    let changeSentence: String
    let compositionSentence: String
    /// Display-formatted body fat for the selected day ("15.8"), nil when none.
    let bodyFatText: String?
    let dateText: (BodyMetrics) -> String
    let phaseSentence: String?
    let loggedSentence: String?
    var systemState: HomeV2SystemState?
    let onOpenPhoto: () -> Void
    let onViewProgress: () -> Void
    let onTodayDetails: () -> Void
    let onAllPhotos: () -> Void
    let onLogWeight: () -> Void
    var onConnectHealth: () -> Void = {}
    let onDone: () -> Void
    let onUndo: () -> Void

    @AppStorage(HomeV2Copy.coachDismissedDefaultsKey) private var coachDismissed = false
    @State private var hasAppeared = false

    private var isLogged: Bool { loggedSentence != nil }
    private var isHealthOff: Bool { systemState == .healthOff }
    private var hasAnyPhoto: Bool {
        bodyMetrics.contains { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                if systemState == .offline {
                    HomeV2OfflineBanner()
                } else if isHealthOff {
                    HomeV2HealthOffRow()
                }

                timelinePager(size: geometry.size)
                photoNumberBlock
                if isHealthOff {
                    todayDetailsRow
                }
                rangeRow

                if hasAnyPhoto {
                    HomeV2DisclosureLink(
                        title: HomeV2PhotoCopy.allPhotos,
                        identifier: "home_v2_all_photos_row",
                        action: onAllPhotos
                    )
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                timelineScrubber

                if !coachDismissed {
                    HomeV2TimelineCoachMark(onDismiss: { coachDismissed = true })
                }

                if isHealthOff, !isLogged {
                    HomeV2Dock(
                        title: HomeV2SystemCopy.connectAppleHealth,
                        identifier: "home_v2_connect_health",
                        action: onConnectHealth
                    )
                } else {
                    HomeV2Dock(
                        title: isLogged ? HomeV2Copy.done : HomeV2Copy.logWeight,
                        identifier: isLogged ? "home_v2_done" : "home_v2_log_weight",
                        action: isLogged ? onDone : onLogWeight
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .onAppear { hasAppeared = true }
            .onChange(of: selectedIndex) { _, _ in
                // The first successful swipe or scrub means the lesson landed.
                if hasAppeared { coachDismissed = true }
            }
        }
    }

    private func timelinePager(size: CGSize) -> some View {
        HomeV2TimelinePager(
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            size: CGSize(
                width: size.width,
                height: HomeV2Layout.homeStageHeight(width: size.width, height: size.height)
            ),
            dateText: dateText,
            onOpenPhoto: onOpenPhoto
        )
    }

    /// The scrubber is the same selection the pager drives: chronological days,
    /// one tick per day, the selected day tallest.
    private var timelineScrubber: some View {
        HomeV2PhotoTimelineRuler(
            dates: HomeV2TimelinePolicy.chronologicalIndices(in: bodyMetrics).map { bodyMetrics[$0].date },
            selected: HomeV2TimelinePolicy.chronologicalPosition(of: selectedIndex, in: bodyMetrics),
            onSelect: { position in
                if let index = HomeV2TimelinePolicy.index(at: position, in: bodyMetrics) {
                    selectedIndex = index
                }
            },
            accessibilityId: "home_v2_timeline_scrubber"
        )
        .padding(.bottom, HomeV2Tokens.Space.tight)
    }

    private var photoNumberBlock: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text(HomeV2Copy.dayCaption(date: dateText(metric), source: HomeV2Provenance.label(for: metric)))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .accessibilityIdentifier("home_v2_photo_caption")

            numberRow(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .semibold, kerning: -1.2)

            Text(changeSentence)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .accessibilityIdentifier("home_v2_change_sentence")

            detailLine

            statusLine
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

    /// The selected day's body fat with provenance, or the 30-day composition
    /// headline when the day has no body fat of its own.
    private var detailSentence: String {
        if let bodyFatText {
            return HomeV2Copy.dayBodyFatLine(
                value: bodyFatText,
                source: HomeV2Provenance.bodyFatSubline(for: metric)
            )
        }
        return compositionSentence
    }

    private var detailLine: some View {
        Text(detailSentence)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home_v2_composition_sentence")
    }

    private var todayDetailsRow: some View {
        Button(action: isHealthOff ? onLogWeight : onTodayDetails) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(isHealthOff ? HomeV2SystemCopy.logWeightManually : HomeV2Copy.todayDetails)
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
