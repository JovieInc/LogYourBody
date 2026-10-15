//
// HomeV2Surface.swift
// LogYourBody
//
import Charts
import SwiftUI

/// A shared editorial card keeps Home's geometry stable with or without a photo.
/// The photo fills its card; a data graphic uses only the selected day's readings
/// or its recorded weight history. Composition leads; weight and movement give context.
struct HomeV2Surface: View {
    let metric: BodyMetrics
    let bodyMetrics: [BodyMetrics]
    let timeline: HomeV2TimelinePolicy.Snapshot
    @Binding var selectedID: HomeV2TimelinePolicy.EntryID
    let weightValue: String
    let weightUnit: String
    let ffmiValue: String?
    let stepsValue: String
    let stepsDetail: String
    let changeSentence: String
    let dateText: (BodyMetrics) -> String
    let loggedSentence: String?
    var systemState: HomeV2SystemState?
    let onOpenPhoto: () -> Void
    let onViewProgress: () -> Void
    let onViewMetric: (HomeV2ProgressMetric) -> Void
    let onTodayDetails: () -> Void
    let onAllPhotos: () -> Void
    let onLogWeight: () -> Void
    var onConnectHealth: () -> Void = {}
    let onDone: () -> Void
    let onUndo: () -> Void

    @AppStorage(HomeV2Copy.coachDismissedDefaultsKey) private var coachDismissed = false
    @State private var showsProvenance = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isLogged: Bool { loggedSentence != nil }
    private var isHealthOff: Bool { systemState == .healthOff }
    private var hasAnyPhoto: Bool {
        bodyMetrics.contains { PhotoTimelineHUDPolicy.hasUsablePhoto($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    systemBanner
                    HomeV2TimelinePager(
                        snapshot: timeline, selectedID: userSelection,
                        size: CGSize(width: geometry.size.width, height: geometry.size.width / HomeV2Tokens.photoAspectRatio),
                        unit: weightUnit, dateText: dateText, onOpenPhoto: onOpenPhoto
                    )
                    photoNumberBlock
                    if hasAnyPhoto {
                        HomeV2DisclosureLink(
                            title: HomeV2PhotoCopy.allPhotos,
                            identifier: "home_v2_all_photos_row",
                            action: onAllPhotos
                        )
                        .frame(maxWidth: .infinity)
                    }
                    rangeRow
                    if !hasPhoto || isHealthOff { todayDetailsRow }
                    if !coachDismissed {
                        HomeV2TimelineCoachMark(onDismiss: { coachDismissed = true })
                    }
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("home_v2_content_scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                timelineScrubber
                actionDock
            }
            .background(HomeV2Tokens.Colors.shell)
        }
    }

    @ViewBuilder
    private var systemBanner: some View {
        if systemState == .offline {
            HomeV2OfflineBanner()
        } else if isHealthOff {
            HomeV2HealthOffRow()
        }
    }

    @ViewBuilder
    private var actionDock: some View {
        if isHealthOff, !isLogged {
            HomeV2Dock(
                title: HomeV2SystemCopy.connectAppleHealth,
                identifier: "home_v2_connect_health",
                action: onConnectHealth
            )
        } else {
            HomeV2Dock(
                title: isLogged ? HomeV2Copy.done : HomeV2Copy.logCheckIn,
                identifier: isLogged ? "home_v2_done" : "home_v2_log_weight",
                action: isLogged ? onDone : onLogWeight
            )
        }
    }

    private var hasPhoto: Bool { PhotoTimelineHUDPolicy.hasUsablePhoto(metric) }

    private var userSelection: Binding<HomeV2TimelinePolicy.EntryID> {
        Binding(get: { selectedID }, set: { next in
            guard next != selectedID else { return }
            selectedID = next
            coachDismissed = true
        })
    }

    private var timelineScrubber: some View {
        HomeV2PhotoTimelineRuler(
            dates: timeline.chronologicalDates,
            selected: timeline.chronologicalPosition(for: selectedID),
            onSelect: { position in
                if let next = timeline.id(atChronologicalPosition: position) { userSelection.wrappedValue = next }
            },
            allowsVerticalScrolling: true,
            accessibilityId: "home_v2_timeline_scrubber",
            accessibilityName: "Body timeline"
        )
        .padding(.top, HomeV2Tokens.Space.tight)
    }

    private var photoNumberBlock: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text(dateText(metric))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .accessibilityIdentifier("home_v2_photo_caption")

            if let provenance = HomeV2MetricEditorial.timelineProvenance(for: metric) {
                HomeV2ProvenanceChip(detail: provenance) { showsProvenance = true }
            }

            if HomeV2EditorialPolicy.bodyFat(in: metric) == nil {
                compositionLine
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
                        ffmiSummary
                        weightSummary
                    }
                } else {
                    HStack(alignment: .top, spacing: HomeV2Tokens.Space.margin) {
                        ffmiSummary
                        weightSummary
                    }
                }
            }
            .padding(.vertical, HomeV2Tokens.Space.tight)

            HomeV2Hairline()
            HomeV2StepsSummary(value: stepsValue, detail: stepsDetail, dateText: dateText(metric)) {
                onViewMetric(.steps)
            }
                .padding(.vertical, HomeV2Tokens.Space.tight)
            HomeV2Hairline()

            if HomeV2EditorialPolicy.bodyFat(in: metric) == nil {
                Text(changeSentence)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .accessibilityIdentifier("home_v2_change_sentence")
            }
            if isLogged { statusLine }
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .padding(.top, HomeV2Tokens.Space.compact)
        .sheet(isPresented: $showsProvenance) {
            if let provenance = HomeV2MetricEditorial.timelineProvenance(for: metric) {
                HomeV2ProvenanceSheet(detail: provenance)
            }
        }
        .onChange(of: metric.id) { _, _ in showsProvenance = false }
    }

    private var ffmiSummary: some View {
        metricSummary(.ffmi, value: ffmiValue ?? "—",
                      detail: ffmiValue == nil ? "Needs weight, body fat and height" : "Derived from weight, body fat and height")
    }

    private var weightSummary: some View {
        metricSummary(.weight, value: weightValue, detail: weightValue == "—" ? "Not logged" : weightUnit)
    }

    private var compositionLine: some View {
        Text(visibleComposition)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home_v2_composition_sentence")
    }

    private func metricSummary(_ kind: HomeV2ProgressMetric, value: String, detail: String) -> some View {
        Button { onViewMetric(kind) } label: {
            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                Text(kind == .steps ? "Steps · \(dateText(metric))" : kind.title)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                Text(value)
                    .scaledSystemFont(size: 28, weight: .semibold, relativeTo: .title2)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .accessibilityIdentifier("home_v2_\(kind.identifier)_value")
                Text(detail)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityHint("View \(kind.title.lowercased()) progress")
        .accessibilityIdentifier("home_v2_\(kind.identifier)_summary")
    }

    /// The missing-day sentence stays exact. A recorded percentage names no second source.
    private var visibleComposition: String {
        guard let reading = HomeV2EditorialPolicy.bodyFat(in: metric) else {
            return HomeV2TimelinePolicy.bodyFatSentence(for: metric)
        }
        return HomeV2MetricEditorial.compositionLine(percentage: reading.percentage)
    }

    private var todayDetailsRow: some View {
        Button(action: isHealthOff ? onLogWeight : onTodayDetails) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(isHealthOff ? HomeV2Copy.logCheckIn : HomeV2Copy.todayDetails)
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

struct HomeV2StepsSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let value: String
    let detail: String
    let dateText: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                        heading
                        stepValue
                        detailText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: HomeV2Tokens.Space.compact) {
                        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
                            heading
                            detailText
                        }
                        Spacer(minLength: 0)
                        stepValue
                    }
                }
            }
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityHint("View steps progress")
        .accessibilityIdentifier("home_v2_steps_summary")
    }

    private var heading: some View {
        Text("Steps · \(dateText)")
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
    }

    private var detailText: some View {
        Text(detail)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepValue: some View {
        Text(value)
            .scaledSystemFont(size: 28, weight: .semibold, relativeTo: .title2)
            .foregroundStyle(HomeV2Tokens.Colors.ink)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            .accessibilityIdentifier("home_v2_steps_value")
    }
}
/// The same full-bleed card as the photo, using only data the person has saved.
struct HomeV2DataHero: View {
    let metric: BodyMetrics?
    let metrics: [BodyMetrics]
    let unit: String

