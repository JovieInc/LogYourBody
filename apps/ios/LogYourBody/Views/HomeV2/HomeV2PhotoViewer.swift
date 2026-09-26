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
    let weightUnit: String
}

enum HomeV2PhotoIndex {
    static func photoIndices(in bodyMetrics: [BodyMetrics]) -> [Int] {
        bodyMetrics.indices.filter { PhotoTimelineHUDPolicy.hasUsablePhoto(bodyMetrics[$0]) }
    }

    /// The earliest day with a photo, so change reads "since <first photo>".
    static func firstPhotoIndex(in bodyMetrics: [BodyMetrics]) -> Int? {
        photoIndices(in: bodyMetrics).min { bodyMetrics[$0].date < bodyMetrics[$1].date }
    }
}

/// Full-screen photo viewer (Pencil P2): the plate edge to edge, swipe between
/// days with photos, the day's numbers below, the shared filmstrip. Nothing is
/// drawn over the person.
struct HomeV2PhotoViewer: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let formatters: HomeV2Formatters
    let onClose: () -> Void

    private var photoIndices: [Int] { HomeV2PhotoIndex.photoIndices(in: bodyMetrics) }

    private var current: BodyMetrics? {
        bodyMetrics.indices.contains(selectedIndex) ? bodyMetrics[selectedIndex] : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let stage = CGSize(
                width: geometry.size.width,
                height: HomeV2Layout.stageHeight(width: geometry.size.width, height: geometry.size.height - 44)
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

                if let current {
                    numbers(for: current)
                }

                HomeV2Filmstrip(bodyMetrics: bodyMetrics, selectedIndex: $selectedIndex)

                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
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
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.muted)
            }

            Spacer(minLength: 0)

            Color.clear
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    private func numbers(for metric: BodyMetrics) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formatters.weightText(metric))
                        .scaledSystemFont(size: 28, weight: .semibold, relativeTo: .title)
                        .foregroundStyle(HomeV2Tokens.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("home_v2_viewer_weight")

                    Text(formatters.weightUnit)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.muted)
                }

                Text(sinceSentence(for: metric))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }

            Spacer(minLength: HomeV2Tokens.Space.tight)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatters.bodyFatText(metric))
                    .scaledSystemFont(size: 28, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Body fat")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .footnote)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .padding(.top, HomeV2Tokens.Space.compact)
    }

    private func position(of index: Int) -> Int {
        let sorted = photoIndices.sorted { bodyMetrics[$0].date < bodyMetrics[$1].date }
        return (sorted.firstIndex(of: index) ?? 0) + 1
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
}
