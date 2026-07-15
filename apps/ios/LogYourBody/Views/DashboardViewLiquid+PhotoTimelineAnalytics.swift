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
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    photoTimelineStatsHeader
                        .padding(.horizontal, JovieTokens.screenInset)

                    photoTimelinePresenceSummary
                        .padding(.horizontal, JovieTokens.screenInset)

                    metricsView
                }
                .padding(.top, JovieTokens.itemGap)
                .padding(.bottom, JovieTokens.sectionGap)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    var photoTimelineStatsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Body trends")
                .font(.title.weight(.bold))
                .foregroundColor(theme.colors.text)
                .accessibilityAddTraits(.isHeader)

            Text("Open a metric for chart and history.")
                .font(.body)
                .foregroundColor(theme.colors.textSecondary)
        }
    }

    var photoTimelinePresenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    timelineDataTitle
                    Spacer(minLength: JovieTokens.itemGap)
                    timelineValueCount
                }

                VStack(alignment: .leading, spacing: 4) {
                    timelineDataTitle
                    timelineValueCount
                }
            }

            Text(photoTimelinePresenceLegendText)
                .font(.footnote.weight(.medium))
                .foregroundColor(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("photo_timeline_stats_presence_legend")
        }
        .padding(JovieTokens.compactInset)
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

    private var timelineDataTitle: some View {
        Text("Timeline data")
            .font(.body.weight(.semibold))
            .foregroundColor(theme.colors.text)
    }

    private var timelineValueCount: some View {
        Text("\(timelinePresenceValueCount) values")
            .font(.footnote.weight(.semibold))
            .foregroundColor(theme.colors.textTertiary)
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
