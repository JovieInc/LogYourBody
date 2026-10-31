//
// ChaosMonkeyUITests+ElementFingerprint.swift
// LogYourBody
//
// Element scoring helpers split out of ChaosMonkeyUITests.swift to honor the
// per-file size budget; behavior is unchanged.
//
import XCTest

extension ChaosMonkeyUITests {
    func hasFiniteNonZeroFrame(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        return frame.width.isFinite && frame.height.isFinite
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width > 0 && frame.height > 0
    }

    /// A cheap fingerprint of the candidate set `StuckDetector` compares
    /// across steps: identifier + label + enabled state for each element,
    /// order-sensitive (the query order is stable for an unchanged tree).
    func treeFingerprint(_ elements: [XCUIElement]) -> Int {
        var hasher = Hasher()
        for element in elements {
            hasher.combine(element.identifier)
            hasher.combine(element.label)
            hasher.combine(element.isEnabled)
        }
        return hasher.finalize()
    }
}
