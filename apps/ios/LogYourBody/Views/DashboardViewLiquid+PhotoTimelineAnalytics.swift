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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(timelinePresenceValueCount) values")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.metricTextTertiary)
            }

            Text(photoTimelinePresenceLegendText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricTextSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("photo_timeline_stats_presence_legend")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline data. \(photoTimelinePresenceLegendText). \(timelinePresenceValueCount) values.")
        .accessibilityIdentifier("photo_timeline_stats_presence_summary")
    }

    var photoTimelinePresenceLegendText: String {
        MetricPresence.allCases.map { presence in
            let label = photoTimelinePresenceLabel(for: presence)
            let count = timelinePresenceCounts[presence] ?? 0
            return "\(label) \(count)"
        }
        .joined(separator: " • ")
    }
}
