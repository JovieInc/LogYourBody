import SwiftUI

/// The first screen asks where the person's numbers already live. A DEXA or
/// InBody report is the primary path for existing body-composition data;
/// Apple Health and typing the numbers are the alternatives.
struct BodyScoreHookView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSelectingScan = false
    @State private var selectedScan: DexaPDFFileSelection?
    @State private var scanPickerError: String?

    static let scanImportFixtureArgument = "-lybUITestOnboardingScanImportFixture"

    private var offersScanImport: Bool {
        viewModel.entryContext == .authenticated
    }

    var body: some View {
        OnboardingPageTemplate(
            title: LaunchPromiseCopy.nativeHeadline,
            subtitle: LaunchPromiseCopy.explanation,
            showsBackButton: false,
            progress: viewModel.progress(for: .hook),
            screen: .bodyScoreIntro
        ) {
            VStack(spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    BodyScoreContourField()
                        .frame(height: 170)
                }

                if let scanPickerError {
                    Text(scanPickerError)
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appError)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body_score_onboarding_scan_error")
                }

                if dynamicTypeSize.isAccessibilitySize {
                    alternativeActions
                }
            }
        } footer: {
            VStack(spacing: 12) {
                primaryAction

                if !dynamicTypeSize.isAccessibilitySize {
                    alternativeActions
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("body_score_onboarding_hook_footer")
        }
        .fileImporter(
            isPresented: $isSelectingScan,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedScan = DexaPDFFileSelection(url: url)
                }
            case .failure:
                scanPickerError = "Choose a readable DEXA or InBody PDF and try again."
            }
        }
        .sheet(item: $selectedScan) { selection in
            DexaPDFImportSheet(fileURL: selection.url) { scans in
                viewModel.applyImportedScans(scans)
            }
            .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if offersScanImport {
            Button(action: startScanImport) {
                Label("Import a DEXA or InBody scan", systemImage: "doc.text.viewfinder")
            }
            .accessibilityIdentifier("body_score_onboarding_import_scan_button")
            .buttonStyle(OnboardingPrimaryButtonStyle())
        } else {
            Button {
                viewModel.chooseHealthPath()
            } label: {
                Label("Use Apple Health", systemImage: "heart.fill")
            }
            .accessibilityIdentifier("body_score_onboarding_use_health_button")
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }

    private var alternativeActions: some View {
        VStack(spacing: 12) {
            if offersScanImport {
                Button {
                    viewModel.chooseHealthPath()
                } label: {
                    Label("Use Apple Health", systemImage: "heart.fill")
                }
                .accessibilityIdentifier("body_score_onboarding_use_health_button")
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            OnboardingTextButton(title: "Enter my numbers") {
                viewModel.chooseManualPath()
            }
            .accessibilityIdentifier("body_score_onboarding_start_button")

            if viewModel.entryContext == .preAuth {
                OnboardingTextButton(title: "I already have an account") {
                    dismiss()
                }
            }
        }
    }

    private func startScanImport() {
        scanPickerError = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.scanImportFixtureArgument) {
            viewModel.applyImportedScans(Self.fixtureScans)
            return
        }
        #endif
        isSelectingScan = true
    }

    #if DEBUG
    /// Two BodySpec-style scans, so UI tests can cover the "what changed" reveal
    /// without the Files picker or the parser endpoint.
    static let fixtureScans: [DexaPDFScan] = [
        DexaPDFScan(
            date: "2026-06-02", weight: 186, weightUnit: "lbs", bodyFatPercentage: 22,
            muscleMass: nil, boneMass: nil, source: "BodySpec"
        ),
        DexaPDFScan(
            date: "2026-09-01", weight: 180, weightUnit: "lbs", bodyFatPercentage: 19,
            muscleMass: nil, boneMass: nil, source: "BodySpec"
        )
    ]
    #endif
}

/// The gated first run collects the dated constraint before any measurement or
/// optional permission. A manual entry is enough to continue neutral tracking.
struct DatedOutcomeLaunchView: View {
    let auth: AuthManager
    let owner: AuthManager.ProfileSessionOwnership
    let store: DatedOutcomeStore
    var onCompleted: () -> Void
    @State private var showsEditor = false
    @State private var showsMeasurement = false
    @State private var showsSavedOutcome = false
    @State private var model: DatedOutcomeEditorModel
    @State private var baselineSnapshot: DatedTimelineProjector.Snapshot?
    private let projector = DatedTimelineProjector()

    init(
        auth: AuthManager, owner: AuthManager.ProfileSessionOwnership, store: DatedOutcomeStore,
        onCompleted: @escaping () -> Void
    ) {
        self.auth = auth
        self.owner = owner
        self.store = store
        self.onCompleted = onCompleted
        _model = State(initialValue: DatedOutcomeEditorModel(store: store) { auth.ownsAccountSession(owner) })
    }

