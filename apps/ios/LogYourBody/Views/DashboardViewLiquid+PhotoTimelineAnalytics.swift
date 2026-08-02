import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Photo Timeline Analytics

    var photoTimelineStatsDestination: some View {
        photoTimelineAnalyticsPage
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("photo_timeline_stats_destination")
            .worldClassScreen(.stats)
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

            Text("Four measurements. One direction. Open any metric for source, chart, and history.")
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
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .stroke(theme.colors.border.opacity(JovieTokens.hairlineOpacity), lineWidth: 1)
        }
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
