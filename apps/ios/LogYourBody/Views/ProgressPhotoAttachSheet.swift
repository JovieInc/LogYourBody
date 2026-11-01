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
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var uploadManager = PhotoUploadManager.shared
    let photoLibrary: PhotoLibraryManaging = LivePhotoLibraryAdapter.shared
    let cameraAuthorizer: CameraAuthorizing = LiveCameraAuthorizationAdapter.shared

    let targetMetric: BodyMetrics?
    let fallbackDate: Date
    var photoHistory: [WeeklyPhotoProvenance] = []
    var previousPhotoURL: String?
    let onComplete: () async -> Void
    var onCheckInSaved: (WeeklyPhotoSaveOutcome) -> Void = { _ in }

    @State var selectedImage: UIImage?
    @State var selectedOriginalData: Data?
    @State var selectedImageDate: Date?
    @State var chosenPhotoDate: Date?
    @State var captureViewpoint = "unspecified"
    @State var captureMirror = "unknown"
    @State var captureSource = "library"
    @State var submissionId = UUID().uuidString
    @State var captureStartedAt: Date?
    @State var didFinishAttempt = false
    @State var attachStatus: ProgressPhotoAttachStatus = .empty
    @State var isCameraPresented = false
    @State var cameraSessionStarted = false
    @State var photoSelectionLoadID = UUID()
    @State private var sheetDetent = NativeSheetPresentationPolicy.initialDetent(for: .progressPhotoAttach)
    @AccessibilityFocusState var isStatusFocused: Bool

    var targetDate: Date {
        chosenPhotoDate ?? selectedImageDate ?? targetMetric?.date ?? fallbackDate
    }

    private var isBusy: Bool {
        ProgressPhotoAttachPolicy.isBusy(status: attachStatus)
    }

    var isSuccess: Bool {
        if case .success = attachStatus {
            return true
        }
        return false
    }

    private var canAttach: Bool {
        selectedImage != nil && !isBusy && !isSuccess
    }

    #if DEBUG
    var usesProgressPhotoAttachFixture: Bool {
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
}
