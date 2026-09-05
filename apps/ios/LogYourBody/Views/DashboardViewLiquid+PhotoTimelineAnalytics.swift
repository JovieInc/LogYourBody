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

                    if isGlp1WeeklyCheckInEnabled {
                        hudGlp1WeeklyCheckIn
                            .padding(.horizontal, JovieTokens.screenInset)
                    }

                    if isPhaseInsightEnabled {
                        hudPhaseInsight
                            .padding(.horizontal, JovieTokens.screenInset)
                    }
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
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
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

            photoTimelinePresenceChipGrid
        }
        .padding(JovieTokens.compactInset)
        .dashboardContentSurface(cornerRadius: theme.radius.card, border: theme.colors.border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline data. \(photoTimelinePresenceLegendText). \(timelinePresenceValueCount) values.")
        .accessibilityIdentifier("photo_timeline_stats_presence_summary")
    }

    private var photoTimelinePresenceChipGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(MetricPresence.allCases, id: \.self) { presence in
                HStack(spacing: 8) {
                    Circle()
                        .fill(photoTimelinePresenceColor(for: presence))
                        .frame(width: 8, height: 8)

                    Text(photoTimelinePresenceLabel(for: presence))
                        .font(.footnote.weight(.medium))
                        .foregroundColor(theme.colors.text)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text("\(timelinePresenceCounts[presence] ?? 0)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(theme.colors.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    theme.colors.backgroundSecondary,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .accessibilityIdentifier("photo_timeline_stats_presence_legend")
    }

    func photoTimelinePresenceColor(for presence: MetricPresence) -> Color {
        switch presence {
        case .present:
            return theme.colors.primary
        case .estimated:
            return theme.colors.accentOrange
        case .interpolated:
            return theme.colors.accentPink
        case .lastKnown:
            return theme.colors.accentViolet
        case .missing:
            return theme.colors.textTertiary
        }
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
