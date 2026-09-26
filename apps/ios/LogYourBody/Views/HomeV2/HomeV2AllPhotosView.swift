//
// HomeV2AllPhotosView.swift
// LogYourBody
//
import SwiftUI

/// All photos (Pencil P5): a month-grouped grid of plates. Browsing opens a
/// photo; picking chooses the before and after for Compare.
struct HomeV2AllPhotosView: View {
    enum Mode: Equatable {
        case browse
        case pick
    }

    let bodyMetrics: [BodyMetrics]
    let formatters: HomeV2Formatters
    let mode: Mode
    let onSelect: (Int) -> Void
    let onClose: () -> Void
    var onTools: (() -> Void)?
    var pickHint = HomeV2PhotoCopy.chooseBefore

    private var chronological: [Int] { HomeV2PhotoIndex.chronologicalPhotoIndices(in: bodyMetrics) }

    private var sections: [(title: String, delta: String?, indices: [Int])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: chronological) { index -> String in
            let parts = calendar.dateComponents([.year, .month], from: bodyMetrics[index].date)
            return "\(parts.year ?? 0)-\(String(format: "%02d", parts.month ?? 0))"
        }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let indices = grouped[key], let first = indices.first else { return nil }
            let weights = indices.compactMap { formatters.weightValue(bodyMetrics[$0]) }
            return (
                title: HomeV2ContextCopy.monthTitle(for: bodyMetrics[first].date),
                delta: weights.count > 1
                    ? HomeV2ContextCopy.monthDelta(first: weights.first, last: weights.last, unit: formatters.weightUnit)
                    : nil,
                indices: indices.reversed()
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = 4
            let spacing: CGFloat = 2
            let cellWidth = (geometry.size.width - spacing * CGFloat(columns - 1) - spacing * 2) / CGFloat(columns)
            let cell = CGSize(width: cellWidth, height: cellWidth / HomeV2Tokens.photoAspectRatio)

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HomeV2Tokens.Space.row) {
                        ForEach(sections, id: \.title) { section in
                            HStack(alignment: .lastTextBaseline, spacing: HomeV2Tokens.Space.tight) {
                                Text(section.title)
                                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                                Spacer(minLength: HomeV2Tokens.Space.tight)
                                if let delta = section.delta {
                                    Text(delta)
                                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                                }
                            }
                            .padding(.horizontal, HomeV2Tokens.Space.inset)
                            .padding(.top, HomeV2Tokens.Space.compact)

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(cell.width), spacing: spacing), count: columns),
                                spacing: spacing
                            ) {
                                ForEach(section.indices, id: \.self) { index in
                                    photoCell(index, size: cell)
                                }
                            }
                            .padding(.horizontal, spacing)
                        }
                    }
                    .padding(.bottom, HomeV2Tokens.Space.margin)
                }

                hint
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(HomeV2Tokens.Colors.canvas.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: mode == .pick ? "xmark" : "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mode == .pick ? HomeV2PhotoCopy.cancel : "Back")
            .accessibilityIdentifier("home_v2_all_photos_close")

            Spacer(minLength: 0)

            Text(HomeV2PhotoCopy.photos)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_all_photos")

            Spacer(minLength: 0)

            if let onTools, mode == .browse {
                Button(action: onTools) {
                    Text(HomeV2PhotoCopy.tools)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home_v2_all_photos_tools")
            } else {
                Color.clear.frame(width: 64, height: JovieTokens.minimumHitTarget)
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    private func photoCell(_ index: Int, size: CGSize) -> some View {
        let metric = bodyMetrics[index]
        return Button {
            HapticManager.shared.selection()
            onSelect(index)
        } label: {
            SubjectPlateView(urlString: metric.photoUrl ?? "", size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formatters.dateText(metric)), \(formatters.weightText(metric)) \(formatters.weightUnit)")
        .accessibilityHint(mode == .pick ? "Chooses this photo" : "Opens this photo")
        .accessibilityIdentifier("home_v2_all_photos_cell")
    }

    private var hint: some View {
        Text(hintText)
            .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
            .foregroundStyle(HomeV2Tokens.Colors.secondary)
            .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
            .padding(.bottom, HomeV2Tokens.Space.tight)
            .accessibilityIdentifier("home_v2_all_photos_hint")
    }

    private var hintText: String {
        switch mode {
        case .browse: return HomeV2PhotoCopy.tapToOpen
        case .pick: return pickHint
        }
    }
}
