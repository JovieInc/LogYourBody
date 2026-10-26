import ActivityKit
import Foundation

/// Shared with the Live Activity extension; intentionally contains no account or health data.
struct TrainingRestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let startedAt: Date
        let endsAt: Date
    }
}
