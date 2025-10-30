//
// BackgroundTaskType.swift
// LogYourBody
//
import Foundation

// MARK: - Background Task Type

/// Represents different types of background tasks that can run in the app
enum BackgroundTaskType: String, CaseIterable {
    case scanning = "Scanning"
    case importing = "Importing"
    case uploading = "Uploading"
    case processing = "Processing"

    /// Priority order for displaying when multiple tasks are active
    var priority: Int {
        switch self {
        case .importing: return 4  // Highest priority
        case .uploading: return 3
        case .processing: return 2
        case .scanning: return 1   // Lowest priority
        }
    }

    /// SF Symbol name for the task icon
    var iconName: String {
        switch self {
        case .scanning:
            return "magnifyingglass.circle.fill"
        case .importing:
            return "arrow.down.circle.fill"
        case .uploading:
            return "icloud.and.arrow.up"
        case .processing:
            return "sparkles"
        }
    }

    /// Whether this task type should show animated icon
    var shouldAnimateIcon: Bool {
        return true  // All task types animate
    }
}

// MARK: - Background Task Info

/// Information about an active background task
struct BackgroundTaskInfo: Identifiable {
    let id: UUID
    let type: BackgroundTaskType
    let title: String
    let subtitle: String?
    let progress: Double? // 0.0 to 1.0, nil for indeterminate
    let itemCount: (current: Int, total: Int)? // For countable tasks
    let canCancel: Bool
    let isFailed: Bool
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        type: BackgroundTaskType,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        itemCount: (current: Int, total: Int)? = nil,
        canCancel: Bool = true,
        isFailed: Bool = false,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.itemCount = itemCount
        self.canCancel = canCancel
        self.isFailed = isFailed
        self.errorMessage = errorMessage
    }

    /// Formatted progress string (e.g., "3 of 10", "75%")
    var progressText: String? {
        if let count = itemCount {
            return "\(count.current) of \(count.total)"
        } else if let progress = progress {
            return "\(Int(progress * 100))%"
        }
        return nil
    }
}
