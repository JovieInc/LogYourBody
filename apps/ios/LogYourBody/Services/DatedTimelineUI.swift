import SwiftUI

extension DashboardViewLiquid {
    var isDatedTimelineEnabled: Bool {
        _ = featureGateRefreshToken
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestDatedTimelineFixture") { return true }
        #endif
        return AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: DatedOutcomeStore.featureGate)
    }

    var datedTimelineIsOwned: Bool {
        guard let owner = datedTimelineOwner else { return false }
        return authManager.ownsAccountSession(owner)
    }

    var datedTimelineEntry: DatedTimelineProjector.Entry? {
        guard datedTimelineIsOwned, let metric = currentMetric else { return nil }
        return datedTimelineSnapshot?.entries[metric.id]
    }

    var datedTimelineCanShowHistory: Bool {
        datedTimelineIsOwned && datedTimelineSnapshot?.containsOnlyOwnerRecords == true &&
            (currentMetric == nil || datedTimelineEntry != nil)
    }

    var datedTimelineDirective: some View {
        VStack(alignment: .leading, spacing: 8) {
            if datedTimelineIsOwned, let snapshot = datedTimelineSnapshot {
                if let text = snapshot.outcomeText {
                    Button(text) { openDatedTimelineEditor() }
                        .font(.subheadline)
                        .accessibilityIdentifier("dated_timeline_outcome")
                }
                if datedTimelineLoadFailed {
                    Button("Retry sync") { scheduleDatedTimelineRefresh() }
                        .accessibilityIdentifier("dated_timeline_retry")
                } else {
                    LaunchDirectiveCard(presentation: snapshot.presentation) {
                        performDatedTimelineAction()
                    }
                }
            } else if datedTimelineLoadFailed {
                Button("Retry sync") { scheduleDatedTimelineRefresh() }
                    .accessibilityIdentifier("dated_timeline_retry")
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, JovieTokens.screenInset)
        .sheet(isPresented: $showsDatedTimelineEditor) {
            if let owner = datedTimelineOwner, authManager.ownsAccountSession(owner) {
                LaunchOutcomeEditor(existing: datedTimelineSnapshot?.outcome, errorText: launchOutcomeError) { outcome in
                    Task {
                        do {
                            try await realtimeSyncManager.datedOutcomeStore.saveForPresentation(outcome) {
                                authManager.ownsAccountSession(owner)
                            }
                            guard authManager.ownsAccountSession(owner) else { return }
                            launchOutcomeError = nil
                            showsDatedTimelineEditor = false
                            scheduleDatedTimelineRefresh()
                        } catch {
                            guard authManager.ownsAccountSession(owner) else { return }
                            launchOutcomeError = "That outcome could not be saved. Revise the date or value."
                        }
                    }
                }
            }
        }
    }

    var datedTimelineEmptyState: some View {
        VStack(spacing: 12) {
            Text("No progress photo")
                .font(.headline)
            Button("Add photo") { presentProgressPhotoAttach(for: nil) }
                .accessibilityIdentifier("launch_timeline_add_photo")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch_timeline_surface")
    }

    func openDatedTimelineEditor() {
        guard datedTimelineIsOwned else { return }
        launchOutcomeError = nil
        showsDatedTimelineEditor = true
    }

    func performDatedTimelineAction() {
        guard datedTimelineIsOwned, let snapshot = datedTimelineSnapshot else { return }
        switch snapshot.destination {
        case .editor:
            openDatedTimelineEditor()
        case .measurement:
            presentAddEntrySheet(initialTab: snapshot.baselineTab)
        case .profile:
            isHomeV2SettingsPresented = true
        case .retry:
            realtimeSyncManager.syncAll()
            scheduleDatedTimelineRefresh()
        case .timeline:
            selectedPhotoTimelineRootPage = .timeline
            isHomeChatExpanded = false
        }
    }

    func clearDatedTimelineContext() {
        let hadDatedContext = datedTimelineOwner != nil || isDatedTimelineEnabled
        datedTimelineRefreshTask?.cancel()
        datedTimelineRefreshID = UUID()
        datedTimelineSnapshot = nil
        datedTimelineOwner = nil
        datedTimelineLoadFailed = false
        showsDatedTimelineEditor = false
        guard hadDatedContext else { return }
        launchOutcomeError = nil
        launchHoldNote = nil
        showsLaunchOutcomeEditor = false
        // Dismiss actions bound to the previous account, including interrupted imports.
        showAddEntrySheet = false
        isProgressPhotoAttachPresented = false
        progressPhotoAttachTarget = nil
        isShowingPhotoTimelineMenu = false
        isHomeV2AllPhotosPresented = false
    }

    func scheduleDatedTimelineRefresh(metrics: [BodyMetrics]? = nil) {
        datedTimelineRefreshTask?.cancel()
        let request = UUID()
        datedTimelineRefreshID = request
        guard isDatedTimelineEnabled, let owner = authManager.captureAccountSession() else {
            datedTimelineSnapshot = nil
            datedTimelineOwner = nil
            return
        }
        let metrics = metrics ?? bodyMetrics
        let offline = !realtimeSyncManager.isOnline
        let height = authManager.currentUser?.profile?.height
        // HealthKit does not disclose read denial. Do not reuse another session's
        // authorization prompt result; missing readings always allow manual entry.
        datedTimelineRefreshTask = Task {
            do {
                let outcome = try await realtimeSyncManager.datedOutcomeStore.loadForPresentation {
                    authManager.ownsAccountSession(owner)
                }
                let snapshot = await datedTimelineProjector.project(
                    owner: owner.subject, metrics: metrics,
                    input: LaunchJourney.Input(
                        now: Date(), outcome: outcome?.value, offline: offline
                    ), heightCm: height
                )
                guard !Task.isCancelled, datedTimelineRefreshID == request,
                      authManager.ownsAccountSession(owner) else { return }
                datedTimelineSnapshot = snapshot
                datedTimelineOwner = owner
                datedTimelineLoadFailed = false
            } catch {
                guard !Task.isCancelled, datedTimelineRefreshID == request,
                      authManager.ownsAccountSession(owner) else { return }
                datedTimelineLoadFailed = true
            }
        }
    }
}
