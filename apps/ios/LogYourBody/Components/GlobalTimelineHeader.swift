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
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var barRow: some View {
        HStack(spacing: 4) {
            zoneView(buckets: weeklyBuckets)
            zoneView(buckets: monthlyBuckets)
            zoneView(buckets: yearlyBuckets)
        }
        .frame(height: 24)
    }

    private func zoneView(buckets: [GlobalTimelineBucket]) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.10))

                let width = geometry.size.width
                let segmentWidth = buckets.isEmpty ? width : max(width / CGFloat(buckets.count), 2)

                HStack(spacing: 1) {
                    ForEach(buckets) { bucket in
                        let isSelected = bucket.id == cursor?.bucketId
                        Rectangle()
                            .fill(isSelected ? Color.liquidAccent : Color.white.opacity(0.25))
                            .frame(width: segmentWidth)
                            .onTapGesture {
                                let newCursor = GlobalTimelineCursor(
                                    date: bucket.endDate,
                                    scale: bucket.scale,
                                    bucketId: bucket.id
                                )
                                onCursorChange(newCursor)
                            }
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
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
}
