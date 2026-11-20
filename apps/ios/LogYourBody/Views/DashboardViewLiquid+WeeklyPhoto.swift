import SwiftUI

extension DashboardViewLiquid {
    func weeklyPhotoAttachSheet<Content: View>(on content: Content) -> some View {
        content
            .sheet(isPresented: $isProgressPhotoAttachPresented) {
                if !isDatedTimelineEnabled || datedTimelineIsOwned {
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
                        },
                        presentationOwner: isDatedTimelineEnabled ? datedTimelineOwner : nil
                    )
                    .environmentObject(authManager)
                }
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

    /// The newest other diary photo, used only as an optional pose outline.
    var weeklyPhotoOutlineURL: String? {
        let excluded = progressPhotoAttachTarget?.id
        return bodyMetrics
            .filter { PhotoTimelineHUDPolicy.hasUsablePhoto($0) && $0.id != excluded }
            .max { $0.date < $1.date }?
            .photoUrl
    }

    /// A weekly check-in creates a photo observation, independent of the selected entry.
    func presentWeeklyPhotoCheckIn() {
        if isDatedTimelineEnabled {
            guard datedTimelineIsOwned else { return }
        }
        progressPhotoAttachFallbackOverride = Date()
        progressPhotoAttachTarget = nil
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