    var body: some View {
        OnboardingPageTemplate(
            title: showsSavedOutcome ? "Your outcome and date" : LaunchPromiseCopy.datedOutcomePromise,
            subtitle: LaunchPromiseCopy.framing,
            showsBackButton: showsSavedOutcome,
            onBack: { showsSavedOutcome = false },
            screen: .bodyScoreIntro,
            content: {
                if showsSavedOutcome, let saved = model.snapshot {
                    Text(baselineSnapshot?.outcomeText ?? saved.value.outcomeDate)
                        .accessibilityIdentifier("dated_launch_saved_outcome")
                    if let decision = baselineSnapshot?.presentation { Text(decision.action.detail) }
                    if model.hasPending {
                        Text("Saved on this device. Waiting to sync.")
                            .accessibilityIdentifier("dated_outcome_pending")
                    }
                }
                if let error = model.errorText { Text(error) }
            }, footer: {
                VStack(spacing: 12) {
                    Button(nextActionTitle, action: performNextAction)
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .accessibilityIdentifier("dated_launch_continue")
                    if showsSavedOutcome {
                        if baselineSnapshot?.destination == .editor {
                            OnboardingTextButton(title: "Enter one measurement") { showsMeasurement = true }
                        } else {
                            OnboardingTextButton(title: "Edit outcome and date") { showsEditor = true }
                        }
                        OnboardingTextButton(title: "Continue with tracking", action: complete)
                    }
                }
            }
        )
        .sheet(isPresented: $showsEditor) {
            DatedOutcomeEditorHost(store: store, auth: auth, owner: owner) {
                showsEditor = false
                Task { await refresh() }
            }
        }
        .sheet(isPresented: $showsMeasurement) {
            AddEntrySheet(
                isPresented: $showsMeasurement,
                initialTab: baselineSnapshot?.baselineTab ?? 0,
                onWeightSaved: { _ in complete() },
                onBodyFatSaved: { _ in complete() },
                presentationOwner: owner
            )
            .environmentObject(auth)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        await model.load(refresh: true)
        guard auth.ownsAccountSession(owner) else { return }
        let metrics = await CoreDataManager.shared.fetchVisibleBodyMetrics(for: owner.subject)
        let snapshot = await projector.project(
            owner: owner.subject, metrics: metrics,
            input: .init(
                now: Date(), outcome: model.snapshot?.value, offline: !RealtimeSyncManager.shared.isOnline,
                enforcesDatedOutcomeDecision: true
            ), heightCm: auth.currentUser?.profile?.height
        )
        guard !Task.isCancelled, auth.ownsAccountSession(owner) else { return }
        baselineSnapshot = snapshot
        showsSavedOutcome = model.snapshot != nil
    }

    private func performNextAction() {
        guard auth.ownsAccountSession(owner) else { return }
        guard showsSavedOutcome else { showsEditor = true; return }
        if store.syncIssue == .conflict { showsEditor = true; return }
        if store.syncIssue == .retry {
            RealtimeSyncManager.shared.syncAll()
            Task { await refresh() }
            return
        }
        switch baselineSnapshot?.destination {
        case .editor: showsEditor = true
        case .retry:
            RealtimeSyncManager.shared.syncAll()
            Task { await refresh() }
        case .measurement, .profile, .timeline, .none: showsMeasurement = true
        }
    }

    private var nextActionTitle: String {
        guard showsSavedOutcome else { return "Choose an outcome and date" }
        if store.syncIssue == .conflict { return "Review account outcome" }
        if store.syncIssue == .retry { return "Retry outcome sync" }
        return baselineSnapshot?.presentation.action.title ?? "Enter one measurement"
    }

    private func complete() {
        guard auth.ownsAccountSession(owner) else { return }
        onCompleted()
    }
}

private struct BodyScoreContourField: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
            let maximum = min(size.width, size.height) * 0.82

            for ring in 0..<9 {
                let progress = CGFloat(ring) / 8
                let width = maximum * (0.2 + progress * 0.8)
                let height = width * (0.58 + progress * 0.18)
                let rect = CGRect(
                    x: center.x - width / 2,
                    y: center.y - height / 2,
                    width: width,
                    height: height
                )
                let color = ring.isMultiple(of: 2) ? theme.colors.info : theme.colors.accentPink
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.14 + Double(8 - ring) * 0.016)),
                    lineWidth: ring == 0 ? 1.5 : 1
                )
            }
        }
        .background {
            RadialGradient(
                colors: [theme.colors.info.opacity(JovieTokens.ambientAccentOpacity), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 150
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BodyScoreHookView(viewModel: OnboardingFlowViewModel())
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
