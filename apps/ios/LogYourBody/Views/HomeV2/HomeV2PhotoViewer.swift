//
// HomeV2PhotoViewer.swift
// LogYourBody
//
import SwiftUI

/// Formatting the viewer borrows from the dashboard so values read exactly as
/// they do on Home.
struct HomeV2Formatters {
    let dateText: (BodyMetrics) -> String
    let weightText: (BodyMetrics) -> String
    let weightValue: (BodyMetrics) -> Double?
    let bodyFatText: (BodyMetrics) -> String
    var bodyFatValue: (BodyMetrics) -> Double? = { $0.bodyFatPercentage }
    let weightUnit: String
}

enum HomeV2PhotoIndex {
    static func photoIndices(in bodyMetrics: [BodyMetrics]) -> [Int] {
        bodyMetrics.indices.filter { PhotoTimelineHUDPolicy.hasUsablePhoto(bodyMetrics[$0]) }
    }

    /// Photo indices oldest first, the order the ruler, compare and timelapse use.
    static func chronologicalPhotoIndices(in bodyMetrics: [BodyMetrics]) -> [Int] {
        photoIndices(in: bodyMetrics).sorted { bodyMetrics[$0].date < bodyMetrics[$1].date }
    }

    /// The earliest day with a photo, so change reads "since <first photo>".
    static func firstPhotoIndex(in bodyMetrics: [BodyMetrics]) -> Int? {
        photoIndices(in: bodyMetrics).min { bodyMetrics[$0].date < bodyMetrics[$1].date }
    }
}

