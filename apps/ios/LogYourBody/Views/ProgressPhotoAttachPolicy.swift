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
