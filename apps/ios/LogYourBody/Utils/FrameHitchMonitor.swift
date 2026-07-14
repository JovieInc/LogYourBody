//
// FrameHitchMonitor.swift
// LogYourBody
//
// DEBUG-only frame hitch counter built on CADisplayLink. A "hitch" is any frame
// whose render interval exceeds the display's nominal frame budget by more than
// `hitchThresholdMultiplier`. Use it to capture an objective scroll/scrub
// smoothness baseline and to confirm later optimization phases drive hitches → 0.
//
// It only runs when explicitly enabled (launch argument `-lybPerfHitchMonitor`
// or env `LYB_PERF_HITCH_MONITOR=1`) so it never skews normal debug sessions and
// never ships in release builds.
//
// Typical flow:
//   FrameHitchMonitor.shared.start()          // app launch (guarded internally)
//   FrameHitchMonitor.shared.flush(label: ...) // after a measured gesture
//

#if DEBUG
import QuartzCore
import UIKit

@MainActor
final class FrameHitchMonitor {
    static let shared = FrameHitchMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    private(set) var hitchCount = 0
    private(set) var frameCount = 0
    private(set) var worstFrameMs: Double = 0

    /// A frame counts as a hitch when it takes longer than this multiple of the
    /// nominal frame duration (e.g. > 1.5× of 8.3ms on a 120Hz display).
    private let hitchThresholdMultiplier: Double = 1.5

    private var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-lybPerfHitchMonitor") ||
            ProcessInfo.processInfo.environment["LYB_PERF_HITCH_MONITOR"] == "1"
    }

    private init() {}

    /// Start monitoring. No-op unless explicitly enabled.
    func start() {
        guard isEnabled, displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        reset()
        AppLogger.ui.info("FrameHitchMonitor started")
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func reset() {
        lastTimestamp = 0
        hitchCount = 0
        frameCount = 0
        worstFrameMs = 0
    }

    /// Log the rolling counters and reset. Call at the end of a measured gesture.
    func flush(label: String) {
        guard isEnabled else { return }
        let worst = String(format: "%.1f", worstFrameMs)
        AppLogger.ui.info("hitches[\(label)] \(hitchCount)/\(frameCount) frames, worst \(worst) ms")
        reset()
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp != 0 else { return }

        let frameMs = (link.timestamp - lastTimestamp) * 1_000
        let nominalMs = link.duration > 0 ? link.duration * 1_000 : 1_000.0 / 60.0

        frameCount += 1
        if frameMs > nominalMs * hitchThresholdMultiplier {
            hitchCount += 1
        }
        worstFrameMs = max(worstFrameMs, frameMs)
    }
}
#endif
