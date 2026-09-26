//
// HomeV2PhotoTimelineRuler.swift
// LogYourBody
//
import SwiftUI

/// The scrubbable ruler under a photo (Pencil P3): months, weekly ticks,
/// a tick per photo, the selected photo tallest. Dragging selects the
/// nearest photo.
struct HomeV2PhotoTimelineRuler: View {
    let dates: [Date]
    let selected: Int
    let onSelect: (Int) -> Void
    var showsMonthLabels = true
    var calendar = Calendar.current

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private var span: DateInterval { HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar) }

    var body: some View {
        VStack(spacing: HomeV2Tokens.Space.tight) {
            if showsMonthLabels {
                monthLabels
            }
            ticks
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo timeline")
        .accessibilityValue(dates.indices.contains(selected) ? HomeV2ContextCopy.dayFormatter.string(from: dates[selected]) : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if selected + 1 < dates.count { onSelect(selected + 1) }
            case .decrement: if selected > 0 { onSelect(selected - 1) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("home_v2_photo_ruler")
    }

    private var monthLabels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ForEach(HomeV2PhotoRulerPolicy.monthStarts(in: span, calendar: calendar), id: \.self) { month in
                let x = HomeV2PhotoRulerPolicy.fraction(of: month, in: span) * width
                Text(Self.monthFormatter.string(from: month))
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .position(x: min(max(x, 14), width - 14), y: 8)
            }
        }
        .frame(height: 16)
    }

    private var ticks: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                ForEach(HomeV2PhotoRulerPolicy.weekTicks(in: span, calendar: calendar), id: \.self) { week in
                    tick(
                        at: HomeV2PhotoRulerPolicy.fraction(of: week, in: span) * width,
                        height: 8,
                        color: HomeV2Tokens.Colors.borderStrong
                    )
                }
                ForEach(HomeV2PhotoRulerPolicy.monthStarts(in: span, calendar: calendar), id: \.self) { month in
                    tick(
                        at: HomeV2PhotoRulerPolicy.fraction(of: month, in: span) * width,
                        height: 20,
                        color: HomeV2Tokens.Colors.quiet
                    )
                }
                ForEach(dates.indices, id: \.self) { index in
                    tick(
                        at: HomeV2PhotoRulerPolicy.fraction(of: dates[index], in: span) * width,
                        height: index == selected ? 28 : 14,
                        color: index == selected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary
                    )
                }
            }
            .frame(width: width, height: JovieTokens.minimumHitTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let fraction = value.location.x / max(width, 1)
                    if let index = HomeV2PhotoRulerPolicy.nearestIndex(to: fraction, dates: dates, span: span),
                       index != selected {
                        onSelect(index)
                        HapticManager.shared.selection()
                    }
                }
            )
        }
        .frame(height: JovieTokens.minimumHitTarget)
    }

    private func tick(at x: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: height)
            .position(x: x, y: JovieTokens.minimumHitTarget / 2)
    }
}
