import SwiftUI

struct GlobalTimelineHeaderZone: Identifiable, Equatable {
    let scale: GlobalTimelineScale
    let buckets: [GlobalTimelineBucket]

    var id: String {
        scale.rawValue
    }
}

enum GlobalTimelineHeaderPresentation {
    static let emptyTimelineLabel = "Your timeline will appear after your first check-in"

    static func visibleZones(
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket]
    ) -> [GlobalTimelineHeaderZone] {
        [
            GlobalTimelineHeaderZone(scale: .week, buckets: weeklyBuckets),
            GlobalTimelineHeaderZone(scale: .month, buckets: monthlyBuckets),
            GlobalTimelineHeaderZone(scale: .year, buckets: yearlyBuckets)
        ]
        .filter { !$0.buckets.isEmpty }
    }

    static func currentLabel(
        cursor: GlobalTimelineCursor?,
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket],
        calendar: Calendar = .current
    ) -> String {
        guard let cursor else {
            return visibleZones(
                weeklyBuckets: weeklyBuckets,
                monthlyBuckets: monthlyBuckets,
                yearlyBuckets: yearlyBuckets
            ).isEmpty ? emptyTimelineLabel : "Timeline"
        }

        let referenceDate = bucket(
            for: cursor,
            weeklyBuckets: weeklyBuckets,
            monthlyBuckets: monthlyBuckets,
            yearlyBuckets: yearlyBuckets
        )?.startDate ?? bucketStartDate(for: cursor, calendar: calendar)

        switch cursor.scale {
        case .week:
            return "Week of \(referenceDate.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return referenceDate.formatted(.dateTime.year())
        }
    }

    private static func bucket(
        for cursor: GlobalTimelineCursor,
        weeklyBuckets: [GlobalTimelineBucket],
        monthlyBuckets: [GlobalTimelineBucket],
        yearlyBuckets: [GlobalTimelineBucket]
    ) -> GlobalTimelineBucket? {
        let buckets: [GlobalTimelineBucket]

        switch cursor.scale {
        case .week:
            buckets = weeklyBuckets
        case .month:
            buckets = monthlyBuckets
        case .year:
            buckets = yearlyBuckets
        }

        return buckets.first { $0.id == cursor.bucketId }
    }

    private static func bucketStartDate(for cursor: GlobalTimelineCursor, calendar: Calendar) -> Date {
        switch cursor.scale {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: cursor.date)?.start ?? cursor.date
        case .month:
            return calendar.dateInterval(of: .month, for: cursor.date)?.start ?? cursor.date
        case .year:
            return calendar.dateInterval(of: .year, for: cursor.date)?.start ?? cursor.date
        }
    }
}

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
            if visibleZones.isEmpty {
                emptyBarRow
            } else {
                barRow
            }
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
            .disabled(visibleZones.isEmpty)
            .opacity(visibleZones.isEmpty ? 0.4 : 1)
        }
    }

    private var barRow: some View {
        HStack(spacing: 4) {
            ForEach(visibleZones) { zone in
                zoneView(buckets: zone.buckets)
            }
        }
        .frame(height: 24)
    }

    private var emptyBarRow: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
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

    private var visibleZones: [GlobalTimelineHeaderZone] {
        GlobalTimelineHeaderPresentation.visibleZones(
            weeklyBuckets: weeklyBuckets,
            monthlyBuckets: monthlyBuckets,
            yearlyBuckets: yearlyBuckets
        )
    }

    private var currentLabel: String {
        GlobalTimelineHeaderPresentation.currentLabel(
            cursor: cursor,
            weeklyBuckets: weeklyBuckets,
            monthlyBuckets: monthlyBuckets,
            yearlyBuckets: yearlyBuckets
        )
    }
}
