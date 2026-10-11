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
}
