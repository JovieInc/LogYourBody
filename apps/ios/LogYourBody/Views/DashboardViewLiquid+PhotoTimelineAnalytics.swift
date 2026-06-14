import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Photo Timeline Analytics

    var photoTimelineStatsDestination: some View {
        photoTimelineAnalyticsPage
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("photo_timeline_stats_destination")
    }

    var photoTimelineAnalyticsPage: some View {
        ZStack {
            Color.metricCanvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    photoTimelineStatsHeader
                        .padding(.horizontal, 20)

                    photoTimelinePresenceSummary
                        .padding(.horizontal, 20)

                    metricsView
                }
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
    }

    var photoTimelineStatsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body trends")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("Open a metric for chart and history.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.metricTextSecondary)
        }
    }

    var photoTimelinePresenceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline states")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(timelinePresenceValueCount) values")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.metricTextTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(MetricPresence.allCases, id: \.rawValue) { presence in
                    photoTimelinePresenceChip(
                        title: photoTimelinePresenceLabel(for: presence),
                        count: timelinePresenceCounts[presence] ?? 0,
                        color: photoTimelinePresenceColor(for: presence)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("photo_timeline_stats_presence_summary")
    }

    func photoTimelinePresenceChip(
        title: String,
        count: Int,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricTextSecondary)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.055))
        )
        .accessibilityLabel("\(title), \(count) timeline values")
    }
}
