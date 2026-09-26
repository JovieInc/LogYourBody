//
// HomeV2Policy.swift
// LogYourBody
//
import CoreGraphics
import Foundation

/// Gate for the photo-first Home (Pencil H2, picked 2026-09-26). Off by default
/// in production; the Statsig gate owns rollout. Debug fixtures force it on so
/// XCUITest can cover both states without a network.
enum HomeV2Policy {
    static let gateKey = "home_v2_photo_first"
    static let fixtureArgument = "-lybUITestHomeV2Fixture"
    static let photoFixtureArgument = "-lybUITestHomeV2PhotoFixture"

    /// `isGateEnabled` defaults to the Statsig-backed analytics port; tests inject
    /// their own so the policy stays deterministic.
    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument) || arguments.contains(photoFixtureArgument) {
            return true
        }
        #endif
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }
}

/// Copy for the v2 Home. Changes read as sentences instead of arrows and units.
enum HomeV2Copy {
    static let addPhotoRow = "Add a progress photo"
    static let addPhotoDetail = "Optional"
    static let estimatedSubline = "Estimated"

    static func changeSentence(delta: Double?, unit: String, days: Int = 30) -> String {
        guard let delta else { return "No \(days)-day trend yet" }
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change in \(days) days" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(String(format: "%.1f", magnitude)) \(unit) in \(days) days"
    }

    static let firstPhoto = "First photo"

    /// "Down 12.8 lb since Apr 2" — change against the first photo.
    static func sinceSentence(delta: Double, unit: String, since: String) -> String {
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change since \(since)" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(String(format: "%.1f", magnitude)) \(unit) since \(since)"
    }

    static func photoPosition(_ position: Int, of total: Int) -> String {
        "Photo \(position) of \(total)"
    }

    /// Row detail: "−0.9 pts", "+0.2", "No change", "No 30-day trend".
    static func compactChange(delta: Double?, unit: String, days: Int = 30) -> String {
        guard let delta else { return "No \(days)-day trend" }
        let magnitude = abs(delta)
        guard magnitude >= 0.05 else { return "No change" }
        let sign = delta < 0 ? "−" : "+"
        let value = String(format: "%.1f", magnitude)
        return unit.isEmpty ? "\(sign)\(value)" : "\(sign)\(value) \(unit)"
    }
}

/// Geometry that must hold on every iPhone: the photo stays full width at 4:5
/// when it fits, and gives up height (never width) on short screens so the
/// number and filmstrip stay on screen.
enum HomeV2Layout {
    static let numberAndFilmstripHeight: CGFloat = 150
    static let minimumStageHeight: CGFloat = 200

    static func stageHeight(width: CGFloat, height: CGFloat) -> CGFloat {
        let fourByFive = width / HomeV2Tokens.photoAspectRatio
        let available = max(minimumStageHeight, height - numberAndFilmstripHeight)
        return min(fourByFive, available)
    }
}