/// Full-screen photo viewer (Pencil P2/P3): the plate edge to edge, swipe
/// between days with photos, "Photo details" behind one disclosure that
/// opens the numbers, the timeline ruler and the photo tools. Nothing is
/// drawn over the person.
struct HomeV2PhotoViewer: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let formatters: HomeV2Formatters
    let sourceLine: String?
    let onClose: () -> Void
    let onTool: (HomeV2PhotoTool) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDetails = false
    @State private var showsTools = false
    @State private var pendingTool: HomeV2PhotoTool?

    private static let detailsCollapsedHeight: CGFloat = 64

    private var photoIndices: [Int] { HomeV2PhotoIndex.photoIndices(in: bodyMetrics) }
    private var chronological: [Int] { HomeV2PhotoIndex.chronologicalPhotoIndices(in: bodyMetrics) }
    private var photoDates: [Date] { chronological.map { bodyMetrics[$0].date } }

    private var current: BodyMetrics? {
        bodyMetrics.indices.contains(selectedIndex) ? bodyMetrics[selectedIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                ScrollView {
                    HomeV2ViewerContentLayout(viewport: geometry.size) {
                        GeometryReader { stage in
                            photoStage(size: stage.size)
                        }
                        VStack(spacing: 0) {
                            if let current {
                                if showsDetails {
                                    details(for: current)
                                } else {
                                    detailsRow(for: current)
                                }
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("home_v2_viewer_scroll")
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showsTools, onDismiss: {
            guard let tool = pendingTool else { return }
            pendingTool = nil
            onTool(tool)
        }, content: {
            HomeV2PhotoToolsSheet(
                dateText: current.map(formatters.dateText) ?? "",
                positionText: HomeV2Copy.photoPosition(position(of: selectedIndex), of: photoIndices.count),
                onSelect: { tool in
                    if tool == .timeline {
                        showsDetails = true
                    } else {
                        pendingTool = tool
                    }
                    showsTools = false
                },
                onDone: { showsTools = false }
            )
        })
    }

    private func photoStage(size: CGSize) -> some View {
        let height = min(size.height, size.width / HomeV2Tokens.photoAspectRatio)
        let photoSize = CGSize(width: height * HomeV2Tokens.photoAspectRatio, height: height)
        return TabView(selection: $selectedIndex) {
            ForEach(photoIndices, id: \.self) { index in
                SubjectPlateView(urlString: bodyMetrics[index].photoUrl ?? "", size: photoSize)
                    .frame(width: size.width, height: size.height)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { "Progress photo, \(formatters.dateText($0))" } ?? "Progress photo")
        .accessibilityIdentifier("home_v2_viewer_stage")
    }

    private var topBar: some View {
        VStack(spacing: HomeV2Tokens.Space.tight) {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                closeButton
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize { photoHeading }
                Spacer(minLength: 0)
                toolsButton
            }
            if dynamicTypeSize.isAccessibilitySize { photoHeading }
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? HomeV2Tokens.Space.tight : 0)
        .frame(minHeight: JovieTokens.compactControlHeight)
    }

    private var photoHeading: some View {
        VStack(spacing: 2) {
            Text(current.map(formatters.dateText) ?? "")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home_v2_viewer_date")
            Text(HomeV2Copy.photoPosition(position(of: selectedIndex), of: photoIndices.count))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("home_v2_viewer_close")
    }

    private var toolsButton: some View {
        Button {
            showsTools = true
        } label: {
            HStack(spacing: HomeV2Tokens.Space.tight / 2) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                Text(HomeV2PhotoCopy.tools)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HomeV2PhotoCopy.photoTools)
        .accessibilityIdentifier("home_v2_viewer_tools")
    }

    private func detailsRow(for metric: BodyMetrics) -> some View {
        Button {
            withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsDetails = true }
        } label: {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2PhotoCopy.photoDetails(weight: "\(formatters.weightText(metric)) \(formatters.weightUnit)"))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home_v2_viewer_weight")
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .frame(minHeight: Self.detailsCollapsedHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the day's numbers, the timeline and the photo tools")
        .accessibilityIdentifier("home_v2_viewer_details")
    }

    private func details(for metric: BodyMetrics) -> some View {
        VStack(spacing: 0) {
            metricDetails(for: metric)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .padding(.top, HomeV2Tokens.Space.compact)

            HomeV2PhotoTimelineRuler(
                dates: photoDates,
                selected: max(position(of: selectedIndex) - 1, 0),
                onSelect: { position in
                    guard chronological.indices.contains(position) else { return }
                    selectedIndex = chronological[position]
                },
                allowsVerticalScrolling: true
            )
            .padding(.top, HomeV2Tokens.Space.compact)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4),
                spacing: HomeV2Tokens.Space.tight
            ) {
                ForEach([HomeV2PhotoTool.compare, .timelapse, .allPhotos, .share]) { tool in
                    toolButton(tool)
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.inset)
            .padding(.top, HomeV2Tokens.Space.tight)

            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(sourceLine ?? HomeV2PhotoCopy.measurementsSeparate)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: HomeV2Tokens.Space.tight)
                Button {
                    withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsDetails = false }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeV2Tokens.Colors.quiet)
                        .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HomeV2PhotoCopy.hideDetails)
                .accessibilityIdentifier("home_v2_viewer_details_hide")
            }
            .padding(.leading, HomeV2Tokens.Space.margin)
            .padding(.trailing, HomeV2Tokens.Space.row)
            .padding(.bottom, HomeV2Tokens.Space.tight)
        }
    }

    private func metricDetails(for metric: BodyMetrics) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HomeV2Tokens.Space.compact))
            : AnyLayout(HStackLayout(alignment: .top, spacing: HomeV2Tokens.Space.tight))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatters.weightText(metric)) \(formatters.weightUnit)")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .medium, relativeTo: .title2)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .accessibilityIdentifier("home_v2_viewer_weight")
                Text(sinceSentence(for: metric))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .accessibilityIdentifier("home_v2_viewer_since")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(HomeV2PhotoCopy.bodyFatEstimated(formatters.bodyFatText(metric)))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                Text(HomeV2PhotoCopy.bodyFatChange(bodyFatDelta(for: metric)))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .accessibilityIdentifier("home_v2_viewer_body_fat_change")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
    }

    private func toolButton(_ tool: HomeV2PhotoTool) -> some View {
        Button {
            onTool(tool)
        } label: {
            VStack(spacing: HomeV2Tokens.Space.tight / 2) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 22, weight: .regular))
                Text(tool.shortTitle)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .frame(maxWidth: .infinity, minHeight: HomeV2Tokens.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityIdentifier("home_v2_viewer_action_\(tool.identifier)")
    }

    private func position(of index: Int) -> Int {
        (chronological.firstIndex(of: index) ?? 0) + 1
    }

    private func sinceSentence(for metric: BodyMetrics) -> String {
        guard let firstIndex = HomeV2PhotoIndex.firstPhotoIndex(in: bodyMetrics),
              firstIndex != selectedIndex,
              let now = formatters.weightValue(metric),
              let then = formatters.weightValue(bodyMetrics[firstIndex]) else {
            return HomeV2Copy.firstPhoto
        }
        return HomeV2Copy.sinceSentence(
            delta: now - then,
            unit: formatters.weightUnit,
            since: formatters.dateText(bodyMetrics[firstIndex])
        )
    }

    private func bodyFatDelta(for metric: BodyMetrics) -> Double? {
        guard let firstIndex = HomeV2PhotoIndex.firstPhotoIndex(in: bodyMetrics),
              firstIndex != selectedIndex,
              let now = formatters.bodyFatValue(metric),
              let then = formatters.bodyFatValue(bodyMetrics[firstIndex]) else {
            return nil
        }
        return now - then
    }
}

/// Uses the details' intrinsic height so a wrapped date never loses space to
/// the photo. Larger content scrolls while the close and tools controls stay visible.
private struct HomeV2ViewerContentLayout: Layout {
    let viewport: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? viewport.width
        let heights = heights(width: width, subviews: subviews)
        return CGSize(width: width, height: max(viewport.height, heights.photo + heights.details))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let heights = heights(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: heights.photo)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - heights.details), anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: heights.details)
        )
    }

    private func heights(width: CGFloat, subviews: Subviews) -> (photo: CGFloat, details: CGFloat) {
        guard subviews.count == 2 else { return (0, 0) }
        let details = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let photo = min(
            width / HomeV2Tokens.photoAspectRatio,
            max(HomeV2Layout.minimumStageHeight, viewport.height - details)
        )
        return (photo, details)
    }
}
