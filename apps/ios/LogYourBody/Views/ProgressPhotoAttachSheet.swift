import SwiftUI
import UIKit

enum ProgressPhotoAttachStatus: Equatable {
    case empty
    case ready
    case permissionDenied
    case processing
    case success
    case failed(String)
}

struct ProgressPhotoAttachPolicy {
    static func title(targetHasPhoto: Bool) -> String {
        targetHasPhoto ? "Update progress photo" : "Add progress photo"
    }

    static func targetCopy(hasTargetMetric: Bool, targetDate: Date) -> String {
        let dateText = FormatterCache.mediumDateFormatter.string(from: targetDate)
        return hasTargetMetric ? "Attaches to \(dateText)" : "Adds to \(dateText)"
    }

    static func statusTitle(for status: ProgressPhotoAttachStatus) -> String {
        switch status {
        case .empty:
            return "Choose a photo"
        case .ready:
            return "Ready to attach"
        case .permissionDenied:
            return "Permission needed"
        case .processing:
            return "Processing photo"
        case .success:
            return "Photo added"
        case .failed:
            return "Photo failed"
        }
    }

    static func statusMessage(for status: ProgressPhotoAttachStatus) -> String {
        switch status {
        case .empty:
            return "Take one photo or choose one from your library."
        case .ready:
            return "Review the photo, then attach it to this timeline point."
        case .permissionDenied:
            return "Enable camera or photo access in Settings, then try again."
        case .processing:
            return "Keep this sheet open while the photo is prepared and uploaded."
        case .success:
            return "The photo is now part of your body-composition timeline."
        case .failed(let message):
            return message.isEmpty ? "Try again with another photo." : message
        }
    }

    static func canUseCamera(isAvailable: Bool, authorizationStatus: AppAuthorizationState) -> Bool {
        guard isAvailable else { return false }
        switch authorizationStatus {
        case .authorized, .notDetermined:
            return true
        case .denied, .restricted, .unknown:
            return false
        }
    }

    static func isBusy(status: ProgressPhotoAttachStatus) -> Bool {
        if case .processing = status {
            return true
        }
        return false
    }

    static func canDismiss(status: ProgressPhotoAttachStatus) -> Bool {
        NativeSheetPresentationPolicy.canDismissProgressPhotoAttach(status: status)
    }
}

