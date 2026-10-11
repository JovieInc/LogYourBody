//
// HomeV2TimelapseView.swift
// LogYourBody
//
import SwiftUI

/// Timelapse (Pencil P7): the photos in order, with pause, progress, the
/// ruler, and playback settings behind one disclosure.
struct HomeV2TimelapseView: View {
    let bodyMetrics: [BodyMetrics]
    let formatters: HomeV2Formatters
    let onClose: () -> Void

    @State private var frame = 0
    @State private var isPlaying = false
    @State private var isReady = false
    @State private var speed: Double = 1
    @State private var loops = false
    @State private var showsSettings = false

    /// Top bar, transport, ruler and the settings row below the stage.
    private static let chromeHeight: CGFloat = 52 + 60 + 72 + 60

    private var chronological: [Int] { HomeV2PhotoIndex.chronologicalPhotoIndices(in: bodyMetrics) }
    private var dates: [Date] { chronological.map { bodyMetrics[$0].date } }
    private var current: BodyMetrics? {
        chronological.indices.contains(frame) ? bodyMetrics[chronological[frame]] : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let stage = CGSize(
                width: geometry.size.width,
                height: HomeV2Layout.stageHeight(
                    width: geometry.size.width,
                    height: geometry.size.height - Self.chromeHeight + HomeV2Layout.belowPhotoHeight
                )
            )
            VStack(spacing: 0) {
                topBar

                if let current {
                    SubjectPlateView(urlString: current.photoUrl ?? "", size: stage)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Timelapse, \(formatters.dateText(current))")
                        .accessibilityIdentifier("home_v2_timelapse_stage")
                }

                transport
                HomeV2PhotoTimelineRuler(dates: dates, selected: frame) { selected in
                    frame = selected
                    isPlaying = false
                }
                    .padding(.top, HomeV2Tokens.Space.tight)

                Spacer(minLength: 0)

                settings
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await prepare() }
        .task(id: "\(isPlaying)-\(speed)-\(loops)") { await play() }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("home_v2_timelapse_close")

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(HomeV2PhotoCopy.timelapse)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home_v2_timelapse")
                if let first = dates.first, let last = dates.last {
                    Text(HomeV2PhotoCopy.timelapseSubtitle(
                        from: FormatterCache.monthDayFormatter.string(from: first),
                        to: FormatterCache.monthDayFormatter.string(from: last),
                        count: dates.count
                    ))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }
            }

            Spacer(minLength: 0)

            Color.clear.frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    private var transport: some View {
        HStack(spacing: HomeV2Tokens.Space.compact) {
            Button {
                isPlaying.toggle()
                HapticManager.shared.selection()
            } label: {
                Image(systemName: isPlaying ? "pause" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("home_v2_timelapse_play")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(HomeV2Tokens.Colors.borderStrong).frame(height: 3)
                    Capsule().fill(HomeV2Tokens.Colors.ink).frame(width: geometry.size.width * progress, height: 3)
                }
                .frame(height: geometry.size.height)
            }
            .frame(height: JovieTokens.minimumHitTarget)
            .accessibilityHidden(true)

            Text(current.map { FormatterCache.monthDayFormatter.string(from: $0.date) } ?? HomeV2PhotoCopy.preparing)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("home_v2_timelapse_date")
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(minHeight: 60)
    }

    private var progress: CGFloat {
        guard dates.count > 1 else { return 1 }
        return CGFloat(frame) / CGFloat(dates.count - 1)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            if showsSettings {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    Text(HomeV2PhotoCopy.speed)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    ForEach(HomeV2TimelapsePolicy.speeds, id: \.self) { candidate in
                        let isSelected = candidate == speed
                        Button {
                            speed = candidate
                        } label: {
                            Text(HomeV2PhotoCopy.speedText(candidate))
                                .scaledSystemFont(
                                    size: HomeV2Tokens.TypeSize.secondary,
                                    weight: .medium,
                                    relativeTo: .subheadline
                                )
                                .foregroundStyle(isSelected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary)
                                .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
                                .background(isSelected ? HomeV2Tokens.Colors.card : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier(
                            "home_v2_timelapse_speed_\(HomeV2PhotoCopy.speedText(candidate))"
                        )
                    }
                }
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: JovieTokens.minimumHitTarget)

                Toggle(isOn: $loops) {
                    HStack(spacing: HomeV2Tokens.Space.tight) {
                        Image(systemName: "repeat")
                            .font(.system(size: 16, weight: .medium))
                        Text(loops ? HomeV2PhotoCopy.loopOn : HomeV2PhotoCopy.loopOff)
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    }
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }
                .tint(HomeV2Tokens.Colors.ion)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .accessibilityIdentifier("home_v2_timelapse_loop")
            }

            Button {
                withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsSettings.toggle() }
            } label: {
                HStack(spacing: HomeV2Tokens.Space.tight) {
                    Text(HomeV2PhotoCopy.playbackSummary(speed: speed, loops: loops))
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    Spacer(minLength: HomeV2Tokens.Space.tight)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeV2Tokens.Colors.quiet)
                        .rotationEffect(.degrees(showsSettings ? 180 : 0))
                }
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_v2_timelapse_settings")
        }
        .padding(.bottom, HomeV2Tokens.Space.tight)
    }

    /// Plates render lazily; warm every frame once so playback never waits.
    private func prepare() async {
        for index in chronological {
            guard let urlString = bodyMetrics[index].photoUrl, !Task.isCancelled else { continue }
            if SubjectPlateStore.shared.cachedPlate(for: urlString) != nil { continue }
            if let image = await ImageCacheService.shared.loadImage(from: urlString) {
                _ = await SubjectPlateStore.shared.plate(for: urlString, image: image)
            }
        }
        isReady = true
        isPlaying = dates.count > 1
    }

    private func play() async {
        guard isPlaying else { return }
        while isPlaying, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(HomeV2TimelapsePolicy.frameInterval(speed: speed)))
            guard isPlaying, !Task.isCancelled else { return }
            if let next = HomeV2TimelapsePolicy.next(after: frame, count: dates.count, loops: loops) {
                frame = next
            } else {
                isPlaying = false
            }
        }
    }
}
