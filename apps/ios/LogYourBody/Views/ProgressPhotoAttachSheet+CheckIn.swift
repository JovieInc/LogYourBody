import SwiftUI
import UIKit

extension ProgressPhotoAttachSheet {
    func previewHeight(for availableHeight: CGFloat) -> CGFloat {
        min(260, max(184, availableHeight * 0.30))
    }

    func announceStatusChange(_ status: ProgressPhotoAttachStatus) {
        let message = "\(ProgressPhotoAttachPolicy.statusTitle(for: status)). \(ProgressPhotoAttachPolicy.statusMessage(for: status))"
        UIAccessibility.post(notification: .announcement, argument: message)
        isStatusFocused = true
    }

    func updateInitialPermissionState() {
        switch photoLibrary.weeklyLibraryAccess() {
        case .denied, .restricted:
            attachStatus = .permissionDenied
            finishAbandoned(outcome: "permission_denied", source: "library")
        case .limited, .authorized, .notDetermined, .unknown:
            break
        }
    }

    func noteCaptureStarted(_ source: String) {
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

    func finishAbandoned(outcome: String, source: String) {
        guard !didFinishAttempt else { return }
        didFinishAttempt = true
        WeeklyPhotoCheckInTelemetry.emit([
            WeeklyPhotoCheckInPolicy.failureMetric(source: source, outcome: outcome)
        ])
    }

    func loadSelectedPhoto(_ asset: AppPhotoAsset?) {
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

    func startCameraCapture() {
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

    func handleCameraImage(_ image: UIImage) {
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

    func attachSelectedPhoto() {
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

    func weeklyProvenance(
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

    func finishCheckIn(
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
    func selectFixturePhoto() {
        photoSelectionLoadID = UUID()
        selectedImage = makeFixtureProgressPhoto()
        selectedImageDate = targetDate
        attachStatus = .ready
    }

    func makeFixtureProgressPhoto() -> UIImage {
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

    func attachFixturePhoto(
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

    func writeFixturePhoto(_ image: UIImage) throws -> String? {
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-progress-photo-fixture.jpg")
        try data.write(to: url, options: [.atomic])
        return url.absoluteString
    }
    #endif

    func targetMetrics(
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
