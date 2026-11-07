import SwiftUI
import Charts
import CoreData

extension DashboardViewLiquid {
    func scheduleDashboardDerivedStateRefresh(
        rebuildDailyMetricsLookup: Bool = false,
        animatedIndex: Int? = nil
    ) {
        // Scrub hot path: index-only updates must NOT rebuild weekly/monthly/yearly
        // global timeline buckets (that is multi-ms main-thread work and causes jank).
        if let animatedIndex, !rebuildDailyMetricsLookup {
            Task { @MainActor in
                guard !viewModel.bodyMetrics.isEmpty else { return }
                PerfSignpost.measure("dashboard_scrub_refresh") {
                    updateAnimatedValues(for: animatedIndex, animate: false)
                }
            }
            return
        }

        Task { @MainActor in
            await Task.yield()

            PerfSignpost.measure("dashboard_derived_refresh") {
                if rebuildDailyMetricsLookup {
                    rebuildDailyMetricsLookupCache()
                }

                refreshGlobalTimelineStore()

                if let animatedIndex, !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: animatedIndex, animate: true)
                }
            }
        }
    }

    func refreshGlobalTimelineStore() {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        globalTimelineStore.updateMetrics(
            bodyMetrics,
            dailyMetrics: recentDailyMetrics,
            heightInches: heightInches
        )
    }
}
