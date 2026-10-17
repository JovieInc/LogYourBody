//
// HomeV2PhotoTimelineRuler.swift
// LogYourBody
//
import SwiftUI

/// The scrubbable ruler under a photo (Pencil P3). Screen-space buckets bound
/// the visible marks; the complete date array still drives drag and accessibility.
struct HomeV2PhotoTimelineRuler: View {
    let dates: [Date]
    let selected: Int
    let onSelect: (Int) -> Void
    var showsMonthLabels = true
    var allowsVerticalScrolling = false
    var calendar = Calendar.current
    var accessibilityId = "home_v2_photo_ruler"
    var accessibilityName = "Photo timeline"

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption) private var minimumLabelSpacing: CGFloat = 88

    var body: some View {
        // One immutable span per evaluation. Both rendering and all gesture
        // callbacks capture this value; scrubbing never sorts/rebuilds the axis.
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        VStack(spacing: HomeV2Tokens.Space.tight) {
            if showsMonthLabels {
                // Intrinsic caption height participates in safe-area measurement,
                // including Dynamic Type, without a fixed-height label row.
                Text("September 2026")
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .lineLimit(1)
                    .hidden()
                    .frame(maxWidth: .infinity)
            }
            Color.clear.frame(height: JovieTokens.minimumHitTarget)
        }
        .overlay {
            GeometryReader { geometry in
                let width = geometry.size.width
                let plan = HomeV2PhotoRulerPolicy.renderPlan(
                    dates: dates, selected: selected, span: span, width: width,
                    minimumLabelSpacing: minimumLabelSpacing, calendar: calendar, locale: locale
                )
                VStack(spacing: HomeV2Tokens.Space.tight) {
                    if showsMonthLabels {
                        monthLabels(plan.labels, width: width)
                            .frame(height: max(0, geometry.size.height - JovieTokens.minimumHitTarget - HomeV2Tokens.Space.tight))
                    }
                    ticks(plan, width: width, span: span)
                }
            }
        }
        .padding(.horizontal, HomeV2Tokens.Space.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(dates.indices.contains(selected) ? HomeV2ContextCopy.dayFormatter.string(from: dates[selected]) : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if selected + 1 < dates.count { onSelect(selected + 1) }
            case .decrement: if selected > 0 { onSelect(selected - 1) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier(accessibilityId)
    }

    private func monthLabels(_ labels: [HomeV2PhotoRulerPolicy.CalendarLabel], width: CGFloat) -> some View {
        GeometryReader { geometry in
            ForEach(labels, id: \.date) { label in
                Text(label.text)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
                    .lineLimit(1)
                    .frame(width: min(minimumLabelSpacing, width))
                    .position(x: layoutDirection == .rightToLeft ? width - label.position : label.position,
                              y: geometry.size.height / 2)
            }
        }
    }

    @ViewBuilder
    private func ticks(_ plan: HomeV2PhotoRulerPolicy.RenderPlan, width: CGFloat, span: DateInterval) -> some View {
        if allowsVerticalScrolling {
            tickMarks(plan, width: width, span: span)
                .gesture(HomeV2HorizontalPhotoScrub { position in
                    select(at: position, width: width, span: span)
                })
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in select(at: value.location.x, width: width, span: span) }
                )
        } else {
            tickMarks(plan, width: width, span: span)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    select(at: value.location.x, width: width, span: span)
                })
        }
    }

    private func tickMarks(_ plan: HomeV2PhotoRulerPolicy.RenderPlan, width: CGFloat, span: DateInterval) -> some View {
        ZStack(alignment: .leading) {
            ForEach(plan.minorTicks, id: \.self) { week in
                tick(
                    at: position(of: week, width: width, span: span),
                    height: 8,
                    color: HomeV2Tokens.Colors.borderStrong
                )
            }
            ForEach(plan.majorTicks, id: \.self) { month in
                tick(
                    at: position(of: month, width: width, span: span),
                    height: 20,
                    color: HomeV2Tokens.Colors.quiet
                )
            }
            ForEach(plan.entryIndices, id: \.self) { index in
                tick(
                    at: position(of: dates[index], width: width, span: span),
                    height: index == selected ? 28 : 14,
                    color: index == selected ? HomeV2Tokens.Colors.ink : HomeV2Tokens.Colors.secondary
                )
            }
        }
        .frame(width: width, height: JovieTokens.minimumHitTarget)
        .contentShape(Rectangle())
    }

    private func select(at position: CGFloat, width: CGFloat, span: DateInterval) {
        let fraction = HomeV2PhotoRulerPolicy.logicalFraction(
            at: position, width: width, isRightToLeft: layoutDirection == .rightToLeft
        )
        if let index = HomeV2PhotoRulerPolicy.nearestIndex(to: fraction, dates: dates, span: span), index != selected {
            onSelect(index)
            HapticManager.shared.selection()
        }
    }

    private func position(of date: Date, width: CGFloat, span: DateInterval) -> CGFloat {
        let fraction = HomeV2PhotoRulerPolicy.fraction(of: date, in: span)
        return (layoutDirection == .rightToLeft ? 1 - fraction : fraction) * width
    }

    private func tick(at x: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: height)
            .position(x: x, y: JovieTokens.minimumHitTarget / 2)
    }
}

/// Rejects vertical intent before recognizing, leaving the enclosing scroll view
/// free to handle it. Ignoring an already-recognized SwiftUI drag is too late.
private struct HomeV2HorizontalPhotoScrub: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        onChange(context.converter.localLocation.x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
