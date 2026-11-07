import SwiftUI

extension DashboardViewLiquid {
    var progressPhotoAttachFallbackDate: Date {
        currentMetric?.date ?? globalTimelineStore.cursor?.date ?? activeTimelineBucket?.endDate ?? Date()
    }

    var progressPhotoAttachMetric: BodyMetrics? {
        if let currentMetric {
            return currentMetric
        }

        let targetDate = progressPhotoAttachFallbackDate
        return bodyMetrics.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(targetDate)) < abs(rhs.date.timeIntervalSince(targetDate))
        }
    }

    func presentProgressPhotoAttach(for metric: BodyMetrics?) {
        if isDatedTimelineEnabled {
            guard datedTimelineIsOwned, metric == nil || metric?.userId == datedTimelineOwner?.subject else { return }
        }
        progressPhotoAttachTarget = metric
        HapticManager.shared.selection()
        isProgressPhotoAttachPresented = true
    }

    @MainActor
    func handleProgressPhotoAttachComplete() async {
        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: realtimeSyncManager
        )
        refreshGlobalTimelineStore()

        if let targetId = progressPhotoAttachTarget?.id,
           let refreshedIndex = bodyMetrics.firstIndex(where: { $0.id == targetId }) {
            selectedIndex = refreshedIndex
            updateAnimatedValues(for: refreshedIndex)
        } else if !bodyMetrics.isEmpty {
            selectedIndex = min(selectedIndex, bodyMetrics.count - 1)
            updateAnimatedValues(for: selectedIndex)
        }
    }

    func selectClosestMetric(to date: Date) {
        PerfSignpost.measure("scrub_select_closest") {
            guard let index = nearestBodyMetricIndex(in: bodyMetrics, to: date) else {
                return
            }

            selectedIndex = index
            updateAnimatedValues(for: index, animate: false)
        }
    }

    func formatHUDDate(_ date: Date) -> String {
        DashboardMetricFormatting.readingDateLabel(effectiveDate: date)
    }
}
