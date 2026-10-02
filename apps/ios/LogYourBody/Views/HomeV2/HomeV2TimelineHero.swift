//
// HomeV2TimelineHero.swift
// LogYourBody
//
import SwiftUI

/// Order helpers shared by the pager and the scrubber (JOV-6016): both resolve
/// to the same bodyMetrics index so swiping and scrubbing never disagree on the
/// selected day.
enum HomeV2TimelinePolicy {
    /// Day indices oldest first — the order the scrubber draws time.
    static func chronologicalIndices(in bodyMetrics: [BodyMetrics]) -> [Int] {
        bodyMetrics.indices.sorted { bodyMetrics[$0].date < bodyMetrics[$1].date }
    }

    /// The scrubber position for a selected index (0-based, oldest first).
    static func chronologicalPosition(of index: Int, in bodyMetrics: [BodyMetrics]) -> Int {
        chronologicalIndices(in: bodyMetrics).firstIndex(of: index) ?? 0
    }

    /// The index at a scrubber position, or nil when out of range.
    static func index(at position: Int, in bodyMetrics: [BodyMetrics]) -> Int? {
        let order = chronologicalIndices(in: bodyMetrics)
        return order.indices.contains(position) ? order[position] : nil
    }
}

/// The signature Home stage (JOV-6016): one full-width 4:5 page per day.
/// Days with a photo show the plate and tap through to the viewer; days
/// without one render the editorial plate so the timeline stays browsable
/// through metric-only history. Swiping left travels back in time because
/// `bodyMetrics` is newest-first.
struct HomeV2TimelinePager: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let size: CGSize
    let dateText: (BodyMetrics) -> String
    let onOpenPhoto: () -> Void

    private var selected: BodyMetrics? {
        bodyMetrics.indices.contains(selectedIndex) ? bodyMetrics[selectedIndex] : nil
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(bodyMetrics.indices, id: \.self) { index in
                page(for: bodyMetrics[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Swipe left or right to move through your history")
        .accessibilityIdentifier("home_v2_photo_stage")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if selectedIndex + 1 < bodyMetrics.count { selectedIndex += 1 }
            case .decrement:
                if selectedIndex > 0 { selectedIndex -= 1 }
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func page(for metric: BodyMetrics) -> some View {
        if PhotoTimelineHUDPolicy.hasUsablePhoto(metric), let photoURL = metric.photoUrl {
            SubjectPlateView(urlString: photoURL, size: size)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenPhoto)
        } else {
            HomeV2EditorialPlate(dateText: dateText(metric), size: size)
        }
    }

    private var accessibilityLabel: String {
        guard let selected else { return "Body timeline" }
        return PhotoTimelineHUDPolicy.hasUsablePhoto(selected)
            ? "Progress photo, \(dateText(selected))"
            : "No photo, \(dateText(selected))"
    }
}

/// The no-photo page of the timeline: the same 4:5 geometry with an editorial
/// treatment — quiet gradient shell, the ruler motif, and the day — so a
/// metric-only history never reads as an empty avatar state.
struct HomeV2EditorialPlate: View {
    let dateText: String
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [HomeV2Tokens.Colors.elevated, HomeV2Tokens.Colors.shell],
                startPoint: .top,
                endPoint: .bottom
            )

            rulerMotif

            VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight / 2) {
                Text(dateText)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.heroPhoto, weight: .light, relativeTo: .largeTitle)
                    .foregroundStyle(HomeV2Tokens.Colors.ink)
                Text(HomeV2Copy.noPhotoThisDay)
                    .scaledSystemFont(size: HomeV2Tokens.TypeSize.small, relativeTo: .caption)
                    .foregroundStyle(HomeV2Tokens.Colors.quiet)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(HomeV2Tokens.Space.margin)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No photo for \(dateText)")
        .accessibilityIdentifier("home_v2_editorial_plate")
    }

    /// The timeline's own marks as the quiet centerpiece, echoing the scrubber.
    private var rulerMotif: some View {
        HStack(alignment: .center, spacing: 6) {
            motifTick(height: 16)
            motifTick(height: 32)
            motifTick(height: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func motifTick(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(HomeV2Tokens.Colors.borderStrong)
            .frame(width: 2, height: height)
    }
}

/// One-time coach mark for the signature interactions (JOV-6016): it teaches
/// swipe and scrub once, then leaves the surface permanently. Dismissal is
/// stored in AppStorage by the surface.
struct HomeV2TimelineCoachMark: View {
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Text(HomeV2Copy.timelineCoachHint)
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.secondary, relativeTo: .subheadline)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, HomeV2Tokens.Space.margin)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HomeV2Copy.timelineCoachHint)
        .accessibilityHint("Double tap to dismiss")
        .accessibilityIdentifier("home_v2_timeline_coach")
    }
}