struct ProgressPhotoAttachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var uploadManager = PhotoUploadManager.shared
    private let photoLibrary: PhotoLibraryManaging = LivePhotoLibraryAdapter.shared
    private let cameraAuthorizer: CameraAuthorizing = LiveCameraAuthorizationAdapter.shared

    let targetMetric: BodyMetrics?
    let fallbackDate: Date
    var photoHistory: [WeeklyPhotoProvenance] = []
    var previousPhotoURL: String?
    let onComplete: () async -> Void
    var onCheckInSaved: (WeeklyPhotoSaveOutcome) -> Void = { _ in }

    @State private var selectedImage: UIImage?
    @State private var selectedOriginalData: Data?
    @State private var selectedImageDate: Date?
    @State private var chosenPhotoDate: Date?
    @State private var captureViewpoint = "unspecified"
    @State private var captureMirror = "unknown"
    @State private var captureSource = "library"
    @State private var submissionId = UUID().uuidString
    @State private var captureStartedAt: Date?
    @State private var didFinishAttempt = false
    @State private var attachStatus: ProgressPhotoAttachStatus = .empty
    @State private var isCameraPresented = false
    @State private var cameraSessionStarted = false
    @State private var photoSelectionLoadID = UUID()
    @State private var sheetDetent = NativeSheetPresentationPolicy.initialDetent(for: .progressPhotoAttach)
    @AccessibilityFocusState private var isStatusFocused: Bool

    private var targetDate: Date {
        chosenPhotoDate ?? selectedImageDate ?? targetMetric?.date ?? fallbackDate
    }

    private var isBusy: Bool {
        ProgressPhotoAttachPolicy.isBusy(status: attachStatus)
    }

    private var isSuccess: Bool {
        if case .success = attachStatus {
            return true
        }
        return false
    }

    private var canAttach: Bool {
        selectedImage != nil && !isBusy && !isSuccess
    }

    #if DEBUG
    private var usesProgressPhotoAttachFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-lybUITestProgressPhotoAttachFixture")
    }
    #endif

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                        header
                        previewPane(height: previewHeight(for: geometry.size.height))
                        statusPane
                        actionPane
                    }
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.top, JovieTokens.itemGap)
                    .padding(.bottom, JovieTokens.itemGap)
                }
                // The navigation-bar Cancel accessibility frame stays 36 points tall.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isBusy)
                        .accessibilityIdentifier("progress_photo_attach_cancel_button")

                        attachButton
                    }
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.vertical, JovieTokens.itemGap)
                }
            }
            .navigationTitle("Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    photoSourceMenu
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented, onDismiss: {
                if cameraSessionStarted, selectedImage == nil {
                    finishAbandoned(outcome: "interrupted", source: "camera")
                }
                cameraSessionStarted = false
            }, content: {
                CameraView(
                    hasPreviousPhoto: previousPhotoURL != nil,
                    previousPhotoURL: previousPhotoURL,
                    onCaptureStarted: { source in
                        noteCaptureStarted(source)
                    },
                    onCaptureContext: { viewpoint, mirror in
                        captureViewpoint = viewpoint
                        captureMirror = mirror
                    },
                    onImageCaptured: { image in
                        Task { @MainActor in
                            handleCameraImage(image)
                            await Task.yield()
                            attachSelectedPhoto()
                        }
                    }
                )
            })
            .onDisappear {
                if !didFinishAttempt, attachStatus != .success, attachStatus != .processing {
                    finishAbandoned(outcome: "cancelled", source: captureSource)
                }
            }
            .interactiveDismissDisabled(!ProgressPhotoAttachPolicy.canDismiss(status: attachStatus))
            .onAppear {
                updateInitialPermissionState()
            }
            .onChange(of: attachStatus) { status in
                announceStatusChange(status)
            }
        }
        .nativeSheetChrome(for: .progressPhotoAttach, detent: $sheetDetent)
        .accessibilityIdentifier("progress_photo_attach_sheet")
        .worldClassScreen(.addProgressPhoto)
    }

    private var photoSourceMenu: some View {
        Menu {
            Button("Take Photo", systemImage: "camera.fill") {
                startCameraCapture()
            }
            .disabled(!cameraAuthorizer.isCameraAvailable)

            #if DEBUG
            if usesProgressPhotoAttachFixture {
                Button("Use Fixture Photo", systemImage: "testtube.2") {
                    selectFixturePhoto()
                }
            }
            #endif
        } label: {
            Label("Add Photo", systemImage: "plus")
        }
        .disabled(isBusy)
        .accessibilityLabel("Add progress photo")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ProgressPhotoAttachPolicy.title(targetHasPhoto: PhotoTimelineHUDPolicy.hasUsablePhoto(targetMetric)))
                .font(theme.typography.displaySmall)
                .foregroundColor(theme.colors.text)

            Text(
                ProgressPhotoAttachPolicy.targetCopy(
                    hasTargetMetric: targetMetric != nil,
                    targetDate: targetDate
                )
            )
            .font(theme.typography.bodySmall)
            .foregroundColor(theme.colors.textSecondary)
        }
    }

    private func previewPane(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                .fill(theme.colors.surface)
                .frame(height: height)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                            .stroke(theme.colors.border, lineWidth: 1)
                    )
                    .accessibilityLabel("Selected progress photo preview")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .foregroundColor(theme.colors.textSecondary)

                    Text("No photo selected")
                        .font(theme.typography.labelLarge)
                        .foregroundColor(theme.colors.textSecondary)
                }
                .accessibilityLabel("No photo selected")
            }

            if isBusy {
                processingOverlay
            }
        }
        .accessibilityIdentifier("progress_photo_attach_preview")
    }

    private var processingOverlay: some View {
        VStack(spacing: 8) {
            ProgressView(value: uploadManager.uploadProgress > 0 ? uploadManager.uploadProgress : nil)
                .tint(theme.colors.text)
                .frame(width: 120)

            Text(uploadProgressText)
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.text)
        }
        .padding(theme.spacing.md)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .fill(Color.black.opacity(0.58))
        )
        .accessibilityIdentifier("progress_photo_attach_processing")
    }

    private var uploadProgressText: String {
        if uploadManager.uploadProgress > 0 {
            return "\(Int(uploadManager.uploadProgress * 100))% uploaded"
        }
        return "Preparing photo"
    }

    private var statusPane: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(statusColor)
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .background(Circle().fill(statusColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(ProgressPhotoAttachPolicy.statusTitle(for: attachStatus))
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)

                Text(ProgressPhotoAttachPolicy.statusMessage(for: attachStatus))
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if selectedImage != nil, !isBusy, !isSuccess {
                    DatePicker(
                        "Photo date",
                        selection: Binding(
                            get: { chosenPhotoDate ?? selectedImageDate ?? targetDate },
                            set: { chosenPhotoDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .font(theme.typography.bodySmall)
                    .accessibilityIdentifier("weekly_photo_date")
                }

                if case .permissionDenied = attachStatus {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.text)
                    .jovieTouchTarget()
                    .accessibilityHint("Opens iPhone Settings to allow camera or photo access")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(theme.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .fill(theme.colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityFocused($isStatusFocused)
        .accessibilityIdentifier("progress_photo_attach_status")
    }

    private var statusIcon: String {
        switch attachStatus {
        case .empty:
            return "photo"
        case .ready:
            return "checkmark.circle.fill"
        case .permissionDenied:
            return "lock.fill"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch attachStatus {
        case .empty:
            return theme.colors.textSecondary
        case .ready:
            return theme.colors.info
        case .permissionDenied, .failed:
            return theme.colors.error
        case .processing:
            return theme.colors.info
        case .success:
            return theme.colors.success
        }
    }

    private var actionPane: some View {
        VStack(spacing: 12) {
            AppPhotosPicker(maxSelectionCount: 1) { assets in
                await MainActor.run {
                    guard let asset = assets.first else {
                        finishAbandoned(outcome: "cancelled", source: "library")
                        return
                    }
                    noteCaptureStarted("library")
                    loadSelectedPhoto(asset)
                }
            } label: {
                Label("Choose from Library", systemImage: "photo.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(isBusy)
            .accessibilityIdentifier("progress_photo_attach_library_button")

            Button {
                startCameraCapture()
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(isBusy || !cameraAuthorizer.isCameraAvailable)
            .accessibilityIdentifier("progress_photo_attach_camera_button")
            .accessibilityHint(cameraSubtitle)

            if !cameraAuthorizer.isCameraAvailable {
                Text("Camera capture is unavailable in Simulator. Choose from Library for simulator validation.")
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            if usesProgressPhotoAttachFixture {
                Button {
                    selectFixturePhoto()
                } label: {
                    Label("Use Fixture Photo", systemImage: "testtube.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(isBusy)
                .accessibilityIdentifier("progress_photo_attach_fixture_button")
            }
            #endif
        }
    }

    private var cameraSubtitle: String {
        cameraAuthorizer.isCameraAvailable
            ? "Use the device camera"
            : "Unavailable in Simulator"
    }

    private var attachButton: some View {
        Button {
            attachSelectedPhoto()
        } label: {
            if isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if isSuccess {
                Label("Close", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Label("Attach Photo", systemImage: "paperclip")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled((!canAttach && !isSuccess) || isBusy)
        .accessibilityLabel(isSuccess ? "Close progress photo" : "Attach progress photo")
        .accessibilityHint(canAttach ? "Attaches the selected photo to this timeline point" : "Choose a photo before attaching")
        .accessibilityIdentifier("progress_photo_attach_submit_button")
    }

    private func previewHeight(for availableHeight: CGFloat) -> CGFloat {
        min(260, max(184, availableHeight * 0.30))
    }

    private func announceStatusChange(_ status: ProgressPhotoAttachStatus) {
        let message = "\(ProgressPhotoAttachPolicy.statusTitle(for: status)). \(ProgressPhotoAttachPolicy.statusMessage(for: status))"
        UIAccessibility.post(notification: .announcement, argument: message)
        isStatusFocused = true
    }

    private func updateInitialPermissionState() {
        switch photoLibrary.weeklyLibraryAccess() {
        case .denied, .restricted:
            attachStatus = .permissionDenied
            finishAbandoned(outcome: "permission_denied", source: "library")
        case .limited, .authorized, .notDetermined, .unknown:
            break
        }
    }

    private func noteCaptureStarted(_ source: String) {
        captureSource = source
        captureStartedAt = Date()
        didFinishAttempt = false
        let access = photoLibrary.weeklyLibraryAccess()
        let accessName: String
        switch access {
        case .limited: accessName = "limited"
        case .authorized: accessName = "authorized"
        default: accessName = "unknown"
        }
        WeeklyPhotoCheckInTelemetry.emit([
            WeeklyPhotoCheckInPolicy.captureStartedMetric(
                source: source,
                access: accessName,
                history: photoHistory
            )
        ])
    }

    private func finishAbandoned(outcome: String, source: String) {
        guard !didFinishAttempt else { return }
        didFinishAttempt = true
        WeeklyPhotoCheckInTelemetry.emit([
            WeeklyPhotoCheckInPolicy.failureMetric(source: source, outcome: outcome)
        ])
    }

    private func loadSelectedPhoto(_ asset: AppPhotoAsset?) {
        let loadID = UUID()
        photoSelectionLoadID = loadID

        guard let asset else {
            selectedImage = nil
            selectedOriginalData = nil
            selectedImageDate = nil
            chosenPhotoDate = nil
            attachStatus = .empty
            return
        }

        attachStatus = .processing
        guard photoSelectionLoadID == loadID else { return }
        submissionId = UUID().uuidString
        captureSource = "library"
        captureViewpoint = "unspecified"
        captureMirror = "unknown"
        selectedImage = asset.image
        selectedOriginalData = asset.data
        let facts = PhotoMetadataService.shared.weeklyPhotoFacts(from: asset.data)
        selectedImageDate = facts.capturedAt
        chosenPhotoDate = nil
        attachStatus = .ready
    }

    private func startCameraCapture() {
        #if DEBUG
        if usesProgressPhotoAttachFixture {
            isCameraPresented = true
            return
        }
        #endif
        guard cameraAuthorizer.isCameraAvailable else {
            attachStatus = .failed("Camera is not available in Simulator. Choose from Library instead.")
            return
        }

        switch cameraAuthorizer.authorizationStatus() {
        case .authorized:
            cameraSessionStarted = true
            noteCaptureStarted("camera")
            isCameraPresented = true
        case .notDetermined:
            attachStatus = .processing
            Task {
                let granted = await cameraAuthorizer.requestAccess()
                await MainActor.run {
                    if granted {
                        cameraSessionStarted = true
                        noteCaptureStarted("camera")
                        attachStatus = .empty
                    } else {
                        attachStatus = .permissionDenied
                        finishAbandoned(outcome: "permission_denied", source: "camera")
                    }
                    isCameraPresented = granted
                }
            }
        case .denied, .restricted, .unknown:
            attachStatus = .permissionDenied
            finishAbandoned(outcome: "permission_denied", source: "camera")
        }
    }

    private func handleCameraImage(_ image: UIImage) {
        photoSelectionLoadID = UUID()
        submissionId = UUID().uuidString
        captureSource = "camera"
        selectedImage = image
        selectedOriginalData = nil
        selectedImageDate = nil
        chosenPhotoDate = nil
        cameraSessionStarted = false
        attachStatus = .ready
    }

    private func attachSelectedPhoto() {
        if isSuccess {
            dismiss()
            return
        }

        guard let selectedImage else {
            attachStatus = .empty
            finishAbandoned(outcome: "empty", source: captureSource)
            return
        }

        guard let ownership = authManager.captureAccountSession(),
              authManager.ownsAccountSession(ownership) else {
            attachStatus = .failed("Sign in again to upload photos.")
            return
        }
        let userId = ownership.subject
        let writeAdmission: CoreDataManager.WriteAdmission = {
            guard authManager.ownsAccountSession(ownership) else {
                throw PhotoUploadManager.PhotoError.notAuthenticated
            }
        }
        let image = selectedImage
        let libraryBytes = selectedOriginalData
        let submission = submissionId
        let source = captureSource
        let viewpoint = captureViewpoint
        let mirror = captureMirror
        let capturedAt = selectedImageDate
        let effective = targetDate
        let userCorrected = chosenPhotoDate.map {
            !Calendar.current.isDate($0, inSameDayAs: selectedImageDate ?? targetMetric?.date ?? fallbackDate)
        } ?? false
        let history = photoHistory
        let started = captureStartedAt ?? Date()
        let access = photoLibrary.weeklyLibraryAccess()

        attachStatus = .processing

        Task {
            let preparedResult = await Task.detached(priority: .userInitiated) {
                WeeklyPhotoAttachPreparation.make(
                    library: libraryBytes, image: image, submissionId: submission
                )
            }.value
            let prepared: WeeklyPhotoAttachPreparation
            switch preparedResult {
            case .ready(let value):
                prepared = value
            case .empty:
                finishAbandoned(outcome: "empty", source: source)
                attachStatus = .failed("Choose a photo with image data.")
                return
            case .unavailable:
                finishAbandoned(outcome: "offline", source: source)
                attachStatus = .failed("The photo could not be saved on this device.")
                return
            }

            var placeholderMetricId: String?
            func makeDraft(uploaded: Bool) -> WeeklyPhotoDraft {
                WeeklyPhotoDraft(
                    submissionId: submission,
                    originalBytes: prepared.bytes,
                    contentType: "unknown",
                    capturedAt: capturedAt,
                    timeZone: TimeZone.current,
                    effectiveAt: effective,
                    dateWasCorrected: userCorrected,
                    importedAt: Date(),
                    exifOrientation: prepared.orientation,
                    mirror: mirror,
                    viewpoint: viewpoint,
                    importSource: source == "camera" ? "camera" : "library",
                    fitSupportsGeometry: false,
                    isPartialOrOccluded: false,
                    libraryAccess: access,
                    persisted: true,
                    uploaded: uploaded,
                    localFileName: prepared.fileURL.lastPathComponent
                )
            }
            let draftBase = makeDraft(uploaded: false)
            if history.contains(where: { $0.submissionId == submission }) {
                let replay = WeeklyPhotoCheckInPolicy.resolve(
                    draftBase, history: history, elapsed: Date().timeIntervalSince(started)
                )
                await finishCheckIn(replay, ownership: ownership)
                return
            }

            do {
                try writeAdmission()
                let metricsResult = try await targetMetrics(
                    userId: userId, diaryDate: effective, writeAdmission: writeAdmission
                )
                try writeAdmission()
                let metrics = metricsResult.metrics
                placeholderMetricId = metrics.id

                #if DEBUG
                if usesProgressPhotoAttachFixture {
                    try await attachFixturePhoto(image: image, to: metrics, userId: userId)
                    try writeAdmission()
                    await onComplete()
                    try writeAdmission()
                    didFinishAttempt = true
                    attachStatus = .success
                    HapticManager.shared.successAction()
                    return
                }
                #endif

                var uploaded = true
                do {
                    _ = try await PhotoUploadManager.shared.uploadProgressPhoto(for: metrics, image: image)
                } catch {
                    guard WeeklyPhotoCheckInPolicy.isRetainedOffline(error) else { throw error }
                    uploaded = false
                    let linked = try await PhotoMetadataService.shared.commitWeeklyPhoto(
                        id: metrics.id,
                        userId: userId,
                        provenance: weeklyProvenance(
                            draftBase, uploaded: false, history: history, started: started
                        ),
                        localDisplayURL: prepared.fileURL.absoluteString,
                        writeAdmission: writeAdmission
                    )
                    guard linked else { throw error }
                }

                if uploaded {
                    _ = try await PhotoMetadataService.shared.commitWeeklyPhoto(
                        id: metrics.id,
                        userId: userId,
                        provenance: weeklyProvenance(
                            draftBase, uploaded: true, history: history, started: started
                        ),
                        localDisplayURL: nil,
                        writeAdmission: writeAdmission
                    )
                }
                let attempt = WeeklyPhotoCheckInPolicy.resolve(
                    makeDraft(uploaded: uploaded),
                    history: history,
                    elapsed: Date().timeIntervalSince(started)
                )
                await finishCheckIn(attempt, ownership: ownership)
            } catch {
                guard authManager.ownsAccountSession(ownership) else { return }
                didFinishAttempt = true
                attachStatus = .failed(error.localizedDescription)
                if let placeholderMetricId {
                    _ = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
                        id: placeholderMetricId,
                        userId: userId,
                        writeAdmission: writeAdmission
                    )
                }
            }
        }
    }

    private func weeklyProvenance(
        _ draft: WeeklyPhotoDraft,
        uploaded: Bool,
        history: [WeeklyPhotoProvenance],
        started: Date
    ) -> WeeklyPhotoProvenance {
        var next = draft
        next.uploaded = uploaded
        next.persisted = true
        let attempt = WeeklyPhotoCheckInPolicy.resolve(
            next, history: history, elapsed: Date().timeIntervalSince(started)
        )
        if let provenance = attempt.outcome?.provenance { return provenance }
        return WeeklyPhotoProvenance(
            submissionId: draft.submissionId,
            originalSHA256: WeeklyPhotoCheckInPolicy.sha256Hex(draft.originalBytes),
            originalByteCount: draft.originalBytes.count,
            contentType: draft.contentType,
            capturedAt: draft.capturedAt,
            timeZoneIdentifier: draft.timeZone.identifier,
            effectiveAt: draft.effectiveAt,
            dateWasCorrected: draft.dateWasCorrected,
            importedAt: draft.importedAt,
            exifOrientation: draft.exifOrientation,
            mirror: draft.mirror,
            viewpoint: draft.viewpoint,
            importSource: draft.importSource,
            isBackfill: false,
            isDuplicate: false,
            fitSupportsGeometry: draft.fitSupportsGeometry,
            isPartialOrOccluded: draft.isPartialOrOccluded,
            countsTowardHabit: false,
            localFileName: draft.localFileName
        )
    }

    private func finishCheckIn(
        _ attempt: WeeklyPhotoCheckInPolicy.Attempt,
        ownership: AuthManager.ProfileSessionOwnership
    ) async {
        guard authManager.ownsAccountSession(ownership) else { return }
        didFinishAttempt = true
        WeeklyPhotoCheckInTelemetry.emit(attempt.metrics)
        guard let outcome = attempt.outcome else {
            attachStatus = .failed("The photo could not be saved.")
            return
        }
        await onComplete()
        onCheckInSaved(outcome)
        attachStatus = .success
        HapticManager.shared.successAction()
        dismiss()
    }

    #if DEBUG
    private func selectFixturePhoto() {
        photoSelectionLoadID = UUID()
        selectedImage = makeFixtureProgressPhoto()
        selectedImageDate = targetDate
        attachStatus = .ready
    }

    private func makeFixtureProgressPhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1_200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            context.cgContext.setFillColor(CGColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1))
            context.cgContext.fillEllipse(in: CGRect(x: 330, y: 170, width: 240, height: 240))

            context.cgContext.setFillColor(CGColor(red: 0.26, green: 0.27, blue: 0.30, alpha: 1))
            let bodyPath = UIBezierPath(
                roundedRect: CGRect(x: 250, y: 430, width: 400, height: 570),
                cornerRadius: 172
            )
            context.cgContext.addPath(bodyPath.cgPath)
            context.cgContext.fillPath()

            context.cgContext.setStrokeColor(CGColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 0.18))
            context.cgContext.setLineWidth(10)
            context.cgContext.move(to: CGPoint(x: 230, y: 1_050))
            context.cgContext.addLine(to: CGPoint(x: 670, y: 1_050))
            context.cgContext.strokePath()
        }
    }

    private func attachFixturePhoto(
        image: UIImage,
        to metrics: BodyMetrics,
        userId: String
    ) async throws {
        guard let photoUrl = try writeFixturePhoto(image) else {
            throw PhotoUploadManager.PhotoError.imageConversionFailed
        }

        _ = try await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: metrics.date,
            photoUrl: photoUrl,
            userId: userId
        )
    }

    private func writeFixturePhoto(_ image: UIImage) throws -> String? {
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-progress-photo-fixture.jpg")
        try data.write(to: url, options: [.atomic])
        return url.absoluteString
    }
    #endif

    private func targetMetrics(
        userId: String,
        diaryDate: Date,
        writeAdmission: @escaping CoreDataManager.WriteAdmission
    ) async throws -> PhotoMetricsUpdateResult {
        if let targetMetric, Calendar.current.isDate(targetMetric.date, inSameDayAs: diaryDate) {
            return try await PhotoMetadataService.shared.prepareExistingMetricsForPhotoUpload(
                id: targetMetric.id,
                userId: userId,
                writeAdmission: writeAdmission
            )
        }

        return try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: diaryDate,
            userId: userId,
            writeAdmission: writeAdmission
        )
    }
}