    private var bodyFat: HomeV2EditorialPolicy.BodyFatReading? { HomeV2EditorialPolicy.bodyFat(in: metric) }
    private var weights: [HomeV2EditorialPolicy.WeightReading] {
        HomeV2EditorialPolicy.weights(in: metrics, selected: metric)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let bodyFat {
                bodyFatGraphic(bodyFat)
            } else if !weights.isEmpty {
                weightGraphic
            } else {
                emptyGraphic
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeV2Tokens.Colors.card)
        .accessibilityElement(children: .contain)
    }

    private func bodyFatGraphic(_ reading: HomeV2EditorialPolicy.BodyFatReading) -> some View {
        VStack(spacing: HomeV2Tokens.Space.compact) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle().stroke(HomeV2Tokens.Colors.border, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(reading.percentage / 100))
                        .stroke(HomeV2Tokens.Metric.bodyFat, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: HomeV2Tokens.Space.tight) {
                        Text(String(format: "%.1f%%", reading.percentage))
                            .scaledSystemFont(
                                size: HomeV2Tokens.TypeSize.progressValue,
                                weight: .semibold,
                                relativeTo: .largeTitle
                            )
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(HomeV2Tokens.Colors.ink)
                        Text("body fat by weight")
                            .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, relativeTo: .body)
                            .foregroundStyle(HomeV2Tokens.Colors.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
                .frame(width: diameter, height: diameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body fat \(String(format: "%.1f", reading.percentage)) percent. \(reading.caption).")
        .accessibilityIdentifier("home_v2_body_fat_graphic")
    }

    private var weightGraphic: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.margin) {
            Text("Recorded weight")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            if weights.count > 1 {
                HomeV2TrendChart(
                    daily: weightPoints,
                    trend: [],
                    accent: HomeV2Tokens.Metric.weight,
                    range: .constant(.month1),
                    showsRangeTabs: false,
                    showsDots: true,
                    chartHeight: HomeV2Tokens.chartHeight,
                    axis: .months,
                    metricTitle: "Weight",
                    usesSevenDayAverage: false,
                    anchorsToZero: false,
                    requiresMinimumDays: false,
                    plotIdentifier: "home_v2_weight_plot",
                    allowsSelection: false,
                    now: metric?.date ?? Date()
                )
            } else if let reading = weights.first {
                HomeV2MetricHero(
                    value: String(format: "%.1f", displayWeight(reading.kilograms)),
                    unit: unit,
                    comparison: "",
                    valueIdentifier: "home_v2_weight_hero_value",
                    valueSize: HomeV2Tokens.TypeSize.progressValue,
                    showsComparison: false
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
            Text("\(weights.count) weight \(weights.count == 1 ? "entry" : "entries") in 30 days · \(unit)")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HomeV2Tokens.Space.margin)
        .accessibilityElement(children: weights.count == 1 ? .contain : .ignore)
        .accessibilityLabel(weightSummary)
        .accessibilityIdentifier("home_v2_weight_graphic")
    }

    private var weightSummary: String {
        guard let latest = weights.last else { return "No weight recorded." }
        return "\(weights.count) recorded weight \(weights.count == 1 ? "entry" : "entries") in 30 days. " +
            "Latest \(String(format: "%.1f", displayWeight(latest.kilograms))) \(unit). Body fat not logged for this day."
    }

    private var emptyGraphic: some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.compact) {
            Spacer(minLength: 0)
            Text(metric == nil ? HomeV2Copy.firstCheckInTitle : "Your check-in")
                .scaledSystemFont(size: 44, weight: .semibold, relativeTo: .largeTitle)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(metric == nil ? "home_v2_day_zero" : "home_v2_empty_graphic")
            Spacer(minLength: 0)
            Text("No weight or body fat logged.")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HomeV2Tokens.Space.margin)
    }

