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

    @State private var showsDetails = false
    @State private var showsTools = false

    private static let detailsCollapsedHeight: CGFloat = 64
    private static let detailsExpandedHeight: CGFloat = 250

    private var photoIndices: [Int] { HomeV2PhotoIndex.photoIndices(in: bodyMetrics) }
    private var chronological: [Int] { HomeV2PhotoIndex.chronologicalPhotoIndices(in: bodyMetrics) }
    private var photoDates: [Date] { chronological.map { bodyMetrics[$0].date } }

    private var current: BodyMetrics? {
        bodyMetrics.indices.contains(selectedIndex) ? bodyMetrics[selectedIndex] : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let reserved = JovieTokens.compactControlHeight
                + (showsDetails ? Self.detailsExpandedHeight : Self.detailsCollapsedHeight)
            let stage = CGSize(
                width: geometry.size.width,
                height: HomeV2Layout.stageHeight(
                    width: geometry.size.width,
                    height: geometry.size.height - reserved + HomeV2Layout.belowPhotoHeight
                )
            )

            VStack(spacing: 0) {
                topBar

                TabView(selection: $selectedIndex) {
                    ForEach(photoIndices, id: \.self) { index in
                        SubjectPlateView(urlString: bodyMetrics[index].photoUrl ?? "", size: stage)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: stage.width, height: stage.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(current.map { "Progress photo, \(formatters.dateText($0))" } ?? "Progress photo")
                .accessibilityIdentifier("home_v2_viewer_stage")

                Spacer(minLength: 0)

                if let current {
                    if showsDetails {
                        details(for: current)
                    } else {
                        detailsRow(for: current)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showsTools) {
            HomeV2PhotoToolsSheet(
                dateText: current.map(formatters.dateText) ?? "",
                positionText: HomeV2Copy.photoPosition(position(of: selectedIndex), of: photoIndices.count),
                onSelect: { tool in
                    showsTools = false
                    if tool == .timeline {
                        showsDetails = true
                    } else {
                        onTool(tool)
                    }
                },
                onDone: { showsTools = false }
            )
        }
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
            .accessibilityLabel("Close")
            .accessibilityIdentifier("home_v2_viewer_close")

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(current.map(formatters.dateText) ?? "")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .lineLimit(1)

                Text(HomeV2Copy.photoPosition(position(of: selectedIndex), of: photoIndices.count))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }

            Spacer(minLength: 0)

            Button {
                showsTools = true
            } label: {
                HStack(spacing: HomeV2Tokens.Space.tight / 2) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                    Text(HomeV2PhotoCopy.tools)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                }
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(HomeV2PhotoCopy.photoTools)
            .accessibilityIdentifier("home_v2_viewer_tools")
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    private func detailsRow(for metric: BodyMetrics) -> some View {
        Button {
            withAnimation(.easeInOut(duration: JovieTokens.subtleDuration)) { showsDetails = true }
        } label: {
            HStack(spacing: HomeV2Tokens.Space.tight) {
                Text(HomeV2PhotoCopy.photoDetails(weight: "\(formatters.weightText(metric)) \(formatters.weightUnit)"))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
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
            HStack(alignment: .top, spacing: HomeV2Tokens.Space.tight) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatters.weightText(metric)) \(formatters.weightUnit)")
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .medium, relativeTo: .title2)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier("home_v2_viewer_weight")
                    Text(sinceSentence(for: metric))
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }

                Spacer(minLength: HomeV2Tokens.Space.tight)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(HomeV2PhotoCopy.bodyFatEstimated(formatters.bodyFatText(metric)))
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .medium, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                    Text(HomeV2PhotoCopy.bodyFatChange(bodyFatDelta(for: metric)))
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                }
            }
            .padding(.horizontal, HomeV2Tokens.Space.margin)
            .padding(.top, HomeV2Tokens.Space.compact)

            HomeV2PhotoTimelineRuler(
                dates: photoDates,
                selected: max(position(of: selectedIndex) - 1, 0),
                onSelect: { position in
                    guard chronological.indices.contains(position) else { return }
                    selectedIndex = chronological[position]
                }
            )
            .padding(.top, HomeV2Tokens.Space.compact)

            HStack(spacing: 0) {
                ForEach([HomeV2PhotoTool.compare, .timelapse, .allPhotos, .share]) { tool in
                    Button {
                        onTool(tool)
                    } label: {
                        VStack(spacing: HomeV2Tokens.Space.tight / 2) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 22, weight: .regular))
                            Text(tool.shortTitle)
                                .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                        }
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(maxWidth: .infinity, minHeight: HomeV2Tokens.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                    .accessibilityIdentifier("home_v2_viewer_action_\(tool.identifier)")
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
