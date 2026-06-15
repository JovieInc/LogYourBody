import AVFoundation
import Photos
import PhotosUI
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

    static func canUseCamera(isAvailable: Bool, authorizationStatus: AVAuthorizationStatus) -> Bool {
        guard isAvailable else { return false }
        switch authorizationStatus {
        case .authorized, .notDetermined:
            return true
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

struct ProgressPhotoAttachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var uploadManager = PhotoUploadManager.shared

    let targetMetric: BodyMetrics?
    let fallbackDate: Date
    let onComplete: () async -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageDate: Date?
    @State private var attachStatus: ProgressPhotoAttachStatus = .empty
    @State private var isCameraPresented = false

    private var targetDate: Date {
        targetMetric?.date ?? selectedImageDate ?? fallbackDate
    }

    private var isBusy: Bool {
        if case .processing = attachStatus {
            return true
        }
        return uploadManager.isUploading
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
            ZStack {
                Color.metricCanvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        previewPane
                        statusPane
                        actionPane
                        attachButton
                    }
                    .padding(20)
                    .padding(.bottom, 18)
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

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSuccess {
                        Button("Done") {
                            dismiss()
                        }
                    }
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
            .onChange(of: selectedPhotoItem) { _, item in
                loadSelectedPhoto(item)
            }
        }
        .accessibilityIdentifier("progress_photo_attach_sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProgressPhotoAttachPolicy.title(targetHasPhoto: PhotoTimelineHUDPolicy.hasUsablePhoto(targetMetric)))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)

            Text(
                ProgressPhotoAttachPolicy.targetCopy(
                    hasTargetMetric: targetMetric != nil,
                    targetDate: targetDate
                )
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color.metricTextSecondary)
        }
    }

    private var previewPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.065))
                .frame(height: 360)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityLabel("Selected progress photo preview")
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.48))

                    Text("No photo selected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.metricTextSecondary)
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
        VStack(spacing: 12) {
            ProgressView(value: uploadManager.uploadProgress > 0 ? uploadManager.uploadProgress : nil)
                .tint(.white)
                .frame(width: 120)

            Text(uploadProgressText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(statusColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(ProgressPhotoAttachPolicy.statusTitle(for: attachStatus))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(ProgressPhotoAttachPolicy.statusMessage(for: attachStatus))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
            return Color.metricTextTertiary
        case .ready:
            return Color.metricAccent
        case .permissionDenied, .failed:
            return Color.metricAccentBodyFat
        case .processing:
            return Color.metricAccentFFMI
        case .success:
            return Color.metricAccentSteps
        }
    }

    private var actionPane: some View {
        VStack(spacing: 10) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
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
            .disabled(isBusy || !UIImagePickerController.isSourceTypeAvailable(.camera))
            .accessibilityIdentifier("progress_photo_attach_camera_button")

            if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text("Camera capture is unavailable in Simulator. Choose from Library for simulator validation.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextTertiary)
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
        UIImagePickerController.isSourceTypeAvailable(.camera)
            ? "Use the device camera"
            : "Unavailable in Simulator"
    }

    private func actionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.metricAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricTextTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
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
                    Label("Done", systemImage: "checkmark")
                } else {
                    Label("Attach Photo", systemImage: "paperclip")
                }

                Spacer()
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(height: 48)
            .background(canAttach || isSuccess ? Color.white : Color.white.opacity(0.18))
            .foregroundColor(canAttach || isSuccess ? .black : Color.white.opacity(0.42))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled((!canAttach && !isSuccess) || isBusy)
        .accessibilityIdentifier("progress_photo_attach_submit_button")
    }

    private func updateInitialPermissionState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            attachStatus = .permissionDenied
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            selectedImage = nil
            selectedImageDate = nil
            attachStatus = .empty
            return
        }

        attachStatus = .processing

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        attachStatus = .failed("Choose a different image file.")
                    }
                    return
                }

                let photoDate = PhotoMetadataService.shared.extractDate(from: data)
                await MainActor.run {
                    selectedImage = image
                    selectedImageDate = photoDate
                    attachStatus = .ready
                }
            } catch {
                await MainActor.run {
                    attachStatus = .failed("Could not read that photo. Choose another image.")
                }
            }
        }
    }

    private func startCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            attachStatus = .failed("Camera is not available in Simulator. Choose from Library instead.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            attachStatus = .processing
            Task {
                let granted = await requestCameraAccess()
                await MainActor.run {
                    attachStatus = granted ? .empty : .permissionDenied
                    isCameraPresented = granted
                }
            }
        case .denied, .restricted:
            attachStatus = .permissionDenied
        @unknown default:
            attachStatus = .permissionDenied
        }
    }

    private func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func handleCameraImage(_ image: UIImage) {
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
            do {
                let metrics = await targetMetrics(userId: userId)

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
            }
        }
    }

    #if DEBUG
    private func selectFixturePhoto() {
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

    private func targetMetrics(userId: String) async -> BodyMetrics {
        if let targetMetric {
            return targetMetric
        }

        return await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: selectedImageDate ?? fallbackDate,
            userId: userId
        )
    }
}
