import SwiftUI

enum BodyFatEntryMethod: String, CaseIterable {
    case visualEstimate = "visual_estimate"
    case bodyScan = "body_scan"
    case calipers = "caliper"
    case bioelectrical = "bia_scale"
    case dexa

    /// A prefilled reading keeps its exact provenance until the user chooses another method.
    static func initialSelection(bodyFat: Double?, recordedMethod: String?) -> String? {
        bodyFat == nil ? visualEstimate.rawValue : recordedMethod
    }

    static func selectionTitle(_ raw: String?) -> String {
        let normalized = raw?.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let normalized, let method = Self(rawValue: normalized) { return method.title }
        switch normalized {
        case "manual", "typed": return "Entered by you"
        case "dexa (bodyspec)", "bodyspec_dexa": return "DEXA"
        case "inbody": return "InBody"
        case "bioelectrical": return "Bioelectrical"
        case "calipers": return "Calipers"
        default: return "Method not specified"
        }
    }

    static func needsPreservedOption(_ raw: String?) -> Bool {
        raw.flatMap(Self.init(rawValue:)) == nil
    }

    struct AccessibleChoice: Equatable, Identifiable {
        let title: String
        let value: String?
        var id: String { title }
    }

    /// Choices shown in the sheet at accessibility sizes. A preserved reading
    /// stays available, and every known method, including DEXA, stays selectable.
    static func accessibleChoices(selected raw: String?) -> [AccessibleChoice] {
        var choices: [AccessibleChoice] = []
        var seen = Set<String>()
        func append(title: String, value: String?) {
            guard seen.insert(title).inserted else { return }
            choices.append(AccessibleChoice(title: title, value: value))
        }
        if needsPreservedOption(raw) {
            append(title: selectionTitle(raw), value: raw)
        }
        for method in allCases {
            append(title: method.title, value: method.rawValue)
        }
        return choices
    }

    var title: String {
        switch self {
        case .visualEstimate: "Visual Estimate"
        case .bodyScan: "Body Scan"
        case .calipers: "Calipers"
        case .bioelectrical: "Bioelectrical"
        case .dexa: "DEXA"
        }
    }
}

struct PhotoUploadBatchPolicy {
    static func progress(completedCount: Int, totalCount: Int) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    static func progressText(processedCount: Int, totalCount: Int) -> String {
        guard totalCount > 0 else { return "Processing photos" }
        let currentIndex = min(processedCount + 1, totalCount)
        return "Processing \(currentIndex) of \(totalCount)"
    }

    static func canChangeSelection(isProcessing: Bool) -> Bool {
        !isProcessing
    }

    static func canStartUpload(selectedCount: Int, isSaving: Bool, isProcessing: Bool) -> Bool {
        selectedCount > 0 && !isSaving && !isProcessing
    }

    static func canDismiss(isSaving: Bool, isProcessing: Bool) -> Bool {
        !isSaving && !isProcessing
    }

    static func shouldDismissAfterUpload(successfulCount: Int, totalCount: Int) -> Bool {
        totalCount > 0 && successfulCount == totalCount
    }

    static func uploadFailureMessage(successfulCount: Int, totalCount: Int) -> String {
        guard successfulCount > 0 else {
            return "Photo upload failed. Please try again."
        }

        let failedCount = max(totalCount - successfulCount, 0)
        let noun = failedCount == 1 ? "photo" : "photos"
        return "Uploaded \(successfulCount) of \(totalCount) photos. \(failedCount) \(noun) failed. Try again."
    }
}
