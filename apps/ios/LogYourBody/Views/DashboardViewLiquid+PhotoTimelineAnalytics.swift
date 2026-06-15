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
            theme.colors.background.ignoresSafeArea()

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
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    var photoTimelineStatsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body trends")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(theme.colors.text)

            Text("Open a metric for chart and history.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
        }
    }

    var photoTimelinePresenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.colors.text)

                Spacer()

                Text("\(timelinePresenceValueCount) values")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.colors.textTertiary)
            }

            Text(photoTimelinePresenceLegendText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.colors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("photo_timeline_stats_presence_legend")
        }
        .padding(14)
        .systemBGlassSurface(
            cornerRadius: theme.radius.card,
            tint: theme.colors.text,
            tintOpacity: 0.025,
            borderColor: theme.colors.border,
            borderOpacity: 0.85
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
