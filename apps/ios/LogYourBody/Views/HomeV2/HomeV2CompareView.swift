//
// HomeV2CompareView.swift
// LogYourBody
//
import SwiftUI

/// Compare (Pencil P4): two plates under one slider, the change between
/// them, three ways to look, and the dates one disclosure away.
struct HomeV2CompareView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case slider
        case sideBySide
        case overlay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slider: return HomeV2PhotoCopy.slider
            case .sideBySide: return HomeV2PhotoCopy.sideBySide
            case .overlay: return HomeV2PhotoCopy.overlay
            }
        }
    }

    let bodyMetrics: [BodyMetrics]
    @Binding var pair: HomeV2PhotoPair
    let formatters: HomeV2Formatters
    let ffmiValue: (BodyMetrics) -> Double?
    let bodyFatSource: String?
    let onClose: () -> Void
    let onShare: (HomeV2PhotoPair) -> Void
    let onChangeDates: () -> Void

    @State private var mode: Mode = .slider
    @State private var split: CGFloat = 0.5

    /// Top bar, delta row, mode row and the dates block below the stage.
    private static let chromeHeight: CGFloat = 52 + 66 + 52 + 120

    private var before: BodyMetrics? { bodyMetrics.indices.contains(pair.before) ? bodyMetrics[pair.before] : nil }
    private var after: BodyMetrics? { bodyMetrics.indices.contains(pair.after) ? bodyMetrics[pair.after] : nil }

    private var days: Int {
        guard let before, let after else { return 0 }
        return Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0
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
                if let before, let after {
                    stageView(before: before, after: after, size: stage)
                    deltaRow(before: before, after: after)
                    modeRow
                    pickDates(before: before, after: after)
                } else {
                    Text(HomeV2PhotoCopy.notEnoughPhotos)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.body, relativeTo: .body)
                        .foregroundStyle(HomeV2Tokens.Colors.secondary)
                        .padding(HomeV2Tokens.Space.margin)
                }
                Spacer(minLength: 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
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
            .accessibilityIdentifier("home_v2_compare_close")

            Spacer(minLength: 0)

            Text(HomeV2PhotoCopy.compareTitle(days: days))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home_v2_compare")

            Spacer(minLength: 0)

            Button {
                onShare(pair)
            } label: {
                HStack(spacing: HomeV2Tokens.Space.tight / 2) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                    Text(HomeV2PhotoCopy.share)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                }
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .frame(minWidth: 64, minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(HomeV2PhotoCopy.shareProgress)
            .accessibilityIdentifier("home_v2_compare_share")
        }
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .frame(height: JovieTokens.compactControlHeight)
    }

    @ViewBuilder
    private func stageView(before: BodyMetrics, after: BodyMetrics, size: CGSize) -> some View {
        switch mode {
        case .slider:
            ZStack(alignment: .topLeading) {
                SubjectPlateView(urlString: after.photoUrl ?? "", size: size)
                SubjectPlateView(urlString: before.photoUrl ?? "", size: size)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * split)
                    }
                Rectangle()
                    .fill(HomeV2Tokens.Colors.ink)
                    .frame(width: 2, height: size.height)
                    .position(x: size.width * split, y: size.height / 2)
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                    .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    .background(HomeV2Tokens.Colors.canvas.opacity(0.65), in: Circle())
                    .overlay(Circle().stroke(HomeV2Tokens.Colors.ink, lineWidth: 1))
                    .position(x: size.width * split, y: size.height / 2)
                tag(for: before, alignment: .leading)
                tag(for: after, alignment: .trailing)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    split = min(max(value.location.x / size.width, 0.05), 0.95)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before and after slider")
            .accessibilityValue("\(Int(split * 100)) percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(split + 0.1, 0.95)
                case .decrement: split = max(split - 0.1, 0.05)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("home_v2_compare_stage")
        case .sideBySide:
            HStack(spacing: 2) {
                let half = CGSize(width: (size.width - 2) / 2, height: size.height)
                SubjectPlateView(urlString: before.photoUrl ?? "", size: half)
                    .overlay(alignment: .topLeading) { tag(for: before, alignment: .leading) }
                SubjectPlateView(urlString: after.photoUrl ?? "", size: half)
                    .overlay(alignment: .topLeading) { tag(for: after, alignment: .leading) }
            }
            .frame(width: size.width, height: size.height)
            .accessibilityIdentifier("home_v2_compare_stage")
        case .overlay:
            ZStack(alignment: .topLeading) {
                SubjectPlateView(urlString: before.photoUrl ?? "", size: size)
                SubjectPlateView(urlString: after.photoUrl ?? "", size: size)
                    .opacity(0.55)
                tag(for: before, alignment: .leading)
                tag(for: after, alignment: .trailing)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityIdentifier("home_v2_compare_stage")
        }
    }

    private func tag(for metric: BodyMetrics, alignment: Alignment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatters.dateText(metric))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, weight: .semibold, relativeTo: .subheadline)
            Text("\(formatters.weightText(metric)) \(formatters.weightUnit)")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
        }
        .foregroundStyle(HomeV2Tokens.Colors.ink)
        .padding(.horizontal, HomeV2Tokens.Space.row)
        .padding(.vertical, HomeV2Tokens.Space.tight)
        .background(HomeV2Tokens.Colors.canvas.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(HomeV2Tokens.Space.row)
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func deltaRow(before: BodyMetrics, after: BodyMetrics) -> some View {
        let weightDelta = zip(formatters.weightValue(after), formatters.weightValue(before)).map { $0 - $1 }
        let bodyFatDelta = zip(formatters.bodyFatValue(after), formatters.bodyFatValue(before)).map { $0 - $1 }
        let ffmiDelta = zip(ffmiValue(after), ffmiValue(before)).map { $0 - $1 }
        return HStack(alignment: .top, spacing: HomeV2Tokens.Space.tight) {
            deltaCell(weightDelta.map { "\(HomeV2PhotoCopy.signed($0)) \(formatters.weightUnit)" }, label: HomeV2PhotoCopy.weight)
            deltaCell(bodyFatDelta.map { "\(HomeV2PhotoCopy.signed($0)) pts" }, label: HomeV2PhotoCopy.estimatedBodyFat)
            deltaCell(ffmiDelta.map { HomeV2PhotoCopy.signed($0) }, label: HomeV2PhotoCopy.derivedFFMI)
        }
        .padding(.horizontal, HomeV2Tokens.Space.margin)
        .frame(minHeight: 66)
        .accessibilityIdentifier("home_v2_compare_deltas")
    }

    private func deltaCell(_ value: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.sheetTitle, weight: .medium, relativeTo: .title2)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var modeRow: some View {
        HStack(spacing: HomeV2Tokens.Space.tight) {
            ForEach(Mode.allCases) { candidate in
                let isSelected = candidate == mode
                Button {
                    mode = candidate
                    HapticManager.shared.selection()
                } label: {
                    Text(candidate.title)
                        .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(isSelected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary)
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                        .background(isSelected ? HomeV2Tokens.Colors.card : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("home_v2_compare_mode_\(candidate.rawValue)")
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .frame(minHeight: HomeV2Tokens.rowHeight)
    }

    private func pickDates(before: BodyMetrics, after: BodyMetrics) -> some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            if let transition = HomeV2PhotoCopy.bodyFatTransition(
                from: formatters.bodyFatValue(before),
                to: formatters.bodyFatValue(after)
            ) {
                let lines = [transition, bodyFatSource.map(HomeV2PhotoCopy.estimatedBySource)].compactMap { $0 }
                Text(lines.joined(separator: "\n"))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HomeV2Tokens.Space.margin)
            }

            HomeV2DisclosureLink(
                title: HomeV2PhotoCopy.changeDates,
                identifier: "home_v2_compare_change_dates",
                action: onChangeDates
            )
                .padding(.horizontal, HomeV2Tokens.Space.margin)
        }
        .padding(.top, HomeV2Tokens.Space.compact)
    }
}

private func zip<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}
