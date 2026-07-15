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
    let onComplete: () async -> Void

    @State private var selectedImage: UIImage?
    @State private var selectedImageDate: Date?
    @State private var attachStatus: ProgressPhotoAttachStatus = .empty
    @State private var isCameraPresented = false
    @State private var photoSelectionLoadID = UUID()
    @AccessibilityFocusState private var isStatusFocused: Bool

    private var targetDate: Date {
        targetMetric?.date ?? selectedImageDate ?? fallbackDate
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
                ZStack {
                    Color.jovieCanvas.ignoresSafeArea()

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
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    attachButton
                        .padding(.horizontal, JovieTokens.screenInset)
                        .padding(.vertical, JovieTokens.itemGap)
                        .background(Color.jovieCanvas.opacity(0.96))
                }
            }
            .navigationTitle("Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraView { image in
                    handleCameraImage(image)
                }
            }
            .onAppear {
                updateInitialPermissionState()
            }
            .onChange(of: attachStatus) { status in
                announceStatusChange(status)
            }
        }
        .accessibilityIdentifier("progress_photo_attach_sheet")
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
                    .aspectRatio(contentMode: .fill)
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
        VStack(spacing: 10) {
            AppPhotosPicker(maxSelectionCount: 1) { assets in
                await MainActor.run {
                    loadSelectedPhoto(assets.first)
                }
            } label: {
                actionRow(
                    title: "Choose from Library",
                    subtitle: "Select one existing progress photo",
                    icon: "photo.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("progress_photo_attach_library_button")

            Button {
                startCameraCapture()
            } label: {
                actionRow(
                    title: "Take Photo",
                    subtitle: cameraSubtitle,
                    icon: "camera.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !cameraAuthorizer.isCameraAvailable)
            .accessibilityIdentifier("progress_photo_attach_camera_button")

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
                    actionRow(
                        title: "Use Fixture Photo",
                        subtitle: "Debug-only simulator image",
                        icon: "testtube.2"
                    )
                }
                .buttonStyle(.plain)
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

    private func actionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(theme.colors.info)
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .background(Circle().fill(theme.colors.info.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)

                Text(subtitle)
                    .font(theme.typography.bodySmall)
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.footnote, design: .default).weight(.semibold))
                .foregroundColor(theme.colors.textSecondary)
        }
        .padding(.horizontal, theme.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .fill(theme.colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.input, style: .continuous)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .jovieTouchTarget()
    }

    private var attachButton: some View {
        Button {
            attachSelectedPhoto()
        } label: {
            HStack {
                Spacer()

                if isBusy {
                    ProgressView()
                        .tint(.black)
                } else if isSuccess {
                    Label("Close", systemImage: "checkmark")
                } else {
                    Label("Attach Photo", systemImage: "paperclip")
                }

                Spacer()
            }
            .font(theme.typography.labelLarge)
            .frame(minHeight: JovieTokens.controlHeight)
            .background(canAttach || isSuccess ? theme.colors.interactive : theme.colors.interactiveDisabled)
            .foregroundColor(canAttach || isSuccess ? Color.jovieActionText : theme.colors.textSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
        let status = photoLibrary.authorizationStatus()
        if status == .denied || status == .restricted {
            attachStatus = .permissionDenied
        }
    }

    private func loadSelectedPhoto(_ asset: AppPhotoAsset?) {
        let loadID = UUID()
        photoSelectionLoadID = loadID

        guard let asset else {
            selectedImage = nil
            selectedImageDate = nil
            attachStatus = .empty
            return
        }

        attachStatus = .processing
        guard photoSelectionLoadID == loadID else { return }
        selectedImage = asset.image
        selectedImageDate = PhotoMetadataService.shared.extractDate(from: asset.data)
        attachStatus = .ready
    }

    private func startCameraCapture() {
        guard cameraAuthorizer.isCameraAvailable else {
            attachStatus = .failed("Camera is not available in Simulator. Choose from Library instead.")
            return
        }

        switch cameraAuthorizer.authorizationStatus() {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            attachStatus = .processing
            Task {
                let granted = await cameraAuthorizer.requestAccess()
                await MainActor.run {
                    attachStatus = granted ? .empty : .permissionDenied
                    isCameraPresented = granted
                }
            }
        case .denied, .restricted:
            attachStatus = .permissionDenied
        case .unknown:
            attachStatus = .permissionDenied
        }
    }

    private func handleCameraImage(_ image: UIImage) {
        photoSelectionLoadID = UUID()
        selectedImage = image
        selectedImageDate = nil
        attachStatus = .ready
    }

    private func attachSelectedPhoto() {
        if isSuccess {
            dismiss()
            return
        }

        guard let selectedImage else {
            attachStatus = .empty
            return
        }

        guard let userId = authManager.currentUser?.id else {
            attachStatus = .failed("Sign in again to upload photos.")
            return
        }

        attachStatus = .processing

        Task {
            var placeholderMetricId: String?

            do {
                let metricsResult = try await targetMetrics(userId: userId)
                let metrics = metricsResult.metrics
                placeholderMetricId = metrics.id

                #if DEBUG
                if usesProgressPhotoAttachFixture {
                    try await attachFixturePhoto(
                        image: selectedImage,
                        to: metrics,
                        userId: userId
                    )
                    await onComplete()
                    await MainActor.run {
                        attachStatus = .success
                        HapticManager.shared.successAction()
                    }
                    return
                }
                #endif

                _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                    for: metrics,
                    image: selectedImage
                )

                await onComplete()
                await MainActor.run {
                    attachStatus = .success
                    HapticManager.shared.successAction()
                }
            } catch {
                await MainActor.run {
                    attachStatus = .failed(error.localizedDescription)
                }
                if let placeholderMetricId {
                    _ = await CoreDataManager.shared.deleteEmptyPhotoPlaceholder(
                        id: placeholderMetricId,
                        userId: userId
                    )
                }
            }
        }
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
                cornerRadius: 170
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

        _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
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

    private func targetMetrics(userId: String) async throws -> PhotoMetricsUpdateResult {
        if let targetMetric {
            return try await PhotoMetadataService.shared.prepareExistingMetricsForPhotoUpload(
                id: targetMetric.id,
                userId: userId
            )
        }

        return try await PhotoMetadataService.shared.createOrUpdateMetricsForPhotoUpload(
            for: selectedImageDate ?? fallbackDate,
            userId: userId
        )
    }
}
