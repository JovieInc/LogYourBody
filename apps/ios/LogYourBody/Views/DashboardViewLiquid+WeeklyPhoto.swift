import SwiftUI

extension DashboardViewLiquid {
    func weeklyPhotoAttachSheet<Content: View>(on content: Content) -> some View {
        content
            .sheet(isPresented: $isProgressPhotoAttachPresented) {
                ProgressPhotoAttachSheet(
                    targetMetric: progressPhotoAttachTarget,
                    fallbackDate: progressPhotoAttachFallbackDate,
                    photoHistory: WeeklyPhotoCheckInPolicy.history(from: bodyMetrics),
                    previousPhotoURL: weeklyPhotoOutlineURL,
                    onComplete: {
                        await handleProgressPhotoAttachComplete()
                    },
                    onCheckInSaved: { outcome in
                        pendingWeeklyPhotoMoment = outcome.selectedMoment
                        pendingWeeklyCompare = outcome.offersComparison && outcome.originalImageUsable
                    }
                )
                .environmentObject(authManager)
            }
            .onChange(of: isProgressPhotoAttachPresented) { _, presented in
                guard !presented else { return }
                let moment = pendingWeeklyPhotoMoment
                let compare = pendingWeeklyCompare
                pendingWeeklyPhotoMoment = nil
                pendingWeeklyCompare = false
                progressPhotoAttachFallbackOverride = nil
                if let moment {
                    selectClosestMetric(to: moment)
                }
                guard compare, HomeV2Policy.isEnabled(), let pair = homeV2DefaultPair else { return }
                homeV2PhotoRoute = .compare(pair)
                isHomeV2ViewerPresented = true
            }
    }

    var progressPhotoAttachFallbackDate: Date {
        if let progressPhotoAttachFallbackOverride {
            return progressPhotoAttachFallbackOverride
        }
        return currentMetric?.date ?? globalTimelineStore.cursor?.date ?? activeTimelineBucket?.endDate ?? Date()
    }

    /// The newest other diary photo, used only as an optional pose outline.
    var weeklyPhotoOutlineURL: String? {
        let excluded = progressPhotoAttachTarget?.id
        return bodyMetrics
            .filter { PhotoTimelineHUDPolicy.hasUsablePhoto($0) && $0.id != excluded }
            .max { $0.date < $1.date }?
            .photoUrl
    }

    /// Weekly check-in attaches to today, even if the timeline is scrubbed elsewhere.
    func presentWeeklyPhotoCheckIn() {
        progressPhotoAttachFallbackOverride = Date()
        progressPhotoAttachTarget = homeV2DisplayedTodayMetric()
        HapticManager.shared.selection()
        isProgressPhotoAttachPresented = true
    }

    func refreshWeeklyPhotoProvenanceIfNeeded() async {
        guard let userId = authManager.currentUser?.id else { return }
        let changed = await PhotoMetadataService.shared.backfillWeeklyPhotoProvenance(userId: userId)
        guard changed > 0 else { return }
        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: realtimeSyncManager
        )
        refreshGlobalTimelineStore()
    }
}
