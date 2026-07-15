import SwiftUI

struct GlobalTimelineHeader: View {
    let weeklyBuckets: [GlobalTimelineBucket]
    let monthlyBuckets: [GlobalTimelineBucket]
    let yearlyBuckets: [GlobalTimelineBucket]
    let cursor: GlobalTimelineCursor?

    let onCursorChange: (GlobalTimelineCursor) -> Void
    let onTodayTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            barRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var headerRow: some View {
        HStack {
            Text(currentLabel)
                .font(.footnote)
                .foregroundColor(Color.liquidTextPrimary)

            Spacer()

            Button(action: onTodayTap) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .accessibilityLabel("Jump to today")
            .accessibilityHint("Selects the most recent timeline period")
        }
    }

    private var barRow: some View {
        HStack(spacing: 4) {
            zoneView(buckets: weeklyBuckets)
            zoneView(buckets: monthlyBuckets)
            zoneView(buckets: yearlyBuckets)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline periods")
    }

    private func zoneView(buckets: [GlobalTimelineBucket]) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let visualHeight: CGFloat = 24

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.10))
                    .frame(height: visualHeight)

                if !buckets.isEmpty {
                    let totalSpacing = CGFloat(max(buckets.count - 1, 0))
                    let segmentWidth = max((width - totalSpacing) / CGFloat(buckets.count), 2)

                    HStack(spacing: 1) {
                        ForEach(buckets) { bucket in
                            let isSelected = bucket.id == cursor?.bucketId

                            Rectangle()
                                .fill(isSelected ? Color.liquidAccent : Color.white.opacity(0.25))
                                .frame(width: segmentWidth, height: visualHeight)
                        }
                    }
                    .frame(width: width, height: 44, alignment: .leading)
                    .accessibilityHidden(true)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                selectBucket(in: buckets, at: value.location.x, width: width)
                            }
                    )
            }
            .frame(width: width, height: 44, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(zoneAccessibilityLabel(for: buckets))
            .accessibilityValue(zoneAccessibilityValue(for: buckets))
            .accessibilityHint("Tap to select a period. Swipe up or down to move between periods.")
            .accessibilityAdjustableAction { direction in
                adjustBucketSelection(in: buckets, direction: direction)
            }
            .accessibilityIdentifier(zoneAccessibilityIdentifier(for: buckets))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var currentLabel: String {
        guard let cursor else { return "Timeline" }
        switch cursor.scale {
        case .week:
            return "Recent weeks"
        case .month:
            return "Recent months"
        case .year:
            return "Past years"
        }
    }

    private func accessibilityLabel(for bucket: GlobalTimelineBucket) -> String {
        let start = bucket.startDate.formatted(.dateTime.month(.abbreviated).day().year())
        let end = bucket.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(scaleName(for: bucket.scale)), \(start) to \(end)"
    }

    private func scaleName(for scale: GlobalTimelineScale) -> String {
        switch scale {
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        }
    }

    private func zoneAccessibilityLabel(for buckets: [GlobalTimelineBucket]) -> String {
        guard let scale = buckets.first?.scale else {
            return "Timeline"
        }
        return "\(scaleName(for: scale)) timeline"
    }

    private func zoneAccessibilityValue(for buckets: [GlobalTimelineBucket]) -> String {
        guard let selected = buckets.first(where: { $0.id == cursor?.bucketId }) else {
            return buckets.isEmpty ? "No periods" : "No period selected"
        }
        return accessibilityLabel(for: selected)
    }

    private func zoneAccessibilityIdentifier(for buckets: [GlobalTimelineBucket]) -> String {
        guard let scale = buckets.first?.scale else {
            return "timeline_zone_empty"
        }
        return "timeline_zone_\(scale.rawValue)"
    }

    private func selectBucket(
        in buckets: [GlobalTimelineBucket],
        at location: CGFloat,
        width: CGFloat
    ) {
        guard !buckets.isEmpty else { return }

        let normalizedPosition = min(max(location / max(width, 1), 0), 0.999999)
        let index = min(Int(normalizedPosition * CGFloat(buckets.count)), buckets.count - 1)
        let bucket = buckets[index]
        onCursorChange(
            GlobalTimelineCursor(
                date: bucket.endDate,
                scale: bucket.scale,
                bucketId: bucket.id
            )
        )
    }

    private func adjustBucketSelection(
        in buckets: [GlobalTimelineBucket],
        direction: AccessibilityAdjustmentDirection
    ) {
        guard !buckets.isEmpty else { return }

        let currentIndex = buckets.firstIndex(where: { $0.id == cursor?.bucketId })
        let nextIndex: Int

        switch direction {
        case .increment:
            nextIndex = currentIndex.map { min($0 + 1, buckets.count - 1) } ?? 0
        case .decrement:
            nextIndex = currentIndex.map { max($0 - 1, 0) } ?? (buckets.count - 1)
        @unknown default:
            return
        }

        let bucket = buckets[nextIndex]
        onCursorChange(
            GlobalTimelineCursor(
                date: bucket.endDate,
                scale: bucket.scale,
                bucketId: bucket.id
            )
        )
    }
}