    private var weightPoints: [MetricChartDataPoint] {
        weights.map { reading in
            MetricChartDataPoint(
                date: reading.date,
                value: displayWeight(reading.kilograms),
                presence: .present
            )
        }
    }

    private func displayWeight(_ kilograms: Double) -> Double {
        unit == "lb" ? kilograms.kgToLbs : kilograms
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
                    .scaledToFill()
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
    @State private var focus: CGPoint?

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
        Image(uiImage: AspectFillCropper.crop(image, to: size, anchor: focus))
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
    }

    private func load() async {
        if let cached = SubjectPlateStore.shared.cachedPlate(for: urlString) {
            plate = cached
        } else {
            plate = nil
        }
        focus = SubjectPlateStore.shared.cachedFocus(for: urlString)

        guard let image = await ImageCacheService.shared.loadImage(from: urlString), !Task.isCancelled else {
            return
        }
        original = image

        if focus == nil {
            focus = await SubjectPlateStore.shared.focus(for: urlString, image: image)
            guard !Task.isCancelled else { return }
        }

        if plate == nil {
            plate = await SubjectPlateStore.shared.plate(for: urlString, image: image)
        }
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

    /// Aspect-fill where `anchor` — a normalized point in image space (x
    /// right, y down, 0–1) — lands on `anchorTarget`, a fraction of the
    /// target. Offsets clamp so the drawn image still covers the frame;
    /// a nil anchor is the centered fill above.
    static func fillRect(imageSize: CGSize, in target: CGSize, anchor: CGPoint?, anchorTarget: CGPoint) -> CGRect {
        let rect = fillRect(imageSize: imageSize, in: target)
        guard let anchor else { return rect }

        let offsetX = min(0, max(target.width - rect.width, anchorTarget.x * target.width - anchor.x * rect.width))
        let offsetY = min(0, max(target.height - rect.height, anchorTarget.y * target.height - anchor.y * rect.height))
        return CGRect(x: offsetX, y: offsetY, width: rect.width, height: rect.height)
    }

    static func crop(_ image: UIImage, to target: CGSize) -> UIImage {
        crop(image, to: target, anchor: nil)
    }

    static func crop(_ image: UIImage, to target: CGSize, anchor: CGPoint?) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        let rect = fillRect(
            imageSize: image.size,
            in: target,
            anchor: anchor,
            anchorTarget: TorsoFocusService.stageAnchor
        )
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: rect)
        }
    }
}
